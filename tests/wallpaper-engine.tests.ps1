$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../scripts/media.ps1')
Initialize-DynamicMedia -InstallRoot (Join-Path $PSScriptRoot '..')
. (Join-Path $PSScriptRoot '../scripts/wallpaper-library.ps1')
function Assert($Condition,$Message){if(-not $Condition){throw $Message}}
Assert ([bool](Get-Command Import-DynamicWallpaperEngine -ErrorAction SilentlyContinue)) 'Wallpaper Engine batch import is missing'
$root=Join-Path ([IO.Path]::GetTempPath()) ('we-import-'+[guid]::NewGuid().ToString('N'))
try {
  $steam=Join-Path $root 'Steam';$other=Join-Path $root 'SecondLibrary'
  [IO.Directory]::CreateDirectory((Join-Path $steam 'steamapps'))|Out-Null
  [IO.File]::WriteAllText((Join-Path $steam 'steamapps/libraryfolders.vdf'),('"libraryfolders" { "1" { "path" "'+$other.Replace('\','\\')+'" } }'))
  $workshop=Join-Path $other 'steamapps/workshop/content/431960'
  foreach($id in @('1','2','3','4','5')){[IO.Directory]::CreateDirectory((Join-Path $workshop $id))|Out-Null}
  Copy-Item (Join-Path $PSScriptRoot '../docs/images/earth-preview.png') (Join-Path $workshop '1/image.png')
  [IO.File]::WriteAllText((Join-Path $workshop '1/project.json'),'{"title":"Earth","type":"image","file":"image.png"}')
  [IO.File]::WriteAllText((Join-Path $workshop '2/project.json'),'{"title":"Scene","type":"scene","file":"scene.pkg"}')
  [IO.File]::WriteAllText((Join-Path $workshop '3/project.json'),'{"type":"image","file":"../../outside.png"}')
  [IO.File]::WriteAllText((Join-Path $workshop '4/project.json'),'{bad')
  [IO.File]::WriteAllText((Join-Path $workshop '5/project.json'),'{"type":"video","file":"missing.mp4"}')
  $roots=@(Get-DynamicWallpaperEngineRoots -SteamRoots @($steam,$steam.ToUpperInvariant()))
  Assert ($roots.Count -eq 1) 'Case variants duplicated a Steam library'
  Assert ($roots -contains $workshop) 'Secondary Steam library was not discovered'
  $state=Join-Path $root 'state'
  $result=Import-DynamicWallpaperEngine -Roots $roots -StateRoot $state
  Assert ($result.Imported -eq 1 -and $result.Skipped -eq 1 -and $result.Failed -eq 3) 'Mixed batch did not preserve valid imports and report each unsupported/broken project'
  $items=@(Get-DynamicWallpaperItems $state)
  Assert ($items.Count -eq 1 -and $items[0].Name -eq 'Earth') 'Project title or durable import lost'
  $again=Import-DynamicWallpaperEngine -Roots $roots -StateRoot $state
  Assert ($again.Imported -eq 0 -and $again.Existing -eq 1) 'Repeated batch duplicated wallpapers'
  Assert (-not (Test-Path (Join-Path $state 'active-theme'))) 'Batch import changed active background'
  'PASS: multi-library discovery, mixed batch, unsafe paths, missing media, deduplication and import isolation'
}finally{
  if([IO.Path]::GetFullPath($root).StartsWith([IO.Path]::GetTempPath(),[StringComparison]::OrdinalIgnoreCase) -and (Test-Path $root)){Remove-Item -LiteralPath $root -Recurse -Force}
}
