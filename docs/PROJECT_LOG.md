# Project Log

## Status (always latest)
- Completion: 35% (Phase 1 + Phase 2 + Phase 3 complete)
- Phase: Phase 3 complete, moving to Phase 4 (GUI)
- Active milestone: Flutter GUI — device list, send/accept popup, progress bar (Phase 4)
- Network strategy locked: private Wi-Fi first, router Wi-Fi fallback (Decision 006)
- GUI framework locked: Flutter (Decision 007)
- Engine language locked: Dart (Decision 008)
- File transfer method locked: file-by-file, multi-file supported (Decision 009)
- Active milestone: Flutter GUI scaffold setup (Phase 4) — engine code restructured and ready
- Active milestone: Flutter device list screen (Phase 4)
- Active milestone: Send file flow (Phase 4)

## Completed Work
- Created `broadcaster.dart` and `listener.dart` for UDP discovery (Phase 1)
- Created `sender.dart` and `receiver.dart` for raw TCP file transfer (Phase 2)
- Dart 3.12.2 installed and confirmed working on Ubuntu 24.04
- Tested Phase 2 transfer on loopback (127.0.0.1) — file arrived intact
- Fixed port 7979 already-in-use error during Phase 2 testing
- Updated `receiver.dart` to use `SecureServerSocket` with TLS (Phase 3)
- Updated `sender.dart` to use `SecureSocket` with SHA-256 cert fingerprint verification (Phase 3)
- Added `pubspec.yaml` with `crypto: ^3.0.3` dependency (first external dep in project)
- Generated self-signed cert + key pair with openssl, confirmed working
- Tested TLS transfer on loopback — file arrived intact, TLS confirmed active

## Current Architecture
See ARCHITECTURE.md. Summary: GUI Layer, Discovery Service, Transfer Engine, Security Module, Network Layer.
Tech stack: Flutter + Dart. Discovery: UDP broadcast. Transfer: TCP sockets wrapped in TLS (Phase 3 complete).

## Current Tasks
See TASK_BOARD.md.

## Next Recommended Tasks
- Test mismatched cert rejection on loopback (generate a second cert pair, pass wrong cert to sender)
- Test TLS transfer on two physical devices on the same Wi-Fi
- Re-confirm Phase 1 (broadcaster/listener) actually runs on loopback — checked off before Dart was installed
- Begin Phase 4: Flutter GUI (device list, send/accept popup, progress bar)

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

### Session 2026-06-22 (Phase 3 — TLS Implementation)
**Summary:** Implemented Phase 3 TLS + device verification. Updated `receiver.dart` to use `SecureServerSocket` with a `SecurityContext` loaded from `cert.pem` + `key.pem` passed as CLI args. Updated `sender.dart` to use `SecureSocket` with a `SecurityContext` trusting only the receiver's cert; `onBadCertificate` callback computes SHA-256 fingerprint of the presented cert and compares against the fingerprint derived from the cert file on disk — aborts with a clear error on mismatch. Added `pubspec.yaml` with `crypto: ^3.0.3` as the first project dependency. All file transfer logic after the connection is unchanged from Phase 2. Ran `dart pub get` (resolved crypto 3.0.7 + transitive deps collection, typed_data). Generated cert/key pair with openssl. Tested TLS transfer on loopback — confirmed working end-to-end.
**Files Modified:** receiver.dart, sender.dart, pubspec.yaml (new), docs/PROJECT_LOG.md, docs/TASK_BOARD.md, docs/TODO.md
**Decisions Made:** none (implementation follows Decision 002 and Decision 003 as specced)
**Remaining Work:** Test mismatched cert rejection; test on two physical devices; begin Phase 4 (Flutter GUI)

### Session 2026-06-20 (Doc Review)
**Summary:** Reviewed the full repo (all docs + actual code) for consistency. Confirmed `broadcaster.dart`, `listener.dart`, `sender.dart`, `receiver.dart` all match their specs on code review. Found and fixed two gaps: ROADMAP.md status table was stale (still showed all phases "Not started"), and DECISIONS.md was missing Decisions 007-009 even though other docs already treated them as locked. Flagged that Phase 1's "confirmed on loopback" checkbox predates the Dart install, so it may not have been truly tested.
**Files Modified:** docs/ROADMAP.md, docs/DECISIONS.md, docs/PROJECT_LOG.md
**Decisions Made:** none (documentation consistency fixes only)
**Remaining Work:** Re-verify Phase 1 actually runs, then build Phase 3 (TLS + device verification) per TODO.md

