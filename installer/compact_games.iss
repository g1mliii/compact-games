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
AppVerName={#AppName} {#AppVersion}
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
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Registry]
; Autostart entry — removed on uninstall if the task was selected
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "{#AppName}"; ValueData: """{app}\{#AppExeName}"" --minimized"; Flags: uninsdeletevalue; Tasks: autostart
; App registry subtree — removed on uninstall if empty
Root: HKCU; Subkey: "Software\{#AppPublisher}\{#AppName}"; Flags: uninsdeletekeyifempty
Root: HKCU; Subkey: "Software\{#AppPublisher}"; Flags: uninsdeletekeyifempty

[Run]
Filename: "{app}\{#AppExeName}"; Description: "Launch {#AppName}"; Flags: nowait postinstall skipifsilent

[Code]

var
  DeleteUserDataCheckbox: TNewCheckBox;

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
