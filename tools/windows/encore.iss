; Encore's Windows setup program (Inno Setup 6). It installs for you only (no administrator needed), in
; %LOCALAPPDATA%\Programs\Encore, with a Start menu entry. Encore updates itself by running the next
; version's setup program quietly with /launch=1 (lib/data/updates.dart).
; Built by tools/windows/build.ps1:  iscc /DAppVersion=1.8.0 /DBuildDir=<the Release folder> encore.iss

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef BuildDir
  #define BuildDir "..\..\build\windows\x64\runner\Release"
#endif
#ifndef OutDir
  #define OutDir "..\..\dist"
#endif

[Setup]
AppId={{8C2B5D4E-7A1F-4E3B-9D6C-5F0A1B2C3D4E}
AppName=Encore
AppVersion={#AppVersion}
AppPublisher=Encore
AppPublisherURL=https://github.com/d-safro/encore
AppSupportURL=https://github.com/d-safro/encore/issues
AppUpdatesURL=https://github.com/d-safro/encore/releases
DefaultDirName={autopf}\Encore
DisableProgramGroupPage=yes
DisableDirPage=auto
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutDir}
OutputBaseFilename=encore-{#AppVersion}-windows-x64-setup
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\encore.exe
UninstallDisplayName=Encore
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
; an update closes the running Encore first (it saves where you are as it quits)
CloseApplications=force
RestartApplications=no

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
Name: "autostart"; Description: "Start Encore in the tray when you log in"; Flags: unchecked

[Files]
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[InstallDelete]
; files a previous version had and this one doesn't: the whole data folder is replaced
Type: filesandordirs; Name: "{app}\data"

[Icons]
; the id matches the one Encore's notifications use, so Windows shows them as Encore's
Name: "{autoprograms}\Encore"; Filename: "{app}\encore.exe"; AppUserModelID: "dev.safro.encore"
Name: "{autodesktop}\Encore"; Filename: "{app}\encore.exe"; Tasks: desktopicon

[Registry]
; the same switch as Settings > Desktop > Start when you log in
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "Encore"; ValueData: """{app}\encore.exe"" --hidden"; Tasks: autostart; Flags: uninsdeletevalue

[Run]
Filename: "{app}\encore.exe"; Description: "{cm:LaunchProgram,Encore}"; Flags: nowait postinstall skipifsilent
; after an update Encore started itself: start the new version again
Filename: "{app}\encore.exe"; Flags: nowait; Check: LaunchAfterUpdate

[UninstallRun]
Filename: "{cmd}"; Parameters: "/C reg delete HKCU\Software\Microsoft\Windows\CurrentVersion\Run /v Encore /f"; Flags: runhidden; RunOnceId: "RemoveAutostart"

[Code]
function LaunchAfterUpdate: Boolean;
begin
  Result := ExpandConstant('{param:launch|0}') = '1';
end;
