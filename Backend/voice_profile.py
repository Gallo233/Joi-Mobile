#!/usr/bin/env python3
"""Reads the character's voice identity from an existing character package.

The reference clips, their transcripts and their absolute paths are private
data. Nothing here is committed: the profile is located at run time through
`JOI_VOICE_PROFILE`, which points at a character package manifest that already
carries the voice under `localizations.<lang>.voice`. Reading that manifest
directly - rather than copying its values into this repository - keeps one
source of truth and cannot drift from the desktop app.
"""

from __future__ import annotations

import json
import os
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class VoiceTake:
    """One emotion's reference clip and the transcript that describes it.

    The two always travel together. A clip described by the wrong text degrades
    the voice instead of colouring it, so this type has no way to carry one
    without the other.
    """

    reference_audio: Path
    prompt_text: str
    speed: float

    def validate(self) -> None:
        if not self.prompt_text.strip():
            raise ValueError("a reference clip without its transcript is not usable")
        if not self.reference_audio.is_file():
            raise FileNotFoundError("reference clip missing")


@dataclass(frozen=True)
class VoiceProfile:
    label: str
    prompt_language: str
    takes: dict[str, VoiceTake]
    volume: float

    def take(self, emotion: str) -> VoiceTake:
        """Falls back to neutral for an unknown emotion rather than guessing."""
        return self.takes.get(emotion) or self.takes["neutral"]

    @property
    def emotions(self) -> list[str]:
        return sorted(self.takes)


def load_profile(language: str = "ja") -> VoiceProfile:
    raw = os.environ.get("JOI_VOICE_PROFILE", "").strip()
    if not raw:
        raise SystemExit(
            "JOI_VOICE_PROFILE is not set. Point it at a character package "
            "manifest.json that carries the voice identity; do not copy the "
            "voice data into this repository."
        )
    manifest_path = Path(raw).expanduser()
    if not manifest_path.is_file():
        raise SystemExit("JOI_VOICE_PROFILE does not name a readable manifest")

    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    voice = ((manifest.get("localizations") or {}).get(language) or {}).get("voice")
    if not isinstance(voice, dict):
        raise SystemExit(f"manifest carries no {language} voice identity")

    package_root = manifest_path.parent
    default_prompt = str(voice.get("prompt_text") or "")
    default_reference = voice.get("reference_audio")
    prompt_language = str(voice.get("prompt_language") or language)
    default_speed = float(voice.get("speed") or 1.0)

    takes: dict[str, VoiceTake] = {}
    emotion_map = voice.get("emotion_map") or {}
    for emotion, entry in emotion_map.items():
        if not isinstance(entry, dict):
            continue
        reference = entry.get("reference_audio") or default_reference
        prompt = str(entry.get("prompt_text") or default_prompt)
        if not reference or not prompt.strip():
            # Skipped rather than silently paired with a mismatched transcript.
            continue
        take = VoiceTake(
            reference_audio=(package_root / str(reference)),
            prompt_text=prompt,
            speed=float(entry.get("speed") or default_speed),
        )
        try:
            take.validate()
        except (ValueError, FileNotFoundError):
            continue
        takes[emotion] = take

    if "neutral" not in takes:
        if not default_reference or not default_prompt.strip():
            raise SystemExit("manifest has no usable neutral voice take")
        neutral = VoiceTake(
            reference_audio=package_root / str(default_reference),
            prompt_text=default_prompt,
            speed=default_speed,
        )
        neutral.validate()
        takes["neutral"] = neutral

    return VoiceProfile(
        label=str(voice.get("label") or "unnamed"),
        prompt_language=prompt_language,
        takes=takes,
        volume=float(voice.get("volume") or 1.0),
    )
