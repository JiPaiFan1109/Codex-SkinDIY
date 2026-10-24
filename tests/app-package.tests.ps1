param([string]$SetupPath)
$ErrorActionPreference='Stop'
if(-not $SetupPath){$SetupPath=Join-Path $PSScriptRoot '../dist/CodexPage-Setup.exe'}
if(-not(Test-Path $SetupPath)){throw 'Windows application installer is missing'}
# Installation lifecycle is exercised only by installer/verify-setup.ps1 with an isolated AppId.
$sum=([IO.File]::ReadAllText(($SetupPath+'.sha256')) -split '\s+')[0]
if((Get-FileHash $SetupPath -Algorithm SHA256).Hash -ine $sum){throw 'Installer checksum mismatch'}
$app=Join-Path (Split-Path ([IO.Path]::GetFullPath($SetupPath)) -Parent) 'app-package/CodexSkinManager.exe'
if(-not(Test-Path $app)){throw 'Staged application launcher is missing'}
if([Diagnostics.FileVersionInfo]::GetVersionInfo($app).FileDescription -ne 'CodexPage'){throw 'Launcher application identity is incorrect'}
'PASS setup checksum and compiled application identity'
