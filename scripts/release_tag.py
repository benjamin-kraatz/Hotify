"""Tag a tested main update only when its marketing version increases."""

import argparse
import os
import re
import subprocess

PROJECT = "Hotify.xcodeproj/project.pbxproj"
VERSION = re.compile(r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)")


def git(*args):
    return subprocess.check_output(["git", *args], text=True).strip()


def marketing_version(contents):
    values = re.findall(r"^\s*MARKETING_VERSION\s*=\s*([^;]+);", contents, re.MULTILINE)
    values = {value.strip().strip('"') for value in values}
    if len(values) != 1:
        raise ValueError(
            "Expected one consistent MARKETING_VERSION across configurations"
        )
    value = values.pop()
    if not VERSION.fullmatch(value):
        raise ValueError(f"Marketing version must be MAJ.MIN.PATCH: {value!r}")
    return value


def release_version(before, commit):
    # Require actual commit IDs so a moving branch cannot change the tag target.
    for revision in (before, commit):
        if not re.fullmatch(r"[0-9a-f]{40}", revision):
            raise ValueError("Expected full before and commit SHAs")
    subprocess.run(["git", "merge-base", "--is-ancestor", before, commit], check=True)
    previous = marketing_version(git("show", f"{before}:{PROJECT}"))
    current = marketing_version(git("show", f"{commit}:{PROJECT}"))
    if previous == current:
        return None
    if tuple(map(int, current.split("."))) <= tuple(map(int, previous.split("."))):
        raise ValueError(f"Marketing version must increase: {previous} -> {current}")
    return current


def remote_target(tag):
    ref = f"refs/tags/{tag}"
    refs = {}
    for line in git("ls-remote", "origin", ref, f"{ref}^{{}}").splitlines():
        sha, name = line.split()
        refs[name] = sha
    return refs.get(f"{ref}^{{}}", refs.get(ref))


def verify_target(tag, actual, expected):
    if actual != expected:
        raise ValueError(
            f"{tag} already points to {actual}; refusing to move it to {expected}"
        )


def publish_tag(version, commit):
    tag = f"v{version}"
    existing = remote_target(tag)
    if existing:
        verify_target(tag, existing, commit)
        return f"{tag} already exists on {commit}"

    ref = f"refs/tags/{tag}"
    local = subprocess.run(["git", "show-ref", "--verify", "--quiet", ref], check=False)
    if local.returncode == 0:
        verify_target(tag, git("rev-parse", f"{ref}^{{commit}}"), commit)
    elif local.returncode == 1:
        git(
            "-c",
            "user.name=github-actions[bot]",
            "-c",
            "user.email=41898282+github-actions[bot]@users.noreply.github.com",
            "tag",
            "-a",
            tag,
            commit,
            "-m",
            f"Hotify {version}",
        )
    else:
        raise RuntimeError("Unable to inspect local tags")

    # Push one tag only. A concurrent run may win, but may never move this tag.
    pushed = subprocess.run(["git", "push", "origin", f"{ref}:{ref}"], check=False)
    actual = remote_target(tag)
    if actual is None:
        raise RuntimeError(
            f"Tag push failed or {tag} is missing remotely (exit {pushed.returncode})"
        )
    verify_target(tag, actual, commit)
    return f"Published {tag} on {commit}"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--before", required=True)
    parser.add_argument("--commit", required=True)
    parser.add_argument(
        "--publish",
        action="store_true",
        help="Create and push the tag; default is read-only",
    )
    args = parser.parse_args()
    version = release_version(args.before, args.commit)
    if version is None:
        print("Marketing version unchanged; no release tag")
    elif args.publish:
        print(publish_tag(version, args.commit))
        # Tell the workflow which tag exists, so a later step can publish its GitHub Release.
        output = os.environ.get("GITHUB_OUTPUT")
        if output:
            with open(output, "a", encoding="utf-8") as file:
                file.write(f"tag=v{version}\n")
    else:
        print(f"Would tag {args.commit} as v{version}")


if __name__ == "__main__":
    main()
