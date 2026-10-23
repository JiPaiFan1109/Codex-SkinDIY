$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../engine/scripts/common-windows.ps1')

. (Join-Path $PSScriptRoot '../engine/scripts/theme-windows.ps1')
function Assert($Condition,$Message){if(-not $Condition){throw $Message}}
$root=Join-Path ([IO.Path]::GetTempPath()) ('codex-manual-selection-'+[guid]::NewGuid().ToString('N'))
$exe=Join-Path $root 'ChatGPT.exe';[IO.Directory]::CreateDirectory($root)|Out-Null;[IO.File]::WriteAllText($exe,'fixture')
$install=[pscustomobject]@{Version='26.1013.4894.0';Executable=$exe;PackageFullName='OpenAI.Codex_26.1013.4894.0_x64__2p2nqsd0c76g0';PackageFamilyName='OpenAI.Codex_2p2nqsd0c76g0';ApplicationId='App';AppUserModelId='OpenAI.Codex_2p2nqsd0c76g0!App';PackageRoot=$root;SignatureKind='Store'}
try{
  function Get-DreamSkinRegisteredCodexInstalls {return @($install)}
  $resolved=Resolve-DreamSkinCodexManualSelection $exe
  Assert ($resolved.AppUserModelId -eq $install.AppUserModelId) 'Validated ChatGPT.exe was not resolved to the registered package'
  $bad=Join-Path $root 'Other.exe';[IO.File]::WriteAllText($bad,'fixture')
  $rejected=$false;try{$null=Resolve-DreamSkinCodexManualSelection $bad}catch{$rejected=$true}
  Assert $rejected 'An unrelated executable was accepted as Codex'
  Write-DreamSkinManualCodexSelection -StateRoot $root -Install $install|Out-Null
  $manual=Get-Content (Join-Path $root 'codex-manual.json') -Raw|ConvertFrom-Json
  Assert ($manual.Executable -eq $exe -and $manual.PackageFullName -eq $install.PackageFullName) 'Manual selection did not persist only the validated identity'
  $previousLocalAppData=$env:LOCALAPPDATA
  $env:LOCALAPPDATA=$root
  $stateDir=Join-Path $root 'CodexDynamicSkin';[IO.Directory]::CreateDirectory((Join-Path $stateDir 'engine/scripts'))|Out-Null
  Copy-Item (Join-Path $PSScriptRoot '../engine/scripts/common-windows.ps1') (Join-Path $stateDir 'engine/scripts/common-windows.ps1')
  foreach($dependency in @('loopback-http.ps1','config-utf8.ps1')){Copy-Item (Join-Path $PSScriptRoot ('../engine/scripts/'+$dependency)) (Join-Path $stateDir ('engine/scripts/'+$dependency))}
  . (Join-Path $stateDir 'engine/scripts/common-windows.ps1')
  $install.PackageFullName=Split-Path $root -Leaf
  $manualPayload=[pscustomobject]@{Executable=$install.Executable;PackageFullName=$install.PackageFullName;AppUserModelId=$install.AppUserModelId}
  $manualPayload|ConvertTo-Json -Compress|Set-Content (Join-Path $stateDir 'codex-manual.json') -Encoding utf8
  function Get-DreamSkinRegisteredCodexInstalls {throw 'Appx enumeration unavailable'}
  function Get-AppxPackage {[CmdletBinding()]param();return [pscustomobject]@{Name='OpenAI.Codex';InstallLocation=$root;PackageFullName=$install.PackageFullName;PackageFamilyName=$install.PackageFamilyName;SignatureKind='Store';IsDevelopmentMode=$false;Version=$install.Version}}
  function ConvertTo-DreamSkinCodexInstall {param($Package);return $install}
  $fallback=Get-DreamSkinCodexInstall
  Assert ($fallback.Executable -eq $exe) 'Manual selection did not recover after package enumeration failure'
  $env:LOCALAPPDATA=$previousLocalAppData
  'PASS registered-package matching, unrelated EXE rejection and validated identity persistence'
}finally{if(Test-Path $root){Remove-Item -LiteralPath $root -Recurse -Force}}
