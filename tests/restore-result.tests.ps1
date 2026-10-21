$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $repo 'scripts/media.ps1');Initialize-DynamicMedia -InstallRoot $repo
$root=Join-Path ([IO.Path]::GetTempPath()) ('restore-result-'+[guid]::NewGuid().ToString('N'))
try{
  $scripts=Join-Path $root 'scripts';[IO.Directory]::CreateDirectory($scripts)|Out-Null
  foreach($name in @('common-windows.ps1','config-utf8.ps1','loopback-http.ps1','restore-dream-skin.ps1')){Copy-Item -LiteralPath (Join-Path $repo "engine/scripts/$name") -Destination $scripts}
  # Replace process/installation discovery boundaries; execute the real restore control flow.
  [IO.File]::WriteAllText((Join-Path $scripts 'theme-windows.ps1'),@'
function Enter-DreamSkinOperationLock {return $null}
function Exit-DreamSkinOperationLock {param($Mutex)}
function Get-DreamSkinThemePaths {param($StateRoot);return @{Root=$StateRoot}}
function Ensure-DreamSkinManagedDirectory {param($Path,$Root);[IO.Directory]::CreateDirectory($Path)|Out-Null}
function Read-DreamSkinState {param($Path);return $null}
function Get-DreamSkinCodexInstall {return @{Executable='fake.exe';PackageRoot='fake'}}
function Get-DreamSkinCodexStatePathCandidate {param($State);return $null}
function Get-DreamSkinCodexInstallFromState {param($State);return $null}
function Get-DreamSkinCodexProcesses {param($Codex);if($env:SKIN_RESTORE_TEST_CANCEL -eq 'yes'){return @(@{Id=1})};return @()}
function Test-DreamSkinCodexPortOwner {param($Port,$Codex);return $false}
function Test-DreamSkinPortAvailable {param($Port);return $true}
function Confirm-DreamSkinRestart {param($Message);return $false}
function Stop-DreamSkinRecordedInjector {param($State);return $true}
function Stop-DreamSkinRecordedVideo {param($State);return $true}
function Stop-DreamSkinCodex {throw 'Test must not stop any real process'}
'@,(New-Object Text.UTF8Encoding($true)))
  [IO.File]::WriteAllText((Join-Path $scripts 'localization-windows.ps1'),'function Resolve-DreamSkinLanguage {return ''en''}; function Get-DreamSkinText {param($Key,$Language);return $Key}')
  [IO.File]::WriteAllText((Join-Path $scripts 'video-windows.ps1'),'# All process boundaries stubbed in theme fixture.')
  foreach($cancel in @($false,$true)){
    $token=[guid]::NewGuid().ToString('N')
    $info=New-Object Diagnostics.ProcessStartInfo
    $info.FileName='powershell.exe';$info.UseShellExecute=$false;$info.CreateNoWindow=$true
    $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
    $info.EnvironmentVariables['LOCALAPPDATA']=$root
    $info.EnvironmentVariables['SKIN_RESTORE_TEST_CANCEL']='no';if($cancel){$info.EnvironmentVariables['SKIN_RESTORE_TEST_CANCEL']='yes'}
    $info.Arguments='-NoProfile -ExecutionPolicy RemoteSigned -File '+(ConvertTo-DreamSkinProcessArgument (Join-Path $scripts 'restore-dream-skin.ps1'))+' -PromptRestart -ResultToken '+$token
    $process=[Diagnostics.Process]::Start($info)
    try{if(-not $process.WaitForExit(20000)){throw 'Restore control-flow test timed out'};$errorText=$process.StandardError.ReadToEnd();if($process.ExitCode -ne 0){throw ('Real restore script did not support confirmed results: '+$errorText)}}finally{$process.Dispose()}
    $result=Read-DreamSkinStartResult -StateRoot (Join-Path $root 'CodexDynamicSkin') -Token $token
    if($cancel -and $result.outcome -eq 'success'){throw 'Cancelled real restore emitted success'}
    if($cancel -and $result.category -ne 'cancelled'){throw 'Cancelled restore must be distinguishable from failure'}
    if(-not $cancel -and $result.outcome -ne 'success'){throw 'Successful real restore did not emit success'}
  }
  'PASS: real restore control flow emits success only after completion, cancellation stays unsuccessful'
}finally{if(Test-Path $root){Remove-Item -LiteralPath $root -Recurse -Force}}
