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

## Decision 012
Date: 2026-06-22
Topic: Accept/reject before file write
Decision: FileReceiver gained an optional onIncomingRequest(filename, size, senderIp) callback, awaited after the header is parsed but before any bytes are written to disk. Returning false closes the connection with nothing written. If not provided, behavior is unchanged (auto-accept) — so the CLI receiver.dart needed zero changes. A 60-second timeout auto-rejects if nobody responds, so a sender isn't stuck waiting forever.
Reason: A real receiving device should let the person decide whether to accept an incoming file, not write it blindly. Decision 003 already established no-login trust-by-fingerprint; this adds the human-in-the-loop step the original CLI never had.
Consequences: Bytes arriving in the same network chunk as the header tail must be held in memory until the decision is made, instead of being written immediately — small added complexity in FileReceiver, but contained to one method.

## Decision 013
Date: 2026-06-22
Topic: Multi-file transfer protocol
Decision: A single connection now sends a manifest first (file count + list of {name, size}), followed by each file's existing length-prefixed header + bytes, one after another, in order. One accept/reject decision covers the entire batch — no per-file prompts. A single-file send is just a manifest with one entry, so there's no special case for the old Phase 2/3 behavior.
Reason: Implements Decision 009 (file-by-file, multi-file queue support) at the protocol level. One accept/reject for the whole batch matches the "1-2 clicks" goal in ROADMAP.md rather than prompting once per file.
Consequences: Breaking change to the wire protocol — old single-file-only sender/receiver code cannot talk to the new manifest-based code. CLI sender.dart's argument order changed (cert now comes before the file list, since the file list is variable-length: `dart sender.dart <ip> <cert> <file1> [file2]...`). FileReceiver's internal parsing logic got meaningfully more complex (a small buffered _SocketReader helper was added to support reading repeated length-prefixed chunks off one stream).

## Decision 014
Date: 2026-06-22
Topic: Receiver error handling hardening
Decision: Added filename sanitization (strip path separators and ".." to prevent path traversal writes outside targetDir), manifest/header field validation (reject malformed JSON instead of throwing raw exceptions), partial-file cleanup on write failure or early disconnect (delete instead of leaving a corrupt file behind), and a separate onRejected callback distinct from onError — onError now means a true failure (bad network, disk full, malformed protocol); onRejected means an expected non-error outcome (user declined, queue timeout, sender disconnected early).
Reason: Multi-file manifest protocol (Decision 013) increased failure surface area — more round trips, more files that can individually fail mid-batch. A receiver should never trust a filename from the network as-is, never leave broken partial files on disk, and a GUI needs to tell "something went wrong" apart from "the user said no."
Consequences: onIncomingRequest callers (ReceiveScreen, future GUI code) must wire onRejected separately or those messages go nowhere silently. CLI receiver.dart updated to print onRejected the same way as onError, no behavior change there.

# Decision 014
Date: 2026-06-23
Topic: Target platform scope
Decision: Linux and Android only. iOS, Windows, macOS deferred.
Reason: Faster iteration, avoid iOS socket restrictions.
Consequences: Decision 007 partially superseded.

## Decision 015
Date: 2026-06-23
Topic: Cert generation on Android
Decision: Generate self-signed cert in-app using Dart (basic_utils package)
instead of requiring openssl CLI.
Reason: Android has no openssl. Users can't run terminal commands.
Consequences: Adds basic_utils dependency. Cert generated once on
first launch, stored in app documents dir.

## Decision 016
Date: 2026-08-24
Topic: Planned future platform: Windows
Decision: Windows support is planned as a future third platform, added after Linux+Android private-mode networking (Wi-Fi Direct + hotspot) is wired into the Transfer Engine and the Android cert-generation blocker is resolved. Not started yet — no code changes as of this entry.
Reason: The engine/discovery/security layers (lib/engine/) are already cross-platform Dart with no Windows-specific gap, and the Flutter GUI already builds for Windows from the existing scaffold. The only missing piece is a Windows equivalent of the private-mode connection managers (hotspot_manager.dart uses Linux's nmcli; Android uses native WifiP2pManager) — likely a native plugin around Windows' Mobile Hotspot / WlanHostedNetwork APIs. Router-mode fallback would work immediately with no new code. Sequencing after Linux+Android are solid avoids maintaining three half-finished platforms at once (Decision 014).
Consequences: Decision 014's Linux+Android scope stays authoritative until this is picked up. When work starts, add a `hotspot_manager`-equivalent for Windows behind the same private-mode interface, plus GUI platform gating (see HotspotEntryPoint's Platform.isLinux check) extended to Windows.

