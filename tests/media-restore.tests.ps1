$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $repo 'scripts/media.ps1');Initialize-DynamicMedia -InstallRoot $repo
. (Join-Path $repo 'scripts/wallpaper-library.ps1')
$root=Join-Path ([IO.Path]::GetTempPath()) ('media-restore-'+[guid]::NewGuid().ToString('N'))
try{
  $scripts=Join-Path $root 'CodexDynamicSkin/engine/scripts'
  [IO.Directory]::CreateDirectory($scripts)|Out-Null
  Copy-Item -LiteralPath (Join-Path $repo 'engine/scripts/common-windows.ps1'),(Join-Path $repo 'engine/scripts/config-utf8.ps1'),(Join-Path $repo 'engine/scripts/loopback-http.ps1') -Destination $scripts
  [IO.File]::WriteAllText((Join-Path $scripts 'restore-dream-skin.ps1'),@'
param([switch]$PromptRestart,[string]$ResultToken)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'common-windows.ps1')
$root=Join-Path $env:LOCALAPPDATA 'CodexDynamicSkin'
if(-not $PromptRestart -or -not $ResultToken){throw 'Restore lacks explicit prompt or result token'}
if(Test-Path (Join-Path $root 'cancel')){
  Write-DreamSkinStartResult -StateRoot $root -Token $ResultToken -Outcome failure -Category cancelled -AppearanceRecovery retained
  exit 0
}
if(Test-Path (Join-Path $root 'missing-result')){exit 0}
if(Test-Path (Join-Path $root 'failure-result')){
  Write-DreamSkinStartResult -StateRoot $root -Token $ResultToken -Outcome failure -Category cdp-endpoint-unavailable -AppearanceRecovery retained
  exit 7
}
Remove-Item -LiteralPath (Join-Path $root 'paused') -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath (Join-Path $root 'state.json') -Force -ErrorAction SilentlyContinue
Write-DreamSkinStartResult -StateRoot $root -Token $ResultToken -Outcome success -Category none -AppearanceRecovery restored
'@,(New-Object Text.UTF8Encoding($true)))
  $driver=Join-Path $root 'driver.ps1'
  [IO.File]::WriteAllText($driver,@'
param($Repo)
$ErrorActionPreference='Stop'
. (Join-Path $Repo 'scripts/media.ps1');Initialize-DynamicMedia -InstallRoot $Repo
. (Join-Path $Repo 'scripts/wallpaper-library.ps1')
$state=Join-Path $env:LOCALAPPDATA 'CodexDynamicSkin'
$script:DynamicInstallRoot=$state
$restored=Restore-DynamicWallpaperAppearance $state {Invoke-DynamicEngine -StateRoot $state -Restore}
if(Test-Path (Join-Path $state 'cancel')){
  if($restored -ne $false){throw 'Cancellation did not return false'}
  if(Test-DreamSkinPaused -StateRoot $state){throw 'Cancellation paused the current skin'}
  [IO.File]::WriteAllText((Join-Path $state 'cancelled'),'yes')
  exit 0
}
if($restored -ne $true){throw 'Successful restore did not return true'}
if(-not(Test-DreamSkinPaused -StateRoot $state)){throw 'Successful restore still looks active'}
[IO.File]::WriteAllText((Join-Path $state 'passed'),'yes')
'@,(New-Object Text.UTF8Encoding($true)))
  $state=Join-Path $root 'CodexDynamicSkin'
  foreach($mode in @('Success','Cancel','MissingResult','FailureResult')){
    # Each case represents an active managed session, not an untouched installation.
    [IO.File]::WriteAllText((Join-Path $state 'state.json'),'{}')
    if($mode -eq 'Cancel'){
      Remove-Item -LiteralPath (Join-Path $state 'passed'),(Join-Path $state 'paused') -Force
      [IO.File]::WriteAllText((Join-Path $state 'cancel'),'yes')
    }
    if($mode -eq 'MissingResult'){
      Remove-Item -LiteralPath (Join-Path $state 'cancel') -Force
      [IO.File]::WriteAllText((Join-Path $state 'missing-result'),'yes')
    }
    if($mode -eq 'FailureResult'){
      Remove-Item -LiteralPath (Join-Path $state 'missing-result') -Force
      [IO.File]::WriteAllText((Join-Path $state 'failure-result'),'yes')
    }
    $info=New-Object Diagnostics.ProcessStartInfo
    $info.FileName='powershell.exe';$info.UseShellExecute=$false;$info.CreateNoWindow=$true
    $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
    $info.EnvironmentVariables['LOCALAPPDATA']=$root
    $info.Arguments='-NoProfile -ExecutionPolicy RemoteSigned -File '+(ConvertTo-DreamSkinProcessArgument $driver)+' -Repo '+(ConvertTo-DreamSkinProcessArgument $repo)
    $process=[Diagnostics.Process]::Start($info)
    try{if(-not $process.WaitForExit(30000)){throw 'Restore test timed out'};$exit=$process.ExitCode;$errorText=$process.StandardError.ReadToEnd()}finally{$process.Dispose()}
    if($mode -eq 'Success' -and ($exit -ne 0 -or -not(Test-Path (Join-Path $state 'passed')))){throw 'Restore bridge rejected a confirmed real-engine-style success'}
    if($mode -eq 'Cancel' -and ($exit -ne 0 -or -not(Test-Path (Join-Path $state 'cancelled')) -or (Test-Path (Join-Path $state 'passed')) -or (Test-Path (Join-Path $state 'paused')))){throw 'Restore cancellation must finish without errors or changing active state'}
    if($mode -eq 'MissingResult' -and $exit -eq 0){throw 'Missing result must remain a real error'}
    if($mode -eq 'FailureResult' -and ($exit -eq 0 -or $errorText -notmatch 'cdp-endpoint-unavailable')){throw 'A nonzero child exit must preserve its structured failure reason'}
  }
  'PASS: restore prompts before restart, confirms result token and distinguishes cancellation from success'
}finally{if(Test-Path $root){Remove-Item -LiteralPath $root -Recurse -Force}}
