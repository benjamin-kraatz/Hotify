# Operations feature pack

Integration branch: `feat/feature-pack`. The draft umbrella PR targets `main`.
Each feature PR targets the integration branch. No marketing-version change is included.

## Agreed scope

- Deployment details: searchable build output, progress, commit and timing details, older history.
- Database backups: history, failure details, and back up now. No schedule editing or restore.
- Variable comparison and sync: manual source-to-destination operations across instances, selected or all variables, explicit review, optional destination matching with reviewed deletions. Prompt for redeploy or restart after writes, including ordinary edits. Never automatically sync or redeploy.
- Mac menu bar: opt-in monitoring with selected resources, status, deployment progress, and navigation to resources. Keep running after the last window closes when enabled.

## Delivery and verification

Each feature has its own branch and PR. Merge reviewed feature work into this branch before final whole-pack acceptance. Keep the umbrella PR in draft until acceptance is complete.

Use mock HTTP fixtures for decoding, write request shapes, two-instance sync, and partial failures. Run package tests, macOS builds, formatting and strict lint before feature commits. Verify iOS compilation and native interactions for the combined pack. Live checks require designated disposable resources; mocks do not prove live Coolify behavior. Never use the real `.env` token for fixture work.

## Status

- [ ] Deployment details
- [ ] Database backups
- [ ] Variable comparison and sync
- [ ] Mac menu bar
- [ ] Combined native acceptance
