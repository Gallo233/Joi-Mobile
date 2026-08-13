import json
import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class PrivateCharacterFixturePolicyTests(unittest.TestCase):
    def test_private_model_payloads_are_not_tracked(self) -> None:
        output = subprocess.check_output(
            ["git", "ls-files", "-z"], cwd=ROOT
        ).decode("utf-8")
        tracked = [Path(item) for item in output.split("\0") if item]

        forbidden_suffixes = {".moc3", ".vrm", ".vrma"}
        forbidden_parts = {
            ".vrm-lab-assets",
            ".private-character-fixtures",
            "PrivateFixtures",
        }
        violations = [
            str(path)
            for path in tracked
            if path.suffix.lower() in forbidden_suffixes
            or forbidden_parts.intersection(path.parts)
        ]
        self.assertEqual(violations, [])

    def test_private_model_payloads_are_absent_from_reachable_history(self) -> None:
        output = subprocess.check_output(
            ["git", "rev-list", "--objects", "--all"], cwd=ROOT
        ).decode("utf-8")
        paths = [
            Path(line.split(" ", 1)[1])
            for line in output.splitlines()
            if " " in line
        ]
        forbidden_suffixes = {".moc3", ".vrm", ".vrma"}
        self.assertEqual(
            [str(path) for path in paths if path.suffix.lower() in forbidden_suffixes],
            [],
        )

    def test_production_sources_do_not_embed_local_fixture_paths(self) -> None:
        roots = [ROOT / "JoiMobile", ROOT / "Packages"]
        violations: list[str] = []
        for source_root in roots:
            for path in source_root.rglob("*.swift"):
                relative = path.relative_to(source_root)
                if any(part.startswith(".") for part in relative.parts):
                    continue
                text = path.read_text(encoding="utf-8")
                if "/Users/" in text or "New project 2/Joi" in text:
                    violations.append(str(path.relative_to(ROOT)))
        self.assertEqual(violations, [])

    def test_xcodegen_does_not_bundle_private_fixture_roots(self) -> None:
        specification = (ROOT / "project.yml").read_text(encoding="utf-8")
        for forbidden in (
            ".vrm-lab-assets",
            ".private-character-fixtures",
            "PrivateFixtures",
        ):
            with self.subTest(forbidden=forbidden):
                self.assertNotIn(forbidden, specification)

    def test_character_runtime_dependency_graph_allows_only_pinned_zip_container(self) -> None:
        manifest = (ROOT / "Packages/CharacterRuntime/Package.swift").read_text(
            encoding="utf-8"
        )
        self.assertEqual(manifest.count(".package(url:"), 1)
        self.assertIn(
            '.package(url: "https://github.com/weichsel/ZIPFoundation.git", exact: "0.9.20")',
            manifest,
        )
        self.assertNotIn("resources:", manifest)
        self.assertNotIn("Cubism", manifest)
        self.assertNotIn("VRMKit", manifest)

        resolved = json.loads(
            (ROOT / "Packages/CharacterRuntime/Package.resolved").read_text(encoding="utf-8")
        )
        self.assertEqual(len(resolved["pins"]), 1)
        pin = resolved["pins"][0]
        self.assertEqual(pin["identity"], "zipfoundation")
        self.assertEqual(pin["state"]["version"], "0.9.20")
        self.assertEqual(
            pin["state"]["revision"],
            "22787ffb59de99e5dc1fbfe80b19c97a904ad48d",
        )

        notices = (ROOT / "THIRD_PARTY_NOTICES.md").read_text(encoding="utf-8")
        self.assertIn("ZIPFoundation", notices)
        self.assertIn("MIT", notices)

    def test_character_runtime_never_uses_high_level_zip_path_extraction(self) -> None:
        sources = ROOT / "Packages/CharacterRuntime/Sources/CharacterRuntime"
        violations: list[str] = []
        for path in sources.rglob("*.swift"):
            text = path.read_text(encoding="utf-8")
            if "unzipItem(" in text:
                violations.append(str(path.relative_to(ROOT)))
        self.assertEqual(violations, [])

    def test_live2d_sdk_is_never_committed(self) -> None:
        """The Cubism SDK is not redistributable, so no part of it may be tracked."""
        tracked = subprocess.run(
            ["git", "ls-files"], cwd=ROOT, capture_output=True, text=True, check=True
        ).stdout.split()
        forbidden = ("Vendor/", "Live2DCubismCore", "CubismFramework.hpp", ".metallib")
        for name in tracked:
            for pattern in forbidden:
                self.assertNotIn(pattern, name, f"vendored Live2D artefact tracked: {name}")
        self.assertIn("Vendor/", (ROOT / ".gitignore").read_text(encoding="utf-8"))

    def test_default_project_spec_admits_no_vendor_runtime(self) -> None:
        """`project.yml` must still build with no Live2D runtime at all, so a
        clone without the SDK compiles and ships the static fallback."""
        default = (ROOT / "project.yml").read_text(encoding="utf-8")
        for token in ("Live2D", "Cubism", "Vendor/"):
            self.assertNotIn(token, default)
        # The opt-in spec is where admission happens, and it must layer on top of
        # the default rather than replacing it.
        live2d = (ROOT / "project.live2d.yml").read_text(encoding="utf-8")
        self.assertIn("include:", live2d)
        self.assertIn("project.yml", live2d)
        self.assertIn("CSM_TARGET_IPHONE_ES2", live2d)
        # Cubism's Metal renderer uses manual reference counting.
        self.assertIn("-fno-objc-arc", live2d)

    def test_native_runtimes_are_a_spec_ladder_each_rung_buildable(self) -> None:
        """project.yml → live2d → native. Each rung must stay independently
        buildable, so a clone with no SDK at all still ships static fallback."""
        default = (ROOT / "project.yml").read_text(encoding="utf-8")
        for token in ("Live2D", "Cubism", "VRMMetalKit", "Vendor/"):
            self.assertNotIn(token, default)
        live2d = (ROOT / "project.live2d.yml").read_text(encoding="utf-8")
        self.assertIn("project.yml", live2d)
        self.assertNotIn("VRMMetalKit", live2d, "Live2D rung must not require VRM")
        native = (ROOT / "project.native.yml").read_text(encoding="utf-8")
        self.assertIn("project.live2d.yml", native)
        self.assertIn("VRMMetalKit", native)

    def test_vrm_runtime_is_attributed_and_pinned(self) -> None:
        """Apache-2.0 requires attribution, and an unpinned revision would mean
        a different library could build tomorrow under the same review."""
        revision = "8d87fd565c7629881cea980752c9d5518a504c7d"
        notices = (ROOT / "THIRD_PARTY_NOTICES.md").read_text(encoding="utf-8")
        self.assertIn("VRMMetalKit", notices)
        self.assertIn("Apache License 2.0", notices)
        self.assertIn(revision, notices)
        self.assertIn(revision, (ROOT / "Tools/setup_vrm.sh").read_text(encoding="utf-8"))

    def test_character_runtime_still_has_no_native_runtime_dependency(self) -> None:
        """The J1B boundary is unchanged: the bridge lives in the App target, so
        CharacterRuntime and its tests stay free of any vendor runtime."""
        manifest = (ROOT / "Packages/CharacterRuntime/Package.swift").read_text(encoding="utf-8")
        for token in ("Cubism", "Live2DCubismCore", "VRMMetalKit", "Vendor"):
            self.assertNotIn(token, manifest)

    def test_chinese_character_library_copy_remains_in_editable_catalog(self) -> None:
        catalog = json.loads(
            (ROOT / "JoiMobile/Resources/Localizable.xcstrings").read_text(
                encoding="utf-8"
            )
        )
        self.assertEqual(catalog["sourceLanguage"], "zh-Hans")
        keys = catalog["strings"]
        for expected in (
            "安装到本机",
            "设为当前角色",
            "移除只删除此设备上的角色资产，不会删除聊天、记忆或行程。",
        ):
            with self.subTest(expected=expected):
                self.assertIn(expected, keys)


if __name__ == "__main__":
    unittest.main()
