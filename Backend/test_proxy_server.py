import json
import unittest
from pathlib import Path

import proxy_server
from proxy_server import (
    ERROR_UPSTREAM_MALFORMED,
    ERROR_UPSTREAM_UNAVAILABLE,
    UpstreamError,
    companion_events,
    encode_frame,
)

ROOT = Path(__file__).resolve().parents[1]

REQUEST = {
    "requestID": "r1",
    "threadID": "t1",
    "sessionID": "s1",
    "characterID": "c1",
    "text": "你好",
}


def failing_deltas(code):
    yield "开始"
    raise UpstreamError(code)


class CompanionEventMappingTests(unittest.TestCase):
    def test_turn_starts_with_accepted_input_and_ends_with_accepted_final(self) -> None:
        events = list(companion_events(REQUEST, ["你", "好", "呀"]))
        self.assertEqual(events[0]["contentState"], "acceptedInput")
        self.assertEqual(events[0]["displayText"], "你好")
        self.assertEqual(events[0]["memoryEligibility"], "none")
        self.assertEqual(events[-1]["contentState"], "acceptedFinal")
        self.assertEqual(events[-1]["phase"], "done")
        self.assertEqual(events[-1]["displayText"], "你好呀")
        self.assertEqual(events[-1]["memoryEligibility"], "proposalAllowed")

    def test_drafts_are_cumulative_replaceable_projections(self) -> None:
        drafts = [e for e in companion_events(REQUEST, ["你", "好", "呀"])
                  if e["contentState"] == "streamingDraft"]
        self.assertEqual([d["displayText"] for d in drafts], ["你", "你好", "你好呀"])
        for draft in drafts:
            self.assertEqual(draft["memoryEligibility"], "none")
            self.assertEqual(draft["phase"], "thinking")

    def test_every_event_echoes_the_request_identity(self) -> None:
        for event in companion_events(REQUEST, ["ok"]):
            self.assertEqual(event["requestID"], "r1")
            self.assertEqual(event["threadID"], "t1")
            self.assertEqual(event["sessionID"], "s1")
            self.assertEqual(event["characterID"], "c1")
            self.assertEqual(event["schema"], "joi.companion-event.v1")

    def test_event_ids_are_unique_so_the_client_appends_once(self) -> None:
        ids = [e["eventID"] for e in companion_events(REQUEST, ["a", "b", "c"])]
        self.assertEqual(len(ids), len(set(ids)))

    def test_upstream_failure_mid_stream_ends_as_failed_not_accepted(self) -> None:
        events = list(companion_events(REQUEST, failing_deltas(ERROR_UPSTREAM_UNAVAILABLE)))
        self.assertEqual(events[-1]["contentState"], "failed")
        self.assertEqual(events[-1]["phase"], "failed")
        self.assertEqual(events[-1]["errorCode"], ERROR_UPSTREAM_UNAVAILABLE)
        self.assertIsNone(events[-1]["displayText"])
        # A partial draft must never be promoted to an accepted final line.
        self.assertNotIn("acceptedFinal", [e["contentState"] for e in events])

    def test_empty_upstream_answer_is_a_failure_not_an_empty_success(self) -> None:
        for deltas in ([], ["   "], ["\n"]):
            events = list(companion_events(REQUEST, deltas))
            self.assertEqual(events[-1]["contentState"], "failed", deltas)
            self.assertEqual(events[-1]["errorCode"], ERROR_UPSTREAM_MALFORMED, deltas)

    def test_frames_are_blank_line_delimited_sse(self) -> None:
        frame = encode_frame(next(iter(companion_events(REQUEST, ["a"])))).decode("utf-8")
        self.assertTrue(frame.startswith("id: r1-received\n"))
        self.assertIn("event: companion\n", frame)
        self.assertTrue(frame.endswith("\n\n"))
        # Exactly one data line, so the client's framer sees one JSON payload.
        self.assertEqual(len([line for line in frame.split("\n") if line.startswith("data:")]), 1)


class ProviderConfidentialityTests(unittest.TestCase):
    def test_no_client_visible_field_names_the_provider_or_model(self) -> None:
        payload = json.dumps(
            list(companion_events(REQUEST, ["hi"]))
            + list(companion_events(REQUEST, failing_deltas(ERROR_UPSTREAM_UNAVAILABLE))),
            ensure_ascii=False,
        ).lower()
        for secret in ("deepseek", "api.deepseek.com", "bearer", "sk-", proxy_server.UPSTREAM_MODEL):
            self.assertNotIn(secret.lower(), payload)

    def test_error_codes_are_stable_and_provider_independent(self) -> None:
        self.assertEqual(
            {ERROR_UPSTREAM_UNAVAILABLE, ERROR_UPSTREAM_MALFORMED, proxy_server.ERROR_UPSTREAM_REJECTED},
            {"upstream_unavailable", "upstream_malformed", "upstream_rejected"},
        )

    def test_no_provider_key_is_committed_anywhere_in_the_repository(self) -> None:
        """The key belongs in the environment only, never in a tracked file."""
        import subprocess

        tracked = subprocess.run(
            ["git", "ls-files"], cwd=ROOT, capture_output=True, text=True, check=True
        ).stdout.split()
        for name in tracked:
            path = ROOT / name
            if not path.is_file() or path.suffix in {".png", ".vrm", ".moc3"}:
                continue
            try:
                content = path.read_text(encoding="utf-8")
            except (UnicodeDecodeError, OSError):
                continue
            # A real DeepSeek key is "sk-" plus 32 hex characters. The literal
            # prefix may appear in policy text; an actual key must not.
            import re

            self.assertIsNone(
                re.search(r"sk-[0-9a-f]{32}", content),
                f"provider key literal found in tracked file {name}",
            )

    def test_proxy_refuses_to_start_without_a_key_instead_of_faking_success(self) -> None:
        import os

        previous = os.environ.pop("DEEPSEEK_API_KEY", None)
        try:
            with self.assertRaises(SystemExit):
                proxy_server.api_key()
        finally:
            if previous is not None:
                os.environ["DEEPSEEK_API_KEY"] = previous


if __name__ == "__main__":
    unittest.main()
