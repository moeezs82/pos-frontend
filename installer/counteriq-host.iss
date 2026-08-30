#define MyAppName "CounterIQ"
#define MyAppVersion "1.0.3"
#define MyAppPublisher "Moeez"
#define MyAppExeName "CounterIQ.exe"

[Setup]
AppId={{6B3C5A72-DA32-46DD-93A8-CF0A30C7D4CE}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}

DefaultDirName={autopf}\CounterIQ
DefaultGroupName=CounterIQ
DisableProgramGroupPage=yes

PrivilegesRequired=admin

OutputDir=output
OutputBaseFilename=CounterIQ-Host-Setup-{#MyAppVersion}

Compression=lzma2
SolidCompression=yes

WizardStyle=modern

CloseApplications=yes
RestartApplications=no

UninstallDisplayName=CounterIQ

ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Files]
Source: "..\build\windows\x64\runner\Release\*"; \
    DestDir: "{app}"; \
    Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\CounterIQ"; \
    Filename: "{app}\{#MyAppExeName}"

Name: "{autodesktop}\CounterIQ"; \
    Filename: "{app}\{#MyAppExeName}"

[Run]
Filename: "{cmd}"; \
    Parameters: "/C netsh advfirewall firewall delete rule name=""CounterIQ POS LAN"" >nul 2>&1"; \
    Flags: runhidden waituntilterminated

Filename: "{cmd}"; \
    Parameters: "/C netsh advfirewall firewall add rule name=""CounterIQ POS LAN"" dir=in action=allow protocol=TCP localport=8080 profile=private"; \
    Flags: runhidden waituntilterminated

Filename: "{app}\{#MyAppExeName}"; \
    Description: "Launch CounterIQ"; \
    Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "{cmd}"; \
    Parameters: "/C netsh advfirewall firewall delete rule name=""CounterIQ POS LAN"""; \
    Flags: runhidden waituntilterminated

[Code]
function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  ResultCode: Integer;
begin
  { Stop an older CounterIQ frontend if upgrading }
  Exec(
    ExpandConstant('{cmd}'),
    '/C taskkill /F /IM enterprise_pos.exe >nul 2>&1',
    '',
    SW_HIDE,
    ewWaitUntilTerminated,
    ResultCode
  );

  { Stop an older Go sidecar if upgrading }
  Exec(
    ExpandConstant('{cmd}'),
    '/C taskkill /F /IM counteriq-backend.exe >nul 2>&1',
    '',
    SW_HIDE,
    ewWaitUntilTerminated,
    ResultCode
  );

  Result := '';
end;