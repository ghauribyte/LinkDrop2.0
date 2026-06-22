# Project Log

## Status (always latest)
- Completion: 20% (Phase 1 + Phase 2 complete)
- Phase: Phase 2 complete, moving to Phase 3 (Security / TLS)
- Active milestone: TLS + device verification (Phase 3)
- Network strategy locked: private Wi-Fi first, router Wi-Fi fallback (Decision 006)
- GUI framework locked: Flutter (Decision 007)
- Engine language locked: Dart (Decision 008)
- File transfer method locked: file-by-file, multi-file supported (Decision 009)

## Completed Work
- Created `broadcaster.dart` and `listener.dart` for UDP discovery (Phase 1)
- Created `sender.dart` and `receiver.dart` for raw TCP file transfer (Phase 2)
- Dart 3.12.2 installed and confirmed working on Ubuntu 24.04
- Tested Phase 2 transfer on loopback (127.0.0.1) — file arrived intact
- Fixed port 7979 already-in-use error during Phase 2 testing

## Current Architecture
See ARCHITECTURE.md. Summary: GUI Layer, Discovery Service, Transfer Engine, Security Module, Network Layer.
Tech stack: Flutter + Dart. Discovery: UDP broadcast. Transfer: TCP sockets (TLS coming in Phase 3).

## Current Tasks
See TASK_BOARD.md.

## Next Recommended Tasks
- Generate self-signed TLS certificates (`openssl req ...`)
- Update `receiver.dart` to use `SecureServerSocket`
- Update `sender.dart` to use `SecureSocket` with cert fingerprint verification
- Test TLS transfer on loopback, then two physical devices

## Session History

### Session 2026-06-20
**Summary:** Set up the docs folder for LinkDrop, an AirDrop-style local file transfer app. Recorded the full plan: requirements, architecture, roadmap, and first decisions. No code written yet.
**Files Modified:** docs/ARCHITECTURE.md, docs/DECISIONS.md, docs/ROADMAP.md, docs/TASK_BOARD.md, docs/PROJECT_LOG.md
**Decisions Made:** 001 (mDNS/UDP discovery), 002 (TCP+TLS transfer), 003 (no login), 004 (no cloud relay), 005 (build CLI first, GUI later)
**Remaining Work:** Pick GUI framework and language, then start Phase 1 (discovery)

### Session 2026-06-20 (update)
**Summary:** Decided the network connection strategy: app tries a private device-to-device Wi-Fi connection first (Android/Windows/Linux), and falls back to the existing router Wi-Fi automatically when private mode isn't possible (always the case on iOS/macOS). Updated ARCHITECTURE.md data flow and Network Layer to reflect this.
**Files Modified:** docs/DECISIONS.md, docs/ARCHITECTURE.md, docs/TASK_BOARD.md
**Decisions Made:** 006 (private Wi-Fi with automatic router fallback)
**Remaining Work:** GUI framework (Flutter recommended, not yet confirmed), language for core engine, folder transfer method

### Session 2026-06-20 (update 2)
**Summary:** Locked Flutter as the GUI framework. Recommended Dart for the engine. Defined Phase 1 build step: plain Dart UDP broadcast/listener scripts, no GUI yet.
**Files Modified:** docs/DECISIONS.md, docs/ARCHITECTURE.md, docs/TASK_BOARD.md, docs/PROJECT_LOG.md
**Decisions Made:** 007 (Flutter as GUI framework)
**Remaining Work:** Confirm Dart for the engine, decide folder transfer method, then start Phase 1

### Session 2026-06-20 (update 3)
**Summary:** Confirmed Dart as engine language and file-by-file transfer method. All planning decisions closed.
**Files Modified:** docs/DECISIONS.md, docs/ARCHITECTURE.md, docs/TASK_BOARD.md, docs/PROJECT_LOG.md
**Decisions Made:** 008 (Dart language), 009 (file-by-file, multi-file support)
**Remaining Work:** Start Phase 1

### Session 2026-06-20 (update 4)
**Summary:** Added Tech Stack section to ARCHITECTURE.md. Documentation clarity only.
**Files Modified:** docs/ARCHITECTURE.md
**Decisions Made:** none
**Remaining Work:** Start Phase 1

### Session 2026-06-20 (Phase 1 Code)
**Summary:** Implemented `broadcaster.dart` and `listener.dart`. Updated TODO.md to check off Phase 1 requirements.
**Files Modified:** broadcaster.dart, listener.dart, docs/TODO.md, docs/PROJECT_LOG.md
**Decisions Made:** none
**Remaining Work:** Phase 2 TCP transfer, finish Dart/Flutter environment setup

### Session 2026-06-20 (Phase 2 + Environment)
**Summary:** Installed Dart 3.12.2 standalone via apt (Flutter download abandoned — 1.4 GB, unnecessary for CLI phases). Implemented `sender.dart` and `receiver.dart` for raw TCP file transfer. Resolved port-in-use error during testing. Phase 2 confirmed working on loopback. Wrote Phase 3 spec into TODO.md.
**Files Modified:** sender.dart, receiver.dart, docs/TODO.md, docs/PROJECT_LOG.md, docs/TASK_BOARD.md
**Decisions Made:** none (all decisions remain as logged)
**Remaining Work:** Phase 3 — add TLS to sender/receiver, implement cert fingerprint verification