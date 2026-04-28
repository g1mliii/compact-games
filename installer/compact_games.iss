; Compact Games Installer - Inno Setup Script
; Builds a Windows installer for Compact Games.
;
; Usage:
;   iscc /DAppVersion=0.1.0 installer\compact_games.iss
;
; The /DAppVersion define can be passed from CI or defaults to 0.0.0.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

#define AppName "Compact Games"
#define AppPublisher "Compact Games"
#define AppExeName "compact_games.exe"
#define AppUrl "https://github.com/g1mliii/compact-games"

[Setup]
AppId={{E8F2B4A1-7D3C-4E5F-9A1B-2C3D4E5F6A7B}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppUrl}
AppSupportURL={#AppUrl}/issues
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
OutputDir=..\dist
OutputBaseFilename=CompactGames-Setup-{#AppVersion}
SetupIconFile=..\assets\icons\app_icon.ico
UninstallDisplayIcon={app}\{#AppExeName}
Compression=lzma2/ultra
SolidCompression=yes
PrivilegesRequired=admin
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
; Preserve previously-selected [Tasks] (desktop icon, autostart) on upgrade,
; including under silent /SILENT upgrades triggered by the in-app updater.
UsePreviousTasks=yes
CloseApplications=force
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
Name: "autostart"; Description: "Start {#AppName} when Windows starts"; GroupDescription: "Startup:"; Flags: unchecked

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{group}\Uninstall {#AppName}"; Filename: "{uninstallexe}"
; `Check: not IsUpgrade` keeps the desktop icon a first-install-only
; action. Without it, every silent /SILENT upgrade would recreate the
; shortcut even after the user manually deleted it.
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon; Check: not IsUpgrade

[Registry]
; Autostart entry — first install only. The in-app Settings toggle is
; the source of truth for this value post-install, so upgrades must not
; re-assert it (would clobber a user who disabled autostart in settings).
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "{#AppName}"; ValueData: """{app}\{#AppExeName}"" --minimized"; Flags: uninsdeletevalue; Tasks: autostart; Check: not IsUpgrade
; App registry subtree — removed on uninstall if empty
Root: HKCU; Subkey: "Software\{#AppPublisher}\{#AppName}"; Flags: uninsdeletekeyifempty
Root: HKCU; Subkey: "Software\{#AppPublisher}"; Flags: uninsdeletekeyifempty
; Remove obsolete shortcut verbs. `.lnk` targets may be launcher executables
; with arguments, so resolving only the executable path can target the wrong
; folder.
Root: HKCU; Subkey: "Software\Classes\lnkfile\shell\CompactGamesCompress"; Flags: deletekey
Root: HKCU; Subkey: "Software\Classes\lnkfile\shell\CompactGamesDecompress"; Flags: deletekey
; Explorer static shell verbs — per-user only.
Root: HKCU; Subkey: "Software\Classes\Directory\shell\CompactGamesCompress"; ValueType: string; ValueName: ""; ValueData: "Compress/Recompress with {#AppName}"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\Directory\shell\CompactGamesCompress"; ValueType: string; ValueName: "Icon"; ValueData: "{app}\{#AppExeName}"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\Directory\shell\CompactGamesCompress\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#AppExeName}"" --minimized --shell-action compress --path ""%1"""; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\Directory\shell\CompactGamesDecompress"; ValueType: string; ValueName: ""; ValueData: "Decompress with {#AppName}"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\Directory\shell\CompactGamesDecompress"; ValueType: string; ValueName: "Icon"; ValueData: "{app}\{#AppExeName}"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\Directory\shell\CompactGamesDecompress\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#AppExeName}"" --minimized --shell-action decompress --path ""%1"""; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\exefile\shell\CompactGamesCompress"; ValueType: string; ValueName: ""; ValueData: "Compress/Recompress with {#AppName}"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\exefile\shell\CompactGamesCompress"; ValueType: string; ValueName: "Icon"; ValueData: "{app}\{#AppExeName}"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\exefile\shell\CompactGamesCompress\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#AppExeName}"" --minimized --shell-action compress --path ""%1"""; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\exefile\shell\CompactGamesDecompress"; ValueType: string; ValueName: ""; ValueData: "Decompress with {#AppName}"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\exefile\shell\CompactGamesDecompress"; ValueType: string; ValueName: "Icon"; ValueData: "{app}\{#AppExeName}"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\exefile\shell\CompactGamesDecompress\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#AppExeName}"" --minimized --shell-action decompress --path ""%1"""; Flags: uninsdeletekey

[Run]
; `skipifsilent` removed so the in-app updater (which runs /SILENT) still
; auto-relaunches the app after a successful upgrade.
Filename: "{app}\{#AppExeName}"; Description: "Launch {#AppName}"; Flags: nowait postinstall

[Code]

var
  DeleteUserDataCheckbox: TNewCheckBox;

// ---------------------------------------------------------------------------
// IsUpgrade: true when our AppId is already installed (any prior version).
// Used to gate shortcut / autostart creation to first-install only so that
// user deletions (desktop shortcut) or settings toggles (autostart) are not
// reverted by subsequent silent upgrades.
// ---------------------------------------------------------------------------
function IsUpgrade(): Boolean;
var
  PrevVersion: String;
begin
  Result :=
    RegQueryStringValue(HKLM, 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{#SetupSetting("AppId")}_is1', 'DisplayVersion', PrevVersion) or
    RegQueryStringValue(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{#SetupSetting("AppId")}_is1', 'DisplayVersion', PrevVersion);
end;

// ---------------------------------------------------------------------------
// Uninstall: add "remove user data" checkbox above the progress bar.
// Only shown in interactive mode — silent uninstalls preserve user data.
// ---------------------------------------------------------------------------
procedure InitializeUninstallProgressForm();
begin
  DeleteUserDataCheckbox := TNewCheckBox.Create(UninstallProgressForm);
  with DeleteUserDataCheckbox do
  begin
    Parent  := UninstallProgressForm;
    Caption := 'Remove all settings, cover art cache, and user data';
    Checked := True;
    Left    := UninstallProgressForm.InnerNotebook.Left;
    Width   := UninstallProgressForm.InnerNotebook.Width;
    Top     := UninstallProgressForm.InnerNotebook.Top - ScaleY(28);
    Height  := ScaleY(20);
  end;
end;

// ---------------------------------------------------------------------------
// Uninstall: wipe user data directories when the checkbox is ticked.
// Runs after the main uninstall step so the app files are already gone.
// ---------------------------------------------------------------------------
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  ResultCode: Integer;
begin
  if CurUninstallStep <> usPostUninstall then Exit;
  if not (Assigned(DeleteUserDataCheckbox) and DeleteUserDataCheckbox.Checked) then Exit;

  // Rust config dir — %APPDATA%\compact_games
  // Contains: discovery index, compression history, automation journal,
  //           change feed, unsupported games db, hidden paths cache.
  if DirExists(ExpandConstant('{userappdata}\compact_games')) then
    DelTree(ExpandConstant('{userappdata}\compact_games'), True, True, True);

  // Flutter app support dir — %APPDATA%\Compact Games
  // Contains: cover art cache, update downloads, SharedPreferences (settings).
  if DirExists(ExpandConstant('{userappdata}\Compact Games')) then
    DelTree(ExpandConstant('{userappdata}\Compact Games'), True, True, True);

  // Local app data variants (path_provider may use either roaming or local)
  if DirExists(ExpandConstant('{localappdata}\compact_games')) then
    DelTree(ExpandConstant('{localappdata}\compact_games'), True, True, True);

  if DirExists(ExpandConstant('{localappdata}\Compact Games')) then
    DelTree(ExpandConstant('{localappdata}\Compact Games'), True, True, True);

  // Remove SteamGridDB API key from Windows Credential Manager.
  // flutter_secure_storage stores it as a generic Windows credential.
  // Failure is silent — the entry may not exist if the user never set a key.
  Exec(ExpandConstant('{sys}\cmdkey.exe'),
       '/delete:compact_games_steamgriddb_api_key',
       '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
end;
