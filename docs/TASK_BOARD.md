# Task Board

## In Progress
_(none)_

## Pending Review
- [ ] Re-run `broadcaster.dart` + `listener.dart` for real to confirm Phase 1 actually works (checked off before Dart was installed — may not have been truly tested)
- [ ] Test mismatched cert rejection: generate a second cert pair, pass wrong cert to sender — must abort with clear error, no data sent
- [ ] Test TLS transfer on two physical devices on the same Wi-Fi (loopback done, physical not yet)

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
## Next Up — Phase 4: Flutter GUI
- [ ] Send file flow (file picker → pick device → transfer)
- [ ] Accept/reject popup on receiver side
- [ ] Progress bar (per file + overall)