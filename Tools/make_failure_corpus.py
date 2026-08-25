#!/usr/bin/env python3
"""Generate `Contracts/failure-states.json` from PRD §7.1.

The 32 named failure states were written as two tables in `docs/PRD.md` and
nowhere else: `FAIL-001`…`FAIL-032` appeared in no contract, no fixture and no
test, so the "32 failure fixtures" the Product Design scheme gate records as
closing G0 rework were a document, not fixtures.

The state list and its cancellation semantics are read out of the PRD rather
than retyped, so the corpus cannot drift from the requirement it encodes. What
*is* authored here is the part the PRD cannot know: whether this repository
currently implements each state, which module owns it, and which test proves it.
`Tests/test_contracts.py` checks both halves — that the corpus still matches the
PRD, and that every test it names exists.

Usage:  python3 Tools/make_failure_corpus.py
"""

from __future__ import annotations

import json
import re
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PRD = ROOT / "docs/PRD.md"
OUT = ROOT / "Contracts/failure-states.json"

ROW = re.compile(r"^\| `([a-zA-Z]+)` \| `(FAIL-\d{3})` \| (.+?) \|$", re.MULTILINE)

# id -> (status, owner, evidence suites, gap)
#
# `implemented` means the product produces this state and a named test holds it
# there. `partial` means some of the declared semantics hold and the rest is
# named in `gap`. `absent` means the feature does not exist; the gap says so
# rather than leaving a reader to infer it.
STATUS: dict[str, tuple[str, str, list[str], str]] = {
    "FAIL-001": ("implemented", "ChatFeature, App", ["ChatSessionControllerTests", "AppModelTests"], ""),
    "FAIL-002": (
        "implemented",
        "App, ChatFeature",
        ["AppModelTests", "SpeechCoordinationTests", "FailureStateTests"],
        "",
    ),
    "FAIL-003": ("implemented", "CompanionCore, App", ["StateOwnerTests", "SpeechCoordinationTests"], ""),
    "FAIL-004": ("implemented", "App", ["VoiceInputTests"], ""),
    "FAIL-005": ("implemented", "App", ["VoiceInputTests"], ""),
    "FAIL-006": (
        "implemented",
        "App",
        ["VoiceInputTests", "SpeechInterruptionTests", "SpeechFailureTests"],
        "",
    ),
    "FAIL-007": (
        "implemented",
        "App",
        ["SpeechInterruptionTests"],
        "",
    ),
    "FAIL-008": ("implemented", "App", ["MemoryProposalTests"], ""),
    "FAIL-009": ("absent", "SyncClient", [], "No sync client, cursor or conflict resolution exists."),
    "FAIL-010": ("absent", "SyncClient, Backend", [], "No account or sign-in exists."),
    "FAIL-011": (
        "implemented",
        "CharacterRuntime",
        ["CharacterPackageInstallerTests", "CharacterPackageValidatorTests"],
        "",
    ),
    "FAIL-012": (
        "implemented",
        "CharacterRuntime, App",
        ["Live2DNativeAdapterTests", "VRMNativeAdapterTests", "AppModelTests"],
        "",
    ),
    "FAIL-013": (
        "implemented",
        "CharacterRuntime, App",
        ["Live2DNativeAdapterTests", "VRMNativeAdapterTests", "AppModelTests"],
        "",
    ),
    "FAIL-014": ("implemented", "CharacterRuntime", ["CharacterPackageInstallerTests"], ""),
    "FAIL-015": ("implemented", "App", ["FailureStateTests"], ""),
    "FAIL-016": (
        "partial",
        "OfflinePack",
        ["RouteProgressEngineTests", "FailureStateTests"],
        "A non-finite or negative accuracy is rejected, but a merely inaccurate fix is only "
        "widened into the off-route allowance rather than refused, and sample age is never "
        "examined. Choosing an accuracy ceiling and a staleness window needs field evidence "
        "(G4), so neither is invented here.",
    ),
    "FAIL-017": (
        "implemented",
        "OfflinePack, App",
        ["PlaceResolverTests", "ArriveAndTellTests"],
        "",
    ),
    "FAIL-018": (
        "partial",
        "OfflinePack, App",
        ["PlaceResolverTests", "ArriveAndTellTests"],
        "A correction applies locally and immediately and survives later readings that disagree "
        "with it, which is the half that protects the user. Apple Maps search is read-only "
        "presentation and is intentionally not a Joi correction service, so there is still no "
        "remote correction case, acknowledgement or pending status to show.",
    ),
    "FAIL-019": ("absent", "MapFeature", [], "No camera capture path exists."),
    "FAIL-020": ("absent", "MapFeature", [], "No photo selection path exists."),
    "FAIL-021": ("absent", "MapFeature, Backend", [], "No visual recognition exists."),
    "FAIL-022": ("implemented", "CompanionCore, App", ["SourceEligibilityTests", "SourceProjectionTests"], ""),
    "FAIL-023": ("implemented", "CompanionCore", ["SourceEligibilityTests"], ""),
    "FAIL-024": (
        "implemented",
        "ChatFeature, App",
        [
            "ChatSessionControllerTests",
            "ChatStallTimeoutTests",
            "NetworkDegradedTests",
            "ReachabilityTests",
        ],
        "",
    ),
    "FAIL-025": (
        "implemented",
        "OfflinePack, App",
        ["TravelPackInstallerTests", "TravelPackImportTests"],
        "",
    ),
    "FAIL-026": (
        "partial",
        "OfflinePack, App",
        ["OfflinePackVerifierTests", "TravelPackInstallerTests", "TravelPackImportTests"],
        "Schema, rights, expiry, per-file hashes, undeclared content and traversal are all "
        "refused, the candidate is sealed only after every check passes, and a refusal leaves "
        "the installed pack untouched. What is missing is a signature: self-declared hashes "
        "prove integrity, not publisher authenticity, so no pack can yet be attributed to "
        "anyone (the same gap DEC-010 records for character packages).",
    ),
    "FAIL-027": (
        "implemented",
        "OfflinePack, App, MapFeature",
        ["RouteProgressEngineTests", "CachedWalkTests", "MapExperienceStateTests"],
        "",
    ),
    "FAIL-028": ("implemented", "App, MapFeature", ["SystemMapHandoffTests"], ""),
    "FAIL-029": (
        "partial",
        "OfflinePack, App",
        ["TravelPackInstallerTests", "TravelPackImportTests", "DataExportTests"],
        "Travel-pack import and local data export are both covered: each knows its exact byte "
        "requirement before anything is written, refuses with required and available, and "
        "leaves what was already installed or already exported untouched. Character-package "
        "import is not covered — its expanded size is only known while streaming, and telling "
        "the user what to free up needs a failure reason carrying both numbers, which widens a "
        "taxonomy the Kotlin core mirrors and the conformance vectors cover.",
    ),
    "FAIL-030": (
        "absent",
        "App",
        [],
        "The current lane is zh-Hans only, so no locale fallback chain is exercised (DEC-007).",
    ),
    "FAIL-031": ("absent", "SyncClient", [], "No remote deletion or tombstone exists."),
    "FAIL-032": (
        "partial",
        "App, CharacterRuntime",
        ["MemoryProposalTests", "CharacterPackageInstallerTests"],
        "Local deletion refuses to report success it cannot verify, for memory records and for "
        "character installations. Remote acknowledgement does not exist, so no 'complete' claim "
        "is possible to block yet.",
    ),
}