### Session 2026-06-22 (Engine Restructure)
**Summary:** Restructured broadcaster.dart, listener.dart, sender.dart, receiver.dart into lib/engine/ classes (DiscoveryBroadcaster, DiscoveryListener, FileSender, FileReceiver) using callbacks instead of print/exit, so the same logic can be called from Flutter later (Decision 008). Added lib/models/device.dart and lib/models/transfer_progress.dart as shared data types. Old CLI files kept at repo root as thin wrappers — same commands and behavior as before. Ran dart pub get, tested broadcaster+listener pair and receiver+sender TLS transfer — confirmed still working end-to-end.
**Files Modified:** broadcaster.dart, listener.dart, sender.dart, receiver.dart, lib/engine/discovery_broadcaster.dart (new), lib/engine/discovery_listener.dart (new), lib/engine/file_sender.dart (new), lib/engine/file_receiver.dart (new), lib/models/device.dart (new), lib/models/transfer_progress.dart (new), docs/TASK_BOARD.md, docs/PROJECT_LOG.md
**Decisions Made:** none (implementation note added under Decision 008, not a new decision)
**Remaining Work:** Begin Phase 4 — Flutter project scaffold

### Session 2026-06-22 (Transfer Queueing)
**Summary:** Added FIFO queueing to FileReceiver so multiple senders connecting at once are handled one transfer at a time instead of running concurrently. TCP connections are still accepted immediately; only the file-write step waits its turn behind a simple chained-Future lock. Added onQueued callback and a 5-minute queue timeout. Updated receiver.dart CLI wrapper to print queue status. Tested with two senders hitting one receiver simultaneously — confirmed correct ordering and both files arrived intact.
**Files Modified:** lib/engine/file_receiver.dart, receiver.dart, docs/DECISIONS.md, docs/TASK_BOARD.md, docs/PROJECT_LOG.md
**Decisions Made:** 010 (sequential transfer queueing on receiver)
**Remaining Work:** Begin Phase 4 — Flutter project scaffold
### Session 2026-06-22 (Flutter Scaffold)
**Summary:** Ran flutter create in the existing repo root. pubspec.yaml had to be merged manually (flutter create skipped it since it already existed) — added flutter SDK dependency, cupertino_icons, flutter_lints, and the flutter: uses-material-design section, while keeping the existing crypto dependency intact. Fixed two dot-shorthand syntax errors in the generated lib/main.dart (colorScheme: .fromSeed and mainAxisAlignment: .center don't compile on this Dart/Flutter version) by spelling out ColorScheme.fromSeed and MainAxisAlignment.center. Ran flutter run targeting Chrome — confirmed the default counter demo app compiles and launches correctly.
**Files Modified:** pubspec.yaml, lib/main.dart, docs/TASK_BOARD.md, docs/PROJECT_LOG.md
**Decisions Made:** none (scaffold setup only, no architecture changes)
**Remaining Work:** Build device list screen, wired to DiscoveryBroadcaster/DiscoveryListener

### Session 2026-06-22 (Device List Screen)
**Summary:** Built lib/screens/device_list_screen.dart, wired directly to the existing DiscoveryBroadcaster and DiscoveryListener engine classes — no new networking logic. Screen starts broadcasting + listening on load, shows discovered devices live in a ListView, disposes both cleanly on screen exit. Replaced the placeholder counter app in lib/main.dart to open this screen on launch. Added a self-filter (skip any discovered device whose id matches the broadcaster's own deviceId) after first test showed the app finding itself, since broadcaster and listener run in the same process. Tested cross-process discovery on Linux desktop: Flutter app's broadcast was picked up correctly by the standalone CLI dart listener.dart, and the CLI's dart broadcaster.dart showed up correctly inside the Flutter app's device list. Confirmed working both directions.
**Files Modified:** lib/main.dart, lib/screens/device_list_screen.dart (new)
**Decisions Made:** none (UI wiring only, no architecture change)
**Remaining Work:** Send file flow — file picker, pick device from this screen, start transfer via FileSender

### Session 2026-06-22 (Automatic Cert Exchange)
**Summary:** Built lib/engine/cert_exchange.dart with two pieces: CertServer (tiny plain-TCP server that serves cert.pem contents to anyone who connects) and fetchCert() (client function that connects to a given IP/port and downloads the cert, with a PEM sanity check). Wired CertServer into FileReceiver so it starts/stops alongside the existing TLS file server, using the same certPath. This closes the gap flagged in TODO.md ("no automatic cert exchange") that was blocking the GUI send flow. Built fetch_cert_test.dart as a standalone CLI test. Tested against a live receiver — confirmed the full valid cert.pem was fetched correctly over the network with no manual file copying.
**Files Modified:** lib/engine/cert_exchange.dart (new), lib/engine/file_receiver.dart, fetch_cert_test.dart (new)
**Decisions Made:** 011 (automatic plain-TCP cert exchange)
**Remaining Work:** Build the actual send file flow in Flutter — file picker → pick device → fetchCert(device.ip) → FileSender