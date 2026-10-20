$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
. (Join-Path $repo 'scripts/check-upgrade.ps1')
if(-not(Get-Command Invoke-DynamicUpgradePreparation -ErrorAction SilentlyContinue)){throw 'Setup must retire verified skin helpers instead of asking users to restore Codex'}
function Assert($Condition,$Message){if(-not $Condition){throw $Message}}
$root=Join-Path ([IO.Path]::GetTempPath()) ('skin-upgrade-helper-'+[guid]::NewGuid().ToString('N'))
try{
  New-Item $root -ItemType Directory|Out-Null
  $runtime=Join-Path $root 'engine/runtime/node/node.exe'
  $injector=Join-Path $root 'engine/scripts/injector.mjs';$video=Join-Path $root 'engine/scripts/video-server.mjs'
  $started=[datetime]::UtcNow.AddMinutes(-1)
  $state=[ordered]@{nodePath=$runtime;injectorPid=101;injectorStartedAt=$started.ToString('o');injectorPath=$injector;videoPid=102;videoStartedAt=$started.ToString('o');videoScript=$video}
  $statePath=Join-Path $root 'state.json';$state|ConvertTo-Json|Set-Content $statePath -Encoding UTF8
  $before=(Get-FileHash $statePath).Hash
  $script:fixtureProcesses=@(
    [pscustomobject]@{ProcessId=101;ExecutablePath=$runtime;CommandLine=('"'+$runtime+'" "'+$injector+'" --watch')},
    [pscustomobject]@{ProcessId=102;ExecutablePath=$runtime;CommandLine=('"'+$runtime+'" "'+$video+'" --config "'+(Join-Path $root 'video-theme.json')+'" --ready "'+(Join-Path $root 'video-ready.json')+'"')}
  )
  $originalProcesses=@($script:fixtureProcesses);$script:stopped=@();$script:recycled=$false
  function Get-CimInstance {param($ClassName,$Filter);return $script:fixtureProcesses}
  function Get-Process {
    param($Id,$ErrorAction)
    $timestamp=$started;if($script:recycled){$timestamp=$started.AddSeconds(1)}
    $handlePath=$runtime;if($Id -eq 205){$handlePath=Join-Path $env:WINDIR 'System32/WindowsPowerShell/v1.0/powershell.exe'};if($script:noHandlePath){$handlePath=$null}
    $handle=[pscustomobject]@{Id=$Id;Path=$handlePath;StartTime=$timestamp;HasExited=$false}
    $handle|Add-Member ScriptMethod WaitForExit {param($Timeout);return $this.HasExited}
    $handle|Add-Member ScriptMethod Dispose {}
    return $handle
  }
  function Stop-Process {
    param($InputObject,[switch]$Force,$ErrorAction)
    $script:stopped+=$InputObject.Id;$InputObject.HasExited=$true
    $script:fixtureProcesses=@($script:fixtureProcesses|Where-Object ProcessId -ne $InputObject.Id)
  }
  Assert (-not(Invoke-DynamicUpgradePreparation $root)) 'Verified helpers should permit upgrade'
  Assert (($script:stopped -join ',') -eq '101,102') 'Only the recorded injector and video helper should be stopped'
  Assert ((Get-FileHash $statePath).Hash -eq $before) 'Preparation modified saved appearance state'
  $script:fixtureProcesses=@($originalProcesses);$script:stopped=@();$script:noHandlePath=$true
  Assert (-not(Invoke-DynamicUpgradePreparation $root)) '32-bit Process.Path can be unavailable; verified CIM identity must still permit helper cleanup'
  Assert ($script:stopped.Count -eq 2) 'Verified CIM helpers were not retired when Process.Path was unavailable'
  $script:noHandlePath=$false
  $monitorScript=Join-Path $root 'engine/scripts/multi-instance.ps1'
  $monitorExe=Join-Path $env:WINDIR 'System32/WindowsPowerShell/v1.0/powershell.exe'
  $monitorProcess=[pscustomobject]@{ProcessId=205;ExecutablePath=$monitorExe;CommandLine=('"'+$monitorExe+'" -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+$monitorScript+'" -StateRoot "'+$root+'"')}
  $workerProcess=[pscustomobject]@{ProcessId=203;ParentProcessId=205;ExecutablePath=$runtime;CommandLine=('"'+$runtime+'" "'+$injector+'" --watch --port 12912')}
  $status=@{Monitor=@{Id=205;StartedAt=$started.ToString('o');Executable=$monitorExe;Script=$monitorScript;StateRoot=$root};Workers=@(@{Id=203;StartedAt=$started.ToString('o')})}
  $status|ConvertTo-Json -Depth 5|Set-Content (Join-Path $root 'multi-instance-status.json') -Encoding UTF8
  $script:fixtureProcesses=@($originalProcesses)+@($monitorProcess,$workerProcess);$script:stopped=@()
  Assert (-not(Invoke-DynamicUpgradePreparation $root)) 'Verified monitor and worker must permit upgrade'
  Assert (($script:stopped -join ',') -eq '205,101,102,203') 'Supervisor must stop before its workers, then all verified helpers must exit'
  Assert ((Get-FileHash $statePath).Hash -eq $before) 'Multi-instance upgrade altered saved appearance state'
  $workerProcess.ParentProcessId=999
  $script:fixtureProcesses=@($originalProcesses)+@($monitorProcess,$workerProcess);$script:stopped=@()
  Assert ([bool](Invoke-DynamicUpgradePreparation $root)) 'A forged worker parent must block upgrade'
  Assert ($script:stopped.Count -eq 0) 'Validation must finish before stopping the supervisor'
  $workerProcess.ParentProcessId=205
  $script:fixtureProcesses=@($originalProcesses)+@([pscustomobject]@{ProcessId=103;ExecutablePath=$runtime;CommandLine=('"'+$runtime+'" -e "setInterval(()=>{},1000)"')})
  $script:stopped=@()
  Assert ([bool](Invoke-DynamicUpgradePreparation $root)) 'Unrecognized runtime process must block upgrade'
  Assert ($script:stopped.Count -eq 0) 'Blocked upgrade must not partially stop helpers'
  $script:fixtureProcesses=@($originalProcesses);$script:recycled=$true
  Assert ([bool](Invoke-DynamicUpgradePreparation $root)) 'Recycled PID must not be stopped'
  Assert ($script:stopped.Count -eq 0) 'PID identity mismatch terminated a process'
  $script:recycled=$false
  $script:fixtureProcesses=@([pscustomobject]@{ProcessId=101;ExecutablePath=$runtime;CommandLine=('"'+$runtime+'" -e "keepalive" "'+$injector+'" --watch')})
  Assert ([bool](Invoke-DynamicUpgradePreparation $root)) 'Helper filename used as data is not a helper process'
  Assert ($script:stopped.Count -eq 0) 'Command-line impersonation terminated a process'
  'PASS verified helper cleanup, saved-state preservation, foreign process and recycled PID protection'
}finally{if(Test-Path $root){Remove-Item -LiteralPath $root -Recurse -Force}}
