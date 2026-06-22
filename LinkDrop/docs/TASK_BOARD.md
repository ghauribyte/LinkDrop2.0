# Task Board

## In Progress
_(none)_

## Pending Review
_(none)_

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

## Next Up — Phase 3: TLS + Device Verification
- [ ] Generate self-signed cert + key pair with openssl (document exact command)
- [ ] Update `receiver.dart` — swap `ServerSocket` for `SecureServerSocket`, load cert.pem + key.pem from CLI args
- [ ] Update `sender.dart` — swap `Socket` for `SecureSocket`, load receiver cert.pem from CLI arg, verify fingerprint
- [ ] Test: mismatched cert must abort connection with clear error (not silently send)
- [ ] Test: file transfer still byte-for-byte correct after adding TLS
- [ ] Test on loopback first, then two physical devices