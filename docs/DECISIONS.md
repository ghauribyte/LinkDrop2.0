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

---

## Pending Decisions (need to be made before coding starts)
- GUI framework: Electron vs Qt vs Flutter (Flutter recommended since phones are in scope — Electron has no phone support)
- Programming language for discovery + transfer engine
- Folder transfer approach: zip vs file-by-file
