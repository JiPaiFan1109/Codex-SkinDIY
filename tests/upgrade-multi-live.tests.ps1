param([switch]$Legacy)
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
. (Join-Path $repo 'scripts/check-upgrade.ps1')
$fixtureRoot=Join-Path ([IO.Path]::GetTempPath()) ('skin-upgrade-live-'+[guid]::NewGuid().ToString('N'))
$supervisor=$null;$childId=$null
try{
  [IO.Directory]::CreateDirectory((Join-Path $fixtureRoot 'engine/runtime/node'))|Out-Null
  [IO.Directory]::CreateDirectory((Join-Path $fixtureRoot 'engine/scripts'))|Out-Null
  $runtime=Join-Path $fixtureRoot 'engine/runtime/node/node.exe'
  Add-Type -TypeDefinition 'using System.Threading; class WaitingUpdateFixture { static void Main(string[] args) { Thread.Sleep(60000); } }' -OutputAssembly $runtime -OutputType ConsoleApplication
  $scriptText=@'
param([string]$StateRoot)
$node=Join-Path $StateRoot 'engine/runtime/node/node.exe'
$injector=Join-Path $StateRoot 'engine/scripts/injector.mjs'
$worker=Start-Process $node -ArgumentList @(('"'+$injector+'"'),'--watch','--theme-dir',('"'+(Join-Path $StateRoot 'active-theme')+'"'),'--pause-file',('"'+(Join-Path $StateRoot 'paused')+'"')) -WindowStyle Hidden -PassThru
$self=[Diagnostics.Process]::GetCurrentProcess()
$status=@{Monitor=@{Id=$PID;StartedAt=$self.StartTime.ToUniversalTime().ToString('o');Executable=$self.MainModule.FileName;Script=$PSCommandPath;StateRoot=$StateRoot};Workers=@(@{Id=$worker.Id;StartedAt=$worker.StartTime.ToUniversalTime().ToString('o')})}
if(Test-Path (Join-Path $StateRoot 'legacy')){$status=@{Enabled=$true;AdditionalWatchers=1;WorkerFixtureId=$worker.Id}}
[IO.File]::WriteAllText((Join-Path $StateRoot 'multi-instance-status.json'),($status|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
Start-Sleep -Seconds 60
'@
  $monitorPath=Join-Path $fixtureRoot 'engine/scripts/multi-instance.ps1'
  if($Legacy){[IO.File]::WriteAllText((Join-Path $fixtureRoot 'legacy'),'legacy fixture')}
  [IO.File]::WriteAllText($monitorPath,$scriptText,[Text.UTF8Encoding]::new($true))
  [IO.File]::WriteAllText((Join-Path $fixtureRoot 'state.json'),(@{nodePath=$runtime;injectorPid=0;videoPid=0}|ConvertTo-Json))
  $before=(Get-FileHash (Join-Path $fixtureRoot 'state.json')).Hash
  $argsText='-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+$monitorPath+'" -StateRoot "'+$fixtureRoot+'"'
  if($Legacy){$argsText=$argsText.Replace('-WindowStyle Hidden ','')}
  $supervisor=Start-Process (Join-Path $PSHOME 'powershell.exe') -ArgumentList $argsText -WindowStyle Hidden -PassThru
  $deadline=[datetime]::UtcNow.AddSeconds(15)
  while(-not(Test-Path (Join-Path $fixtureRoot 'multi-instance-status.json'))){
    if($supervisor.HasExited -or [datetime]::UtcNow -gt $deadline){throw 'Fixture supervisor startup failed'}
    Start-Sleep -Milliseconds 100
  }
  $status=[IO.File]::ReadAllText((Join-Path $fixtureRoot 'multi-instance-status.json'))|ConvertFrom-Json
  $childId=if($Legacy){[int]$status.WorkerFixtureId}else{[int]$status.Workers[0].Id}
  $reason=Invoke-DynamicUpgradePreparation $fixtureRoot
  if($reason){throw $reason}
  if((Get-Process -Id $supervisor.Id,$childId -ErrorAction SilentlyContinue)){throw 'Verified supervisor or worker survived upgrade preparation'}
  if((Get-FileHash (Join-Path $fixtureRoot 'state.json')).Hash -ne $before){throw 'Saved state was changed'}
  'PASS real isolated PowerShell supervisor and native worker exit; saved wallpaper state preserved; legacy='+[bool]$Legacy
}finally{
  if($supervisor){if(-not $supervisor.HasExited){$supervisor.Kill();$supervisor.WaitForExit()};$supervisor.Dispose()}
  if($childId){$child=Get-Process -Id $childId -ErrorAction SilentlyContinue;if($child -and $child.Path -eq (Join-Path $fixtureRoot 'engine/runtime/node/node.exe')){Stop-Process -InputObject $child -Force}}
  if([IO.Path]::GetFullPath($fixtureRoot).StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()))){Remove-Item -LiteralPath $fixtureRoot -Recurse -Force}
}
