$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
. (Join-Path $repo 'engine/scripts/launch-dream-skin.ps1')

$fixture=Join-Path ([IO.Path]::GetTempPath()) ('dream-skin-quick-'+[guid]::NewGuid().ToString('N'))
$scripts=Join-Path $fixture 'engine\scripts'
New-Item -ItemType Directory -Path $scripts -Force|Out-Null
try{
  $started=[datetime]'2026-10-02T01:02:03Z'
  $state=[ordered]@{
    schemaVersion=3;platform='windows';port=9345;browserId='browser-123'
    codexPackageFamilyName='OpenAI.Codex_2p2nqsd0c76g0';codexExe='C:\Codex\ChatGPT.exe'
    profilePath=(Join-Path $fixture 'cdp-profile');themeDir=(Join-Path $fixture 'active-theme');pauseFile=(Join-Path $fixture 'paused')
    nodePath=(Join-Path $fixture 'engine\runtime\node\node.exe');injectorPath=(Join-Path $fixture 'engine\scripts\injector.mjs')
    injectorPid=11;injectorStartedAt=$started.ToUniversalTime().ToString('o')
  }
  $state|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $fixture 'state.json') -Encoding UTF8
  function Invoke-DreamSkinLoopbackJson { [pscustomobject]@{webSocketDebuggerUrl='ws://127.0.0.1:9345/devtools/browser/browser-123'} }
  function Get-Process { [pscustomobject]@{Id=11;Path=$state.nodePath;StartTime=$started} }
  function Get-CimInstance {
    @(
      [pscustomobject]@{ProcessId=31;ParentProcessId=300;ExecutablePath=$state.codexExe;CommandLine='"C:\Codex\ChatGPT.exe" --remote-debugging-address=127.0.0.1 --remote-debugging-port=9345 --user-data-dir="'+$state.profilePath+'"'},
      [pscustomobject]@{ProcessId=41;ParentProcessId=400;ExecutablePath=$state.codexExe;CommandLine='"C:\Codex\ChatGPT.exe"'}
    )
  }
  $script:activationAttempts=0
  $script:fullStarts=0
  function Initialize-DynamicQuickPackageLauncher {$script:activationAttempts++;throw 'Package activation must not be attempted.'}
  function Start-DynamicFullLauncher {param($ScriptRoot)$script:fullStarts++}

  $result=Invoke-DynamicQuickLauncher -ScriptRoot $scripts
  if($result-ne$false){throw 'FAIL: mixed profiles were accepted by the quick launcher'}
  if($script:activationAttempts-ne0){throw 'FAIL: package activation was attempted while an ordinary Codex instance was open'}
  if($script:fullStarts-ne1){throw 'FAIL: mixed profiles did not fall back to the guarded full launcher'}
  'PASS: quick launch falls back before activation when another Codex profile is open.'
}finally{
  if(Test-Path -LiteralPath $fixture){Remove-Item -LiteralPath $fixture -Recurse -Force}
}
