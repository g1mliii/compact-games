# PressPlay Project Initialization Script
# Run once to bootstrap the development environment.
# Usage: .\init.ps1 [-SkipRust] [-SkipFlutter] [-SkipBridge]

param(
    [switch]$SkipRust,
    [switch]$SkipFlutter,
    [switch]$SkipBridge
)

$ErrorActionPreference = "Stop"
$ProjectRoot = $PSScriptRoot

function Write-Step($msg) { Write-Host "`n[STEP] $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "  [OK] $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "  [WARN] $msg" -ForegroundColor Yellow }
function Write-Fail($msg) { Write-Host "  [FAIL] $msg" -ForegroundColor Red; exit 1 }

# -----------------------------------------------------------------------------
# Prerequisites
# -----------------------------------------------------------------------------
Write-Step "Checking prerequisites"

if (!(Get-Command "rustc" -ErrorAction SilentlyContinue)) {
    Write-Fail "Rust not found. Install from https://rustup.rs/"
}
Write-Ok "Rust $(rustc --version)"

if (!(Get-Command "cargo" -ErrorAction SilentlyContinue)) {
    Write-Fail "Cargo not found."
}
Write-Ok "Cargo $(cargo --version)"

if (!(Get-Command "flutter" -ErrorAction SilentlyContinue)) {
    Write-Fail "Flutter not found. Install from https://flutter.dev/"
}
$flutterVer = (flutter --version 2>&1 | Select-Object -First 1)
Write-Ok "Flutter $flutterVer"

# Ensure Windows desktop support is enabled
flutter config --enable-windows-desktop 2>&1 | Out-Null

# -----------------------------------------------------------------------------
# Rust project
# -----------------------------------------------------------------------------
if (!$SkipRust) {
    Write-Step "Setting up Rust project"

    $rustDir = Join-Path $ProjectRoot "rust"

    if (!(Test-Path (Join-Path $rustDir "Cargo.toml"))) {
        Write-Warn "No Cargo.toml found -- expecting source files already created."
        Write-Warn "If starting fresh, create rust/ files first then re-run."
    } else {
        Write-Ok "rust/Cargo.toml exists"
    }

    # Create module directories (idempotent)
    $modules = @(
        "src/api",
        "src/compression",
        "src/safety",
        "src/discovery",
        "src/automation",
        "src/progress"
    )
    foreach ($mod in $modules) {
        $dir = Join-Path $rustDir $mod
        if (!(Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
    }
    Write-Ok "Rust module directories ready"

    # Verify compilation
    Push-Location $rustDir
    Write-Step "Running cargo check"
    cargo check 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Ok "Rust project compiles"
    } else {
        Write-Warn "Rust compilation has errors -- fix before proceeding"
    }
    Pop-Location
}

# -----------------------------------------------------------------------------
# Flutter project
# -----------------------------------------------------------------------------
if (!$SkipFlutter) {
    Write-Step "Setting up Flutter project"

    if (!(Test-Path (Join-Path $ProjectRoot "pubspec.yaml"))) {
        Push-Location $ProjectRoot
        flutter create . --org com.pressplay --project-name pressplay --platforms windows 2>&1
        Pop-Location
        Write-Ok "Flutter project created"
    } else {
        Write-Ok "pubspec.yaml already exists"
    }

    # Create feature-first directory structure (idempotent)
    $dirs = @(
        "lib/core/theme",
        "lib/core/constants",
        "lib/core/widgets",
        "lib/features/games/data",
        "lib/features/games/domain",
        "lib/features/games/presentation",
        "lib/features/compression/data",
        "lib/features/compression/domain",
        "lib/features/compression/presentation",
        "lib/features/settings/data",
        "lib/features/settings/domain",
        "lib/features/settings/presentation",
        "lib/providers",
        "lib/services"
    )
    foreach ($d in $dirs) {
        $full = Join-Path $ProjectRoot $d
        if (!(Test-Path $full)) {
            New-Item -ItemType Directory -Path $full -Force | Out-Null
        }
    }
    Write-Ok "Flutter directory structure ready"

    # Resolve dependencies
    Push-Location $ProjectRoot
    flutter pub get 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Ok "Flutter dependencies resolved"
    } else {
        Write-Warn "flutter pub get had issues -- check pubspec.yaml"
    }
    Pop-Location
}

# -----------------------------------------------------------------------------
# Flutter Rust Bridge
# -----------------------------------------------------------------------------
if (!$SkipBridge) {
    Write-Step "Checking flutter_rust_bridge_codegen"

    if (Get-Command "flutter_rust_bridge_codegen" -ErrorAction SilentlyContinue) {
        Write-Ok "flutter_rust_bridge_codegen found"
    } else {
        Write-Warn "flutter_rust_bridge_codegen not found."
        Write-Warn "Install with: cargo install flutter_rust_bridge_codegen"
        Write-Warn "Then run: flutter_rust_bridge_codegen generate"
    }
}

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
Write-Step "Initialization summary"
Write-Ok "Project root: $ProjectRoot"

$checks = @(
    @{ Name = "rust/Cargo.toml";  Path = "rust/Cargo.toml" },
    @{ Name = "pubspec.yaml";     Path = "pubspec.yaml" },
    @{ Name = "lib/main.dart";    Path = "lib/main.dart" },
    @{ Name = "rust/src/lib.rs";  Path = "rust/src/lib.rs" }
)
foreach ($c in $checks) {
    $full = Join-Path $ProjectRoot $c.Path
    if (Test-Path $full) {
        Write-Ok "$($c.Name) exists"
    } else {
        Write-Warn "$($c.Name) missing"
    }
}

Write-Host "`nNext steps:" -ForegroundColor White
Write-Host "  1. cargo check            (in rust/)" -ForegroundColor Gray
Write-Host "  2. flutter pub get" -ForegroundColor Gray
Write-Host "  3. flutter run -d windows  (smoke test)" -ForegroundColor Gray
Write-Host ""
