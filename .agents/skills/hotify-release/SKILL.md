---
name: hotify-release
description: Prepare a Hotify release PR when the user asks to cut or prepare a release, or continue an existing release through an explicitly requested merge. Excludes discussion and review of release instructions.
---

# Hotify release

Prepare a version-bump PR. GitHub CI owns publication of the release tag and its GitHub Release after merging; the agent never needs to create either. Read the repository's `AGENTS.md` and [release operations](../../../docs/releases.md) before proceeding.

## Authorization

A request to cut or prepare a release authorizes the version bump, release branch, checks, commit, push, and PR. Merge only when the user explicitly requests it, including advance authorization such as "merge when green". Keep that authorization when resuming the same release.

Creating or editing this skill is not a request to cut a release. Manually submitting to Apple and changing Xcode Cloud settings are outside this workflow. Merging a release intentionally causes the automatic tag to trigger Xcode Cloud distribution for iOS and macOS, and a GitHub Release for the tag. Authorization to merge includes replacing that release's generated notes.

## Prepare

1. Inspect the working tree, remote, current version, remote release tags, and open release PRs. Fetch main and tags. Preserve unrelated changes, using a clean worktree when needed. Base a new release on current remote main. If intended changes are still on another branch, ask which changes belong in the release.
2. Resume an existing release branch or PR when it matches the request. Do not bump twice. If main already has an unreleased bump, read the operations guide and establish its status before preparing another bump.
3. Choose the version from the changes since the previous released tag on main. Use the user's explicit version or bump category when provided. If there is no prior tag, inspect the history and current version; ask only if the intended scope is unclear. Explain the chosen bump briefly.

   While on 0.x, apply this project convention:
   - Breaking changes increment minor and reset patch: `0.2.4 -> 0.3.0`.
   - Compatible features and fixes increment patch: `0.2.4 -> 0.2.5`.
   - Use the highest applicable category for a mixed release.
   - Move to `1.0.0` only on explicit instruction. After 1.0, use standard semantic versioning.

4. Create `release/MAJ.MIN.PATCH` before editing. Update every `MARKETING_VERSION` in `Hotify.xcodeproj/project.pbxproj` consistently. Preserve `CURRENT_PROJECT_VERSION` and other build-number settings exactly. Xcode Cloud owns the build number; exceptional synchronization is the developer's responsibility.
5. Review the diff. Run the macOS app build for the version configuration change, plus any checks required by `AGENTS.md` for other affected files. Run the required formatting and linting before committing, retaining only changes within the release's scope. Never run live Coolify tests unless requested.
6. Commit only intended release changes with `chore: bump version to MAJ.MIN.PATCH`, push the branch to the verified repository remote, and open a PR against main. Include the version, a short summary of changes since the previous release, and validation results. Register the PR with the host's PR-linking tool when available.
7. Wait for GitHub release validation and any configured required checks on the current PR revision. GitHub no longer runs app builds or package tests; Xcode Cloud owns builds and distribution. Missing, failed, and cancelled checks are not green. Diagnose failures and discuss the proposed repair with the user before making code or workflow changes. After approved fixes, verify the new revision. Stop on cancellation unless instructed to retry.

Without merge authorization, finish with the version, PR link, and CI result. State that merging will automatically request tagging and a GitHub Release after GitHub release validation succeeds on main.

## Merge when authorized

Recheck the current PR revision, checks, and mergeability. Use the repository's allowed merge method. Verify CI again after any branch update. Ask about conflicts requiring a product or implementation decision.

After merging, record the resulting main commit and observe its GitHub Release run, including `Tag release`. Confirm the remote `vMAJ.MIN.PATCH` tag resolves to that commit. If access permits, verify that Xcode Cloud started; otherwise report that it remains unverified. Never equate a pushed tag with a successful Apple build.

The same job publishes a GitHub Release titled `Hotify MAJ.MIN.PATCH` for the tag, with GitHub's generated notes. Confirm it exists on the tag, is neither a draft nor a prerelease, and is marked latest. Then replace its notes with the PR's summary of changes using `gh release edit vMAJ.MIN.PATCH --notes-file`. If the tag exists but the release step failed, rerun the failed job on the original run rather than creating the release by hand.

For failed CI, diagnose and discuss the repair. For cancelled CI, report the merged but untagged state and stop. Use the operations guide for recovery; do not manually tag a later main commit or move an existing tag.

Report the version, PR link, merge status, release validation status, tag status, GitHub Release link, and any blocker. The GitHub workflow must finish correctly even when the agent is no longer running.
