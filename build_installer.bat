@echo off
setlocal

set VERSION=%1
set RELEASE_DIR=build\windows\x64\runner\Release
set RUST_DLL=rust\target\release\compact_games_core.dll

if "%VERSION%"=="" (
    echo Usage: build_installer.bat ^<version^>
    echo Example: build_installer.bat 0.1.0
    exit /b 1
)

echo [1/5] Building Rust release...
pushd rust
cargo build --release
if errorlevel 1 (
    echo ERROR: Rust build failed.
    popd
    exit /b 1
)
popd

echo [2/5] Building Flutter Windows release...
set "HAS_PROXY_DEFINES="
if defined COMPACT_GAMES_SGDB_PROXY_URL (
    if defined COMPACT_GAMES_SGDB_TOKEN (
        set "HAS_PROXY_DEFINES=1"
    )
)
if defined HAS_PROXY_DEFINES (
    echo   Including SteamGridDB proxy dart-defines from environment.
    call flutter build windows --release "--dart-define=COMPACT_GAMES_SGDB_PROXY_URL=%COMPACT_GAMES_SGDB_PROXY_URL%" "--dart-define=COMPACT_GAMES_SGDB_TOKEN=%COMPACT_GAMES_SGDB_TOKEN%"
) else (
    if defined COMPACT_GAMES_SGDB_PROXY_URL echo WARNING: COMPACT_GAMES_SGDB_TOKEN is missing; building without SteamGridDB proxy defines.
    if defined COMPACT_GAMES_SGDB_TOKEN echo WARNING: COMPACT_GAMES_SGDB_PROXY_URL is missing; building without SteamGridDB proxy defines.
    call flutter build windows --release
)
if errorlevel 1 (
    echo ERROR: Flutter build failed.
    exit /b 1
)

echo [3/5] Copying Rust DLL to Release folder...
if not exist "%RUST_DLL%" (
    echo ERROR: Rust DLL not found at %RUST_DLL%
    exit /b 1
)
copy /Y "%RUST_DLL%" "%RELEASE_DIR%\" >nul

echo [4/5] Bundling VC++ runtime DLLs...
set "VCRT_FOUND="
for /f "delims=" %%D in ('dir /b /s /ad "C:\Program Files (x86)\Microsoft Visual Studio\*Microsoft.VC*.CRT" 2^>nul ^| findstr /i "x64"') do (
    if exist "%%D\vcruntime140.dll" (
        copy /Y "%%D\vcruntime140.dll" "%RELEASE_DIR%\" >nul
        copy /Y "%%D\vcruntime140_1.dll" "%RELEASE_DIR%\" >nul
        copy /Y "%%D\msvcp140.dll" "%RELEASE_DIR%\" >nul
        set "VCRT_FOUND=1"
        echo   Found VC++ runtime at %%D
        goto :vcrt_done
    )
)
:vcrt_done
if not defined VCRT_FOUND (
    echo WARNING: VC++ runtime DLLs not found. Installer may fail on clean machines.
)

echo [5/5] Building installer...
"C:\Program Files (x86)\Inno Setup 6\ISCC.exe" /DAppVersion=%VERSION% installer\compact_games.iss
if errorlevel 1 (
    echo ERROR: Inno Setup failed.
    exit /b 1
)

echo.
echo Success: dist\CompactGames-Setup-%VERSION%.exe
