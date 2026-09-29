#!/bin/sh
# This target build phase runs for local builds and Xcode Cloud archives, before signing.
set -eu

repo=${SRCROOT:?SRCROOT must identify the source checkout}
output=${SCRIPT_OUTPUT_FILE_0:?Declare the BuildInfo.json output in the build phase}

# Personal Git settings must not invoke hooks or change how we inspect the checkout.
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_OPTIONAL_LOCKS=0

commit=$(git -C "$repo" rev-parse --verify HEAD)
case "$commit" in
    *[!0-9a-f]*|'') echo 'error: Cannot determine the source commit' >&2; exit 1 ;;
esac
if [ "${#commit}" -ne 40 ]; then
    echo 'error: Expected a full Git commit SHA' >&2
    exit 1
fi

# Cloud PR builds can use a synthetic merge; HEAD is the source actually compiled.
# For tag distributions, require the checkout to match the Cloud-provided commit.
if [ -n "${CI_TAG:-}" ] && [ -n "${CI_COMMIT:-}" ] && [ "$commit" != "$CI_COMMIT" ]; then
    echo 'error: Tag build checkout does not match CI_COMMIT' >&2
    exit 1
fi

mkdir -p "$(dirname "$output")"
printf '{"commit":"%s"}\n' "$commit" > "$output"
