# Releases

Ask an agent to "cut a release" or invoke `$hotify-release`. The repository skill is in `.agents/skills/hotify-release/SKILL.md`. This prepares `release/MAJ.MIN.PATCH`, commits the marketing-version bump, pushes it, opens a PR, and waits for PR CI. Merging requires an explicit request, or you can merge the PR yourself at any time.

## Automatic tagging

Merging a marketing-version increase into main requests a release. PR titles, bodies, labels, and branch names do not control tagging. Direct pushes that increase the version on main have the same effect.

The GitHub Release workflow compares `MARKETING_VERSION` before and after the main push. All configurations must agree on a numeric `MAJ.MIN.PATCH`, and a changed version must increase. After the release automation tests and version validation pass, `Tag release` creates an annotated `vMAJ.MIN.PATCH` tag on that run's exact commit and pushes only that tag. Only the tagging job receives `contents: write` permission.

Ordinary commits with an unchanged version do not publish tags, even when that version has no tag yet. A push containing multiple commits releases only its final version. Keep each intended release bump in its own merge/push.

The build number is unchanged. Xcode Cloud owns it.

Xcode Cloud builds pushes to main and distributes iOS and macOS builds from release tags. GitHub no longer builds or tests the app or API package. Tagging does not wait for the independent Xcode Cloud main build. A successful GitHub Release run confirms release validation and tagging, not a successful app build or distribution.

## Xcode Cloud setup and first-run acceptance

Configure the Xcode Cloud release workflow with a **Tag Changes** start condition matching `v*`. Verify the repository connection and the workflow's intended archive/distribution actions. Remove other start conditions from that release workflow if it should run only for tags. See [Apple's workflow reference](https://developer.apple.com/documentation/xcode/xcode-cloud-workflow-reference).

Once this automation is on main, use the first intended release to verify:

1. The PR passes CI and merges.
2. The GitHub Release workflow succeeds, including `Tag release`.
3. The GitHub tag resolves to the main commit validated by that run.
4. Xcode Cloud distributes both platforms for that tag, using the expected marketing version and its own build number. About shows the tag commit, and Copy build details includes the full SHA.

No extra token is configured initially. GitHub's built-in `GITHUB_TOKEN` can publish tags with the job's write permission, subject to repository rules. Its events do not start another GitHub Actions workflow; verify Xcode Cloud delivery separately rather than assuming either outcome. See [GitHub's event documentation](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows). If the Apple integration does not receive the event, investigate the connection and event delivery before choosing a GitHub App credential or another trigger mechanism.

## Recovery

- A failed or cancelled dependency leaves the release untagged. For a transient failure, rerun the original main Release run. Rerunning a job preserves the run's original commit and before/after version comparison. A manually dispatched Release run does not tag.
- If a code fix requires a new commit, rerunning the old run cannot include that fix. Discuss whether to abandon the untagged version and prepare the next version. An ordinary fix commit with the same version intentionally does not publish the abandoned release.
- If only tagging fails, fix the permission or connectivity issue and rerun failed jobs on the original run. An existing remote tag on the expected commit counts as success. A tag on a different commit causes an error and is never moved or deleted.
- If tagging succeeds but Xcode Cloud does not start, repair or manually start the Apple workflow for the existing tag. Do not recreate the Git tag to retrigger it.
- If main is force-pushed or its previous commit is unavailable, validation fails rather than guessing the release baseline.

## Embedded build identity

The app target runs `scripts/write_build_info.sh` for every local build and Cloud archive, before code signing. It writes the full checked-out `HEAD` SHA into the built app's `BuildInfo.json`; no generated metadata is committed. The About view displays seven characters and copies the full SHA. Version and build still come from the final app Info.plist. No new Xcode Cloud secret or manually maintained hash is needed.

The phase always runs so switching commits cannot retain a cached SHA. The SHA identifies the checked-out commit; local edits do not change it. When Cloud tag/commit variables are available, a checkout mismatch fails the build. Builds without Git metadata fail instead of shipping an unknown or stale SHA.

The app target disables build-script sandboxing for this phase's Git inspection because linked worktrees keep refs outside the source directory. App Sandbox and hardened runtime settings are unchanged. The script writes only its declared app-resource output.

Run `python3 -B -m unittest discover -s Tests -p 'test_build_info.py' -v` to check metadata generation, incremental changes, detached tags, Cloud context, and linked worktrees. The first distributed Cloud build still needs live verification.

## Local checks

Run `python3 -B -m unittest discover -s Tests -p 'test_release_tag.py' -v`. These tests use disposable local Git repositories and never contact GitHub.

To inspect a proposed update without publishing, run `python3 -B scripts/release_tag.py --before FULL_BASE_SHA --commit FULL_TESTED_SHA`. Publishing requires the explicit `--publish` flag, which CI supplies only after successful main checks.
