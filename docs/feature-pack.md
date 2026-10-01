# Operations feature pack

Integration branch: `feat/feature-pack`. The draft umbrella PR targets `main`.
Each feature PR targets the integration branch. No marketing-version change is included.

## Agreed scope

- Deployment details: searchable build output, progress, commit and timing details, older history.
- Database backups: history, failure details, and back up now. No schedule editing or restore.
- Variable comparison and sync: manual source-to-destination operations across instances, selected or all variables, explicit review, optional destination matching with reviewed deletions. Prompt for redeploy or restart after writes, including ordinary edits. Never automatically sync or redeploy.
- Mac menu bar: opt-in monitoring with selected resources, status, deployment progress, and navigation to resources. Keep running after the last window closes when enabled.
- Failure explanation: on a failed deployment, a button asks the on-device Apple Intelligence model what went wrong and shows the cause, the log lines behind it, and what to try. On-device model only. The button is hidden on iOS 18, on unsupported devices, and while Apple Intelligence is off or its model still downloads.

## Delivery and verification

Each feature has its own branch and PR. Merge reviewed feature work into this branch before final whole-pack acceptance. Keep the umbrella PR in draft until acceptance is complete.

Use mock HTTP fixtures for decoding, write request shapes, two-instance sync, and partial failures. Run package tests, macOS builds, formatting and strict lint before feature commits. Verify iOS compilation and native interactions for the combined pack. Live checks require designated disposable resources; mocks do not prove live Coolify behavior. Never use the real `.env` token for fixture work.

## Status

- [x] Deployment details
- [x] Database backups
- [x] Variable comparison and sync
- [x] Mac menu bar implementation
- [x] Failure explanation
- [ ] Combined native acceptance

## Native fixture workflow

Run `python3 scripts/mock_coolify.py` to start two in-memory HTTP fixtures on loopback ports 18081 and 18082. They serve deployment output/history, backup history, variables, and manual writes. They also take New Service end to end: projects and environments, service create, setup, and delete, and a start whose containers come up a few seconds later. An address containing `taken.example` answers 409 until it is forced. Two projects with three environments feed the project page: application history with previews, shared variables, and renames, which answer 409 and 422 the way Coolify does. The three applications, the database, and the `metrics` service keep their settings, so the Settings tab can change names, domains, health checks, and the database's public port. Public port 5432 answers 400 as taken. The template gallery itself still loads Coolify's public catalog from cdn.coollabs.io. Restarting the script resets all fixture data. It never reads `.env`, logs request bodies, or contacts another host.

Launch a Debug build with `HOTIFY_FIXTURES=1`. This supplies two in-memory instances and fake clients, disables the variable lock for fixture values, and refuses instance edits. Release builds do not include this entry point. Use a separate Mac bundle identifier, for example `PRODUCT_BUNDLE_IDENTIFIER=de.benn.HotifyFixtures`, to keep menu bar preferences separate from the installed app. The iOS simulator can receive the flag through `SIMCTL_CHILD_HOTIFY_FIXTURES=1 xcrun simctl launch <device-id> com.sebastiankraatz.Hotify`.

The fixtures intentionally implement a small API subset. Package tests cover withheld values, flags, scope isolation, stale comparisons, request bodies, and partial failure. Native fixture success does not establish live Coolify compatibility.

## Acceptance evidence

- Feature PRs #9, #10, #11 and #12 merged into the integration branch; `main` and the marketing version remain unchanged.
- 17 package tests passed; the opt-in live test remained skipped.
- macOS and iOS 18.6 simulator builds passed before the fixture acceptance fixes; final checks are recorded in the supporting PR.
- Mac native checks: opened deployment output and filtered it to the error line; expanded a backup failure; confirmed a backup and observed the new successful execution; enabled the menu bar option and added a watched resource.
- iOS 18.6 native checks: opened deployment details; compared variables between two fixture instances, selected two changes, reviewed and applied them, and accepted the separate redeploy prompt. Fixture request records confirm PATCH envs, POST envs, then POST deploy, with no deletion.
- Acceptance fixes: a scrolling grouped comparison form on Mac, clearer flag labels, generation-safe history pagination state, and detail identity including the instance.
- Outstanding: direct menu bar popover/navigation and final close/reopen acceptance. The native inspector could operate Settings but did not reliably expose the status item. Disposable live Coolify checks also remain outstanding and require designated resources.
