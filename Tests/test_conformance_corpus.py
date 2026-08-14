"""Guards on Contracts/conformance/.

These vectors are only worth anything if they stay well-formed, stay in sync
with the generator, and keep naming codes that actually exist. Everything here
is a property of the corpus itself; whether an implementation satisfies it is
checked by that implementation's own suite, in Swift and in Kotlin.
"""

import json
import re
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONFORMANCE = ROOT / "Contracts/conformance"

sys.path.insert(0, str(ROOT / "Tools"))
import make_conformance_corpus  # noqa: E402

IMPORT_CODE_SOURCE = (
    ROOT / "Packages/CharacterRuntime/Sources/CharacterRuntime/CharacterPackageInstaller.swift"
)


def load(name: str) -> dict:
    return json.loads((CONFORMANCE / name).read_text(encoding="utf-8"))


def stable_import_codes() -> set[str]:
    """The closed set of import codes, read from the Swift declaration."""
    source = IMPORT_CODE_SOURCE.read_text(encoding="utf-8")
    block = re.search(
        r"public enum CharacterPackageImportCode: String[^{]*\{(.*?)\n\}", source, re.S
    )
    assert block, "CharacterPackageImportCode declaration not found"
    return set(re.findall(r"^\s*case (\w+)", block.group(1), re.M))


class CorpusShapeTests(unittest.TestCase):
    def test_every_corpus_file_parses_and_declares_its_schema(self) -> None:
        files = sorted(CONFORMANCE.glob("*.json"))
        self.assertEqual(
            {path.name for path in files},
            {"content-id.json", "manifest-validation.json", "sse-framing.json", "strict-json.json"},
        )
        for path in files:
            with self.subTest(path=path.name):
                document = json.loads(path.read_text(encoding="utf-8"))
                self.assertTrue(document["schema"].startswith("joi.conformance."))
                self.assertTrue(document["description"])
                self.assertGreaterEqual(len(document["cases"]), 8)

    def test_case_ids_are_unique_within_each_file(self) -> None:
        for path in sorted(CONFORMANCE.glob("*.json")):
            ids = [case["id"] for case in json.loads(path.read_text(encoding="utf-8"))["cases"]]
            with self.subTest(path=path.name):
                self.assertEqual(len(ids), len(set(ids)))

    def test_content_id_file_matches_its_generator(self) -> None:
        """A hand-edited digest is a fabricated one, so the file must round-trip."""
        generated = json.dumps(make_conformance_corpus.build(), indent=2, ensure_ascii=False) + "\n"
        self.assertEqual(
            (CONFORMANCE / "content-id.json").read_text(encoding="utf-8"),
            generated,
            "content-id.json is stale; run python3 Tools/make_conformance_corpus.py",
        )

    def test_content_id_vectors_are_well_formed(self) -> None:
        cases = load("content-id.json")["cases"]
        for case in cases:
            with self.subTest(case=case["id"]):
                self.assertRegex(case["contentID"], r"^sha256:[a-f0-9]{64}$")
                paths = [entry["path"] for entry in case["files"]]
                self.assertEqual(len(paths), len(set(paths)))
                for path in paths:
                    self.assertFalse(path.startswith("/"))
                    self.assertNotIn("..", path.split("/"))
                # A vector the implementation is known to fail must say why.
                if case.get("normative") is False:
                    self.assertTrue(case["finding"])

    def test_the_empty_and_reordered_trees_behave_as_the_rule_requires(self) -> None:
        """Two properties worth stating twice: an empty tree still has an
        identity, and authoring order never changes one."""
        cases = {case["id"]: case for case in load("content-id.json")["cases"]}
        self.assertEqual(cases["empty-tree"]["files"], [])
        self.assertEqual(cases["nested-paths"]["contentID"], cases["order-independence"]["contentID"])
        self.assertNotEqual(cases["empty-tree"]["contentID"], cases["single-file"]["contentID"])

    def test_document_vectors_only_expect_codes_that_exist(self) -> None:
        codes = stable_import_codes()
        self.assertIn("invalidManifest", codes)
        used = set()
        for name in ("strict-json.json", "manifest-validation.json"):
            for case in load(name)["cases"]:
                with self.subTest(case=f"{name}/{case['id']}"):
                    self.assertIsInstance(case["document"], str)
                    if case["expect"] != "accept":
                        self.assertIn(case["expect"], codes)
                        used.add(case["expect"])
        self.assertEqual(used, {"invalidManifest", "unsupportedLegacy"})

    def test_manifest_vectors_cover_both_envelopes_and_both_outcomes(self) -> None:
        cases = load("manifest-validation.json")["cases"]
        outcomes = {case["expect"] for case in cases}
        self.assertEqual(outcomes, {"accept", "invalidManifest", "unsupportedLegacy"})
        self.assertGreaterEqual(sum(1 for case in cases if case["expect"] == "accept"), 3)
        self.assertGreaterEqual(
            sum(1 for case in cases if case.get("envelope") == "legacy"), 8
        )

    def test_strict_json_vectors_pin_the_duplicate_key_rule(self) -> None:
        """The rule that motivated an owned scanner must stay covered."""
        cases = {case["id"]: case for case in load("strict-json.json")["cases"]}
        for case_id in ("duplicate-key-adjacent", "duplicate-key-nested", "duplicate-key-separated"):
            self.assertEqual(cases[case_id]["expect"], "invalidManifest")
        self.assertEqual(cases["same-key-different-objects"]["expect"], "accept")
        self.assertEqual(cases["depth-64"]["expect"], "accept")
        self.assertEqual(cases["depth-65"]["expect"], "invalidManifest")

    def test_sse_vectors_are_well_formed_and_keep_the_two_event_case(self) -> None:
        cases = load("sse-framing.json")["cases"]
        for case in cases:
            with self.subTest(case=case["id"]):
                has_text = "chunks" in case
                has_binary = "chunksBase64" in case
                self.assertTrue(has_text != has_binary, "exactly one chunk encoding")
                self.assertIsInstance(case["payloads"], list)
        by_id = {case["id"]: case for case in cases}
        self.assertEqual(len(by_id["two-events"]["payloads"]), 2)
        self.assertEqual(by_id["empty-data-value"]["payloads"], [])

    def test_the_manifest_schema_still_accepts_every_accepted_document(self) -> None:
        """The corpus covers what the schema cannot, so it must not contradict
        it: a document admitted here has to satisfy the shape contract too."""
        from jsonschema import Draft202012Validator, FormatChecker

        schema = json.loads(
            (ROOT / "Contracts/character-package-manifest-v1.schema.json").read_text(encoding="utf-8")
        )
        validator = Draft202012Validator(schema, format_checker=FormatChecker())
        for case in load("manifest-validation.json")["cases"]:
            if case["expect"] != "accept":
                continue
            with self.subTest(case=case["id"]):
                self.assertEqual(list(validator.iter_errors(json.loads(case["document"]))), [])


if __name__ == "__main__":
    unittest.main()
