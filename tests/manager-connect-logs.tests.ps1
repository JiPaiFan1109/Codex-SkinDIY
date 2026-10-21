$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
. (Join-Path $repo 'scripts/media.ps1')
. (Join-Path $repo 'engine/scripts/common-windows.ps1')
. (Join-Path $repo 'engine/scripts/theme-windows.ps1')
function Assert($Condition,$Message){if(-not $Condition){throw $Message}}
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('codex-connect-logs-'+[guid]::NewGuid().ToString('N'))
$previousLocalAppData=$env:LOCALAPPDATA
try{
  $env:LOCALAPPDATA=$fixture
  $install=Join-Path $fixture 'CodexDynamicSkin'
  $scripts=Join-Path $install 'engine/scripts'
  [void][IO.Directory]::CreateDirectory($scripts)
  $script:DynamicInstallRoot=$install
  # This child only writes a structured failure and output. No real application is started.
  $common=(Join-Path $repo 'engine/scripts/common-windows.ps1').Replace("'","''")
  $child=@'
param([switch]$PromptRestart,[string]$ResultToken)
$ErrorActionPreference='Stop'
. '__COMMON__'
if(-not $PromptRestart){throw 'Restart confirmation was bypassed'}
Write-Host 'connection-launch-diagnostic-marker'
Write-DreamSkinStartResult -StateRoot (Join-Path $env:LOCALAPPDATA 'CodexDynamicSkin') -Token $ResultToken -Outcome failure -Category cdp-endpoint-unavailable -AppearanceRecovery not-needed
throw 'connection-launch-error-marker'
'@
  [IO.File]::WriteAllText((Join-Path $scripts 'start-dream-skin.ps1'),$child.Replace('__COMMON__',$common),[Text.UTF8Encoding]::new($true))
  for($i=0;$i -lt 2;$i++){
    $failure=$null
    try{Invoke-DynamicEngine -StateRoot $install}catch{$failure=$_.Exception.Message}
    Assert ($failure -like '*cdp-endpoint-unavailable*') "Structured startup failure category was lost: $failure"
  }
  $outputs=@(Get-ChildItem (Join-Path $install 'logs') -Filter '*-output.log' -ErrorAction SilentlyContinue)
  $errors=@(Get-ChildItem (Join-Path $install 'logs') -Filter '*-error.log' -ErrorAction SilentlyContinue)
  Assert ($outputs.Count -eq 2 -and $errors.Count -eq 2) 'Manager connection attempts must retain separate hidden launch logs'
  foreach($file in $outputs){Assert (([IO.File]::ReadAllText($file.FullName)) -like '*connection-launch-diagnostic-marker*') 'Startup output missing from log'}
  foreach($file in $errors){Assert (([IO.File]::ReadAllText($file.FullName)) -like '*connection-launch-error-marker*') 'Startup exception missing from log'}
  'PASS hidden manager startup logs, separate attempts and preserved failure category/restart prompt'
}finally{
  $env:LOCALAPPDATA=$previousLocalAppData
  $full=[IO.Path]::GetFullPath($fixture)
  if(-not $full.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase)){throw 'Invalid fixture cleanup path'}
  if(Test-Path -LiteralPath $full){Remove-Item -LiteralPath $full -Recurse -Force}
}
