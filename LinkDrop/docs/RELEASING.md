# Releasing LinkDrop

Push a tag; GitHub builds and publishes an Android APK and a Linux tarball.
Nobody hands anyone a file built on a laptop, and an installed copy can tell
its user that a newer one exists.

```
    you                     GitHub                        the user's machine
    ───                     ──────                        ──────────────────

  git push origin v0.2.0 ─► release.yml fires
                              │
                              ├─► version-guard   (~20 s) pubspec == tag?
                              ├─► checks          (~2 min) analyze + test
                              ├─► android         builds + signs the APK
                              ├─► linux           builds the tarball
                              └─► publish
                                    │
                                    ▼
                              GitHub Release "LinkDrop 0.2.0"
                               • linkdrop-0.2.0-android.apk
                               • linkdrop-0.2.0-linux-x64.tar.gz
                               • latest.json         ← the update feed
                                    │
                    ┌───────────────┴──────────────┐
                    ▼                              ▼
              FIRST INSTALL                  ALREADY INSTALLED
              download and run it            About → Check for updates
                                             "0.2.0 is available" + a link
```

---

## The one rule that will bite you

**The version comes from `LinkDrop/pubspec.yaml`, not from the tag.** Flutter
names the artifacts and stamps Android's `versionName`/`versionCode` from it;
git only decides *when* a build happens.

`release.yml`'s `version-guard` job enforces this and fails in about twenty
seconds if they disagree, so a mismatch costs you a re-tag rather than a
release whose filenames lie about their contents.

The `+N` build number is Android's `versionCode`. **It must increase on every
release** or Android refuses to install the update over the old one.

---

## Cutting a release

```bash
# 0. clean tree, up to date
git status && git pull --ff-only

# 1. verify what you're about to ship
cd LinkDrop
flutter analyze                          # must exit 0
flutter test --exclude-tags golden
flutter test test/ui_golden_test.dart    # and LOOK at test/goldens/*.png
cd ..

# 2. bump the version — both the x.y.z and the +N
#    LinkDrop/pubspec.yaml:  version: 0.2.0+2
git commit -am "chore(release): 0.2.0"

# 3. annotated tag — its message becomes the release notes and the
#    "What's new" text in the app. There is no CHANGELOG file.
git tag -a v0.2.0

# 4. push both
git push origin main
git push origin v0.2.0

# 5. watch it (~5 minutes)
gh run watch

# 6. confirm all three assets landed
gh release view v0.2.0 --json assets --jq '[.assets[].name]'
```

Step 6 is also asserted by the workflow itself, but check it anyway. A release
missing `latest.json` looks completely fine on GitHub and silently breaks every
installed copy's update check.

**Do not create an empty GitHub Release by hand.** It becomes "Latest" with no
`latest.json` behind it, and every client's check starts erroring until real
assets appear.

---

## One-time setup: the Android signing key

Until this is done, `release.yml`'s android job fails on purpose. It refuses
to publish a debug-signed APK — that key is shared and public, and an APK
signed with it can never be upgraded in place by a properly signed build.

### 1. Create the keystore (you, not CI, and not Claude)

```bash
keytool -genkeypair -v \
  -keystore linkdrop-release.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias linkdrop \
  -dname "CN=LinkDrop, O=LinkDrop, C=PK"
```

It will prompt for a keystore password and a key password. Use the same value
for both — the Gradle config supports separate ones, but there is no benefit.

**Back this file and its password up somewhere you will still have in five
years.** Losing it means every existing install has to be uninstalled by hand
before it can take another update. There is no recovery.

**Never commit it.** `.gitignore` covers `*.jks`, `*.keystore`, and
`android/key.properties`, but the real protection is not putting it in the
repo directory at all.

### 2. Building a signed APK locally

Create `LinkDrop/android/key.properties` (gitignored):

```properties
storeFile=/absolute/path/to/linkdrop-release.jks
storePassword=...
keyAlias=linkdrop
keyPassword=...
```

