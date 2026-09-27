# NextSet

NextSet 0.1.0 is an early prototype of an offline strength-training log for the Garmin Forerunner 965. It has been checked in the simulator, not on a physical watch. Workouts are stored locally; this version does not create Garmin activities or FIT files.

## Build

Install Garmin Connect IQ SDK 9.2.0 and build from this directory:

```sh
mkdir -p bin
monkeyc -f monkey.jungle -d fr965 -o bin/NextSet.prg
```

For a signed sideload build, add `-y /path/to/developer_key.der`. Keep the signing
key outside this repository. See [docs/TOOLCHAIN.md](docs/TOOLCHAIN.md) for the
local SDK path and validation status.
