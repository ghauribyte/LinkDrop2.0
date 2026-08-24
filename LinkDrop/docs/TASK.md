# Task Log

Chronological log of work sessions on LinkDrop, one entry per task. Complements `docs/TASK_BOARD.md` (status board) and `docs/PROJECT_LOG.md` (narrative dev log) — this file is the running list of discrete tasks, newest first.

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
