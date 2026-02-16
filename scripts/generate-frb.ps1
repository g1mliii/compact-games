param(
    [switch]$Verify
)

$ErrorActionPreference = "Stop"

$expectedVersion = "2.11.1"
$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

if (-not (Get-Command "flutter_rust_bridge_codegen" -ErrorAction SilentlyContinue)) {
    throw "flutter_rust_bridge_codegen is not installed. Install with: cargo install flutter_rust_bridge_codegen --version $expectedVersion"
}

$versionOutput = & flutter_rust_bridge_codegen --version
if ($versionOutput -notmatch [regex]::Escape($expectedVersion)) {
    throw "Expected flutter_rust_bridge_codegen $expectedVersion, got: $versionOutput"
}

& flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

if ($Verify) {
    & cargo check --manifest-path rust/Cargo.toml
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }

    & flutter analyze
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}