## Decision 017
Date: 2026-08-25
Topic: Pause/resume scope — in-session only, no cross-reconnect resume
Decision: Pause/resume is implemented purely sender-side, by gating the byte feed into the socket (FileSender.pause/resume/cancel). The connection, the TLS session, and the whole batch stay open across a pause; the receiver simply blocks on a read that isn't producing bytes yet. The wire protocol (Decision 013) is unchanged. Resuming a transfer across a *dropped connection* is explicitly NOT implemented.
Reason: In-session pause covers the actual user-facing need ("stop this transfer, continue it in a minute") with no protocol change and no new failure modes. Cross-reconnect resume would require negotiating a per-file byte offset in the protocol, and — more importantly — it directly conflicts with the Decision 014 receiver invariant that partial files are deleted on early disconnect. Keeping a partial file around to resume into is exactly what that invariant forbids, so supporting it is a real architectural tradeoff (resumability vs. never leaving a corrupt file on disk) that deserves its own decision rather than being smuggled in as an implementation detail.
Consequences: A pause survives arbitrarily long but not a connection drop — if the link dies while paused, the transfer restarts from zero and the receiver cleans up its partial file as usual. Pausing holds the receiver's FIFO transfer slot (Decision 010) for the duration, so a long pause blocks other queued senders; the 5-minute queue timeout applies to *waiting* senders, not to the in-flight paused one. Very long pauses may also hit TCP keepalive/NAT idle timeouts on some networks. If cross-reconnect resume is wanted later, it needs a new decision that revisits the Decision 014 partial-file rule.

Also added in the same change: FileSender.cancel(), because pause without a way to abort leaves a transfer parked on an open socket with no exit. Cancel releases a paused send loop so it can unwind; the receiver sees a normal early disconnect and reports it via onRejected (not onError), matching Decision 014's error/rejection split.

## Decision 018
Date: 2026-09-04
Topic: UI design system, and rendering screens as goldens to verify layout
Decision: Replaced the single-line `ColorScheme.fromSeed` theme with an explicit design system (lib/theme/linkdrop_theme.dart) and rebuilt every screen on a shared LinkDropShell — icon rail, work pane, and a context pane that must carry real content for that screen or be omitted. Layout is verified by rendering screens to PNG under test/goldens/ rather than by reading code. Throughput is now measured (lib/engine/throughput_meter.dart) so the design's rate/ETA readout shows real numbers.
Reason: The previous build centred a min-height column in whatever window it was given, which is what made the desktop look mostly empty — the complaint was structural, not cosmetic, so a palette swap would not have fixed it. Goldens exist because layout bugs are invisible in source: rendering the screens immediately exposed three that code review had missed — every idle state hugging the top-left of a full-height pane, PulseEmptyState left-aligning its ring/headline/subtitle onto three different edges, and the shell pinning action buttons to the pane bottom in contradiction of its own documented contract, stranding a form's submit button far below the last field. A fourth, a reachable null-check crash in HotspotScreen, surfaced the moment that screen could be rendered at all. ThroughputMeter lives in lib/engine/ under Decision 008: it holds no widgets and reports nothing outward, so the same measurement backs the CLI harness and the GUI.
Consequences: Layout changes must be re-goldened (`flutter test test/ui_golden_test.dart --update-goldens`) and the PNGs reviewed, not just accepted. Goldens verify layout, not typography — the test environment has no Inter, so glyphs render as boxes. Inter is deliberately NOT declared in the theme: naming a family with no bundled asset silently falls back to the platform default while the code claims otherwise, so it stays undeclared until the .ttf files are added. Rate and ETA are withheld rather than estimated until the meter has a large enough sample, and while paused; a stalled transfer shows nothing instead of a countdown that keeps ticking. HotspotScreen gained an `autoStart` flag purely so it can be rendered without nmcli reconfiguring the developer's Wi-Fi as a side effect of a screenshot — it is always true in the app.

## Pending Decisions (need to be made before coding starts)
_(none — all core decisions made, ready to continue through the phases)_
