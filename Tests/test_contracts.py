import json
import re
import unittest
from copy import deepcopy
from pathlib import Path

from jsonschema import Draft202012Validator, FormatChecker


ROOT = Path(__file__).resolve().parents[1]
CONTRACTS = ROOT / "Contracts"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


HAN = re.compile(r"[\u4e00-\u9fff]")

# `%@`, `%lld` and friends, plus the interpolation placeholder below, all stand
# for "a hole the code fills in".
SPECIFIER = re.compile(r"%(?:@|lld|ld|lf|d|s)")
HOLE = "\x00"


def canonical_copy(text: str) -> str:
    """A literal and its catalog key reduced to one comparable form.

    Xcode writes a hole as `%@` or `%lld` depending on the interpolated type, and
    doubles a literal percent. Reducing both sides means this guard checks the
    thing it is for — that a visible string has *an* entry — without having to
    infer Swift types from a regex.
    """
    return SPECIFIER.sub(HOLE, text).replace("%%", "%")


def swift_string_literals(source: str) -> list[str]:
    """Every string literal in Swift source, with each `\\(...)` interpolation
    replaced by a hole.

    Written as a scanner rather than a regex because interpolations nest: the
    previous regex admitted only `\\([^()]*)`, so `\\(Int(x.rounded()))` matched
    nothing and every string containing one was skipped silently — which is how
    a visible Map string reached the surface unchecked. Comments are skipped too,
    so prose that quotes a Chinese string is not mistaken for product copy.
    """
    literals: list[str] = []
    index, end = 0, len(source)
    while index < end:
        char = source[index]
        if char == "/" and source.startswith("//", index):
            newline = source.find("\n", index)
            if newline == -1:
                break
            index = newline + 1
            continue
        if char == "/" and source.startswith("/*", index):
            close = source.find("*/", index + 2)
            index = end if close == -1 else close + 2
            continue
        if char != '"':
            index += 1
            continue
        index += 1
        buffer: list[str] = []
        while index < end:
            char = source[index]
            if char == "\\" and index + 1 < end:
                if source[index + 1] == "(":
                    depth, index = 1, index + 2
                    while index < end and depth:
                        depth += (source[index] == "(") - (source[index] == ")")
                        index += 1
                    buffer.append(HOLE)
                    continue
                buffer.append(source[index : index + 2])
                index += 2
                continue
            if char in '"\n':
                index += 1
                break
            buffer.append(char)
            index += 1
        literals.append("".join(buffer))
    return literals


def constant(source: str, pattern: str) -> int:
    """A literal integer constant, read out of Swift or Kotlin source.

    Accepts the `1_024 * 1_024` form both languages use for byte bounds, so the
    declaration stays readable in the language that owns it.
    """
    match = re.search(pattern, source)
    assert match, f"no constant matching {pattern!r}"
    value = 1
    for factor in re.findall(r"\d[\d_]*", match.group(1)):
        value *= int(factor.replace("_", ""))
    return value


SWIFT_SUITE = re.compile(r"\b(?:final\s+)?class\s+([A-Za-z0-9_]+)\s*:\s*XCTestCase")
PYTHON_SUITE = re.compile(r"^class\s+([A-Za-z0-9_]+)\(", re.MULTILINE)
NAMED_SUITE = re.compile(r"`([A-Za-z0-9_]+Tests)`")


def declared_test_suites() -> set[str]:
    """Every test suite that actually exists in this repository."""
    suites: set[str] = set()
    sources = [
        path
        for path in ROOT.glob("Packages/*/Tests/**/*.swift")
        if ".build" not in path.parts
    ]
    sources += list((ROOT / "Tests/Swift").glob("*.swift"))
    for path in sources:
        suites.update(SWIFT_SUITE.findall(path.read_text(encoding="utf-8")))
    for path in list((ROOT / "Tests").glob("*.py")) + list((ROOT / "Backend").glob("*.py")):
        suites.update(PYTHON_SUITE.findall(path.read_text(encoding="utf-8")))
    return suites