def build() -> dict:
    rows = ROW.findall(PRD.read_text(encoding="utf-8"))
    if len(rows) != 32:
        raise SystemExit(f"expected 32 fixture rows in PRD §7.1, found {len(rows)}")

    states = []
    for state, fail_id, cancellation in rows:
        try:
            status, owner, evidence, gap = STATUS[fail_id]
        except KeyError:
            raise SystemExit(f"{fail_id} ({state}) has no authored status") from None
        entry = {
            "id": fail_id,
            "state": state,
            "cancellation": cancellation.strip(),
            "status": status,
            "owner": owner,
            "evidence": evidence,
        }
        if gap:
            entry["gap"] = gap
        states.append(entry)

    return {
        "schema": "joi.failure-states.v1",
        "note": (
            "The 32 named failure states of PRD §7/§7.1 in executable form. Generated from the "
            "PRD by Tools/make_failure_corpus.py; `status` and `evidence` are authored there "
            "because whether the product implements a state is not derivable from the document "
            "that specifies it."
        ),
        "states": states,
    }


def main() -> None:
    corpus = build()
    OUT.write_text(json.dumps(corpus, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    counts = Counter(entry["status"] for entry in corpus["states"])
    print(f"wrote {OUT.relative_to(ROOT)}: {len(corpus['states'])} states")
    for status in ("implemented", "partial", "absent"):
        print(f"  {status:12} {counts[status]}")


if __name__ == "__main__":
    main()
