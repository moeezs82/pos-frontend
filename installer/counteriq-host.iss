#ifndef MyAppVersion
  #error MyAppVersion must be supplied by the release build script, e.g. /DMyAppVersion=1.0.11
#endif

#define MyAppName "CounterIQ"
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
Source: "prerequisites\VC_redist.x64.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\CounterIQ"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\CounterIQ"; Filename: "{app}\{#MyAppExeName}"

[Run]
Filename: "{tmp}\VC_redist.x64.exe"; Parameters: "/install /quiet /norestart"; StatusMsg: "Installing required Microsoft Visual C++ Runtime..."; Flags: runhidden waituntilterminated
Filename: "{cmd}"; Parameters: "/C netsh advfirewall firewall delete rule name=""CounterIQ POS LAN"" >nul 2>&1"; Flags: runhidden waituntilterminated
Filename: "{cmd}"; Parameters: "/C netsh advfirewall firewall add rule name=""CounterIQ POS LAN"" dir=in action=allow protocol=TCP localport=8080 profile=private"; Flags: runhidden waituntilterminated
Filename: "{app}\{#MyAppExeName}"; Description: "Launch CounterIQ"; Flags: nowait postinstall skipifsilent runasoriginaluser; Check: not IsAutoUpdate
Filename: "{app}\{#MyAppExeName}"; Flags: nowait runasoriginaluser; Check: IsAutoUpdate

[UninstallRun]
Filename: "{cmd}"; Parameters: "/C netsh advfirewall firewall delete rule name=""CounterIQ POS LAN"" >nul 2>&1"; Flags: runhidden waituntilterminated

[Code]
function IsAutoUpdate: Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 1 to ParamCount do
  begin
    if CompareText(ParamStr(I), '/AUTOUPDATE') = 0 then
    begin
      Result := True;
      Exit;
    end;
  end;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  ResultCode: Integer;
begin
  Exec(ExpandConstant('{cmd}'), '/C taskkill /F /IM CounterIQ.exe >nul 2>&1', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Exec(ExpandConstant('{cmd}'), '/C taskkill /F /IM enterprise_pos.exe >nul 2>&1', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Exec(ExpandConstant('{cmd}'), '/C taskkill /F /IM counteriq-backend.exe >nul 2>&1', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Result := '';
end;
