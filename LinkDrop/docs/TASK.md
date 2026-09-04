# Task Log

Chronological log of work sessions on LinkDrop, one entry per task. Complements `docs/TASK_BOARD.md` (status board) and `docs/PROJECT_LOG.md` (narrative dev log) — this file is the running list of discrete tasks, newest first.

---

## 2026-08-25 — Android networking/cert bug hunt

**Status:** Three real bugs found and fixed. **Not verified on hardware.**

**Why:** Reported "certificate issue" on Android. Investigating it turned up a permission bug that *presents* as a certificate error, plus two genuinely separate problems.

### (a) Missing INTERNET permission — the actual "certificate issue"
`android.permission.INTERNET` was declared only in `android/app/src/debug/` and `profile/` manifests — Flutter's stock scaffolding, commented "required for development". It was **absent from `main/AndroidManifest.xml`**.

Consequence: a **release** build has no network access whatsoever. Every socket call fails — UDP discovery, the cert fetch on 7980, the TLS transfer on 7979. And because `send_screen.dart` reports a failed `fetchCert()` as *"Could not get <device>'s certificate"*, the symptom is a certificate error whose root cause is a missing permission. Debug builds work fine, which is exactly why this went unnoticed (all prior Android testing was via `flutter run`, i.e. debug).

Fixed by declaring INTERNET in `main/`.

### (b) No MulticastLock — one-way discovery
Android's Wi-Fi driver drops incoming broadcast/multicast frames unless a `WifiManager.MulticastLock` is held. `CHANGE_WIFI_MULTICAST_STATE` was declared but no lock was ever acquired, so the phone could **send** UDP announcements (hence phone→laptop send working) while frequently never **receiving** peers — an empty device list on the phone. Acquired in `configureFlutterEngine`, released in `onDestroy`, wrapped in try/catch so failure degrades discovery rather than breaking the app.

### (c) Private key written world-readable — regression from earlier today
`CertManager` wrote `key.pem` with default umask (`0664`); the openssl workflow it replaced used `0600`. That left the TLS private key — the entire basis of the fingerprint trust model — readable by any local user. Self-inflicted, introduced earlier in this same session.

Fixed by creating the file, tightening the mode, *then* writing key material, so the key is never on disk in a readable state even briefly. `chmod` is skipped on Android (no usable shell — the very reason `CertManager` exists — and per-app storage is already sandboxed). Verified: `key.pem` is `-rw-------`, `cert.pem` stays readable since it's deliberately served on 7980. `pause_resume_test.dart` still passes byte-identical afterwards.

**Verification gap:** `flutter analyze` does not check Kotlin, so the `MainActivity.kt` change needs a real `flutter build apk` to compile-verify. The build was attempted but did not finish in the time available (slow/flaky network fetching Flutter engine artifacts). **None of these three fixes has been observed working on a real Android device.**

---

## 2026-08-25 — Linux↔Linux hotspot transfer + pause/resume

**Status:** Done (pending commit)

**Why:** Requested flow — one Linux machine hosts a hotspot and shows the password, the other joins it, and files transfer over that direct link with accept/reject and pause/resume. Mapping that against what existed: hotspot *hosting* and accept/reject were already built; hotspot *joining* and pause/resume were not.

