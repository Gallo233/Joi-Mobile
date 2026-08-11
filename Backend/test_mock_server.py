import unittest

from mock_server import companion_events, encode_sse, journey_attachment_error, journey_payload_digest


class MockServerTests(unittest.TestCase):
    def test_events_preserve_identity_and_separate_voice(self) -> None:
        request = {
            "requestID": "request",
            "threadID": "thread",
            "sessionID": "session",
            "characterID": "joi",
            "text": "hello",
        }
        events = companion_events(request)
        self.assertEqual([event["threadID"] for event in events], ["thread", "thread"])
        self.assertEqual(events[-1]["contentState"], "acceptedFinal")
        self.assertNotEqual(events[-1]["displayText"], events[-1]["voiceLine"])

    def test_sse_has_stable_ids_and_terminal_separator(self) -> None:
        payload = encode_sse(
            companion_events(
                {
                    "requestID": "request",
                    "threadID": "thread",
                    "sessionID": "session",
                    "characterID": "joi",
                    "text": "hello",
                }
            )
        )
        self.assertIn(b"id: request-done", payload)
        self.assertTrue(payload.endswith(b"\n\n"))

    def test_journey_attachment_fails_closed_without_receipt(self) -> None:
        request = {
            "requestID": "request",
            "threadID": "thread",
            "sessionID": "session",
            "characterID": "joi",
            "text": "hello",
            "journeyAttachment": {"placeID": "place"},
        }
        self.assertEqual(journey_attachment_error(request), "journey_receipt_required")

    def test_journey_receipt_rejects_identity_and_revocation(self) -> None:
        attachment = {
            "journeyID": "journey",
            "placeID": "place",
            "routeID": "route",
            "stopID": None,
            "coordinate": {"latitude": 31.2304, "longitude": 121.4737},
            "horizontalAccuracyMeters": 8,
            "observedAt": "2027-01-15T08:00:00Z",
            "routeProgress": 0.5,
            "identityConfidence": 0.9,
            "sourceRevisionIDs": ["source-v1"],
            "consentScope": "chatOneTurn",
        }
        request = {
            "requestID": "request",
            "threadID": "thread",
            "journeyAttachment": attachment,
            "journeyReceipt": {
                "receiptID": "receipt",
                "purpose": "chatOneTurn",
                "userAction": "share",
                "payloadDigest": journey_payload_digest(attachment),
                "precision": "place",
                "threadID": "other-thread",
                "requestID": "request",
                "issuedAt": "2026-08-11T00:00:00Z",
                "expiresAt": "2099-08-11T00:00:00Z",
                "revoked": False,
            },
        }
        self.assertEqual(journey_attachment_error(request), "journey_receipt_identity_mismatch")
        request["journeyReceipt"]["threadID"] = "thread"
        request["journeyReceipt"]["revoked"] = True
        self.assertEqual(journey_attachment_error(request), "journey_receipt_revoked")

    def test_journey_receipt_rejects_digest_mismatch(self) -> None:
        attachment = {
            "placeID": "place",
            "sourceRevisionIDs": [],
            "consentScope": "chatOneTurn",
        }
        request = {
            "requestID": "request",
            "threadID": "thread",
            "journeyAttachment": attachment,
            "journeyReceipt": {
                "receiptID": "receipt",
                "purpose": "chatOneTurn",
                "userAction": "share",
                "payloadDigest": "0" * 64,
                "precision": "place",
                "threadID": "thread",
                "requestID": "request",
                "issuedAt": "2026-08-11T00:00:00Z",
                "expiresAt": "2099-08-11T00:00:00Z",
                "revoked": False,
            },
        }
        self.assertEqual(journey_attachment_error(request), "journey_receipt_digest_mismatch")


if __name__ == "__main__":
    unittest.main()
