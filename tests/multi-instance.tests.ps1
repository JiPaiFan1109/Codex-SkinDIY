$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../engine/scripts/common-windows.ps1')
. (Join-Path $PSScriptRoot '../engine/scripts/multi-instance.ps1')
function Assert($Value,$Message){if(-not $Value){throw $Message}}
$install=[pscustomobject]@{Executable='C:\Codex\ChatGPT.exe'}
function App($id,$port,$parent=999){[pscustomobject]@{ProcessId=$id;ParentProcessId=$parent;ExecutablePath=$install.Executable;CommandLine="ChatGPT.exe --remote-debugging-port=$port"}}
$script:browserSuffix='a'
function Get-DreamSkinVerifiedCdpIdentity {param($Port,$Codex);if($Port -in @(9345,12910,12911)){[pscustomobject]@{BrowserId="browser-$Port-$script:browserSuffix"}}}
$apps=@((App 1 9345),(App 2 12910),(App 3 12911),(App 4 12910 2),(App 5 9999))
$endpoints=@(Get-DreamSkinInstanceEndpoints @($install) $apps)
Assert ($endpoints.Count -eq 3) 'Must discover three independent verified instances without renderer duplicates'
$script:browserSuffix='b'
$reopened=@(Get-DreamSkinInstanceEndpoints @($install) $apps)
Assert ($endpoints[1].Key -ne $reopened[1].Key) 'Restarted browser must have a new identity'

$temp=Join-Path ([IO.Path]::GetTempPath()) ('multi-instance-test-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($temp)|Out-Null
[IO.File]::WriteAllText((Join-Path $temp 'state.json'),'revision-one')
$script:tick=0;$script:started=@();$script:stopped=@();$script:removed=0
function Enter-DreamSkinOperationLock {return 'test-lock'}
function Exit-DreamSkinOperationLock {param($Mutex)}
function Read-DreamSkinState {
  param($Path)
  $script:tick++
  if($script:tick -eq 5){return $null}
  if($script:tick -eq 4){[IO.File]::WriteAllText((Join-Path $temp 'state.json'),'revision-two')}
  [pscustomobject]@{injectorPid=100;injectorStartedAt='start';port=9345;browserId='browser-9345-b';videoPid=$null}
}
function Get-DreamSkinRegisteredCodexInstalls {return $install}
function Get-CimInstance {param($ClassName,$Filter);if($script:tick -eq 3){return @($apps[0],$apps[2])};return $apps}
function Get-Process {param($Id);[pscustomobject]@{Id=100;Path=(Join-Path $temp 'engine/runtime/node/node.exe')}}
function Get-DreamSkinProcessStartedAt {param($ProcessId);'start'}
function Start-Process {
  param($FilePath,$ArgumentList,[switch]$PassThru,$WindowStyle,$RedirectStandardOutput,$RedirectStandardError)
  $script:started+=, $ArgumentList
  [pscustomobject]@{HasExited=$false;Id=($script:started.Count+200)}
}
function Stop-DreamSkinInstanceWorker {param($Worker,[switch]$Remove);$script:stopped+= $Worker.Process.Id;if($Remove){$script:removed++}}
try{
  Invoke-DreamSkinInstanceMonitor -StateRoot $temp -MaxCycles 5 -PollMilliseconds 0
  if(Test-Path (Join-Path $temp 'logs/multi-instance/monitor-error.log')){throw [IO.File]::ReadAllText((Join-Path $temp 'logs/multi-instance/monitor-error.log'))}
  Assert ($script:started.Count -eq 3) 'Must start two secondary workers, reuse them, remove closed instance, and refresh remaining worker on theme commit'
  Assert ($script:removed -eq 1) 'Restore must remove wallpaper from the remaining secondary instance'
  Assert ($script:stopped.Count -eq 3) 'Every owned child must be cleaned up exactly once'
  $status=Get-Content (Join-Path $temp 'multi-instance-status.json') -Raw -Encoding UTF8|ConvertFrom-Json
  Assert ($status.Enabled -eq $false -and $status.Ports.Count -eq 0 -and $status.AdditionalWatchers -eq 0) 'Restore must replace stale connected status with disabled status and an empty port list'
  'PASS: discovery, three instances, renderer exclusion, restart identity, duplicate prevention, closure, theme update, restore cleanup'
}finally{
  $absolute=[IO.Path]::GetFullPath($temp)
  if($absolute.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase)){Remove-Item -LiteralPath $absolute -Recurse -Force}
}
