param([string]$SetupPath)
$ErrorActionPreference='Stop'
if(-not $SetupPath){$SetupPath=Join-Path $PSScriptRoot '../dist/Codex-Skin-Manager-Setup.exe'}
if(-not(Test-Path $SetupPath)){throw 'Windows application installer is missing'}
$root=Split-Path $PSScriptRoot -Parent
$output=Join-Path ([IO.Path]::GetTempPath()) ('skin-setup-audit-'+[guid]::NewGuid().ToString('N'))
New-Item $output -ItemType Directory|Out-Null
try{
  $process=Start-Process -FilePath ([IO.Path]::GetFullPath($SetupPath)) -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',('/DIR="'+$output+'"')) -WindowStyle Hidden -PassThru
  $process.WaitForExit()
  if($process.ExitCode -eq 0){throw 'Installer accepted a custom directory that the skin engine cannot operate from'}
  if(Test-Path (Join-Path $output 'engine')){throw 'Rejected setup wrote application files'}
}finally{Remove-Item -LiteralPath $output -Recurse -Force}
$sum=([IO.File]::ReadAllText(($SetupPath+'.sha256')) -split '\s+')[0]
if((Get-FileHash $SetupPath -Algorithm SHA256).Hash -ine $sum){throw 'Installer checksum mismatch'}
$app=Join-Path (Split-Path ([IO.Path]::GetFullPath($SetupPath)) -Parent) 'app-package/CodexSkinManager.exe'
if(-not(Test-Path $app)){throw 'Staged application launcher is missing'}
if([Diagnostics.FileVersionInfo]::GetVersionInfo($app).FileDescription -ne 'CodexPage'){throw 'Launcher application identity is incorrect'}
'PASS setup rejects unsupported paths, checksum and compiled application identity'
