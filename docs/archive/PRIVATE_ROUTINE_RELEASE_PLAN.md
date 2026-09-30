# Connect IQ release and private routines

## Package split

- `monkey.jungle` uses `resources/`, whose `Seeds` resource contains the Garmin exercise definitions and no workout programs. New production installs get one empty `Routine 1` and can create their own routine.
- `monkey.beta.jungle` uses `private/resources/` and a separate `manifest.beta.xml`. The private beta seeds Upper and Lower for the developer while testing Connect fields. Garmin beta apps have a separate app ID and storage from production.
- `monkey.local.jungle` uses the same private seed resource for personal sideload builds. `tests.jungle` uses it as a regression fixture. Never use either private jungle to make the production `.iq` package.

The two routines are retained in `private/resources/data/seeds.xml`. That directory is outside the production resource path, so its routine names, exercise order, set targets, and starting loads do not enter the public package. The repository is private; do not copy the private resource into `resources/` when preparing a production build.

## Existing data and recovery

Current schema v3 routines are stored in the app's watch storage. They should remain available when an update keeps the same app ID and storage namespace, but Garmin does not guarantee that a sideload-to-Store install preserves that data. A beta app always uses its own ID and starts with separate storage. Test upgrades on the FR965 before replacing the working sideloaded app.

The private beta gets Upper and Lower from its private seed resource on first use, so it does not depend on copying watch storage. A local build can restore those defaults with:

```sh
monkeyc -f monkey.local.jungle -d fr965 -o bin/NextSet-local.prg -y "$HOME/.garmin-keys/NextSetDeveloperKey.der"
```

This recovers the original two defaults only; it cannot reconstruct later edits or workout history if watch storage was cleared.

## Beta and public release sequence

1. Keep the FR965-only alternate UUID in `manifest.beta.xml` separate from the production UUID in `manifest.xml`.
2. Build/export the private beta with `monkey.beta.jungle`, then upload it as a developer beta. Confirm the developer account can install it and see the FIT developer fields in Garmin Connect.
3. Keep the production `.iq` build on `monkey.jungle`; inspect the package for `Upper`, `Lower`, seed entry IDs, and starting-load values before submission.
4. After beta/device checks pass, submit the production package and listing through the Connect IQ Store review flow. Do not reuse the beta app ID for the public listing.

## QA gates

- Run the signed unit-test build using `tests.jungle`; it uses the private fixture so routine behavior and old migrations stay covered.
- Build the production resource path and inspect its exported `.iq` for private routine strings and values.
- On the FR965, verify the beta starts with Upper and Lower, records a short Strength activity, and exposes the expected developer fields in Garmin Connect. Separately install/update the public build and confirm it starts with an empty routine and retains any existing v3 storage that Garmin carries forward.
- Mark the beta app ID and storage as separate from production in all migration notes; no transfer between those installations is assumed.
