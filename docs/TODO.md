# TODO — LinkDrop

---

## Phase 1: Core Discovery ✅

- [x] `broadcaster.dart` sends a packet every 2 seconds with name + id
- [x] `listener.dart` receives and prints found devices with the correct IP
- [x] No duplicate spam for the same device in listener output
- [x] Confirmed working on same machine (loopback)
- [x] Ctrl+C cleanly stops both scripts, no crash

---

## Phase 2: Basic TCP File Transfer ✅

- [x] `receiver.dart` starts, prints its IP + port, waits for a connection
- [x] `sender.dart` connects, sends the header + file bytes, prints progress
- [x] Received file matches the original exactly (byte-for-byte)
- [x] Progress output appears in both terminals during transfer
- [x] Tested on the same machine (loopback via 127.0.0.1)
- [x] Ctrl+C on receiver closes cleanly, no crash

---

## Phase 3: Security (TLS + Device Verification)

This is the exact spec for Phase 3. No GUI yet — upgrade the existing `sender.dart` and `receiver.dart` to use TLS-encrypted connections and verify the other device before any file data is sent. Bring the updated files back here for review against this list.

### Goal
Wrap the existing TCP connection in TLS so that:
1. File data cannot be read or tampered with in transit
2. The receiver can verify it is talking to a legitimate LinkDrop sender (not a rogue device)

### What to build

#### Step 1 — Generate self-signed certificates (one-time setup)
Both devices need a certificate + private key pair. For Phase 3, self-signed certs are fine — no CA needed yet.

```bash
# Run once on each device (or generate one pair and copy it for testing)
openssl req -x509 -newkey rsa:4096 -keyout key.pem -out cert.pem -days 365 -nodes -subj "/CN=linkdrop"
```

Files produced: `cert.pem` (public certificate), `key.pem` (private key)

#### Step 2 — Update `receiver.dart`
1. Load `cert.pem` and `key.pem` at startup
2. Wrap the `ServerSocket` in a `SecureServerSocket` using those files
3. All logic after the connection is accepted stays the same — TLS is transparent to the file transfer code
4. Print `Secure receiver listening on port 7979 (TLS)` on startup

#### Step 3 — Update `sender.dart`
1. Load the receiver's `cert.pem` at startup (passed as a third CLI argument)
2. Connect using `SecureSocket` instead of plain `Socket`, passing the cert for verification
3. Use `onBadCertificate` callback to check the incoming cert fingerprint matches the expected one — reject if it doesn't
4. Print `Connected securely to <ip>:7979 (TLS)` before sending
5. All file sending logic after the connection stays the same

#### Updated CLI usage
```bash
# Receiver (cert + key on the receiving device)
dart receiver.dart ./received/ cert.pem key.pem

# Sender (pass receiver's cert for verification)
dart sender.dart 192.168.1.42 ./photo.jpg receiver_cert.pem
```

### Device verification approach (no login — Decision 003)
Since there are no accounts, trust is established by certificate fingerprint:
1. Receiver generates its cert once and keeps it
2. Sender is given the receiver's cert (manually for now — Phase 4 will add a UI flow)
3. Sender checks the fingerprint of the cert presented at connect time matches the one it was given
4. If it doesn't match, sender aborts the connection immediately with a clear error message

### Definition of done
- [ ] `receiver.dart` accepts only TLS connections — plain TCP connections are rejected
- [ ] `sender.dart` verifies the receiver's certificate fingerprint before sending any data
- [ ] Mismatched cert causes sender to abort with a clear error, not silently send
- [ ] File transfer still works correctly end-to-end after adding TLS (byte-for-byte match)
- [ ] Tested on same machine first (loopback), then two physical devices
- [ ] `openssl` commands for cert generation are documented and confirmed working
- [ ] Ctrl+C still cleans up correctly on both sides

### Not in scope yet
- No certificate authority (CA) or certificate signing
- No automatic cert exchange or pairing UI (Phase 4)
- No accept/reject popup (Phase 4)
- No folder support (Phase 5)
- No pause/resume (Phase 5)

---

Once Phase 3 is written, bring both updated files back here. Review against this checklist and Decision 002 (TLS on TCP) and Decision 003 (no login — trust via cert fingerprint) before moving to Phase 4.