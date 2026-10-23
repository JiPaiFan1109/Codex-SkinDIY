$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $repo 'scripts/media.ps1');Initialize-DynamicMedia $repo
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('steam-startup-'+[guid]::NewGuid().ToString('N'))
try{
  [void][IO.Directory]::CreateDirectory((Join-Path $fixture 'active-theme'))
  $tokens=$null;$errors=$null
  $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'engine/scripts/start-dream-skin.ps1'),[ref]$tokens,[ref]$errors)
  $guard=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.IfStatementAst] -and $n.Clauses[0].Item1.Extent.Text -eq 'Test-DreamSkinExternalSourceMissing -StateRoot $StateRoot'},$true))[0]
  if(-not $guard){throw 'Startup must check external source before starting the engine'}
  $script:opened=0;$script:results=0
  function Get-DreamSkinCodexInstall {return @{Executable='fixture'}}
  function Start-DreamSkinCodex {param($Codex);$script:opened++}
  function Write-DreamSkinStartResult {param($StateRoot,$Token,$Outcome,$Category,$AppearanceRecovery);if($Outcome -ne 'success' -or $AppearanceRecovery -ne 'restored'){throw 'Missing source must restore appearance'};$script:results++}
  $StateRoot=$fixture;$ResultToken='a'*32
  foreach($kind in @('Image','Video')){
    @{schemaVersion=1;image='external-image';externalSource=@{kind=$kind;path=(Join-Path $fixture 'deleted-media');size=10;sha256=('a'*64)}}|ConvertTo-Json|Set-Content (Join-Path $fixture 'active-theme/theme.json') -Encoding UTF8
    & ([scriptblock]::Create($guard.Extent.Text.Replace('exit 0','return')))
    if(-not (Test-DreamSkinPaused $fixture)){throw 'Invalid source did not disable wallpaper restoration'}
  }
  if($script:opened -ne 2 -or $script:results -ne 2){throw 'Missing source did not use normal Codex launch'}
  'PASS deleted image/video opens native Codex appearance before engine startup'
}finally{
  if([IO.Path]::GetFullPath($fixture).StartsWith([IO.Path]::GetTempPath(),[StringComparison]::OrdinalIgnoreCase)){Remove-Item -LiteralPath $fixture -Recurse -Force}
}
