; Installer for the Windows POS app.
; Build the release first: flutter build windows --release
; Then compile this script with Inno Setup (ISCC).

#define AppName "POS Platform"
#define AppVersion "1.0.0"
#define AppExe "pos_app.exe"
#define ReleaseDir "..\app\build\windows\x64\runner\Release"

[Setup]
AppId={{A7C3E1B2-4F58-4C1A-9D6E-1B2C3D4E5F60}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=POS Platform
DefaultDirName={localappdata}\POS Platform
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
OutputDir=..\dist
OutputBaseFilename=POS-Platform-Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
UninstallDisplayIcon={app}\{#AppExe}
SetupIconFile=..\app\windows\runner\resources\app_icon.ico

[Files]
Source: "{#ReleaseDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs; Excludes: "*.lib,*.exp,*.pdb,*.ilk"

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"

[Run]
Filename: "{app}\{#AppExe}"; Description: "Launch {#AppName}"; Flags: nowait postinstall skipifsilent
