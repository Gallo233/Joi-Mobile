#!/usr/bin/env python3
"""Local stand-in for the official Joi backend proxy.

This process is the only place a provider key may exist. It reads the key from
the environment, never from a file in this repository, and never returns the
key, the provider name or the model name to the client: the app receives
`joi.companion-event.v1` frames and stable error codes only.

    export DEEPSEEK_API_KEY=...        # never commit this
    Backend/.venv/bin/python Backend/proxy_server.py

`mock_server.py` stays the deterministic contract mock used by tests. This file
speaks the same `/v1/chat/streams` contract but answers from a real provider.
"""

from __future__ import annotations

import argparse
import json
import os
import urllib.error
import urllib.request
from collections.abc import Iterable, Iterator
from datetime import datetime, timezone
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any

from mock_server import journey_attachment_error
from voice_profile import VoiceProfile, load_profile

UPSTREAM_URL = "https://api.deepseek.com/chat/completions"
UPSTREAM_MODEL = "deepseek-v4-flash"
UPSTREAM_TIMEOUT_SECONDS = 60
MAXIMUM_PROMPT_CHARACTERS = 8_000

SPEECH_URL = os.environ.get("JOI_SPEECH_URL", "http://127.0.0.1:9880/tts")
SPEECH_TIMEOUT_SECONDS = 180
SPEECH_TEXT_LANGUAGE = os.environ.get("JOI_SPEECH_TEXT_LANG", "ja")
MAXIMUM_SPEECH_CHARACTERS = 400

# The spoken language and the displayed language differ on purpose, so the model
# is asked for both in one turn rather than a second call: one round trip keeps
# the two consistent and the audio close behind the text.
VOICE_DELIMITER = "###JA###"

SYSTEM_PROMPT = (
    "你是 Joi，用户的角色陪伴。语气自然、简洁、克制。"
    "不要假装拥有位置、相机、记忆或网络访问能力。"
    "如果你不确定某个事实，直接说不确定，不要编造来源。"
    "\n\n输出格式要求：先用简体中文写给用户看的回复，"
    f"然后单独一行写 {VOICE_DELIMITER}，"
    "再写这句回复对应的日语口语台词（用于语音合成，只写台词本身，"
    "不要注音、不要罗马字、不要解释）。两部分意思必须一致。"
)

# Stable, provider-independent codes. The client maps these to its own copy; no
# provider name, model name, upstream message or raw trace may appear here.
ERROR_UPSTREAM_UNAVAILABLE = "upstream_unavailable"
ERROR_UPSTREAM_REJECTED = "upstream_rejected"
ERROR_UPSTREAM_MALFORMED = "upstream_malformed"


def api_key() -> str:
    key = os.environ.get("DEEPSEEK_API_KEY", "").strip()
    if not key:
        raise SystemExit(
            "DEEPSEEK_API_KEY is not set. Export it in this shell; do not place it "
            "in any file inside this repository."
        )
    return key


def timestamp() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def upstream_deltas(text: str, key: str) -> Iterator[str]:
    """Yields incremental assistant text from the provider's streaming API.

    Raises `UpstreamError` with a stable code; the provider's own message is
    deliberately not propagated.
    """
    body = json.dumps(
        {
            "model": UPSTREAM_MODEL,
            "stream": True,
            "messages": [
                {"role": "system", "content": SYSTEM_PROMPT},
                {"role": "user", "content": text[:MAXIMUM_PROMPT_CHARACTERS]},
            ],
        }
    ).encode("utf-8")
    request = urllib.request.Request(
        UPSTREAM_URL,
        data=body,
        headers={
            "Authorization": f"Bearer {key}",
            "Content-Type": "application/json",
            "Accept": "text/event-stream",
        },
        method="POST",
    )
    try:
        response = urllib.request.urlopen(request, timeout=UPSTREAM_TIMEOUT_SECONDS)
    except urllib.error.HTTPError as error:
        # 4xx means our request was rejected; 5xx means the provider is down.
        raise UpstreamError(
            ERROR_UPSTREAM_REJECTED if error.code < 500 else ERROR_UPSTREAM_UNAVAILABLE
        ) from None
    except (urllib.error.URLError, TimeoutError, OSError):
        raise UpstreamError(ERROR_UPSTREAM_UNAVAILABLE) from None

    with response:
        for raw in response:
            line = raw.decode("utf-8", errors="replace").strip()
            if not line.startswith("data:"):
                continue
            payload = line[len("data:") :].strip()
            if payload == "[DONE]":
                return
            try:
                chunk = json.loads(payload)
                choices = chunk.get("choices") or [{}]
                delta = (choices[0].get("delta") or {}).get("content")
            except (json.JSONDecodeError, AttributeError, IndexError, TypeError):
                raise UpstreamError(ERROR_UPSTREAM_MALFORMED) from None
            if delta:
                yield delta


