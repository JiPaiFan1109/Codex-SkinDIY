#ifndef SourceRoot
  #error SourceRoot is required; use scripts/build-app.ps1
#endif
#ifndef AppVersion
  #error AppVersion is required
#endif

[Setup]
#ifdef TestInstallRoot
AppId={{0E7720A7-D16D-4441-85E5-522908601905}
#else
AppId={{97EC4AF8-3971-4B65-A78E-16B0D870C41D}
#endif
AppName=Codex 换肤管理中心
AppVersion={#AppVersion}
AppPublisher=Codex Dynamic Skin contributors
AppPublisherURL=https://github.com/JiPaiFan1109/Codex-SkinDIY
AppSupportURL=https://github.com/JiPaiFan1109/Codex-SkinDIY/issues
#ifdef TestInstallRoot
DefaultDirName={#TestInstallRoot}
#else
DefaultDirName={localappdata}\CodexDynamicSkin
#endif
UsePreviousAppDir=no
DisableDirPage=yes
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17763
SetupIconFile={#SourceRoot}\appearance\skin-manager.ico
UninstallDisplayIcon={app}\CodexSkinManager.exe
OutputBaseFilename=Codex-Skin-Manager-Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
LicenseFile={#SourceRoot}\LICENSE
AppMutex=CodexDynamicSkinManager
CloseApplications=no
RestartApplications=no
Uninstallable=yes

[Languages]
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; Flags: checkedonce

[Files]
Source: "{#SourceRoot}\engine\*"; DestDir: "{app}\engine"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#SourceRoot}\scripts\*"; DestDir: "{app}\scripts"; Excludes: "check-upgrade.ps1"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#SourceRoot}\scripts\check-upgrade.ps1"; Flags: dontcopy
Source: "{#SourceRoot}\appearance\*"; DestDir: "{app}\appearance"; Flags: ignoreversion
Source: "{#SourceRoot}\CodexSkinManager.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceRoot}\VERSION"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceRoot}\LICENSE"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceRoot}\THIRD_PARTY_NOTICES.md"; DestDir: "{app}"; Flags: ignoreversion

[InstallDelete]
Type: files; Name: "{app}\engine\assets\dream-skin.css"
Type: files; Name: "{app}\engine\assets\theme-package-validator.mjs"
Type: files; Name: "{app}\engine\assets\dream-reference.jpg"
Type: files; Name: "{app}\engine\scripts\tray-dream-skin.ps1"
Type: files; Name: "{app}\engine\scripts\apply-community-theme.ps1"
Type: files; Name: "{app}\engine\scripts\check-update.ps1"
Type: files; Name: "{app}\engine\scripts\install-dream-skin.ps1"
Type: files; Name: "{app}\engine\scripts\verify-dream-skin.ps1"

[Icons]
#ifndef TestInstallRoot
Name: "{userprograms}\Codex 换肤管理中心\Codex 换肤管理中心"; Filename: "{app}\CodexSkinManager.exe"
Name: "{userprograms}\Codex 换肤管理中心\打开换肤版 Codex"; Filename: "{app}\engine\launcher\CodexDynamicSkinLauncher.exe"; IconFilename: "{app}\CodexSkinManager.exe"
Name: "{userprograms}\Codex 换肤管理中心\卸载"; Filename: "{uninstallexe}"
Name: "{userdesktop}\Codex 换肤管理中心"; Filename: "{app}\CodexSkinManager.exe"; Tasks: desktopicon
#endif

[Run]
#ifndef TestInstallRoot
Filename: "{app}\CodexSkinManager.exe"; Description: "打开 Codex 换肤管理中心"; Flags: nowait postinstall skipifsilent
#endif

[Code]
function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  ExitCode: Integer;
  Params: String;
  BlockReason: AnsiString;
begin
  Result := '';
  ExtractTemporaryFile('check-upgrade.ps1');
  Params := '-NoProfile -WindowStyle Hidden -ExecutionPolicy RemoteSigned -File "' + ExpandConstant('{tmp}\check-upgrade.ps1') + '" -InstallRoot "' + ExpandConstant('{app}') + '" -ResultPath "' + ExpandConstant('{tmp}\upgrade-check-result.txt') + '"';
  if not Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'), Params, '', SW_HIDE, ewWaitUntilTerminated, ExitCode) then
    Result := '无法完成安装前检查，本次安装未替换文件。请重新运行安装程序。'
  else if ExitCode <> 0 then begin
    if LoadStringFromFile(ExpandConstant('{tmp}\upgrade-check-result.txt'), BlockReason) and (Length(BlockReason) > 0) then
      Result := UTF8Decode(BlockReason)
    else
      Result := '无法完成后台检查，本次安装未替换文件。请退出相关程序后重试。';
  end;
end;

function InitializeSetup: Boolean;
var
  ExpectedDirectory: String;
begin
  Result := True;
#ifdef TestInstallRoot
  ExpectedDirectory := '{#TestInstallRoot}';
#else
  ExpectedDirectory := ExpandConstant('{localappdata}\CodexDynamicSkin');
#endif
  if CompareText(ExpandConstant('{param:DIR|' + ExpectedDirectory + '}'), ExpectedDirectory) <> 0 then begin
    if not WizardSilent then MsgBox('安装位置固定为当前用户目录，以便自动连接 Codex。', mbError, MB_OK);
    Result := False;
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  ExitCode: Integer;
  Params: String;
begin
  if CurUninstallStep <> usUninstall then Exit;
  { This event runs after uninstall confirmation and before any files are deleted. }
  Params := '-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy RemoteSigned -File "' + ExpandConstant('{app}\scripts\uninstall-app.ps1') + '"';
  if UninstallSilent then Params := Params + ' -Silent';
  if not Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'), Params, '', SW_HIDE, ewWaitUntilTerminated, ExitCode) then
    RaiseException('无法启动外观恢复，卸载已停止，应用和壁纸库均保留。');
  if ExitCode = 2 then Abort;
  if ExitCode <> 0 then
    RaiseException('外观恢复未完成，卸载已停止。请先在换肤管理中心恢复原始外观后重试。');
end;
