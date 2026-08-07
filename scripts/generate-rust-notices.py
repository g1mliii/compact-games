from __future__ import annotations

import argparse
import json
import re
import subprocess
from pathlib import Path


# Crates spell their license text a dozen ways: LICENSE/LICENCE, UNLICENSE,
# COPYING, COPYRIGHT, NOTICE, and any of those with a suffix (LICENSE-MIT,
# LICENSE.md). Missing a spelling makes generate() raise and fails packaging,
# so match the known variants rather than only the three most common ones.
NOTICE_FILE = re.compile(
    r"^(un)?(licen[cs]e|copying|copyright|notice)(?:$|[._-])",
    re.IGNORECASE,
)
NOTICE_DIRS = ("licenses", "licences")
PACKAGE_LINE = re.compile(r"^(?P<name>\S+) v(?P<version>\S+)")
LICENSE_OVERRIDES = {
    ("dart-sys", "4.1.5"): "dart-sys-4.1.5-LICENSE-MIT.txt",
    ("flutter_rust_bridge", "2.12.0"): "flutter-rust-bridge-2.12.0-LICENSE.txt",
    ("flutter_rust_bridge_macros", "2.12.0"): "flutter-rust-bridge-2.12.0-LICENSE.txt",
}


def cargo_metadata(manifest: Path) -> dict[str, object]:
    output = subprocess.check_output(
        [
            "cargo.exe",
            "metadata",
            "--manifest-path",
            str(manifest),
            "--format-version",
            "1",
            "--locked",
        ]
    )
    return json.loads(output)


def resolved_package_keys(manifest: Path, target: str) -> set[tuple[str, str]]:
    output = subprocess.check_output(
        [
            "cargo.exe",
            "tree",
            "--manifest-path",
            str(manifest),
            "--target",
            target,
            "--edges",
            "normal,build",
            "--prefix",
            "none",
            "--format",
            "{p}",
            "--locked",
        ],
        text=True,
    )
    keys: set[tuple[str, str]] = set()
    for line in output.splitlines():
        match = PACKAGE_LINE.match(line)
        if match:
            keys.add((match.group("name"), match.group("version")))
    return keys


def notice_paths(package: dict[str, object]) -> list[Path]:
    crate_dir = Path(str(package["manifest_path"])).parent
    candidates = {
        path.resolve()
        for path in crate_dir.iterdir()
        if path.is_file() and NOTICE_FILE.match(path.name)
    }
    # Some crates keep only a LICENSES/ directory (one file per SPDX id).
    for entry in crate_dir.iterdir():
        if entry.is_dir() and entry.name.lower() in NOTICE_DIRS:
            candidates.update(
                path.resolve() for path in entry.iterdir() if path.is_file()
            )
    license_file = package.get("license_file")
    if license_file:
        path = Path(str(license_file))
        if not path.is_absolute():
            path = crate_dir / path
        if path.is_file():
            candidates.add(path.resolve())
    return sorted(candidates, key=lambda path: path.name.lower())


def generate(manifest: Path, output: Path, target: str, overrides: Path) -> None:
    metadata = cargo_metadata(manifest)
    workspace_members = set(metadata["workspace_members"])
    resolved = resolved_package_keys(manifest, target)
    packages = sorted(
        (
            package
            for package in metadata["packages"]
            if package["id"] not in workspace_members
            and (str(package["name"]), str(package["version"])) in resolved
        ),
        key=lambda package: (str(package["name"]).lower(), str(package["version"])),
    )

    sections = [
        "Compact Games - Rust Third-Party Notices",
        "",
        "Generated from Cargo metadata and the license files distributed with each crate.",
        "This file is informational and does not replace the license terms below.",
        f"Selected Rust target: {target}",
        "",
    ]
    for package in packages:
        name = str(package["name"])
        version = str(package["version"])
        license_expression = package.get("license") or "See included license file"
        repository = package.get("repository") or package.get("homepage") or ""
        sections.extend(
            [
                "=" * 80,
                f"{name} {version}",
                f"SPDX/license declaration: {license_expression}",
            ]
        )
        if repository:
            sections.append(f"Project: {repository}")

        paths = notice_paths(package)
        if not paths:
            override_name = LICENSE_OVERRIDES.get((name, version))
            override_path = overrides / override_name if override_name else None
            if override_path is None or not override_path.is_file():
                raise RuntimeError(
                    f"No license text is available for resolved dependency {name} {version}. "
                    "Add and review a version-pinned license override before packaging."
                )
            sections.extend(
                [
                    "",
                    f"--- reviewed override: {override_path.name} ---",
                    override_path.read_text(encoding="utf-8", errors="strict").rstrip(),
                ]
            )
        for path in paths:
            sections.extend(
                [
                    "",
                    f"--- {path.name} ---",
                    path.read_text(encoding="utf-8", errors="replace").rstrip(),
                ]
            )
        sections.append("")

    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text("\n".join(sections).rstrip() + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate Rust dependency notices.")
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--target", default="x86_64-pc-windows-msvc")
    parser.add_argument("--license-overrides", type=Path, required=True)
    args = parser.parse_args()
    generate(
        args.manifest.resolve(),
        args.out.resolve(),
        args.target,
        args.license_overrides.resolve(),
    )


if __name__ == "__main__":
    main()
