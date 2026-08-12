import json
import re
import unittest
from copy import deepcopy
from pathlib import Path

from jsonschema import Draft202012Validator, FormatChecker


ROOT = Path(__file__).resolve().parents[1]
CONTRACTS = ROOT / "Contracts"


class ContractArtifactTests(unittest.TestCase):
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

    def test_no_visible_chat_copy_bypasses_the_editable_catalog(self) -> None:
        """Every zh-Hans literal in the Chat surface must have a catalog key."""
        catalog = json.loads(
            (ROOT / "JoiMobile/Resources/Localizable.xcstrings").read_text(encoding="utf-8")
        )
        keys = catalog["strings"]
        source = (ROOT / "JoiMobile/App/ChatStageView.swift").read_text(encoding="utf-8")
        # Chinese string literals, with Swift interpolation normalised to %@.
        literals = re.findall(r'"([^"\\\n]*[一-鿿][^"\\\n]*)"', source)
        missing = [
            normalised
            for literal in literals
            if (normalised := re.sub(r"\\\([^)]*\)", "%@", literal)) not in keys
        ]
        self.assertEqual(missing, [], f"chat copy missing from catalog: {missing}")

    def test_schemas_close_security_boundaries(self) -> None:
        for path in CONTRACTS.glob("*.schema.json"):
            schema = json.loads(path.read_text(encoding="utf-8"))
            self.assertFalse(schema.get("additionalProperties", True), path.name)

    def test_fixtures_validate_against_json_schemas(self) -> None:
        pairs = [
            ("character-package-manifest-v1.schema.json", "character-package.valid.json"),
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


if __name__ == "__main__":
    unittest.main()
