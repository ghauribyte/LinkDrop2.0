# Architecture

## Overview
LinkDrop is an AirDrop-style app. It sends files between devices on the same Wi-Fi network. No cloud, no login — direct device-to-device transfer.

## Tech Stack
- **App framework:** Flutter (one codebase for Android, iOS, Windows, macOS, Linux)
- **Language:** Dart (used for both the app UI and the networking engine)
- **Discovery:** mDNS/Bonjour, UDP broadcast as fallback
- **Transfer:** TCP sockets, file-by-file (not zipped), multiple files/folders supported per send
- **Security:** TLS over the TCP connection, plus a device check before transfer
- **Storage:** local only — no database, no cloud, no backend server

## Modules
1. **GUI Layer (Flutter)** — device list, send/receive buttons, progress bars, accept/reject popup
2. **Discovery Service** — finds other devices on the local network (mDNS/Bonjour or UDP broadcast)
3. **Transfer Engine** — sends/receives file data over TCP, one file at a time, queues multiple files/folders
4. **Security Module** — wraps the connection in TLS, verifies the other device before sending
5. **Network Layer** — raw networking underneath, with two modes:
   - **Private mode**: Wi-Fi Direct or app-created hotspot (Android, Windows, Linux only)
   - **Router mode**: existing Wi-Fi/LAN, used as fallback everywhere, and the only mode on iOS/macOS
   - App tries private mode first, falls back to router mode automatically — no user choice needed

## Data Flow
1. App checks if private Wi-Fi mode is possible on this platform/network. If yes, sets it up. If not, uses the router Wi-Fi instead
2. Discovery Service broadcasts presence on whichever network is active
3. Other devices answer back, GUI shows them in a list
4. User picks a device and files, Transfer Engine opens a TCP connection
5. Security Module wraps it in TLS and checks the other device
6. Receiver gets an accept/reject popup
7. If accepted, file data streams over TCP, GUI shows progress
8. Transfer is saved in history

## Dependency Map
```
GUI Layer → Transfer Engine → Security Module → Network Layer
GUI Layer → Discovery Service → Network Layer
```

## Open Items (not decided yet)
_(none — all core decisions made)_