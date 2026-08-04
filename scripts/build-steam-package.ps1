param(
  [string]$AppId = '',
  [string]$DepotId = '',
  [string]$Description = '',
  [string]$FlutterExecutable = 'flutter.bat',
  [switch]$SkipCompile,
  [switch]$AllowMissingCoverProxy
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$pubspecPath = Join-Path $repoRoot 'pubspec.yaml'
$pubspec = Get-Content -LiteralPath $pubspecPath -Raw
$versionMatch = [regex]::Match($pubspec, '(?m)^version:\s*([^+\s]+)(?:\+\d+)?\s*$')
if (-not $versionMatch.Success) {
  throw 'Could not read the application version from pubspec.yaml.'
}

$version = $versionMatch.Groups[1].Value
$releaseDir = Join-Path $repoRoot 'build\windows\x64\runner\Release'
$rustDll = Join-Path $repoRoot 'rust\target\release\compact_games_core.dll'
$buildMetadataPath = Join-Path $releaseDir 'compact_games_build.json'
$steamRoot = Join-Path $repoRoot 'dist\steam'
$contentDir = Join-Path $steamRoot 'content'
$scriptsDir = Join-Path $steamRoot 'scripts'
$outputDir = Join-Path $steamRoot 'output'
$repoRootFull = [System.IO.Path]::GetFullPath($repoRoot).TrimEnd('\') + '\'
$contentDirFull = [System.IO.Path]::GetFullPath($contentDir)
if (-not $contentDirFull.StartsWith($repoRootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
  throw "Refusing to stage Steam content outside the repository: $contentDirFull"
}
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$requiredFlutterVersion = '3.44.8'

function Get-Sha256Lower([string]$Path) {
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Assert-SteamBuildMetadata {
  if (-not (Test-Path -LiteralPath $buildMetadataPath -PathType Leaf)) {
    throw 'Cannot skip compilation because compact_games_build.json is missing. Only a bundle produced by this script can be restaged.'
  }

  try {
    $metadata = Get-Content -LiteralPath $buildMetadataPath -Raw | ConvertFrom-Json
  } catch {
    throw "Cannot skip compilation because compact_games_build.json is invalid: $($_.Exception.Message)"
  }

  if ($metadata.distributionChannel -ne 'steam') {
    throw "Cannot stage a '$($metadata.distributionChannel)' bundle as Steam content."
  }
  if ($metadata.version -ne $version) {
    throw "Cannot stage Steam build version $($metadata.version) while pubspec.yaml declares $version."
  }
  if (-not $metadata.coverProxyConfigured -and -not $AllowMissingCoverProxy) {
    throw 'This Steam bundle was built without the cover proxy. Rebuild with both proxy variables or explicitly pass -AllowMissingCoverProxy for non-production validation.'
  }

  $artifacts = @(
    @{ Path = (Join-Path $releaseDir 'compact_games.exe'); Hash = $metadata.executableSha256; Label = 'compact_games.exe' },
    @{ Path = (Join-Path $releaseDir 'data\app.so'); Hash = $metadata.appSoSha256; Label = 'data\app.so' },
    @{ Path = $rustDll; Hash = $metadata.rustCoreSha256; Label = 'compact_games_core.dll' }
  )
  foreach ($artifact in $artifacts) {
    if (-not (Test-Path -LiteralPath $artifact.Path -PathType Leaf)) {
      throw "Cannot skip compilation because $($artifact.Label) is missing."
    }
    if ([string]::IsNullOrWhiteSpace($artifact.Hash) -or
        (Get-Sha256Lower $artifact.Path) -ne $artifact.Hash) {
      throw "Cannot skip compilation because $($artifact.Label) no longer matches the recorded Steam build."
    }
  }
}

if ([string]::IsNullOrWhiteSpace($Description)) {
  $Description = "Compact Games $version"
}
if (($AppId -and -not $DepotId) -or ($DepotId -and -not $AppId)) {
  throw 'Pass both -AppId and -DepotId, or omit both while waiting for Steamworks IDs.'
}
if ($AppId -and ($AppId -notmatch '^\d+$' -or $DepotId -notmatch '^\d+$')) {
  throw 'Steam App ID and Depot ID must contain digits only.'
}

$proxyUrl = $env:COMPACT_GAMES_SGDB_PROXY_URL
$proxyToken = $env:COMPACT_GAMES_SGDB_TOKEN
$hasProxyUrl = -not [string]::IsNullOrWhiteSpace($proxyUrl)
$hasProxyToken = -not [string]::IsNullOrWhiteSpace($proxyToken)
if ($hasProxyUrl -ne $hasProxyToken) {
  throw 'Both COMPACT_GAMES_SGDB_PROXY_URL and COMPACT_GAMES_SGDB_TOKEN are required together.'
}
$coverProxyConfigured = $hasProxyUrl -and $hasProxyToken
if (-not $coverProxyConfigured -and -not $AllowMissingCoverProxy -and -not $SkipCompile) {
  throw 'Steam release packaging requires the cover proxy. Set both proxy variables, or pass -AllowMissingCoverProxy only for non-production validation.'
}

Push-Location $repoRoot
try {
  if (-not $SkipCompile) {
    $flutterCommand = Get-Command $FlutterExecutable -ErrorAction SilentlyContinue
    if (-not $flutterCommand) {
      throw "Flutter executable was not found: $FlutterExecutable"
    }
    $flutterPath = $flutterCommand.Source
    $flutterVersionJson = & $flutterPath --version --machine
    if ($LASTEXITCODE -ne 0) { throw 'Could not inspect the Flutter SDK version.' }
    try {
      $flutterVersion = ($flutterVersionJson | ConvertFrom-Json).frameworkVersion
    } catch {
      throw "Could not parse Flutter version output from $flutterPath"
    }
    if ($flutterVersion -ne $requiredFlutterVersion) {
      throw "Steam packaging requires Flutter $requiredFlutterVersion, but $flutterPath reports $flutterVersion. Pass -FlutterExecutable with the pinned SDK path."
    }
    $flutterBin = Split-Path -Parent $flutterPath
    $env:PATH = "$flutterBin;$env:PATH"

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'scripts\generate-frb.ps1'
    if ($LASTEXITCODE -ne 0) { throw 'Flutter Rust Bridge generation failed.' }

    & cargo.exe build --manifest-path 'rust\Cargo.toml' --release
    if ($LASTEXITCODE -ne 0) { throw 'Rust release build failed.' }

    $flutterArgs = @(
      'build', 'windows', '--release',
      '--dart-define=COMPACT_GAMES_DISTRIBUTION=steam'
    )
    if ($coverProxyConfigured) {
      $flutterArgs += "--dart-define=COMPACT_GAMES_SGDB_PROXY_URL=$proxyUrl"
      $flutterArgs += "--dart-define=COMPACT_GAMES_SGDB_TOKEN=$proxyToken"
    } else {
      Write-Warning 'Building a non-production Steam validation bundle without the cover proxy.'
    }

    & $flutterPath @flutterArgs
    if ($LASTEXITCODE -ne 0) { throw 'Flutter Steam release build failed.' }
  } else {
    if (-not (Test-Path -LiteralPath $releaseDir -PathType Container)) {
      throw 'Cannot skip compilation because no Windows release bundle exists.'
    }
    Assert-SteamBuildMetadata
  }

  if (-not (Test-Path -LiteralPath $rustDll -PathType Leaf)) {
    throw "Rust DLL is missing: $rustDll"
  }
  Copy-Item -LiteralPath $rustDll -Destination $releaseDir -Force

  $runtimeRoots = @(
    'C:\Program Files\Microsoft Visual Studio',
    'C:\Program Files (x86)\Microsoft Visual Studio'
  )
  $runtimeFiles = @('vcruntime140.dll', 'vcruntime140_1.dll', 'msvcp140.dll')
  $runtimeDir = Get-ChildItem -LiteralPath $runtimeRoots -Directory -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match 'Microsoft\.VC.*\.CRT' -and $_.FullName -match '\\x64($|\\)' } |
    Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'vcruntime140.dll') } |
    Select-Object -First 1
  if ($runtimeDir) {
    foreach ($runtimeFile in $runtimeFiles) {
      $runtimePath = Join-Path $runtimeDir.FullName $runtimeFile
      if (-not (Test-Path -LiteralPath $runtimePath -PathType Leaf)) {
        throw "VC++ runtime file is missing: $runtimePath"
      }
      Copy-Item -LiteralPath $runtimePath -Destination $releaseDir -Force
    }
  } else {
    throw 'VC++ runtime DLLs were not found. Install the Visual C++ build tools before packaging.'
  }

  Copy-Item -LiteralPath (Join-Path $repoRoot 'LICENSE') -Destination (Join-Path $releaseDir 'LICENSE.txt') -Force
  & python.exe 'scripts\generate-rust-notices.py' `
    --manifest 'rust\Cargo.toml' `
    --out (Join-Path $releaseDir 'THIRD_PARTY_NOTICES-RUST.txt') `
    --target 'x86_64-pc-windows-msvc' `
    --license-overrides 'third_party\rust-license-overrides'
  if ($LASTEXITCODE -ne 0) { throw 'Rust third-party notice generation failed.' }

  if (-not $SkipCompile) {
    $executablePath = Join-Path $releaseDir 'compact_games.exe'
    $appSoPath = Join-Path $releaseDir 'data\app.so'
    if (-not (Test-Path -LiteralPath $executablePath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $appSoPath -PathType Leaf)) {
      throw 'Cannot record Steam build provenance because the compiled Dart artifacts are missing.'
    }
    $gitCommit = (& git.exe rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($gitCommit)) {
      throw 'Could not determine the Git commit for Steam build provenance.'
    }
    $sourceTreeDirty = [bool](& git.exe status --porcelain)
    if ($LASTEXITCODE -ne 0) { throw 'Could not inspect the Git worktree for Steam build provenance.' }
    $metadata = [ordered]@{
      schemaVersion = 1
      distributionChannel = 'steam'
      version = $version
      gitCommit = $gitCommit
      sourceTreeDirty = $sourceTreeDirty
      builtAtUtc = [DateTime]::UtcNow.ToString('o')
      coverProxyConfigured = [bool]$coverProxyConfigured
      executableSha256 = Get-Sha256Lower $executablePath
      appSoSha256 = Get-Sha256Lower $appSoPath
      rustCoreSha256 = Get-Sha256Lower $rustDll
    }
    [System.IO.File]::WriteAllText(
      $buildMetadataPath,
      ($metadata | ConvertTo-Json),
      $utf8NoBom
    )
  }

  New-Item -ItemType Directory -Path $contentDir, $scriptsDir, $outputDir -Force | Out-Null
  Get-ChildItem -LiteralPath $contentDir -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force
  Copy-Item -Path (Join-Path $releaseDir '*') -Destination $contentDir -Recurse -Force

  $requiredFiles = @(
    'compact_games.exe',
    'compact_games_core.dll',
    'flutter_windows.dll',
    'compact_games_build.json',
    'vcruntime140.dll',
    'vcruntime140_1.dll',
    'msvcp140.dll',
    'LICENSE.txt',
    'THIRD_PARTY_NOTICES-RUST.txt',
    'data\icudtl.dat',
    'data\flutter_assets\AssetManifest.bin'
  )
  foreach ($requiredFile in $requiredFiles) {
    $requiredPath = Join-Path $contentDir $requiredFile
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf) -or
        (Get-Item -LiteralPath $requiredPath).Length -eq 0) {
      throw "Steam content is missing required file: $requiredFile"
    }
  }

  $hashes = Get-ChildItem -LiteralPath $contentDir -File -Recurse |
    Sort-Object FullName |
    ForEach-Object {
      $relative = $_.FullName.Substring($contentDirFull.TrimEnd('\').Length).TrimStart('\').Replace('\', '/')
      $hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
      "$hash  $relative"
    }
  [System.IO.File]::WriteAllLines(
    (Join-Path $steamRoot 'sha256sums.txt'),
    [string[]]$hashes,
    $utf8NoBom
  )

  $resolvedAppId = if ($AppId) { $AppId } else { '__APP_ID__' }
  $resolvedDepotId = if ($DepotId) { $DepotId } else { '__DEPOT_ID__' }
  $safeDescription = $Description.Replace('"', "'")
  $depotFileName = "depot_build_$resolvedDepotId.vdf"

  $depotVdf = @"
"DepotBuildConfig"
{
  "DepotID" "$resolvedDepotId"
  "FileMapping"
  {
    "LocalPath" "*"
    "DepotPath" "."
    "recursive" "1"
  }
  "FileExclusion" "*.pdb"
}
"@
  [System.IO.File]::WriteAllText(
    (Join-Path $scriptsDir $depotFileName),
    $depotVdf,
    $utf8NoBom
  )

  $appVdf = @"
"AppBuild"
{
  "AppID" "$resolvedAppId"
  "Desc" "$safeDescription"
  "BuildOutput" "..\output"
  "ContentRoot" "..\content"
  "Depots"
  {
    "$resolvedDepotId" "$depotFileName"
  }
}
"@
  [System.IO.File]::WriteAllText(
    (Join-Path $scriptsDir "app_build_$resolvedAppId.vdf"),
    $appVdf,
    $utf8NoBom
  )

  Write-Host "Steam depot content prepared: $contentDir"
  Write-Host "SteamPipe scripts prepared: $scriptsDir"
  if (-not $AppId) {
    Write-Host 'Re-run with -AppId and -DepotId after Steamworks assigns them.'
  }
} finally {
  Pop-Location
}
