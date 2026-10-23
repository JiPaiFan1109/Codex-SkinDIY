$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../engine/scripts/common-windows.ps1')
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot '../engine/scripts/start-dream-skin.ps1'),[ref]$tokens,[ref]$errors)
$fn=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Test-DreamSkinPendingVerificationOutput'},$true)
if(-not $fn){throw 'Missing hidden-start pending classifier'}
. ([scriptblock]::Create($fn.Extent.Text))
$r=@{installed=$true;stylePresent=$true;version='1';expectedVersion='1';themeId='custom';expectedThemeId='custom';revision='abc';expectedRevision='abc';documentVisibility='hidden';documentHidden=$true;businessClassPollution=0;readiness=@{structurePass=$true;viewportPass=$true};video=@{playing=$false}}
function Check($want){$json=@{targets=@(@{result=$r})}|ConvertTo-Json -Depth 8;if((Test-DreamSkinPendingVerificationOutput @($json)) -ne $want){throw "Unexpected pending classification: $json"}}
Check $true
$r.documentHidden=$false;$r.documentVisibility='visible';Check $false
$r.documentHidden=$true;$r.documentVisibility='hidden';$r.revision='wrong';Check $false
$r.revision='abc';$r.installed=$false;Check $false
$r.installed=$true;$r.readiness.structurePass=$false;Check $false
if(Test-DreamSkinPendingVerificationOutput @('invalid json')){throw 'Malformed probe accepted'}
$r.readiness.structurePass=$true
$script:probe=@{targets=@(@{result=$r})}|ConvertTo-Json -Depth 8
$loop=$ast.Find({param($n) $n -is [Management.Automation.Language.WhileStatementAst] -and $n.Extent.Text.Contains('$verify = Invoke-DreamSkinNative')},$true)
function Invoke-DreamSkinNative {param($FilePath,$ArgumentList);if($ArgumentList -contains '--once'){throw 'Hidden ordinary startup should not force reapply'};[pscustomobject]@{ExitCode=2;Output=@($script:probe)}}
function Write-DreamSkinUtf8FileAtomically {}
$daemon=[pscustomobject]@{HasExited=$false};$node=@{Path='fixture-node'};$Injector='fixture';$Port=9345
$cdpIdentity=@{BrowserId='fixture'};$themePaths=@{Active='fixture'};$injectorVideoArgs=@();$VerifyPath='fixture'
$ResultToken=$null;$startupPending=$false
. ([scriptblock]::Create($loop.Extent.Text))
if(-not $startupPending){throw 'Actual startup loop did not retain hidden window'}
'PASS: hidden valid payload remains pending; visible failure, wrong revision, missing runtime and invalid probe are rejected'
