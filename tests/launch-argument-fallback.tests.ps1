$ErrorActionPreference='Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'engine/scripts/common-windows.ps1')
function Start-DreamSkinCodex {return 100}
function Wait-DreamSkinCodexDebugArgumentStatus {if($script:direct){return 'forwarded'};return $script:status}
function Stop-DreamSkinCodex {param($Codex,$PreserveProcessIds,[switch]$AllowForce);if($PreserveProcessIds -notcontains 77){throw 'Existing process protection lost'}}
function Start-DreamSkinCodexDirect {$script:direct=$true;return 101}
foreach($status in @('protocol-redirected','not-forwarded','forwarded')){
  $script:status=$status;$script:direct=$false
  $result=Start-DreamSkinCodexForDebugging -Codex @{} -Arguments @('--remote-debugging-port=9345') -Port 9345 -PreserveProcessIds @(77)
  if(($status -eq 'forwarded') -eq $script:direct){throw 'Wrong launch strategy'}
}
'PASS discarded activation arguments use direct launch while preserving existing processes'
