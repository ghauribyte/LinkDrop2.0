# Decisions

## Decision 001
Date: 2026-06-20
Topic: Discovery method
Decision: Use mDNS/Bonjour (UDP broadcast as fallback) to find devices on the local network
Reason: Same approach AirDrop uses. No manual setup, no central server needed
Consequences: Both devices must be on the same Wi-Fi/subnet. Some networks block mDNS, so UDP broadcast is the backup

## Decision 002
Date: 2026-06-20
Topic: File transfer protocol
Decision: Use TCP sockets wrapped in TLS for sending files
Reason: TCP is reliable for file data. TLS stops files being read or changed in transit
Consequences: Small overhead from encryption. Need a way to verify the other device (see Decision 003)

## Decision 003
Date: 2026-06-20
Topic: No accounts or login
Decision: The app will not require any account or login
Reason: Keeps it simple — 1-2 clicks to send a file
Consequences: Device trust must be handled another way (e.g. on-screen confirm, pairing code) instead of a login

## Decision 004
Date: 2026-06-20
Topic: No cloud relay
Decision: All transfers go directly over the local network, never through a cloud server
Reason: Faster, more private, no server cost
Consequences: Transfer only works if both devices are on the same network

## Decision 005
Date: 2026-06-20
Topic: Build order
Decision: Build as a command-line tool first (Phases 1-2: discovery + basic transfer). Add the GUI after transfer works
Reason: Easier to debug discovery and transfer without GUI complexity on top
Consequences: GUI work is delayed until Phase 4

## Decision 006
Date: 2026-06-20
Topic: Network connection mode (private Wi-Fi vs router Wi-Fi)
Decision: Try to set up a private device-to-device Wi-Fi connection first (Wi-Fi Direct or app hotspot). If that's not possible on the platform or fails, fall back automatically to the existing Wi-Fi router/LAN. The pick happens automatically — no user action needed
Reason: Gives the best possible speed where supported (Android, Windows, Linux), but still works everywhere, including iOS and macOS, where private Wi-Fi connections aren't allowed for third-party apps
Consequences: Two network code paths to build and test instead of one. Needs a check at connect-time to decide which mode to use. iOS/macOS will always use router Wi-Fi, never private mode

## Decision 007
Date: 2026-06-20
Topic: GUI framework
Decision: Use Flutter for the app (Android, iOS, Windows, macOS, Linux from one codebase)
Reason: Phones are in scope. Electron has no phone support. Flutter is the only option that covers phones and desktop together from one codebase
Consequences: Wi-Fi Direct/hotspot and other low-level networking need small native "plugin" code per platform, wired into Flutter through platform channels

## Decision 008
Date: 2026-06-20
Topic: Programming language for discovery + transfer engine
Decision: Use Dart
Reason: Flutter already requires Dart for the app. Dart's built-in `dart:io` library supports UDP, TCP, and TLS sockets directly, so the same code used for Phase 1-2 (console scripts) drops into the Flutter app later with no rewrite
Consequences: All core networking code is written once, in one language, for every platform
Update 2026-06-22: CLI logic restructured into lib/engine/ classes (callback-based) so Flutter can call it directly with no rewrite, per the original plan.

## Decision 009
Date: 2026-06-20
Topic: Folder/multi-file transfer method
Decision: Send files one by one (file-by-file), not as a zipped folder. User can select multiple files (or a whole folder, sent as its individual files) and they queue up and send one after another over the same connection
Reason: No wait time to zip first, no extra disk space needed, each file gets its own progress, a failed file doesn't block the rest, and pause/resume works per file instead of breaking a whole zip
Consequences: Need a small file list/manifest sent first (names, sizes, count) so the receiver knows what's coming and can show progress per file and overall


## Decision 010
Date: 2026-06-22
Topic: Concurrent transfer handling on the receiver
Decision: When multiple senders connect to one receiver at the same time, transfers are queued and run one at a time, in the order connections arrived (FIFO). TCP connections are still accepted immediately so senders never get connection-refused — only the actual file write waits its turn. A 5-minute queue timeout drops a connection if it waits too long.
Reason: Two transfers writing to disk at once competes for bandwidth and disk I/O, and a future GUI needs a clean "1 of 2" status to show the user — that's only possible if transfers are strictly sequential. Matches the same sequential philosophy as Decision 009 (file-by-file, no zipping).
Consequences: Receiver throughput is capped at one transfer at a time even on fast networks/hardware. A future version could allow limited parallelism if this becomes a real bottleneck, but simple-and-sequential is the right default for now.
---

## Decision 011
Date: 2026-06-22
Topic: Automatic certificate exchange
Decision: Add a small plain-TCP "cert server" (port 7980) alongside the existing secure file-receiving server. Anyone who connects to it receives the receiver's cert.pem contents immediately, no request format needed — connecting IS the request. The sender then computes the fingerprint from this fetched cert and proceeds with the existing TLS fingerprint-check flow (Decision 002/003) unchanged.
Reason: Removes the manual "copy cert.pem to the sender's machine by hand" step, which was blocking the GUI send flow. A public certificate is not sensitive information — handing it out over plain TCP is exactly as safe as putting it on a public webpage. The actual trust decision still happens later, via fingerprint verification at TLS connect time.
Consequences: One more open port per device (7980). Anyone on the network can ask any LinkDrop device for its cert — this is intentional and harmless, same as how AirDrop/Bluetooth pairing works without secrecy of the public key itself.
## Pending Decisions (need to be made before coding starts)
_(none — all core decisions made, ready to continue through the phases)_
