$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'engine/scripts/start-dream-skin.ps1'),[ref]$tokens,[ref]$errors)
if($errors){throw 'Startup parse failed'}
$branch=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.IfStatementAst] -and $n.Clauses[0].Item1.Extent.Text -eq '$null -ne $fastState' -and $n.Extent.Text -match 'fastVerify'},$true))
if($branch.Count -ne 1){throw 'Expected one fast apply branch'}
function Get-DreamSkinVerifiedCdpIdentity { [pscustomobject]@{BrowserId='test-browser'} }
function Get-DreamSkinFastResumeCandidate {if(-not $script:watcherStopped){return $fastState}}
function Invoke-DreamSkinNative {param($FilePath,$ArgumentList);$script:observed=@($ArgumentList);[pscustomobject]@{ExitCode=0;Output=@('{}')} }
function Write-DreamSkinUtf8FileAtomically {}
function Write-DreamSkinStartResult {param($StateRoot,$Token,$Outcome,$Category,$AppearanceRecovery);$script:result=$Outcome}
$fastState=[pscustomobject]@{port=9345;browserId='test-browser';themeDir='C:\Skin\active-theme';videoPid=$null;videoReadyPath=$null}
$node=[pscustomobject]@{Path='node.exe'};$Injector='injector.mjs';$StateRoot='C:\Skin';$currentCodex=@{};$startupTimer=[Diagnostics.Stopwatch]::StartNew()
foreach($apply in @($false,$true)){
  $ResultToken=if($apply){'123'}else{$null};$script:result=$null
  & ([scriptblock]::Create($branch[0].Extent.Text.Replace('exit 0','return')))
  if($script:observed -contains '--video-state'){throw 'Static fast path passed an empty video state'}
  if($apply -and ($script:observed -notcontains '--once' -or $script:result -ne 'success')){throw 'Fast apply must install the revision and report success'}
  if(-not $apply -and $script:observed -notcontains '--verify'){throw 'Open must verify the current revision'}
}
$script:watcherStopped=$true;$ResultToken='123';$script:result=$null
& ([scriptblock]::Create($branch[0].Extent.Text.Replace('exit 0','return')))
if($script:result -eq 'success'){throw 'Exited watcher must fall back instead of reporting success'}
'PASS actual fast apply installs and reports success; static open verifies without a video argument'
