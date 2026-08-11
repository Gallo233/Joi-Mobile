#!/usr/bin/env python3
"""Local-only Joi Mobile contract mock. It has no provider keys or persistence."""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from datetime import datetime, timezone
from typing import Any


def companion_events(request: dict[str, Any]) -> list[dict[str, Any]]:
    common = {
        "schema": "joi.companion-event.v1",
        "requestID": request["requestID"],
        "threadID": request["threadID"],
        "sessionID": request["sessionID"],
        "characterID": request["characterID"],
        "timestamp": "2026-08-11T00:00:00Z",
        "sources": [],
        "errorCode": None,
    }
    return [
        {
            **common,
            "eventID": f"{request['requestID']}-received",
            "phase": "received",
            "contentState": "acceptedInput",
            "displayText": request["text"],
            "voiceLine": None,
            "memoryEligibility": "none",
        },
        {
            **common,
            "eventID": f"{request['requestID']}-done",
            "phase": "done",
            "contentState": "acceptedFinal",
            "displayText": "这是来自官方代理边界的本地模拟回复。",
            "voiceLine": "这是本地模拟回复。",
            "memoryEligibility": "proposalAllowed",
        },
    ]


def encode_sse(events: list[dict[str, Any]]) -> bytes:
    frames = []
    for event in events:
        frames.append(f"id: {event['eventID']}\nevent: companion\ndata: {json.dumps(event, ensure_ascii=False)}\n\n")
    return "".join(frames).encode("utf-8")


def journey_payload_digest(attachment: dict[str, Any]) -> str:
    def encoded(value: Any) -> str:
        if value is None:
            return "-"
        return base64.b64encode(str(value).encode("utf-8")).decode("ascii")

    def number(value: Any, decimals: int) -> str:
        if value is None:
            return "-"
        return f"{float(value):.{decimals}f}"

    coordinate = attachment.get("coordinate") or {}
    observed_at = attachment.get("observedAt")
    if observed_at is None:
        observed_milliseconds = "-"
    else:
        parsed = datetime.fromisoformat(str(observed_at).replace("Z", "+00:00"))
        observed_milliseconds = str(round(parsed.timestamp() * 1_000))
    fields = [
        "joi.journey-context-digest.v1",
        encoded(attachment.get("journeyID")),
        encoded(attachment.get("placeID")),
        encoded(attachment.get("routeID")),
        encoded(attachment.get("stopID")),
        number(coordinate.get("latitude"), 8),
        number(coordinate.get("longitude"), 8),
        number(attachment.get("horizontalAccuracyMeters"), 3),
        observed_milliseconds,
        number(attachment.get("routeProgress"), 6),
        number(attachment.get("identityConfidence"), 6),
        ".".join(encoded(value) for value in attachment.get("sourceRevisionIDs", [])),
        encoded(attachment.get("consentScope")),
    ]
    return hashlib.sha256("\n".join(fields).encode("utf-8")).hexdigest()


def journey_attachment_error(request: dict[str, Any]) -> str | None:
    attachment = request.get("journeyAttachment")
    receipt = request.get("journeyReceipt")
    if attachment is None and receipt is None:
        return None
    if attachment is None or not isinstance(receipt, dict):
        return "journey_receipt_required"
    required = {
        "receiptID", "purpose", "userAction", "payloadDigest", "precision",
        "threadID", "requestID", "issuedAt", "expiresAt", "revoked",
    }
    if not required.issubset(receipt):
        return "journey_receipt_invalid"
    if receipt["purpose"] != "chatOneTurn" or not receipt["userAction"]:
        return "journey_receipt_invalid"
    if receipt["threadID"] != request.get("threadID") or receipt["requestID"] != request.get("requestID"):
        return "journey_receipt_identity_mismatch"
    if receipt["revoked"] is not False:
        return "journey_receipt_revoked"
    try:
        expires_at = datetime.fromisoformat(receipt["expiresAt"].replace("Z", "+00:00"))
    except (AttributeError, TypeError, ValueError):
        return "journey_receipt_invalid"
    if expires_at <= datetime.now(timezone.utc):
        return "journey_receipt_expired"
    digest = receipt["payloadDigest"]
    if not isinstance(digest, str) or len(digest) != 64:
        return "journey_receipt_invalid"
    try:
        if digest != journey_payload_digest(attachment):
            return "journey_receipt_digest_mismatch"
    except (AttributeError, TypeError, ValueError):
        return "journey_receipt_invalid"
    return None


class MockHandler(BaseHTTPRequestHandler):
    server_version = "JoiMobileMock/0.1"

    def do_GET(self) -> None:  # noqa: N802
        if self.path != "/health":
            self.send_error(HTTPStatus.NOT_FOUND)
            return
        self._json(HTTPStatus.OK, {"status": "ok", "persistence": False})

    def do_POST(self) -> None:  # noqa: N802
        request = self._read_json()
        if request is None:
            return
        if self.path == "/v1/chat/streams":
            required = {"requestID", "threadID", "sessionID", "characterID", "text"}
            if not required.issubset(request):
                self._json(HTTPStatus.BAD_REQUEST, {"code": "invalid_request"})
                return
            if error_code := journey_attachment_error(request):
                self._json(HTTPStatus.BAD_REQUEST, {"code": error_code})
                return
            payload = encode_sse(companion_events(request))
            self.send_response(HTTPStatus.OK)
            self.send_header("Content-Type", "text/event-stream; charset=utf-8")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
            return
        if self.path == "/v1/routes":
            self._json(HTTPStatus.OK, {"routeID": "mock-walk", "mode": "walking", "provider": "mock"})
            return
        if self.path in {"/v1/sync/push", "/v1/sync/pull"}:
            self._json(HTTPStatus.OK, {"records": [], "cursor": "mock-cursor"})
            return
        self.send_error(HTTPStatus.NOT_FOUND)

    def log_message(self, format: str, *args: object) -> None:
        # Avoid request-body logging; only the standard status line is emitted.
        super().log_message(format, *args)

    def _read_json(self) -> dict[str, Any] | None:
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            length = 0
        if length <= 0 or length > 64 * 1024:
            self._json(HTTPStatus.BAD_REQUEST, {"code": "invalid_length"})
            return None
        try:
            value = json.loads(self.rfile.read(length))
        except (json.JSONDecodeError, UnicodeDecodeError):
            self._json(HTTPStatus.BAD_REQUEST, {"code": "invalid_json"})
            return None
        if not isinstance(value, dict):
            self._json(HTTPStatus.BAD_REQUEST, {"code": "invalid_request"})
            return None
        return value

    def _json(self, status: HTTPStatus, value: dict[str, Any]) -> None:
        payload = json.dumps(value).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8787)
    args = parser.parse_args()
    ThreadingHTTPServer((args.host, args.port), MockHandler).serve_forever()


if __name__ == "__main__":
    main()
