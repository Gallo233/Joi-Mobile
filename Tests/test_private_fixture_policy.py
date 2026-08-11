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

    def test_character_runtime_keeps_vendor_runtimes_out_of_dependency_graph(self) -> None:
        manifest = (ROOT / "Packages/CharacterRuntime/Package.swift").read_text(
            encoding="utf-8"
        )
        self.assertNotIn(".package(url:", manifest)
        self.assertNotIn("resources:", manifest)
        self.assertNotIn("Cubism", manifest)
        self.assertNotIn("VRMKit", manifest)


if __name__ == "__main__":
    unittest.main()