**What shipped:**
- `HotspotManager.join()` / `.leave()` — the missing other half of `start()`. Uses `nmcli device wifi connect`, with a forced rescan first (a hotspot created seconds ago on another machine is usually absent from nmcli's cached scan list, which otherwise surfaces as a confusing "No network with SSID found").
- `lib/screens/join_hotspot_screen.dart` — SSID/password entry (SSID prefilled to `LinkDrop`, the name `start()` always creates, so normally only the password is typed). On success shows the joined IP and jumps straight to Receive/Send. Linux-only entry point on the home screen, mirroring `HotspotEntryPoint`.
- `FileSender.pause()` / `.resume()` / `.cancel()` + `onPausedChanged` callback — see Decision 017 for the in-session-only scope and why cross-reconnect resume was deliberately excluded.
- Pause/Resume/Cancel controls wired into `send_screen.dart`, with an indeterminate progress bar and "Paused" label while halted. `dispose()` cancels any in-flight sender so a paused loop can't outlive its screen.

**Verified (not just analyzed):**
- `pause_resume_test.dart` — real 24 MB transfer over loopback: progress froze at exactly 21,102,592 bytes and did not move across a 2-second pause, then resumed to a **byte-identical SHA-256** on the received file.
- `cancel_test.dart` — cancel issued *while paused* returns promptly instead of deadlocking the parked send loop, and the receiver leaves **no partial file** behind, reporting via `onRejected` rather than `onError` (Decision 014's split holds).
- `flutter analyze` clean — no new issues.

**Not verified:** the actual two-machine hotspot join. Needs a second Linux box; also can't be exercised on this dev machine because `nmcli device wifi hotspot` would repurpose the adapter and drop its real Wi-Fi connection.

---

## 2026-08-24 — Android in-app cert generation

**Status:** Done (pending commit)

**Why:** Top blocker on `docs/TASK_BOARD.md` → Pending Review — Android cannot receive files because `receive_screen.dart` expects `cert.pem`/`key.pem` to already exist at `<app docs>/linkdrop/`, and the only way to create them so far is the manual `openssl` command in `docs/TODO.md`, which requires shell access Android doesn't have.

**What shipped (Decision 015):** Self-signed ECDSA (P-256) cert + key pair generated in pure Dart via `basic_utils`/`pointycastle`, cached at `<app docs>/linkdrop/{cert,key}.pem`. EC chosen over RSA for near-instant keygen on-device (RSA-4096 pure-Dart keygen can take seconds on a phone; P-256 is near-instant).

**Steps:**
- [x] Add `basic_utils` + `pointycastle` dependencies (`flutter pub add`)
- [x] `lib/engine/cert_manager.dart` — `CertManager.ensureCertExists()`: generates EC keypair, self-signed cert via CSR, writes PEM files if not already present (no-op if both already exist, so identity/fingerprint persists across launches)
- [x] Wire into `receive_screen.dart` — replaced the "no cert found, run openssl" error path with a call to `CertManager.ensureCertExists`
- [x] `flutter analyze` clean on touched files (one pre-existing unrelated info-level lint in a doc comment I didn't write)
- [x] Verified for real: generated a cert with `CertManager`, confirmed it's a valid X.509 ECDSA cert (`openssl x509 -text`), then ran the CLI `receiver.dart`/`sender.dart` harness against it over loopback — TLS handshake, fingerprint verification, and file transfer all succeeded end-to-end
- [x] Live GUI test on Linux desktop: built and ran the real `linkdrop_app` GTK binary under Xvfb (driven via synthetic X11 input, no xdotool/Electron tooling available — used python-xlib + mss instead), removed any pre-existing cert, opened "Receive Files" from a cold start, confirmed `CertManager` generated a fresh ECDSA P-256 cert/key on disk (`openssl x509` confirmed `id-ecPublicKey`, 256-bit), then sent a real file from the CLI harness — TLS handshake, fingerprint verification, the Incoming File accept dialog, and the actual file write all worked end-to-end against the GUI-generated cert.
- [ ] Manual test on an actual Android device (needs physical hardware — not yet run)

**Build environment notes for next time (Linux desktop build was previously never exercised on this machine):** needed `cmake`, `ninja`, and `clang`/`clang++` (Flutter's Linux build hardcodes `CXX=clang++`/`CC=clang` in `build_linux.dart`, ignoring any exported `CXX`/`CC`) — none were preinstalled, all needed `sudo apt-get install`. Also: this machine runs a real GNOME Wayland session, so `GDK_BACKEND` defaults to `wayland` — launching under Xvfb for headless/agent-driven testing requires explicitly forcing `GDK_BACKEND=x11`, otherwise the app connects to the real Wayland compositor instead of the virtual display and screenshots come back blank.

**Not yet committed** — sitting alongside other in-progress uncommitted work (Wi-Fi Direct/hotspot screens). See `docs/TASK_BOARD.md`.
