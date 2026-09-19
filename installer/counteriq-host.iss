#define MyAppName "CounterIQ"
#define MyAppVersion "1.0.10"
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

; ============================================================
; Microsoft Visual C++ 2015-2022 Runtime
; Fixes VCRUNTIME140.dll, VCRUNTIME140_1.dll,
; MSVCP140.dll and related runtime DLL errors.
; ============================================================

Source: "prerequisites\VC_redist.x64.exe"; \
    DestDir: "{tmp}"; \
    Flags: deleteafterinstall

; ============================================================
; CounterIQ Windows Release
; IMPORTANT: Keep copying the entire Release directory.
; ============================================================

Source: "..\build\windows\x64\runner\Release\*"; \
    DestDir: "{app}"; \
    Flags: ignoreversion recursesubdirs createallsubdirs


[Icons]

Name: "{autoprograms}\CounterIQ"; \
    Filename: "{app}\{#MyAppExeName}"

Name: "{autodesktop}\CounterIQ"; \
    Filename: "{app}\{#MyAppExeName}"


[Run]

; ============================================================
; Install/update Microsoft Visual C++ Runtime
; ============================================================

Filename: "{tmp}\VC_redist.x64.exe"; \
    Parameters: "/install /quiet /norestart"; \
    StatusMsg: "Installing required Microsoft Visual C++ Runtime..."; \
    Flags: runhidden waituntilterminated

; ============================================================
; Remove old CounterIQ firewall rule
; ============================================================

Filename: "{cmd}"; \
    Parameters: "/C netsh advfirewall firewall delete rule name=""CounterIQ POS LAN"" >nul 2>&1"; \
    Flags: runhidden waituntilterminated

; ============================================================
; Add CounterIQ Host LAN firewall rule
; ============================================================

Filename: "{cmd}"; \
    Parameters: "/C netsh advfirewall firewall add rule name=""CounterIQ POS LAN"" dir=in action=allow protocol=TCP localport=8080 profile=private"; \
    Flags: runhidden waituntilterminated

; ============================================================
; Normal/manual installation:
; keep the existing post-install "Launch CounterIQ" behavior.
; skipifsilent ensures this entry does not run during /VERYSILENT.
; runasoriginaluser prevents CounterIQ from reopening elevated.
; ============================================================

Filename: "{app}\{#MyAppExeName}"; \
    Description: "Launch CounterIQ"; \
    Flags: nowait postinstall skipifsilent runasoriginaluser; \
    Check: not IsAutoUpdate

; ============================================================
; Automatic update:
; when Flutter launches setup with /AUTOUPDATE, reopen CounterIQ
; automatically after the silent update finishes.
; ============================================================

Filename: "{app}\{#MyAppExeName}"; \
    Flags: nowait runasoriginaluser; \
    Check: IsAutoUpdate


[UninstallRun]

; ============================================================
; Remove CounterIQ LAN firewall rule on uninstall
; ============================================================

Filename: "{cmd}"; \
    Parameters: "/C netsh advfirewall firewall delete rule name=""CounterIQ POS LAN"" >nul 2>&1"; \
    Flags: runhidden waituntilterminated


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

  { ----------------------------------------------------------
    Stop current CounterIQ executable before upgrade
    ---------------------------------------------------------- }

  Exec(
    ExpandConstant('{cmd}'),
    '/C taskkill /F /IM CounterIQ.exe >nul 2>&1',
    '',
    SW_HIDE,
    ewWaitUntilTerminated,
    ResultCode
  );


  { ----------------------------------------------------------
    Stop legacy frontend executable name if an older version
    of CounterIQ was installed using enterprise_pos.exe
    ---------------------------------------------------------- }

  Exec(
    ExpandConstant('{cmd}'),
    '/C taskkill /F /IM enterprise_pos.exe >nul 2>&1',
    '',
    SW_HIDE,
    ewWaitUntilTerminated,
    ResultCode
  );


  { ----------------------------------------------------------
    Stop existing CounterIQ Go backend/sidecar
    ---------------------------------------------------------- }

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
