$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
. (Join-Path $repo 'engine/scripts/common-windows.ps1')
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'engine/scripts/start-dream-skin.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Startup script did not parse'}
$loop=@($ast.FindAll({param($n) $n -is [Management.Automation.Language.WhileStatementAst] -and $n.Extent.Text.Contains('$verify = Invoke-DreamSkinNative')},$true))
if($loop.Count -ne 1){throw 'Expected one real startup verification loop'}
$rendered=@($ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Test-DreamSkinRenderedVerificationOutput'},$true))
. ([scriptblock]::Create($rendered[0].Extent.Text))
$testRoot=Join-Path ([IO.Path]::GetTempPath()) ('skin-watcher-health-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot|Out-Null
$daemon=Start-Process -FilePath "$env:SystemRoot\System32\cmd.exe" -ArgumentList '/c exit 0' -WindowStyle Hidden -PassThru
$daemon.WaitForExit();$daemon.Refresh()
try {
  # Replace only the external native probe/activation boundaries. Execute the
  # shipped verification loop against an actual exited Process object.
  function Invoke-DreamSkinNative {
    param($FilePath,$ArgumentList)
    if($ArgumentList -contains '--verify'){return [pscustomobject]@{ExitCode=$script:verifyExit;Output=@('{}')}}
    if($ArgumentList -contains '--once'){return [pscustomobject]@{ExitCode=0;Output=@('{}')}}
    throw 'Unexpected native operation'
  }
  function Invoke-DreamSkinCodexWindowActivation {param($Codex) return $true}
  foreach($exit in @(0,2)) {
    $script:verifyExit=$exit
    $Injector='fixture-injector';$node=@{Path='fixture-node'};$Port=9345
    $cdpIdentity=@{BrowserId='fixture-browser'};$themePaths=@{Active='fixture-theme'}
    $injectorVideoArgs=@();$VerifyPath=Join-Path $testRoot 'verify.json'
    $StderrPath=Join-Path $testRoot 'error.log';$codex=@{}
    $forceInjectedAfterVerifyFailure=$false;$skinLooksRendered=$false
    $verifyDeadline=(Get-Date).AddSeconds(2)
    $failure=$null
    try { & ([scriptblock]::Create($loop[0].Extent.Text)) } catch {$failure=$_}
    if($null -eq $failure -or $failure.Exception.Message -notmatch 'injector exited during startup'){
      throw "FAIL: exited watcher accepted when initial verify exit was $exit"
    }
  }
  'PASS: neither successful verify nor successful one-shot apply can accept an exited watcher'
} finally {
  $daemon.Dispose()
  $resolved=[IO.Path]::GetFullPath($testRoot)
  if(-not $resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe fixture cleanup path'}
  Remove-Item -LiteralPath $resolved -Recurse -Force
}
