# Contributing to NextSet

Thanks for helping. NextSet is a small hobby project, so short, focused changes are easiest to review.

## Ways to help

- **Watch reports.** Only the Forerunner 965 has been used on real hardware. If you run NextSet on another watch, open an issue with the model, firmware version, NextSet version, and what worked or looked wrong (a photo of the screen helps).
- **Bug reports.** Say what you did, what you expected and what happened. If NextSet crashed, connect the watch by USB and attach `GARMIN/APPS/LOGS/CIQ_LOG.YML`. If the whole watch restarted, also attach `GARMIN/DEBUG/err_log.bak`. **Never post your Liftosaur API key**; check logs and screenshots for it before attaching them.
- **Pull requests.** For larger changes, open an issue first so we can agree on the approach.

## Development setup

1. Install the [Connect IQ SDK Manager](https://developer.garmin.com/connect-iq/sdk/), then SDK **9.2.0** and the device definitions you need (at least `fr965`). Put the SDK's `bin` directory on your `PATH`. Java 21 is needed for the compiler.
2. Create a developer key once, outside the repository:

   ```sh
   mkdir -p ~/.garmin-keys && cd ~/.garmin-keys
   openssl genrsa -out NextSetDeveloperKey.pem 4096
   openssl pkcs8 -topk8 -inform PEM -outform DER -in NextSetDeveloperKey.pem -out NextSetDeveloperKey.der -nocrypt
   ```

   A `.prg` signed with your key installs over another `.prg` only if that was signed with the same key, so keep it. Never commit a key; `*.der` and `*.pem` are ignored.

## Build and test

Every `monkeyc` call needs `-y` with the key, including simulator and test builds.

```sh
KEY="$HOME/.garmin-keys/NextSetDeveloperKey.der"
mkdir -p bin

# App for one watch, then run it in the simulator
monkeyc -f monkey.jungle -d fr965 -o bin/NextSet.prg -y "$KEY"
monkeydo bin/NextSet.prg fr965

# Unit tests: builds, runs in the simulator, exits 0 only on "PASSED (… failed=0, errors=0)"
scripts/test.sh
```

Read the test summary line rather than the `monkeydo` exit code; the runner can exit 1 after a passing run. `scripts/test.sh` restarts the simulator itself, because a stale one can hang `monkeydo`.

Before a pull request:

- `scripts/test.sh` passes.
- The app builds for `fr965` and for `fr255s` (a small MIP watch without vector fonts, which catches API gaps).
- UI changes are checked in the simulator on a large and a small screen, for example `fr965` (454 px) and `fenix7s` (240 px). Add screenshots to the pull request.

## Screenshots

`monkey.demo.jungle` builds a demo app (separate app id, `manifest.demo.xml`, never shipped) that fills the simulator with a made-up program from `demo/resources/data/demo.xml`, starts a workout with two logged sets and switches between the set screens, the editors (Change weight, last set with Delete), the delete confirmation, the Overview and Home every 8 s, so screens can be captured without button input:

```sh
monkeyc -f monkey.demo.jungle -d fr965 -o bin/NextSet-demo.prg -y "$KEY"
monkeydo bin/NextSet-demo.prg fr965
```

The demo clears the simulator's app storage on every start. README images are in `docs/screenshots/`.

## Code conventions

[AGENTS.md](AGENTS.md) holds the repository rules and [CLAUDE.md](CLAUDE.md) the architecture notes. In short:

- Four-space indentation, typed parameters and returns, `UpperCamelCase` classes, `lowerCamelCase` functions, `UPPER_SNAKE_CASE` constants. Match the surrounding code.
- Logic goes in `source/`, screens and navigation in `source/ui/`. Keep everything usable with buttons only (UP, DOWN, START, BACK, hold UP as the one shortcut on the set screen and the Overview).
- **Callbacks passed to `method(:name)` (timers, web requests) must be public.** A private one compiles but fails on the watch.
- **Guard APIs that some watches lack** with `has` (for example `Graphics has :getVectorFont`). The project targets Connect IQ 5.0+.
- Requests stay asynchronous and outside timing-sensitive work. Do not run storage writes, FIT laps or requests in the same timer tick as a vibration.
- Persisted values (job states, journal phases, error codes in `source/Liftosaur.mc` and `source/ErrorCodes.mc`) never change: they are stored on users' watches. Add error codes in `source/ErrorCodes.mc` only, with both texts.
- Changes to stored data must stay readable by the previous version's data and keep the two-generation commits in `source/Store.mc` intact.

## Tests

Tests live in `tests/*.mc` as free functions marked `(:test)` that take a `Test.Logger` and return a `Boolean`; `check()` is in `tests/WorkoutTests.mc`. Combine check results (`ok1 && ok2 && check(...)`): a `check` whose result is dropped does not fail the test. Keep long conditions split into named variables; one huge expression ran the compiler out of memory. Fixtures under `tests/resources/` must be sanitized: no real API keys, names or account data.

## Liftosaur and secrets

- The Liftosaur API key is a full-access credential. Do not hard-code it, print it, log it, commit it or put it in fixtures. Tests use fakes (`UploadMemoryStore`) and never call the network.
- Do not send real `POST` requests to Liftosaur while developing unless you are testing on your own account on purpose. Uploads change your history and progression.
- API behavior NextSet relies on is documented in [docs/LIFTOSAUR_API.md](docs/LIFTOSAUR_API.md).

## Device evidence

Simulator results are not device results. Record what was checked on a real watch in [docs/DEVICE_TESTS.md](docs/DEVICE_TESTS.md), with the watch model, NextSet version and date, and keep unverified items marked as pending.

## Releases (maintainers)

1. `scripts/bump-version.sh X.Y.Z` updates both manifests and `AppVersion`; add the `CHANGELOG.md` entry and `docs/release-notes/X.Y.Z.md`; run `scripts/test.sh`; commit.
2. Push the tag `vX.Y.Z`, or run the **release** workflow with the tag as input; without a tag it only builds and checks.
3. Build the store package locally and upload it in the Connect IQ developer dashboard:

   ```sh
   monkeyc -e -r -f monkey.jungle -o bin/NextSet-X.Y.Z.iq -y "$KEY"
   ```

The workflow checks that the tag matches the manifest version, builds the store `.iq` and one `.prg` per watch, and fails if any of them contains `lftsk_`. It then creates a GitHub release with notes only (from `docs/release-notes/X.Y.Z.md`, else the annotated tag message). No build files are published or kept as workflow artifacts, because anyone can download the artifacts of a public repository: the Connect IQ Store is the only install channel. The private-beta package (`monkey.beta.jungle`, separate app id) is built locally only when needed: `monkeyc -e -r -f monkey.beta.jungle -o bin/NextSet-X.Y.Z-private-beta.iq -y "$KEY"`. The **ci** workflow compiles `fr965` and `fr255s` on pushes to `main` and on pull requests; unit tests do not run in CI because the simulator needs a GUI.

CI needs two things that are not in the repository:

- **Signing key:** the secret `NEXTSET_DEV_KEY` holds the base64 of the `.der` (`base64 -i ~/.garmin-keys/NextSetDeveloperKey.der | gh secret set NEXTSET_DEV_KEY`). A new key means users reinstall once.
- **Device files:** the Linux SDK has no device definitions. `scripts/pack-devices.sh` zips them for every manifest product into `bin/ciq-devices.zip`; upload it as the asset `ciq-devices.zip` of a draft release tagged `ci-devices` (`gh release upload ci-devices bin/ciq-devices.zip --clobber`). Repeat after adding a watch or updating devices in the SDK Manager.
