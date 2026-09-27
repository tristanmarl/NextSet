# Repository Guidelines

## Project Structure

NextSet is a Monkey C Connect IQ watch app targeting the Garmin Forerunner 965. Core workout, catalog, storage, and clock logic lives in `source/`; watch screens and menu navigation are in `source/ui/`. Automated test cases are in `tests/` and are included through `tests.jungle`. App metadata is in `manifest.xml`, with strings, drawables, and seed data in `resources/`. Build and device evidence belongs in `docs/`.

## Build, Test, and Run

Install Connect IQ SDK 9.2.0 and add its `bin` directory to `PATH`.

```sh
mkdir -p bin
monkeyc -f monkey.jungle -d fr965 -o bin/NextSet.prg
monkeydo bin/NextSet.prg fr965
```

The first command builds the app; the second launches it in the FR965 simulator. Build and run the automated test target with:

```sh
monkeyc --unit-test -f tests.jungle -d fr965 -o bin/NextSet-tests.prg
monkeydo bin/NextSet-tests.prg fr965
```

Check the test summary: the current SDK runner may return exit code 1 even after reporting all tests passed. Record simulator and physical-watch evidence separately in `docs/DEVICE_TESTS.md`.

## Style and Testing

Use four spaces for indentation, typed Monkey C parameters and returns, `UpperCamelCase` for classes, `lowerCamelCase` for functions and locals, and `UPPER_SNAKE_CASE` for constants. Add tests beside related cases under `tests/`, name test functions `test...`, and mark them with `(:test)`. Prefer focused logic changes and tests over broad refactors; keep UI changes compatible with button-only watch navigation.

## Commits and Pull Requests

The available history has one release commit, so no repeated commit convention is established. Use short imperative subjects, such as `Fix rest timer vibration`. Pull requests should explain the user-visible change, list build/test results, link relevant issues when present, and include simulator screenshots for visual changes. Clearly identify device checks that remain unverified.

## Security and Configuration

The current signing key is `/private/tmp/NextSetDeveloperKey.der` (PEM source: `/private/tmp/NextSetDeveloperKey.pem`); pass the DER path to `monkeyc -y`. These temporary files are outside the repository, but `/private/tmp` is not durable, so keep a secure backup. Reuse the same key for updates; never commit, upload, or package either key. Do not check in local SDK files or generated build artifacts. The app is currently local-only and does not generate Garmin activities or FIT files; documentation must not claim otherwise.