def traceability_rows() -> list[list[str]]:
    tdd = read(ROOT / "docs/TDD.md")
    section = tdd[tdd.index("## 12. PRD Traceability") :]
    section = section[: section.index("## 13")]
    return [
        [cell.strip() for cell in line.strip().strip("|").split("|")]
        for line in section.splitlines()
        if line.strip().startswith("| JM-P0")
    ]


class ContractArtifactTests(unittest.TestCase):
    def test_every_test_named_in_traceability_actually_exists(self) -> None:
        """A P0 may not be traced to a test that was never written.

        `check_prd_tdd.py` requires each P0 row to carry a non-empty evidence
        cell, which a plausible-looking suite name satisfies without any such
        suite existing. On 2026-08-18 that was true of 24 of the 30 names in the
        table. A requirement whose evidence is fictional is worse than one openly
        marked unimplemented, because it reads as covered — so an unimplemented
        P0 must say so in words instead of naming a suite.
        """
        declared = declared_test_suites()
        self.assertGreater(len(declared), 20, "the suite inventory itself looks broken")
        fictional: list[str] = []
        for row in traceability_rows():
            for name in NAMED_SUITE.findall(row[4]):
                if name not in declared:
                    fictional.append(f"{row[0]}: {name}")
        self.assertEqual(fictional, [], f"traceability names tests that do not exist: {fictional}")

    def test_every_p0_requirement_has_a_traceability_row(self) -> None:
        rows = traceability_rows()
        self.assertEqual(len(rows), 24)
        for row in rows:
            self.assertTrue(row[4], f"{row[0]} has an empty evidence cell")

    def test_failure_state_corpus_matches_the_prd_exactly(self) -> None:
        """`FAIL-001`…`FAIL-032` must stay the states the PRD actually names.

        The corpus is generated from PRD §7.1 rather than retyped, so this guards
        the direction that generation cannot: a PRD edit that renames, reorders
        or adds a state leaves a stale committed corpus behind until someone
        re-runs the tool.
        """
        prd = read(ROOT / "docs/PRD.md")
        states_section = prd[prd.index("## 7. Named failure and degraded states") : prd.index("### 7.1")]
        fixture_section = prd[prd.index("### 7.1") : prd.index("## 8.")]
        declared = re.findall(r"^\| `([a-zA-Z]+)` \|", states_section, re.MULTILINE)
        fixtures = re.findall(r"^\| `([a-zA-Z]+)` \| `(FAIL-\d{3})` \|", fixture_section, re.MULTILINE)

        self.assertEqual(len(declared), 32)
        self.assertEqual(declared, [state for state, _ in fixtures], "§7 and §7.1 name different states")
        self.assertEqual(
            [fixture for _, fixture in fixtures],
            [f"FAIL-{index:03d}" for index in range(1, 33)],
            "fixture IDs must be unique and contiguous",
        )

        corpus = json.loads(read(ROOT / "Contracts/failure-states.json"))
        self.assertEqual(corpus["schema"], "joi.failure-states.v1")
        self.assertEqual(
            [(entry["id"], entry["state"]) for entry in corpus["states"]],
            [(fixture, state) for state, fixture in fixtures],
            "corpus is stale; re-run Tools/make_failure_corpus.py",
        )

    def test_failure_states_claim_only_evidence_that_exists(self) -> None:
        """A state may not call itself implemented on the strength of a test nobody wrote.

        This is the same failure the traceability table had: a plausible name
        reads as coverage. Here it would be worse, because the corpus is what a
        reader consults to learn which degraded paths are real.
        """
        corpus = json.loads(read(ROOT / "Contracts/failure-states.json"))
        declared = declared_test_suites()
        problems: list[str] = []
        for entry in corpus["states"]:
            self.assertIn(entry["status"], {"implemented", "partial", "absent"}, entry["id"])
            for suite in entry["evidence"]:
                if suite not in declared:
                    problems.append(f"{entry['id']}: {suite} does not exist")
            if entry["status"] == "implemented" and not entry["evidence"]:
                problems.append(f"{entry['id']}: claims implemented with no evidence")
            if entry["status"] != "implemented" and not entry.get("gap"):
                problems.append(f"{entry['id']}: is {entry['status']} but names no gap")
            if entry["status"] == "absent" and entry["evidence"]:
                problems.append(f"{entry['id']}: is absent but cites evidence")
        self.assertEqual(problems, [], f"failure-state corpus problems: {problems}")

    def test_all_json_contracts_and_fixtures_parse(self) -> None:
        files = sorted(CONTRACTS.rglob("*.json"))
        self.assertGreaterEqual(len(files), 7)
        for path in files:
            with self.subTest(path=path.name):
                with path.open(encoding="utf-8") as stream:
                    self.assertIsInstance(json.load(stream), dict)

    def test_character_fixture_uses_current_chinese_lane_and_no_user_state(self) -> None:
        fixture = json.loads((CONTRACTS / "fixtures/character-package.valid.json").read_text(encoding="utf-8"))
        self.assertEqual(fixture["locales"], ["zh-Hans"])
        forbidden = {"memory", "messages", "affinity", "permissions", "secrets", "syncState"}
        self.assertTrue(forbidden.isdisjoint(fixture))

    def test_simplified_chinese_copy_catalog_is_editable_and_complete_for_shell(self) -> None:
        catalog = json.loads(
            (ROOT / "JoiMobile/Resources/Localizable.xcstrings").read_text(encoding="utf-8")
        )
        self.assertEqual(catalog["sourceLanguage"], "zh-Hans")
        expected = {
            "聊天", "地图", "本地会话", "个人面板", "原生角色舞台",
            # The composer placeholder follows the current character name, so the
            # catalog key is the interpolated form rather than a literal "Joi".
            "给 %@ 发消息", "按住说话", "已缓存的文化步行", "离线可用",
            "路线预览", "查看来源",
            # G2-J2A conversation turn copy.
            "发送", "停止", "%@ 正在回应",
            "已停止这次回应；对话没有变化。",
            "这次回应没有完成；对话没有变化。",
            "服务暂时无法回应，请稍后再试。",
            "无法连接到 Joi 的服务；对话没有变化。",
        }
        self.assertTrue(expected.issubset(catalog["strings"]))

    def test_no_visible_surface_copy_bypasses_the_editable_catalog(self) -> None:
        """Every zh-Hans literal on a product surface must have a catalog key."""
        catalog = json.loads(
            (ROOT / "JoiMobile/Resources/Localizable.xcstrings").read_text(encoding="utf-8")
        )
        keys = {canonical_copy(key) for key in catalog["strings"]}
        surface = [
            "JoiMobile/App/ChatStageView.swift",
            "JoiMobile/App/CharacterStageView.swift",
            "JoiMobile/App/ChatBubbleAndTranscript.swift",
            # G2-J3A/J3B put visible copy on the Map surface and in the journey
            # attachment, so both are guarded here rather than only Chat.
            "JoiMobile/App/MapExperienceView.swift",
            "JoiMobile/App/JourneyAttachment.swift",
            "JoiMobile/App/AppModel.swift",
            # G2-J2D memory proposal, list and category labels.
            "JoiMobile/App/MemoryViews.swift",
            "JoiMobile/App/MemoryProposal.swift",
            # G2-J3C source projection copy.
            "JoiMobile/App/SourceViews.swift",
        ]
        missing: list[str] = []
        for name in surface:
            source = (ROOT / name).read_text(encoding="utf-8")
            for literal in swift_string_literals(source):
                if not HAN.search(literal):
                    continue
                if canonical_copy(literal) not in keys:
                    missing.append(f"{name}: {literal}")
        self.assertEqual(missing, [], f"surface copy missing from catalog: {missing}")

    def test_schemas_close_security_boundaries(self) -> None:
        for path in CONTRACTS.glob("*.schema.json"):
            schema = json.loads(path.read_text(encoding="utf-8"))
            self.assertFalse(schema.get("additionalProperties", True), path.name)

    def test_fixtures_validate_against_json_schemas(self) -> None:
        pairs = [
            ("character-package-manifest-v1.schema.json", "character-package.valid.json"),
            ("character-package-manifest-v1.schema.json", "character-package-vrm-motions.valid.json"),
            ("companion-event-v1.schema.json", "companion-event.valid.json"),
        ]
        for schema_name, fixture_name in pairs:
            schema = json.loads((CONTRACTS / schema_name).read_text(encoding="utf-8"))
            fixture = json.loads((CONTRACTS / "fixtures" / fixture_name).read_text(encoding="utf-8"))
            validator = Draft202012Validator(schema, format_checker=FormatChecker())
            with self.subTest(fixture=fixture_name):
                self.assertEqual(list(validator.iter_errors(fixture)), [])

    def test_invalid_source_projection_is_rejected(self) -> None:
        schema = json.loads(
            (CONTRACTS / "companion-event-v1.schema.json").read_text(encoding="utf-8")
        )
        fixture = json.loads(
            (CONTRACTS / "fixtures/companion-event.valid.json").read_text(encoding="utf-8")
        )
        invalid = deepcopy(fixture)
        invalid["sources"][0]["claimSupportConfidence"] = 1.5
        invalid["sources"][0]["conflictStatus"] = "invented"

        errors = list(
            Draft202012Validator(schema, format_checker=FormatChecker()).iter_errors(invalid)
        )
        self.assertGreaterEqual(len(errors), 2)

    def test_character_manifest_rejects_unsafe_paths_unknown_fields_and_noncanonical_hashes(self) -> None:
        schema = json.loads(
            (CONTRACTS / "character-package-manifest-v1.schema.json").read_text(encoding="utf-8")
        )
        fixture = json.loads(
            (CONTRACTS / "fixtures/character-package.valid.json").read_text(encoding="utf-8")
        )
        validator = Draft202012Validator(schema, format_checker=FormatChecker())

        unsafe_path = deepcopy(fixture)
        unsafe_path["entryPath"] = "../portrait.png"
        self.assertTrue(list(validator.iter_errors(unsafe_path)))

        windows_path = deepcopy(fixture)
        windows_path["assets"][0]["path"] = "assets\\portrait.png"
        self.assertTrue(list(validator.iter_errors(windows_path)))

        uppercase_hash = deepcopy(fixture)
        uppercase_hash["assets"][0]["sha256"] = "A" * 64
        self.assertTrue(list(validator.iter_errors(uppercase_hash)))

        unknown_field = deepcopy(fixture)
        unknown_field["memory"] = {"imported": True}
        self.assertTrue(list(validator.iter_errors(unknown_field)))

        local_source = deepcopy(fixture)
        local_source["provenance"]["source"] = "file:///Users/test/private/avatar.vrm"
        self.assertTrue(list(validator.iter_errors(local_source)))

        absolute_source = deepcopy(fixture)
        absolute_source["provenance"]["source"] = "/private/avatar.vrm"
        self.assertTrue(list(validator.iter_errors(absolute_source)))

    def test_the_declared_asset_bound_is_one_number_in_every_artifact(self) -> None:
        """DEC-028: the defect was three artifacts disagreeing in silence.

        The schema said 2000, the runtime limit said 2000, and the admission
        walk's generic array guard said 300 without anyone writing that down.
        Nothing in a JSON Schema or a Swift file can notice that, so it is
        checked here, where all of them can be read at once.
        """
        schema = json.loads(
            (CONTRACTS / "character-package-manifest-v1.schema.json").read_text(encoding="utf-8")
        )
        limits_swift = read(ROOT / "Packages/CharacterRuntime/Sources/CharacterRuntime/CharacterRuntime.swift")
        walk_swift = read(
            ROOT / "Packages/CharacterRuntime/Sources/CharacterRuntime/CharacterManifestValidation.swift"
        )
        limits_kotlin = read(ROOT / "android/companion-core/src/main/kotlin/com/joi/mobile/core/CharacterContracts.kt")
        walk_kotlin = read(
            ROOT / "android/character-runtime/src/main/kotlin/com/joi/mobile/character/CharacterManifestAdmission.kt"
        )

        declared = schema["properties"]["assets"]["maxItems"]
        self.assertEqual(declared, constant(limits_swift, r"maximumFileCount = ([\d_ *]+)"))
        self.assertEqual(declared, constant(limits_kotlin, r"MAXIMUM_FILE_COUNT: Int = ([\d_ *]+)"))

        # The generic guard stays smaller than the declared bound on both
        # platforms. That gap is the whole reason the exemption has to be
        # written explicitly; if these two numbers ever meet, the exemption is
        # dead code and this test should be the thing that says so.
        guard = constant(walk_swift, r"maximumArrayElements = ([\d_ *]+)")
        self.assertEqual(guard, constant(walk_kotlin, r"MAXIMUM_ARRAY_ELEMENTS = ([\d_ *]+)"))
        self.assertLess(guard, declared)

        # And the manifest must physically hold what the contract promises: a
        # byte bound that bit first would cap the declared count at a number
        # written nowhere. Measured against a real document, not asserted.
        manifest_bytes = constant(limits_swift, r"maximumManifestBytes = ([\d_ *]+)")
        self.assertEqual(manifest_bytes, constant(limits_kotlin, r"MAXIMUM_MANIFEST_BYTES: Int = ([\d_ *]+)"))
        full = json.loads((CONTRACTS / "fixtures/character-package.valid.json").read_text(encoding="utf-8"))
        full["assets"] = [
            {"path": f"motions/{index:05d}.motion3.json", "mediaType": "application/json", "sha256": "0" * 64}
            for index in range(declared)
        ]
        full["entryPath"] = full["assets"][0]["path"]
        full.pop("portraitPath", None)
        self.assertEqual(list(Draft202012Validator(schema, format_checker=FormatChecker()).iter_errors(full)), [])
        self.assertLessEqual(len(json.dumps(full, separators=(",", ":")).encode("utf-8")), manifest_bytes)

    def test_motion_table_admits_vrma_only_and_keeps_paths_bounded(self) -> None:
        """DEC-024: motions carry animation into a VRM package without opening it up."""
        schema = json.loads(
            (CONTRACTS / "character-package-manifest-v1.schema.json").read_text(encoding="utf-8")
        )
        fixture = json.loads(
            (CONTRACTS / "fixtures/character-package-vrm-motions.valid.json").read_text(encoding="utf-8")
        )
        validator = Draft202012Validator(schema, format_checker=FormatChecker())

        # A motion may only point at a .vrma; the model itself carries no animation.
        wrong_extension = deepcopy(fixture)
        wrong_extension["motions"][0]["animation"] = "model.vrm"
        self.assertTrue(list(validator.iter_errors(wrong_extension)))

        escaping = deepcopy(fixture)
        escaping["motions"][0]["animation"] = "../outside/idle.vrma"
        self.assertTrue(list(validator.iter_errors(escaping)))

        absolute = deepcopy(fixture)
        absolute["motions"][0]["animation"] = "/tmp/idle.vrma"
        self.assertTrue(list(validator.iter_errors(absolute)))

        bad_name = deepcopy(fixture)
        bad_name["motions"][0]["motion"] = "Idle Dance"
        self.assertTrue(list(validator.iter_errors(bad_name)))

        unknown_field = deepcopy(fixture)
        unknown_field["motions"][0]["duration_ms"] = 7270
        self.assertTrue(list(validator.iter_errors(unknown_field)))


if __name__ == "__main__":
    unittest.main()
