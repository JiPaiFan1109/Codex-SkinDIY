$ErrorActionPreference='Stop'
$path=Join-Path $PSScriptRoot '../scripts/uninstall-app.ps1'
if(-not(Test-Path $path)){throw 'Application uninstall restore guard is missing'}
. $path
. (Join-Path $PSScriptRoot '../engine/scripts/theme-windows.ps1')
function Assert($Condition,$Message){if(-not $Condition){throw $Message}}
$root=Join-Path ([IO.Path]::GetTempPath()) ('skin-uninstall-'+[guid]::NewGuid().ToString('N'))
try{
  New-Item $root -ItemType Directory|Out-Null
  Assert (Invoke-DynamicUninstallRestore -InstallRoot $root -Silent) 'Unused installation should uninstall without prompting'
  Set-Content (Join-Path $root 'state.json') '{}'
  $rejected=$false
  try{Invoke-DynamicUninstallRestore -InstallRoot $root -Silent}catch{$rejected=$true}
  Assert $rejected 'Silent uninstall must refuse an active skin instead of closing Codex'
  Assert (Test-Path (Join-Path $root 'state.json')) 'Refused uninstall removed state'
  function Initialize-DynamicMedia {}
  function Invoke-DynamicEngine { return $false }
  $rejected=$false
  $cancelled=$false
  try{Invoke-DynamicUninstallRestore -InstallRoot $root}catch{$rejected=$true;$cancelled=$_.Exception -is [OperationCanceledException]}
  Assert $rejected 'Cancelled restore must abort uninstall'
  Assert $cancelled 'User cancellation must not be reported as an uninstall error'
  Assert (Test-Path (Join-Path $root 'state.json')) 'Cancelled restore removed active state'
  Assert (-not(Test-Path (Join-Path $root 'paused'))) 'Cancelled restore changed inactive marker'
  function Invoke-DynamicEngine { throw 'QA restore failure' }
  $failed=$false
  try{Invoke-DynamicUninstallRestore -InstallRoot $root}catch{$failed=$_.Exception.Message -eq 'QA restore failure'}
  Assert $failed 'Failed restore must abort uninstall'
  Assert (Test-Path (Join-Path $root 'state.json')) 'Failed restore removed active state'
  Assert (-not(Test-Path (Join-Path $root 'paused'))) 'Failed restore changed inactive marker'
  New-Item (Join-Path $root 'active-theme') -ItemType Directory|Out-Null
  function Invoke-DynamicEngine {
    param([string]$StateRoot,[switch]$Restore)
    # Match the real engine contract: it removes both session and pause files.
    Remove-Item -LiteralPath (Join-Path $StateRoot 'state.json')
    if(Test-Path (Join-Path $StateRoot 'paused')){Remove-Item -LiteralPath (Join-Path $StateRoot 'paused')}
    return $true
  }
  Assert (Invoke-DynamicUninstallRestore -InstallRoot $root) 'Successful restore did not permit uninstall'
  Assert (-not(Test-Path (Join-Path $root 'state.json'))) 'Successful restore left active state'
  Assert (Test-Path (Join-Path $root 'paused')) 'Successful uninstall restore must persist inactive state for retained themes'
  function Invoke-DynamicEngine { throw 'Already restored appearance must not run the engine again' }
  Assert (Invoke-DynamicUninstallRestore -InstallRoot $root -Silent) 'Restored appearance with retained theme files should allow silent uninstall'
}finally{
  $resolved=[IO.Path]::GetFullPath($root)
  $expectedPrefix=Join-Path ([IO.Path]::GetFullPath([IO.Path]::GetTempPath())) 'skin-uninstall-'
  if(-not $resolved.StartsWith($expectedPrefix,[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe test cleanup path'}
  if(Test-Path $root){Remove-Item -LiteralPath $root -Recurse -Force}
}
'PASS uninstall no-state, silent guard, cancellation and successful restore'