class UpstreamError(Exception):
    def __init__(self, code: str) -> None:
        super().__init__(code)
        self.code = code


def split_display_and_voice(answer: str) -> tuple[str, str | None]:
    """Separates the displayed reply from the spoken line.

    A model that ignores the format simply yields no voice line, which stays
    silent rather than speaking the Chinese text with a Japanese voice.
    """
    if VOICE_DELIMITER not in answer:
        return answer.strip(), None
    display, _, voice = answer.partition(VOICE_DELIMITER)
    spoken = voice.strip()
    return display.strip(), (spoken or None)


def synthesize(text: str, emotion: str, profile: VoiceProfile, key: str = "") -> bytes:
    """Returns WAV bytes for one spoken line from the local speech service.

    `key` is unused: the local service needs no credential. It is accepted so the
    caller does not have to special-case this engine.
    """
    take = profile.take(emotion)
    payload = json.dumps(
        {
            "ref_audio_path": str(take.reference_audio),
            "prompt_text": take.prompt_text,
            "prompt_lang": profile.prompt_language,
            "text": text[:MAXIMUM_SPEECH_CHARACTERS],
            "text_lang": SPEECH_TEXT_LANGUAGE,
            "media_type": "wav",
            "streaming_mode": 0,
            "speed_factor": take.speed,
            "seed": int(os.environ.get("JOI_SPEECH_SEED", "20260809")),
            "top_k": 5,
            "top_p": 0.85,
            "temperature": 0.7,
            "repetition_penalty": 1.35,
        }
    ).encode("utf-8")
    request = urllib.request.Request(
        SPEECH_URL,
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=SPEECH_TIMEOUT_SECONDS) as response:
            audio = response.read()
    except urllib.error.HTTPError as error:
        raise UpstreamError(
            ERROR_UPSTREAM_REJECTED if error.code < 500 else ERROR_UPSTREAM_UNAVAILABLE
        ) from None
    except (urllib.error.URLError, TimeoutError, OSError):
        raise UpstreamError(ERROR_UPSTREAM_UNAVAILABLE) from None
    if not audio.startswith(b"RIFF"):
        raise UpstreamError(ERROR_UPSTREAM_MALFORMED)
    return audio


def companion_events(request: dict[str, Any], deltas: Iterable[str]) -> Iterator[dict[str, Any]]:
    """Maps provider deltas onto the frozen companion-event contract.

    The user's own line is echoed as `acceptedInput` because the client appends
    the transcript from accepted events only (DEC-015).
    """
    common = {
        "schema": "joi.companion-event.v1",
        "requestID": request["requestID"],
        "threadID": request["threadID"],
        "sessionID": request["sessionID"],
        "characterID": request["characterID"],
        "sources": [],
        "errorCode": None,
    }
    yield {
        **common,
        "eventID": f"{request['requestID']}-received",
        "phase": "received",
        "contentState": "acceptedInput",
        "displayText": request["text"],
        "voiceLine": None,
        "memoryEligibility": "none",
        "timestamp": timestamp(),
    }

    accumulated: list[str] = []
    try:
        for index, delta in enumerate(deltas, start=1):
            accumulated.append(delta)
            # Drafts show only the displayed half. Once the delimiter arrives the
            # rest is the spoken line, which must not appear as visible text.
            visible, _ = split_display_and_voice("".join(accumulated))
            yield {
                **common,
                "eventID": f"{request['requestID']}-draft-{index}",
                "phase": "thinking",
                "contentState": "streamingDraft",
                "displayText": visible,
                "voiceLine": None,
                "memoryEligibility": "none",
                "timestamp": timestamp(),
            }
    except UpstreamError as error:
        yield {
            **common,
            "eventID": f"{request['requestID']}-failed",
            "phase": "failed",
            "contentState": "failed",
            "displayText": None,
            "voiceLine": None,
            "memoryEligibility": "none",
            "errorCode": error.code,
            "timestamp": timestamp(),
        }
        return

    final, spoken = split_display_and_voice("".join(accumulated))
    if not final:
        yield {
            **common,
            "eventID": f"{request['requestID']}-failed",
            "phase": "failed",
            "contentState": "failed",
            "displayText": None,
            "voiceLine": None,
            "memoryEligibility": "none",
            "errorCode": ERROR_UPSTREAM_MALFORMED,
            "timestamp": timestamp(),
        }
        return

    yield {
        **common,
        "eventID": f"{request['requestID']}-done",
        "phase": "done",
        "contentState": "acceptedFinal",
        "displayText": final,
        # The spoken line is a separate language from the displayed text, so it
        # is carried separately rather than assumed to be the same string. A
        # missing line means the turn stays silent, never spoken in the wrong
        # language.
        "voiceLine": spoken,
        "memoryEligibility": "proposalAllowed",
        "timestamp": timestamp(),
    }


