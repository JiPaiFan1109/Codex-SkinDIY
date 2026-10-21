$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'engine/scripts/common-windows.ps1')
. (Join-Path $root 'engine/scripts/video-windows.ps1')
$old='2000-01-01T00:00:00.0000000Z'
$state=[pscustomobject]@{
  injectorPid=$PID;injectorStartedAt=$old;injectorPath='C:\fixture\injector.mjs'
  videoPid=$PID;videoStartedAt=$old;videoScript='C:\fixture\video-server.mjs'
  videoReadyPath=(Join-Path ([IO.Path]::GetTempPath()) 'missing-video-ready.json')
  nodePath='C:\fixture\node.exe';port=9345;browserId='fixture-browser'
}
$injectorResult=Stop-DreamSkinRecordedInjector -State $state
if($injectorResult -ne $false){throw 'FAIL: reused injector PID was treated as the recorded process'}
if(-not(Get-Process -Id $PID -ErrorAction SilentlyContinue)){throw 'FAIL: reused injector PID was stopped'}
$videoResult=Stop-DreamSkinRecordedVideo -State $state
if($videoResult -ne $false){throw 'FAIL: reused video PID was treated as the recorded process'}
if(-not(Get-Process -Id $PID -ErrorAction SilentlyContinue)){throw 'FAIL: reused video PID was stopped'}
# Old saved video state may omit a readiness path after its helper has exited.
$exited=Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList '-NoProfile -NonInteractive -Command exit 0' -WindowStyle Hidden -PassThru
$exited.WaitForExit()
$missingReady=[pscustomobject]@{videoPid=$exited.Id;videoStartedAt=$old}
if((Stop-DreamSkinRecordedVideo -State $missingReady) -ne $true){throw 'FAIL: exited video without a readiness path blocked restore'}
$reusedWithoutReady=[pscustomobject]@{videoPid=$PID;videoStartedAt=$old}
if((Stop-DreamSkinRecordedVideo -State $reusedWithoutReady) -ne $false){throw 'FAIL: reused video PID without a readiness path was accepted'}
if(-not(Get-Process -Id $PID -ErrorAction SilentlyContinue)){throw 'FAIL: reused video PID without readiness was stopped'}
'PASS: reused injector and video PIDs are archived as stale without stopping unrelated processes'
