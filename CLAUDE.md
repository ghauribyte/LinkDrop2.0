# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository layout

The git root is `/home/noor/Linkdrop`, but the Flutter project lives one level down in `LinkDrop/`. **All `flutter`/`dart` commands must be run from `LinkDrop/`, not the git root.**

## Prerequisite: TLS certificate

Nothing that receives files will start without a cert/key pair. They are gitignored (`*.pem`), so a fresh clone must generate them:

```bash
cd LinkDrop
openssl req -x509 -newkey rsa:4096 -keyout key.pem -out cert.pem -days 365 -nodes -subj "/CN=linkdrop"
```

`FileReceiver.start()` returns `false` with an error callback if `cert.pem`/`key.pem` are missing — it does not throw.

## Commands

```bash
cd LinkDrop

flutter pub get
flutter run -d linux              # Linux desktop
flutter run -d <android-device>   # `flutter devices` to list
flutter analyze                   # lint (flutter_lints via analysis_options.yaml)
flutter test                      # all tests
flutter test test/widget_test.dart --plain-name "substring of test name"   # single test
```

### CLI harness (primary debugging loop)

Standalone Dart entry points at `LinkDrop/`'s root drive the engine with no Flutter/GUI in the way. Use these to debug networking rather than launching the app — they were the Phase 1–3 development path (Decision 005) and remain the fastest way to isolate engine behaviour:

```bash
dart receiver.dart <target_dir> cert.pem key.pem
dart sender.dart <receiver_ip> <receiver_cert.pem> <file1> [file2...]   # cert BEFORE file list
dart broadcaster.dart      # announce this device over UDP
dart listener.dart         # print discovered devices
dart fetch_cert_test.dart  # exercise the cert-fetch path
```

Loopback (`127.0.0.1`) works for both sides on one machine.

## Architecture

### Engine/UI split

`lib/engine/` is UI-free and must stay that way. Every engine class reports outward through **optional callbacks** (`onStatus`, `onProgress`, `onError`, …) rather than returning rich results or throwing — this is what lets the same classes back both the CLI harness and the Flutter screens with no rewrite (Decision 008). `lib/screens/` wires those callbacks into `setState`. Preserve this shape when adding engine features.

Engine methods return `bool`/null and report failures via `onError`; they should never call `exit()` or throw to the caller.

### Ports

| Port | Protocol | Purpose |
|---|---|---|
| 6868 | UDP broadcast | Device discovery (name + id, every 2s, de-duped) |
| 7979 | TCP + TLS | File transfer |
| 7980 | TCP plain | Cert server — connecting *is* the request; cert is returned immediately |

### Connect flow (spans several files)

A send is a two-phase connection, which is easy to miss reading any single file:

1. Sender fetches the receiver's `cert.pem` from port **7980** in the clear (`cert_exchange.dart`). A public cert is not secret — this only removes the manual copy step (Decision 011).
2. Sender computes the SHA-256 fingerprint of that cert, connects to **7979** over TLS, and in `onBadCertificate` compares the presented cert's fingerprint against the expected one. Mismatch aborts before any bytes are sent.

Trust is fingerprint-based, not PKI — there are no accounts and no CA (Decision 003).

### Wire protocol (Decision 013)

One connection carries a whole batch:

```
[4-byte BE length][manifest JSON: {type, count, files:[{name,size}]}]
then, per file, in order:
[4-byte BE length][header JSON: {filename, size}][raw file bytes]
```

A single-file send is just a manifest with one entry — there is no separate single-file path. `FileReceiver` uses an internal `_SocketReader` to pull exact byte counts off the stream, buffering whatever arrives early; changing framing means changing both `file_sender.dart` and that reader together.

**One accept/reject decision covers the entire batch**, via `onIncomingRequest(files, senderIp)` awaited after the manifest is parsed but before any bytes hit disk (Decision 012). Returning `false` closes the connection with nothing written; a 60s timeout auto-rejects.

### Receiver invariants (Decision 014)

Do not weaken these when editing `file_receiver.dart`:

- Filenames from the network are sanitized (`_sanitizeFilename`) — last path segment only, `..` stripped. Never write a network-supplied name directly.
- Partial files are deleted on write failure or early disconnect; never leave a corrupt file behind.
- `onError` means a genuine failure (bad network, disk full, malformed protocol). `onRejected` means an expected outcome (user declined, queue timeout, sender hung up). Callers wire these separately — collapsing them loses the GUI's ability to distinguish "broken" from "declined".
- Concurrent senders are queued FIFO and run **one at a time** (Decision 010). Connections are accepted immediately so senders never see connection-refused; only the disk write waits its turn, with a 5-minute queue timeout.