def encode_frame(event: dict[str, Any]) -> bytes:
    return (
        f"id: {event['eventID']}\n"
        f"event: companion\n"
        f"data: {json.dumps(event, ensure_ascii=False)}\n\n"
    ).encode("utf-8")


class ProxyHandler(BaseHTTPRequestHandler):
    server_version = "JoiMobileProxy/0.1"
    # Close-delimited so frames can be flushed as they arrive instead of being
    # buffered behind a Content-Length.
    protocol_version = "HTTP/1.0"

    def do_GET(self) -> None:  # noqa: N802
        if self.path != "/health":
            self.send_error(HTTPStatus.NOT_FOUND)
            return
        self._json(HTTPStatus.OK, {"status": "ok", "persistence": False, "upstream": True})

    def do_POST(self) -> None:  # noqa: N802
        if self.path == "/v1/speech":
            self._speech()
            return
        if self.path != "/v1/chat/streams":
            self.send_error(HTTPStatus.NOT_FOUND)
            return
        request = self._read_json()
        if request is None:
            return
        required = {"requestID", "threadID", "sessionID", "characterID", "text"}
        if not required.issubset(request):
            self._json(HTTPStatus.BAD_REQUEST, {"code": "invalid_request"})
            return
        if not isinstance(request["text"], str) or not request["text"].strip():
            self._json(HTTPStatus.BAD_REQUEST, {"code": "invalid_request"})
            return
        if error_code := journey_attachment_error(request):
            self._json(HTTPStatus.BAD_REQUEST, {"code": error_code})
            return

        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", "text/event-stream; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        deltas = upstream_deltas(request["text"], self.server.api_key)  # type: ignore[attr-defined]
        try:
            for event in companion_events(request, deltas):
                self.wfile.write(encode_frame(event))
                self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError):
            # The client cancelled the turn. Nothing to report.
            return

    def _speech(self) -> None:
        """Synthesises one spoken line. Returns WAV, or a stable code and no audio.

        Failure must never be papered over with a different voice: the client
        keeps the text and stays silent.
        """
        request = self._read_json()
        if request is None:
            return
        text = request.get("text")
        if not isinstance(text, str) or not text.strip():
            self._json(HTTPStatus.BAD_REQUEST, {"code": "invalid_request"})
            return
        emotion = str(request.get("emotion") or "neutral")
        profile: VoiceProfile | None = getattr(self.server, "voice_profile", None)
        if profile is None:
            self._json(HTTPStatus.SERVICE_UNAVAILABLE, {"code": "voice_unavailable"})
            return
        try:
            audio = synthesize(text, emotion, profile)
        except UpstreamError as error:
            self._json(HTTPStatus.BAD_GATEWAY, {"code": error.code})
            return
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", "audio/wav")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(audio)))
        self.end_headers()
        try:
            self.wfile.write(audio)
        except (BrokenPipeError, ConnectionResetError):
            return

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
    server = ThreadingHTTPServer((args.host, args.port), ProxyHandler)
    # Held in memory for the process lifetime only.
    server.api_key = api_key()  # type: ignore[attr-defined]
    # Voice is optional: without a profile the app still chats, and stays silent
    # rather than substituting a different voice.
    try:
        profile = load_profile(os.environ.get("JOI_VOICE_LANG", "ja"))
        server.voice_profile = profile  # type: ignore[attr-defined]
        print(f"voice: {profile.label} [{', '.join(profile.emotions)}]")
    except SystemExit as reason:
        server.voice_profile = None  # type: ignore[attr-defined]
        print(f"voice: disabled ({reason})")
    print(f"Joi proxy on http://{args.host}:{args.port} -> provider streaming enabled")
    server.serve_forever()


if __name__ == "__main__":
    main()
