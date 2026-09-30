# Toolchain

- Connect IQ SDK 9.2.0 (`connectiq-sdk-mac-9.2.0-2026-06-09-92a1605b2`), target `fr965` (minimum API 5.2.0), Connect IQ Compiler 9.2.0, Device Simulator 9.2.0 (Forerunner 965).
- Host: macOS, Java 21.
- Signing key: `~/.garmin-keys/NextSetDeveloperKey.der` (PEM beside it, mode 600), outside the repository, never committed. Every build, including simulator and test builds, needs `-y`. Reuse the same key for updates of an installed app and keep a backup.

Put the SDK's `bin` directory on `PATH`, then:

```sh
KEY="$HOME/.garmin-keys/NextSetDeveloperKey.der"
mkdir -p bin
monkeyc -f monkey.jungle -d fr965 -o bin/NextSet.prg -y "$KEY"              # app
monkeyc -r -f monkey.jungle -d fr965 -o bin/NextSet-release.prg -y "$KEY"    # release, no debug info
monkeyc -e -r -f monkey.beta.jungle -d fr965 -o bin/NextSet-beta.iq -y "$KEY" # beta package (separate app id)
monkeyc --unit-test -f tests.jungle -d fr965 -o bin/NextSet-tests.prg -y "$KEY"
monkeydo bin/NextSet-tests.prg fr965 -t
```

`scripts/test.sh` does the test build, restarts the simulator, runs the tests with a timeout and exits 0 only on `PASSED (passed=N, failed=0, errors=0)`. 51 tests pass in the simulator (version 0.3.4). `monkeydo` may exit 1 after a passing summary and a stale simulator can hang it, so read the summary line, not the exit code. `bin/` is ignored by git. Simulator results are not device results; device evidence is recorded in [DEVICE_TESTS.md](DEVICE_TESTS.md).

CI: `.github/workflows/release.yml` (tag `v*` or manual run: build `.iq` + `.prg`, key scan, pre-release) and `ci.yml` (compile check) share `.github/actions/setup-ciq` (Java 21 Temurin, Linux SDK 9.2.0 from `https://developer.garmin.com/downloads/connect-iq/sdks/connectiq-sdk-lin-9.2.0-2026-06-09-92a1605b2.zip` cached, FR965 device files from the `ci-devices` release asset `fr965-device.zip` into `~/.Garmin/ConnectIQ/Devices`, key from the `NEXTSET_DEV_KEY` secret). See the README section "Release from anywhere".
