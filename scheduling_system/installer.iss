[Setup]
AppName=Scheduling and Duty Management System
AppVersion=1.0.0
DefaultDirName={autopf}\SchedulingSystem
DefaultGroupName=Scheduling and Duty Management System
OutputDir=installer
OutputBaseFilename=SchedulingSystemSetup
Compression=lzma
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64

[Files]
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion

[Icons]
Name: "{autoprograms}\Scheduling and Duty Management System"; Filename: "{app}\scheduling_system.exe"
Name: "{autodesktop}\Scheduling and Duty Management System"; Filename: "{app}\scheduling_system.exe"

[Run]
Filename: "{app}\scheduling_system.exe"; Description: "Launch Scheduling and Duty Management System"; Flags: nowait postinstall skipifsilent