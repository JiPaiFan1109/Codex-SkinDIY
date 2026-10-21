$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
. (Join-Path $repo 'engine/scripts/common-windows.ps1')
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'engine/scripts/start-dream-skin.ps1'),[ref]$tokens,[ref]$errors)
if($errors){throw 'Startup parse failed'}
$root=Join-Path ([IO.Path]::GetTempPath()) ('skin-cancel-'+[guid]::NewGuid().ToString('N'))
try{
  New-Item $root -ItemType Directory|Out-Null
  function Get-DreamSkinText {param($Key,$Language);return $Key}
  foreach($condition in @('$coexistenceAction -ceq ''cancel''','-not $restartAuthorized')){
    $branch=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.IfStatementAst] -and $n.Clauses[0].Item1.Extent.Text -eq $condition -and $n.Extent.Text -match '\bexit\s+0'},$true))
    if($branch.Count -ne 1){throw "Expected one cancellation branch: $condition"}
    $StateRoot=$root;$ResultToken=[guid]::NewGuid().ToString('N');$coexistenceAction='cancel';$restartAuthorized=$false;$language='en'
    # Run only the actual cancellation branch; return in place of process exit keeps assertions alive.
    & ([scriptblock]::Create($branch[0].Extent.Text.Replace('exit 0','return')))
    $result=Read-DreamSkinStartResult -StateRoot $root -Token $ResultToken
    if($result.outcome -ne 'failure' -or $result.category -ne 'cancelled'){throw 'Cancellation must return a bounded cancelled result'}
  }
  'PASS both real startup cancellation branches emit cancelled results'
}finally{if(Test-Path $root){Remove-Item -LiteralPath $root -Recurse -Force}}
