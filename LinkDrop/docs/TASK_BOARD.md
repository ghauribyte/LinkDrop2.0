# Task Board

## In Progress
_(none)_

## Pending Review
- [ ] **Android: 3 networking/cert bugs fixed, none hardware-verified** (see docs/TASK.md 2026-08-25):
  - INTERNET permission was missing from main/AndroidManifest.xml — release builds had zero network access; presented as "Could not get <device>'s certificate". **This is the reported cert issue.**
  - No MulticastLock — phone could send UDP discovery but often not receive it.
  - CertManager wrote key.pem world-readable (0664 vs openssl's 0600); fixed.
  - Kotlin change still needs `flutter build apk` to compile-verify (flutter analyze doesn't cover Kotlin).
- [ ] Receiving on Android — cert.pem/key.pem now auto-generate in-app via CertManager (basic_utils, Decision 015), verified working over the CLI harness on loopback. Still needs a manual test on a real Android device before this can be marked Done. See docs/TASK.md 2026-08-24.

## Blocked
_(none)_

## Done
- [x] Pick GUI framework → Flutter (Decision 007)
- [x] Pick programming language → Dart (Decision 008)
- [x] Decide folder transfer method → file-by-file (Decision 009)
- [x] Phase 1: broadcaster.dart — UDP broadcast every 2s with name + id
- [x] Phase 1: listener.dart — receive + de-dupe device announcements
- [x] Phase 2: sender.dart — TCP connect, send header + file bytes with progress
- [x] Phase 2: receiver.dart — TCP listen, read header, write file to disk with progress
- [x] Install Dart 3.12.2 on Ubuntu 24.04 (via apt dartlang repo)
- [x] Phase 3: Generate self-signed cert + key pair with openssl
- [x] Phase 3: receiver.dart — SecureServerSocket with cert.pem + key.pem from CLI args
- [x] Phase 3: sender.dart — SecureSocket with SHA-256 cert fingerprint verification
- [x] Phase 3: Add pubspec.yaml with crypto dependency, run dart pub get
- [x] Phase 3: TLS transfer confirmed working on loopback
- [x] Restructure broadcaster/listener/sender/receiver into lib/engine/ classes (callback-based, no print/exit)
- [x] Confirmed restructured code still works: pub get, broadcaster+listener pair, receiver+sender TLS transfer
- [x] Add transfer queueing to FileReceiver (FIFO, one transfer at a time, 5 min timeout)
- [x] Tested two simultaneous senders against one receiver — second one queues, transfers after first finishes, both files intact
- [x] Set up Flutter project scaffold
- [x] Device list screen (shows discovered devices from broadcaster/listener)
- [x] Build CertServer + fetchCert (lib/engine/cert_exchange.dart) — automatic cert exchange over plain TCP
- [x] Wire CertServer into FileReceiver (starts/stops alongside main TLS server)
- [x] Tested fetch_cert_test.dart against live receiver — confirmed valid PEM returned over the network
- [x] Send file flow (file picker → pick device → transfer)
- [x] Accept/reject popup on receiver side
- [x] Fixed receiver-side broadcasting gap — ReceiveScreen now runs DiscoveryBroadcaster + FileReceiver together as one unit
- [x] Progress bar on receiver side (ReceiveScreen shows live progress once accepted)
- [x] Multi-file/folder support — manifest-based protocol, one accept/reject for the whole batch (Decision 013)
- [x] Updated FileSender for multiple files per connection
- [x] Updated FileReceiver with buffered _SocketReader for repeated manifest/header/body reads
- [x] Updated send_screen.dart for multi-select file picking
- [x] Updated receive_screen.dart popup to show batch file list + total size
- [x] Updated CLI sender.dart/receiver.dart for new protocol and batch progress display
- [x] Tested: single-file regression, 3-file batch send, CLI multi-file with new arg order — all passed
- [x] Error handling polish — filename sanitization, manifest/header validation, partial-file cleanup, onRejected vs onError split (Decision 014)
- [x] Android SDK command-line tools installed and configured (cmdline-tools, platform-tools, platforms;android-36, build-tools)
- [x] Resolved Java/Gradle toolchain detection failure (stale Gradle cache after JDK install)
- [x] Bumped compileSdk to 36 in android/app/build.gradle.kts
- [x] Pinned file_picker to 10.3.10 (11.0.0+ has an upstream regression — missing kotlin-android plugin application, breaks GeneratedPluginRegistrant.java compile)
- [x] App successfully built and ran on real Android device (Pixel 7, Android 16/API 36)
- [x] Confirmed phone-to-laptop send over router Wi-Fi — cross-device discovery and TLS transfer both work on Android
- [x] Pause/resume/cancel on the sending side (Decision 017 — in-session scope). Verified with pause_resume_test.dart (byte-identical after resume) and cancel_test.dart (no deadlock, no partial file).
- [x] Linux→Linux hotspot join — HotspotManager.join()/leave() + join_hotspot_screen.dart, completing the host/join pair for router-free transfers.

## Next Up — Phase 5: Polish
- [ ] Transfer history (sent/received log) — the remaining unstarted Phase 5 item
- [ ] Cross-reconnect resume — needs a new decision first; conflicts with Decision 014's partial-file cleanup rule (see Decision 017)

## Next Up — Android Wi-Fi Direct
- [x] Native Kotlin WifiP2pManager implementation
- [x] Flutter platform channel bridge (MethodChannel/EventChannel)
- [x] Runtime permission handling (NEARBY_WIFI_DEVICES on Android 13+, location on older versions)
- [x] Wi-Fi Direct / hotspot wired into the transfer engine (SendScreen.presetDevice — a private-mode link hands its known peer IP straight to FileSender, bypassing UDP discovery)
- [ ] Automatic network-mode selection (Decision 006) — private mode first with router fallback. The private-mode paths now work, but choosing between them is still manual, not automatic.
- [ ] **Untested on real hardware:** no Android device testing this session; Wi-Fi Direct needs two phones, hotspot join needs a second Linux box.