Then `flutter build apk --release`. Without this file the build still works —
it falls back to debug signing so a fresh clone isn't broken — so verify what
you actually produced:

```bash
$ANDROID_HOME/build-tools/*/apksigner verify --print-certs \
  build/app/outputs/flutter-apk/app-release.apk
```

`CN=Android Debug` in the output means the keystore was not picked up.

### 3. The four repository secrets

Settings → Secrets and variables → Actions → New repository secret:

| Secret | Value |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | `base64 -w0 linkdrop-release.jks` |
| `ANDROID_KEYSTORE_PASSWORD` | the keystore password |
| `ANDROID_KEY_ALIAS` | `linkdrop` |
| `ANDROID_KEY_PASSWORD` | the key password |

`GITHUB_TOKEN` is injected by Actions automatically — there is nothing to
create, but `release.yml` must declare `permissions: contents: write` or
publishing 403s at the very end of an otherwise successful build.

---

## What the update check does, and does not do

`lib/engine/update_checker.dart` fetches
`releases/latest/download/latest.json` — a URL GitHub always redirects to the
newest release — and compares its `version` against the running build's.

It **checks and notifies. It never downloads or installs.** A sideloaded APK
cannot replace itself without `REQUEST_INSTALL_PACKAGES` and a FileProvider,
and a Linux tarball has no package manager to hand the job to. The user gets
a version number, the release notes, and a link.

A check that cannot complete — offline, GitHub blocked, a release published
without its manifest, a truncated body — is reported as a **failure**, never
as "you're up to date". That distinction is the whole reason the feature is
trustworthy.

The manifest is read as a release *asset* rather than through the GitHub REST
API, because asset downloads are not subject to the API's unauthenticated
rate limit (60/hour, shared per source IP — easy to exhaust on an office
network).

---

## Installing what comes out

**Android.** Download the `.apk` and open it. Android will ask permission to
install from this source the first time. The app is signed with LinkDrop's own
key, not a Play Store identity, so the warning is expected.

**Linux.** The tarball unpacks to a self-contained folder:

```bash
mkdir -p ~/linkdrop && tar -xzf linkdrop-0.2.0-linux-x64.tar.gz -C ~/linkdrop
~/linkdrop/linkdrop_app
```

It needs GTK 3 at runtime (`libgtk-3-0`), present on any normal desktop
install. It is built on the oldest supported runner so the glibc it links
against is old enough for most distributions; a very old distribution may
still refuse it.

No certificate setup is needed. The app generates its own TLS keypair on first
launch (`lib/engine/cert_manager.dart`, Decision 015) — the `openssl` step in
CLAUDE.md applies to the CLI harness only.

---

## When something goes wrong

| Symptom | Cause | Fix |
|---|---|---|
| No build after pushing a tag | The tag doesn't start with `v` | Re-tag |
| Fails in ~20 s at `version-guard` | `pubspec.yaml` version ≠ tag | Fix pubspec, delete the tag and release, re-tag |
| Fails in ~2 min at `checks` | `flutter analyze` or a test | Reproduce locally; the gate runs exactly the same two commands |
| android job: "ANDROID_KEYSTORE_BASE64 is not set" | Secrets never added | See "One-time setup" above |
| android job: "The APK is debug-signed" | A signing secret is wrong or empty | Re-check all four; the keystore password and key password are separate fields |
| Publish fails with 403 | Missing `permissions: contents: write` | It's in `release.yml`; check it wasn't edited out |
| App says "Could not reach github.com" | Network blocks GitHub | Hand over the file directly |
| App says "No update manifest was published" | A release exists without `latest.json` | Usually a hand-created release — delete it, or re-run the workflow |
| Android refuses to install the update | `+N` build number didn't increase | Bump it, re-release |

Building locally is always a valid fallback: `flutter build apk --release` and
`flutter build linux --release` produce the same artifacts the workflow does,
without publishing anything.