### Network modes (in progress)

Target platforms are **Linux and Android only** (Decision 014 — iOS/Windows/macOS deferred; this partially supersedes Decision 007's all-platform goal). Two direct-connection paths are being built so transfers work with no router present:

- **Android** — `wifi_direct_channel.dart` bridges to native Kotlin `WifiP2pManager` in `MainActivity.kt` over `MethodChannel('linkdrop/wifi_direct')` and `EventChannel('linkdrop/wifi_direct_events')`. Group owner is typically `192.168.49.1`.
- **Linux** — `hotspot_manager.dart` shells out to `nmcli` to host a "LinkDrop" hotspot and renders a Wi-Fi QR string for the phone to scan.

Neither is wired into `FileSender`/`FileReceiver` yet — they establish connectivity only. Screens for both are gated by platform (`HotspotEntryPoint` renders only on Linux; `WifiDirectChannel` no-ops off Android), and the navigation rail hides destinations that don't exist on the running platform rather than disabling them (`railDestinations()` in `lib/navigation/rail_scope.dart`).

### Android gallery export

Received files are staged in app-private storage, which no gallery can see. `media_export.dart` bridges to `MethodChannel('linkdrop/media_store')` and moves each completed file into the system media collections — scoped storage on API 29+, legacy insert below that. A successful export deletes the staged copy, so anything still in `received/` is by definition unpublished; `ReceiveScreen` sweeps that backlog on startup. No-op on Linux, where the folder is already user-visible.

## UI layer

`lib/theme/`, `lib/widgets/`, and `lib/navigation/` hold the design system (Decision 018). Two rules matter when editing screens:

- **Everything sits in `LinkDropShell`** — icon rail, work pane, optional context pane. The context pane must carry real content *for that screen*; if a screen has nothing legitimate to put there, pass `null` and let the content take the width. Never centre a narrow column in an empty window, which is the problem the shell exists to remove.
- **`centerContent` is set from state, not per screen.** A waiting or empty state is one centred subject; the moment a list, a queue, or a live transfer exists it must anchor to the top and read downward.

### Verifying layout

Layout bugs are invisible in source. `test/ui_golden_test.dart` renders screens at the two canvases the design was drawn on (1280dp Linux, 412dp Android):

```bash
flutter test test/ui_golden_test.dart --update-goldens   # PNGs land in test/goldens/
```

**Look at the PNGs — regenerating without reviewing them defeats the point.** They verify layout, not typography: Inter is not bundled, so glyphs render as boxes and text widths mean nothing. `HotspotScreen` must be rendered with `autoStart: false`; otherwise its `initState` shells out to `nmcli` and a screenshot reconfigures the host's Wi-Fi.

## Known blocker

None currently blocking. **Android can now both send and receive** — in-app cert generation (Decision 015) removed the old openssl-on-mobile blocker, and received files are published to the system gallery via `media_export.dart`. See `docs/TASK_BOARD.md` for current work.

Unverified rather than broken: transfer-in-progress and outcome states have no goldens, and no end-to-end phone↔laptop transfer has been run since the UI rebuild.

## Documentation conventions

This project keeps a deliberate paper trail; treat it as part of the work, not an afterthought:

- `docs/DECISIONS.md` — every architectural choice as Decision NNN with Date / Topic / Decision / **Reason** / **Consequences**. Add a new numbered entry rather than editing history; supersede by noting it in the new entry. (Note: two entries are both numbered 014 — check dates when citing one. Also: `wifi_direct_channel.dart` cites "Decision 015" for the Wi-Fi Direct platform channel, but 015 is in-app cert generation — that citation is wrong and the Wi-Fi Direct channel has no decision entry of its own.)
- `docs/PROJECT_LOG.md` — dated session summaries, including what failed and why.
- `docs/TASK_BOARD.md` — Pending Review / Next Up.
- `docs/ROADMAP.md` — phase status. `docs/ARCHITECTURE.md` predates the Linux+Android narrowing and still describes the all-platform/mDNS design; `DECISIONS.md` is the current source of truth where they conflict.

## Stray file

`lib/screens/live_feed_server.py` is a Python WebSocket server for relaying scraped WhatsApp messages. It has no connection to LinkDrop and appears to have been misplaced here.
