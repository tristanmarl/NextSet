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

## Code conventions

[AGENTS.md](AGENTS.md) holds the repository rules and [CLAUDE.md](CLAUDE.md) the architecture notes. In short:

- Four-space indentation, typed parameters and returns, `UpperCamelCase` classes, `lowerCamelCase` functions, `UPPER_SNAKE_CASE` constants. Match the surrounding code.
- Logic goes in `source/`, screens and navigation in `source/ui/`. Keep everything usable with buttons only (UP, DOWN, START, BACK, hold UP for the menu).
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

1. `scripts/bump-version.sh X.Y.Z` updates both manifests and `AppVersion`; run `scripts/test.sh`; commit.
2. Push the tag `vX.Y.Z`, or run the **release** workflow with the tag as input; without a tag it only builds artifacts.

The workflow checks that the tag matches the manifest version and builds:

- `NextSet-X.Y.Z-private-beta.iq` (separate app id for the Connect IQ beta)
- `NextSet-X.Y.Z.iq` (all watches, for the Connect IQ Store)
- `NextSet-X.Y.Z.prg` (FR965)
- `NextSet-X.Y.Z-sideload.zip` (one `.prg` per watch)

It fails if any artifact contains `lftsk_`, then creates a pre-release. The **ci** workflow compiles `fr965` and `fr255s` on pushes to `main` and on pull requests; unit tests do not run in CI because the simulator needs a GUI.

CI needs two things that are not in the repository:

- **Signing key:** the secret `NEXTSET_DEV_KEY` holds the base64 of the `.der` (`base64 -i ~/.garmin-keys/NextSetDeveloperKey.der | gh secret set NEXTSET_DEV_KEY`). A new key means users reinstall once.
- **Device files:** the Linux SDK has no device definitions. `scripts/pack-devices.sh` zips them for every manifest product into `bin/ciq-devices.zip`; upload it as the asset `ciq-devices.zip` of a draft release tagged `ci-devices` (`gh release upload ci-devices bin/ciq-devices.zip --clobber`). Repeat after adding a watch or updating devices in the SDK Manager.
