#ifndef ReleaseVersion
  #error ReleaseVersion is required
#endif
#ifndef PayloadDir
  #error PayloadDir is required
#endif

[Setup]
AppId={{3CE8D969-5294-434D-B316-1DF031407F79}
AppName=OpenSC
AppVersion={#ReleaseVersion}
VersionInfoProductTextVersion={#ReleaseVersion}
DefaultDirName=C:\Games\OpenSC
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
DisableStartupPrompt=yes
CloseApplications=yes
RestartApplications=no
UninstallDisplayIcon={app}\OpenSC.exe
OutputBaseFilename=OpenSC-{#ReleaseVersion}-Windows-x64-Setup
Compression=lzma2
SolidCompression=yes
#ifdef SignRelease
SignTool=OpenSC
SignedUninstaller=yes
#endif

[Files]
Source: "{#PayloadDir}\OpenSC.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#PayloadDir}\*"; DestDir: "{app}"; Excludes: "OpenSC.exe"; Flags: recursesubdirs createallsubdirs ignoreversion
Source: "windows_installer_marker.txt"; DestDir: "{app}"; DestName: "OpenSC.installed"; Flags: ignoreversion

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"

[Icons]
Name: "{autoprograms}\OpenSC"; Filename: "{app}\OpenSC.exe"; WorkingDir: "{app}"
Name: "{autodesktop}\OpenSC"; Filename: "{app}\OpenSC.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\OpenSC.exe"; WorkingDir: "{app}"; Flags: nowait postinstall skipifsilent
Filename: "{app}\OpenSC.exe"; WorkingDir: "{app}"; Flags: nowait; Check: RelaunchAfterUpdate

[Code]
function OpenProcess(Access: Cardinal; Inherit: Boolean; ProcessId: Cardinal): THandle;
  external 'OpenProcess@kernel32.dll stdcall';
function WaitForSingleObject(Handle: THandle; Milliseconds: Cardinal): Cardinal;
  external 'WaitForSingleObject@kernel32.dll stdcall';
function CloseHandle(Handle: THandle): Boolean;
  external 'CloseHandle@kernel32.dll stdcall';
function GetLastError(): Cardinal;
  external 'GetLastError@kernel32.dll stdcall';

function RelaunchAfterUpdate(): Boolean;
begin
  Result := WizardSilent and (ExpandConstant('{param:OPENSCUPDATEPID|}') <> '');
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  GamePID: Integer;
  Game: THandle;
  WaitResult: Cardinal;
  InstallDir: String;
begin
  Result := '';
  if not RelaunchAfterUpdate() then
    Exit;
  InstallDir := ExpandConstant('{app}');
  if (CompareText(InstallDir, ExpandConstant('{param:OPENSCUPDATEDIR|}')) <> 0) or
     not FileExists(AddBackslash(InstallDir) + 'OpenSC.installed') then
  begin
    Result := 'Setup could not locate the running OpenSC installation.';
    Exit;
  end;
  GamePID := StrToIntDef(ExpandConstant('{param:OPENSCUPDATEPID|}'), 0);
  if GamePID <= 0 then
  begin
    Result := 'Setup could not identify the running OpenSC process.';
    Exit;
  end;
  Game := OpenProcess($00100000, False, GamePID);
  if Game = 0 then
  begin
    { ERROR_INVALID_PARAMETER means the process has already exited. }
    if GetLastError() <> 87 then
      Result := 'Setup could not wait for OpenSC to close.';
    Exit;
  end;
  try
    WaitResult := WaitForSingleObject(Game, 30000);
    if WaitResult <> 0 then
      Result := 'OpenSC did not close. Quit the game and run Setup again.';
  finally
    CloseHandle(Game);
  end;
end;
