$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../engine/scripts/common-windows.ps1')
. (Join-Path $PSScriptRoot '../engine/scripts/multi-instance.ps1')
$root=Join-Path ([IO.Path]::GetTempPath()) ('skin-monitor-intent-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($root)|Out-Null
$script:starts=0;$script:ordinary=$false
$install=[pscustomobject]@{Executable='C:\fixture\ChatGPT.exe'}
function Enter-DreamSkinOperationLock {return 'fixture-lock'}
function Exit-DreamSkinOperationLock {param($Mutex)}
function Get-DreamSkinRegisteredCodexInstalls {return $install}
function Get-CimInstance {param($ClassName,$Filter)
  $command=if($script:ordinary){'ChatGPT.exe'}else{'ChatGPT.exe --remote-debugging-port=9345'}
  [pscustomobject]@{ProcessId=222;ParentProcessId=1;ExecutablePath=$install.Executable;CommandLine=$command;CreationDate='new-start'}
}
function Get-DreamSkinVerifiedCdpIdentity {param($Port,$Codex);[pscustomobject]@{BrowserId='new-browser'}}
function Get-Process {param($Id);return $null}
function Get-DreamSkinProcessStartedAt {param($ProcessId);'fixture-start'}
function Start-Process {param($FilePath,$ArgumentList,$WindowStyle,[switch]$PassThru,$RedirectStandardOutput,$RedirectStandardError)
  if($ArgumentList -notcontains 'new-browser'){throw 'Stale identity was reused'}
  $script:starts++;[pscustomobject]@{HasExited=$false;Id=333}
}
function Stop-DreamSkinInstanceWorker {param($Worker,[switch]$Remove)}
try {
  Write-DreamSkinRecoveryIntent $root ([pscustomobject]@{schemaVersion=1;port=9345;injectorPid=123;browserId='old-browser'})
  Invoke-DreamSkinInstanceMonitor $root -MaxCycles 2 -PollMilliseconds 0
  if($script:starts -ne 1){throw 'Missing state must recover exactly one worker using a freshly verified browser'}
  $script:ordinary=$true
  Invoke-DreamSkinInstanceMonitor $root -MaxCycles 1 -PollMilliseconds 0
  $status=Get-Content (Join-Path $root 'multi-instance-status.json') -Raw -Encoding UTF8|ConvertFrom-Json
  if($status.RecoveryState -ne 'connection-required' -or $script:starts -ne 1){throw 'Ordinary launch must be reported without restarting it'}
  Clear-DreamSkinRecoveryIntent $root
  Invoke-DreamSkinInstanceMonitor $root -MaxCycles 1 -PollMilliseconds 0
  $status=Get-Content (Join-Path $root 'multi-instance-status.json') -Raw -Encoding UTF8|ConvertFrom-Json
  if($status.Enabled -or $script:starts -ne 1){throw 'Explicit restore was undone'}
  $errorLog=Join-Path $root 'logs/multi-instance/monitor-error.log'
  if(Test-Path $errorLog){throw (Get-Content $errorLog -Raw)}
  'PASS: lost session recovers once with fresh identity; ordinary launch is reported; restore stays disabled'
} finally {
  $resolved=[IO.Path]::GetFullPath($root)
  if(-not $resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe cleanup'}
  Remove-Item -LiteralPath $resolved -Recurse -Force
}
