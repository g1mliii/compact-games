#!/usr/bin/env python3
"""Validate the version sources that identify a Compact Games release."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


VERSION_PATTERN = re.compile(r"^\d+\.\d+\.\d+$")


def read_match(path: Path, pattern: str, description: str) -> str:
    match = re.search(pattern, path.read_text(encoding="utf-8"), re.MULTILINE)
    if match is None:
        raise ValueError(f"Could not read {description} from {path}.")
    return match.group(1)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--expected-version")
    args = parser.parse_args()

    pubspec_version = read_match(
        Path("pubspec.yaml"),
        r"^version:\s*(\d+\.\d+\.\d+)(?:\+\d+)?\s*$",
        "the pubspec version",
    )
    app_version = read_match(
        Path("lib/core/constants/app_constants.dart"),
        r"appVersion\s*=\s*'([^']+)'",
        "AppConstants.appVersion",
    )

    expected_version = args.expected_version
    if expected_version is not None and not VERSION_PATTERN.fullmatch(expected_version):
        raise ValueError(f"Expected version must be MAJOR.MINOR.PATCH, got {expected_version!r}.")

    versions = {"pubspec": pubspec_version, "app_constants": app_version}
    if expected_version is not None:
        versions["expected"] = expected_version

    if len(set(versions.values())) != 1:
        rendered_versions = ", ".join(f"{source}={version}" for source, version in versions.items())
        raise ValueError(f"Release version sources do not match: {rendered_versions}.")

    print(f"Release source version verified: {pubspec_version}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ValueError as error:
        print(error, file=sys.stderr)
        raise SystemExit(1) from error
