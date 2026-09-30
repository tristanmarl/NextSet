# Repository Guidelines

## Project Structure

NextSet is a Monkey C Connect IQ watch app targeting the Garmin Forerunner 965. Core workout, catalog, storage, and clock logic lives in `source/`; watch screens and menu navigation are in `source/ui/`. Automated test cases are in `tests/` and are included through `tests.jungle`. App metadata is in `manifest.xml`, with strings, drawables, and seed data in `resources/`. Build and device evidence belongs in `docs/`.

## Build, Test, and Run

Install Connect IQ SDK 9.2.0 and add its `bin` directory to `PATH`.

```sh
mkdir -p bin
monkeyc -f monkey.jungle -d fr965 -o bin/NextSet.prg -y ~/.garmin-keys/NextSetDeveloperKey.der
monkeydo bin/NextSet.prg fr965
```

The first command builds the app; the second launches it in the FR965 simulator. Build and run the automated test target with:

```sh
monkeyc --unit-test -f tests.jungle -d fr965 -o bin/NextSet-tests.prg -y ~/.garmin-keys/NextSetDeveloperKey.der
monkeydo bin/NextSet-tests.prg fr965 -t   # without -t it launches as an app and hangs
```

Always pass `-y ~/.garmin-keys/NextSetDeveloperKey.der` to `monkeyc`, including simulator and unit-test builds. This checkout's SDK exits 101 with “The private key was not specified” if it is omitted; do not try an unsigned build first.
Check the test summary: the current SDK runner may return exit code 1 even after reporting all tests passed. Record simulator and physical-watch evidence separately in `docs/DEVICE_TESTS.md`.

## Style and Testing

Use four spaces for indentation, typed Monkey C parameters and returns, `UpperCamelCase` for classes, `lowerCamelCase` for functions and locals, and `UPPER_SNAKE_CASE` for constants. Add tests beside related cases under `tests/`, name test functions `test...`, and mark them with `(:test)`. Prefer focused logic changes and tests over broad refactors; keep UI changes compatible with button-only watch navigation.

Timer callbacks passed through `method(:callback)` must be public. A private `advanceFinalization` callback passed to `Timer.start()` compiled but crashed on the physical FR965 with `Invalid Value / Failed invoking <symbol>` during workout abort. Check callback visibility whenever adding a timer or other asynchronous callback; a successful build does not establish that it can be invoked on the watch.

## Commits and Pull Requests

The available history has one release commit, so no repeated commit convention is established. Use short imperative subjects, such as `Fix rest timer vibration`. Pull requests should explain the user-visible change, list build/test results, link relevant issues when present, and include simulator screenshots for visual changes. Clearly identify device checks that remain unverified.

## Security and Configuration

The current signing key is `~/.garmin-keys/NextSetDeveloperKey.der` (PEM source: `~/.garmin-keys/NextSetDeveloperKey.pem`); pass the DER path to `monkeyc -y`. The key was regenerated on 2026-09-29 after the old `/private/tmp` key was lost; installing a build signed with it requires reinstalling NextSet on the watch once. Keep a secure offline backup of both files. Reuse the same key for updates; never commit, upload, or package either key. Do not check in local SDK files or generated build artifacts. The app now compiles an `ActivityRecording` Strength FIT activity path. A short physical-watch Strength FIT activity was inspected; Garmin Connect visibility and native per-exercise set rendering remain unverified. Local completed set details remain in NextSet history.
