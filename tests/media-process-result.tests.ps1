$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
. (Join-Path $repo 'scripts/media.ps1')
. (Join-Path $repo 'engine/scripts/common-windows.ps1')
. (Join-Path $repo 'engine/scripts/theme-windows.ps1')
# Exercise the real redirected child-process boundary in Windows PowerShell 5.1.
# Losing its exit handle used to turn a successful apply into a wallpaper rollback.
$sandbox=Join-Path ([IO.Path]::GetTempPath()) ('media-result-'+[guid]::NewGuid().ToString('N'))
$originalLocalAppData=$env:LOCALAPPDATA
try {
  $env:LOCALAPPDATA=$sandbox
  $root=Join-Path $sandbox 'CodexDynamicSkin'
  $script:DynamicInstallRoot=$root
  $engine=Join-Path $root 'engine/scripts'
  [void][IO.Directory]::CreateDirectory($engine)
  $fixture=@'
param([switch]$PromptRestart,[string]$ResultToken)
$root=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Start-Sleep -Milliseconds 350
$mode=[IO.File]::ReadAllText((Join-Path $root 'fixture-mode'))
if($mode -eq 'missing'){exit 7}
$outcome='success';$category='none'
if($mode -eq 'cancelled'){$outcome='failure';$category='cancelled'}
if($mode -eq 'failure'){$outcome='failure';$category='cdp-launch-failed'}
$json=@{schemaVersion=1;token=$ResultToken;outcome=$outcome;category=$category;appearanceRecovery='not-needed'}|ConvertTo-Json -Compress
[IO.File]::WriteAllText((Join-Path $root ('.start-result-'+$ResultToken+'.json')),$json)
if($mode -eq 'nonzero'){exit 7}
exit 0
'@
  foreach($name in @('start-dream-skin.ps1','restore-dream-skin.ps1')){
    [IO.File]::WriteAllText((Join-Path $engine $name),$fixture)
  }
  [IO.File]::WriteAllText((Join-Path $root 'fixture-mode'),'success')
  $preview=Join-Path $repo 'engine/assets/demo-background.png'
  foreach($name in @('earth','campfire')){
    $path=Join-Path $root ($name+'.mp4')
    [IO.File]::WriteAllText($path,$name)
    $prepared=[pscustomobject]@{Kind='Video';Path=$path;Preview=$preview;Size=(Get-Item $path).Length;Sha256=(Get-FileHash $path).Hash.ToLowerInvariant()}
    Set-DynamicBackground -Prepared $prepared -StateRoot $root -Apply {Invoke-DynamicEngine -StateRoot $root}
  }
  $null=Initialize-DreamSkinThemeStore -SkillRoot (Join-Path $repo 'engine') -StateRoot $root
  $saved=[IO.File]::ReadAllText((Join-Path $root 'video-theme.json'))|ConvertFrom-Json
  if($saved.filePath -ne (Join-Path $root 'campfire.mp4')){throw 'Successful switch reverted to earth on startup initialization'}
  if(@(Get-ChildItem $root -Filter '.start-result-*.json').Count -ne 2){throw 'Successful switches unexpectedly triggered a rollback apply'}
  'PASS earth to campfire persists through startup initialization without rollback'
  if((Invoke-DynamicEngine -StateRoot $root -Restore) -ne $true){throw 'Successful restore was rejected'}
  'PASS redirected successful apply and restore retain success'
  foreach($mode in @('nonzero','missing','failure','cancelled')){
    [IO.File]::WriteAllText((Join-Path $root 'fixture-mode'),$mode)
    $failure=$null
    try {Invoke-DynamicEngine -StateRoot $root} catch {$failure=$_}
    if(-not $failure){throw "Accepted unsuccessful child: $mode"}
    if($mode -in @('nonzero','missing') -and $failure.Exception.Message -notmatch '7'){throw 'Lost actual nonzero exit code'}
    if($mode -eq 'failure' -and $failure.Exception.Message -notmatch 'cdp-launch-failed'){throw 'Lost structured failure reason'}
    if($mode -eq 'cancelled' -and -not(Test-DynamicOperationCancelled $failure.Exception)){throw 'Lost cancellation semantics'}
    "PASS $mode"
  }
  if((Invoke-DynamicEngine -StateRoot $root -Restore) -ne $false){throw 'Cancelled restore was not preserved'}
} finally {
  $env:LOCALAPPDATA=$originalLocalAppData
  $resolved=[IO.Path]::GetFullPath($sandbox)
  $tempRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
  if(-not $resolved.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe fixture cleanup'}
  if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
