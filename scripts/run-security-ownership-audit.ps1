param(
  [string]$Since = "12 months ago",
  [string]$OutDir = "ownership-map-out-pressplay-sensitive",
  [switch]$EmitCommits
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$skillScripts = "C:/Users/subai/.codex/skills/security-ownership-map/scripts"
$runScript = Join-Path $skillScripts "run_ownership_map.py"
$queryScript = Join-Path $skillScripts "query_ownership.py"
$sensitiveConfig = Join-Path $repoRoot "tasks/security_sensitive_rules.csv"
$expectedRunScriptSha256 = "58182cdf3484b86543e545e84654352c729a99d77eb367aecb80edb9d7738bfe"
$expectedQueryScriptSha256 = "5a94b9db2b09b77f514d861764ea2b21e74b2caec86f888a82ec9b5c846712a1"

function Get-FileHashLower {
  param(
    [Parameter(Mandatory = $true)][string]$Path
  )
  return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Invoke-PreferredPython {
  param(
    [Parameter(Mandatory = $true)][string[]]$Arguments
  )

  $pyLauncher = Get-Command "py" -ErrorAction SilentlyContinue
  if ($pyLauncher) {
    & $pyLauncher.Source -3 @Arguments
    return $LASTEXITCODE
  }

  $python = Get-Command "python" -ErrorAction SilentlyContinue
  if ($python) {
    & $python.Source @Arguments
    return $LASTEXITCODE
  }

  throw "Python interpreter not found. Install Python 3 and ensure `py` or `python` is available."
}

if (-not (Test-Path $runScript)) {
  throw "security-ownership-map runner not found: $runScript"
}
if (-not (Test-Path $queryScript)) {
  throw "security-ownership-map query tool not found: $queryScript"
}
if (-not (Test-Path $sensitiveConfig)) {
  throw "Sensitive config not found: $sensitiveConfig"
}
if ((Get-FileHashLower -Path $runScript) -ne $expectedRunScriptSha256) {
  throw "Integrity check failed for run_ownership_map.py"
}
if ((Get-FileHashLower -Path $queryScript) -ne $expectedQueryScriptSha256) {
  throw "Integrity check failed for query_ownership.py"
}

$emitArgs = @()
if ($EmitCommits) {
  $emitArgs += "--emit-commits"
}

Write-Host "[ownership] Running security ownership map..."
$runArgs = @(
  $runScript,
  "--repo", $repoRoot,
  "--out", $OutDir,
  "--since", $Since,
  "--sensitive-config", $sensitiveConfig
) + $emitArgs
$exitCode = Invoke-PreferredPython -Arguments $runArgs
if ($exitCode -ne 0) {
  exit $exitCode
}

Write-Host "[ownership] Summary slices:"
foreach ($section in @("orphaned_sensitive_code", "hidden_owners", "bus_factor_hotspots")) {
  $queryArgs = @(
    $queryScript,
    "--data-dir", $OutDir,
    "summary",
    "--section", $section
  )
  $queryExitCode = Invoke-PreferredPython -Arguments $queryArgs
  if ($queryExitCode -ne 0) {
    exit $queryExitCode
  }
}

$summaryPath = Join-Path $OutDir "summary.json"
if (-not (Test-Path $summaryPath)) {
  throw "Expected summary output missing: $summaryPath"
}

$summary = Get-Content $summaryPath | ConvertFrom-Json
$hotspots = @($summary.bus_factor_hotspots).Count
$hiddenOwners = @($summary.hidden_owners).Count
$orphaned = @($summary.orphaned_sensitive_code).Count

Write-Host "[ownership] generated_at=$($summary.generated_at)"
Write-Host "[ownership] bus_factor_hotspots=$hotspots hidden_owners=$hiddenOwners orphaned_sensitive_code=$orphaned"
