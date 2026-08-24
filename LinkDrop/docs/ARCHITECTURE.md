# Architecture

## Overview
LinkDrop is an AirDrop-style app. It sends files between devices on the same Wi-Fi network, or over a direct device-to-device link with no router at all. No cloud, no login — direct device-to-device transfer.

**Target platforms: Linux and Android only** (Decision 014, 2026-06-23). iOS, Windows, and macOS are deferred — this supersedes the original all-platform goal in Decision 007.

## Tech Stack
- **App framework:** Flutter (Android + Linux from one codebase)
- **Language:** Dart (used for both the app UI and the networking engine)
- **Discovery:** UDP broadcast on port 6868 (device name + id, every 2s, de-duped). mDNS/Bonjour was the original Decision 001 plan but is not implemented — UDP broadcast is the only discovery mechanism in the codebase today
- **Transfer:** TCP sockets on port 7979, file-by-file (not zipped), multiple files/folders supported per send via a manifest protocol (Decision 013)
- **Security:** TLS over the TCP connection (fingerprint-verified, no CA/PKI), plus a cert-exchange helper on port 7980 and a human accept/reject step before any bytes are written
- **Storage:** local only — no database, no cloud, no backend server

## Modules
1. **GUI Layer (Flutter)** — device list, send/receive buttons, progress bars, accept/reject popup, plus platform-gated screens for the two direct-connection modes below
2. **Discovery Service** — finds other devices on the local network via UDP broadcast (`discovery_broadcaster.dart` / `discovery_listener.dart`, port 6868)
3. **Transfer Engine** — sends/receives file data over TCP, one file at a time, queues multiple files/folders (`file_sender.dart` / `file_receiver.dart`)
4. **Security Module** — wraps the connection in TLS, verifies the other device's cert fingerprint before sending (`cert_exchange.dart`)
5. **Network Layer** — raw networking underneath, with two modes:
   - **Private mode**: no router needed. Two platform-specific mechanisms, still being wired into the Transfer Engine:
     - **Android**: Wi-Fi Direct via native `WifiP2pManager` (Kotlin, `MainActivity.kt`), bridged to Dart through `wifi_direct_channel.dart`. Group owner is typically reachable at `192.168.49.1`.
     - **Linux**: app-created Wi-Fi hotspot via `nmcli` (`hotspot_manager.dart`), with a QR code (SSID + password) for the phone to scan and join.
   - **Router mode**: existing Wi-Fi/LAN, used as fallback when private mode isn't available or fails
   - Intended behavior: app tries private mode first, falls back to router mode automatically — no user choice needed. Not yet implemented: both private-mode paths currently only establish connectivity and are not wired into the Transfer Engine, so automatic fallback doesn't exist yet in code

## Data Flow
1. App checks if private Wi-Fi mode is possible on this platform/network. If yes, sets it up. If not, uses the router Wi-Fi instead
2. Discovery Service broadcasts presence on whichever network is active
3. Other devices answer back, GUI shows them in a list
4. User picks a device and files. Sender first fetches the receiver's cert over the plain cert-exchange port (7980), then opens a TLS connection on port 7979 and verifies the presented cert's fingerprint matches
5. Receiver gets an accept/reject popup covering the whole batch before any bytes are written
6. If accepted, file data streams over TCP per the manifest protocol, GUI shows progress
7. Transfer is saved in history

## Dependency Map
```
GUI Layer → Transfer Engine → Security Module → Network Layer
GUI Layer → Discovery Service → Network Layer
```

## Open Items (not decided yet)
- Wire Wi-Fi Direct (Android) and hotspot (Linux) connectivity into the Transfer Engine so private mode is actually usable end-to-end, and implement the automatic private → router fallback described above
- Android cannot receive files: no in-app cert generation exists yet (see `docs/TASK_BOARD.md`)