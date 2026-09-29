# Toolchain

- Connect IQ SDK: 9.2.0, package `connectiq-sdk-mac-9.2.0-2026-06-09-92a1605b2`
- Target: `fr965` (manifest minimum API 5.2.0)
- Host: macOS 27.0; Java 21.0.4; Connect IQ Compiler 9.2.0.
- Simulator: Connect IQ Device Simulator 9.2.0, Forerunner 965 (API 5.2.0).
- Watch firmware: not validated on a physical watch.
- Signing key: `~/.garmin-keys/NextSetDeveloperKey.der` (PEM beside it, mode 600). It is outside the repository and must never be committed. Reuse the same key for every build of an installed app; keep a backup.

Build command used:

```sh
mkdir -p bin
monkeyc -f monkey.jungle -d fr965 -o bin/NextSet.prg -y "$HOME/.garmin-keys/NextSetDeveloperKey.der"
```

Add the Connect IQ SDK's `bin` directory to `PATH` before running the build command.

Tests (35 tests, all passing on 2026-09-29; `monkeydo` may still exit 1 after a passing summary):

```sh
monkeyc --unit-test -f tests.jungle -d fr965 -o bin/NextSet-tests.prg -y "$HOME/.garmin-keys/NextSetDeveloperKey.der"
monkeydo bin/NextSet-tests.prg fr965 -t
```

Release build (manifest version 0.2.0). NextSet is not published to the Connect IQ store; the `-r` build is sideloaded and attached to a GitHub release as `NextSet-<version>.prg`:

```sh
monkeyc -r -f monkey.jungle -d fr965 -o bin/NextSet-release.prg -y "$HOME/.garmin-keys/NextSetDeveloperKey.der"
```

`-r` strips debug information. Output files under `bin/` are ignored by git. Sideloaded updates must be signed with the same key.

## Current evidence

The integrated production build compiled successfully for `fr965` with Connect IQ SDK 9.2.0 using the command above. The signed build on 2026-09-29 includes `ActivityRecording`, Fit permission, bundled Garmin exercise data, and editable routines. On 2026-09-27, the test target was built with `monkeyc --unit-test` and run in the FR965 simulator: all 17 tests reported PASS at that time (31 pass now). `monkeydo` nevertheless returned exit code 1 after printing the passing summary, including for a single passing test; treat this as a runner-status issue until its cause is resolved.

The production build was relaunched in the FR965 simulator. Home, Overview, and Exercise screens were inspected; the visible overview and exercise text fit without clipping, including long exercise names. This is simulator-only layout evidence. No physical FR965 validation is recorded. See [DEVICE_TESTS.md](DEVICE_TESTS.md) and [SPIKES.md](SPIKES.md) for remaining acceptance work.

The production code creates and saves a Strength `ActivityRecording.Session`. The simulator connection attempt on 2026-09-29 returned `Unable to connect to simulator.`, so no FIT file or activity rendering was inspected. Physical FR965 recording and Garmin Connect visibility remain pending. Local detailed sets are preserved; native Garmin strength set rendering is not claimed. See [DEVICE_TESTS.md](DEVICE_TESTS.md) and [SPIKES.md](SPIKES.md).
