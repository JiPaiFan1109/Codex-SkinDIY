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
  [IO.File]::WriteAllText((Join-Path $workshop '1/unrelated.dat'),'must not copy')
  $state=Join-Path $root 'state'
  $result=Import-DynamicWallpaperEngine -Roots $roots -StateRoot $state
  Assert ($result.Imported -eq 1 -and $result.Skipped -eq 1 -and $result.Failed -eq 3) 'Mixed batch did not preserve valid imports and report each unsupported/broken project'
  $items=@(Get-DynamicWallpaperItems $state)
  Assert ($items.Count -eq 1 -and $items[0].Name -eq 'Earth') 'Project title or durable import lost'
  Assert (@(Get-ChildItem $state -Recurse -File | Where-Object Name -in @('unrelated.dat','project.json')).Count -eq 0) 'Import copied unrelated project files'
  Assert ((Get-FileHash $items[0].MediaPath).Hash -eq (Get-FileHash (Join-Path $workshop '1/image.png')).Hash) 'Imported image is not a durable media copy'
  $again=Import-DynamicWallpaperEngine -Roots $roots -StateRoot $state
  Assert ($again.Imported -eq 0 -and $again.Existing -eq 1) 'Repeated batch duplicated wallpapers'
  $partial=Import-DynamicWallpaperEngine -Roots @((Join-Path $root 'missing'),$workshop) -StateRoot $state
  Assert ($partial.Existing -eq 1 -and $partial.Failed -eq 4) 'Unavailable root aborted remaining imports'
  $null=Rename-DynamicWallpaper $state $items[0].Id 'My renamed wallpaper'
  $newProject=Join-Path $workshop '6';[IO.Directory]::CreateDirectory($newProject)|Out-Null
  Add-Type -AssemblyName System.Drawing
  $newImage=[Drawing.Bitmap]::new(64,64)
  try{$newImage.SetPixel(0,0,[Drawing.Color]::Blue);$newImage.Save((Join-Path $newProject 'new.png'),[Drawing.Imaging.ImageFormat]::Png)}finally{$newImage.Dispose()}
  [IO.File]::WriteAllText((Join-Path $newProject 'project.json'),'{"title":"New wallpaper","type":"image","file":"new.png"}')
  $refresh=Import-DynamicWallpaperEngine -Roots $roots -StateRoot $state
  Assert ($refresh.Imported -eq 1 -and $refresh.Existing -eq 1 -and @(Get-DynamicWallpaperItems $state).Count -eq 2) 'Refresh must import only newly added wallpaper'
  $repeat=Import-DynamicWallpaperEngine -Roots $roots -StateRoot $state
  Assert ($repeat.Imported -eq 0 -and $repeat.Existing -eq 2 -and @(Get-DynamicWallpaperItems $state).Count -eq 2) 'Repeated refresh duplicated wallpapers'
  Assert ((Get-DynamicWallpaperItem $state $items[0].Id).Name -eq 'My renamed wallpaper') 'Refresh overwrote the user name'
  Assert (-not (Test-Path (Join-Path $state 'active-theme'))) 'Batch import changed active background'
  $external=$items[0]
  Assert ($external.External -and $external.MediaPath -ieq (Join-Path $workshop '1/image.png')) 'Steam import must reference the original file'
  Assert (@(Get-ChildItem (Join-Path $state 'wallpaper-library/items') -Recurse -Filter 'wallpaper.*').Count -eq 0) 'Steam import retained a full media copy'
  Use-DynamicWallpaper $state $external.Id {} | Out-Null
  Assert ((Read-DreamSkinTheme (Join-Path $state 'active-theme')).ImagePath -ieq $external.MediaPath) 'Active image was copied instead of referenced'
  Assert (@(Get-ChildItem (Join-Path $state 'active-theme') -File | Where-Object Extension -in @('.png','.jpg','.webp')).Count -eq 0) 'Active Steam image retained a copy'
  $local=Import-DynamicWallpaper $external.MediaPath Image $state
  Assert (-not $local.Item.External -and $local.Item.Id -ne $external.Id) 'Local import reused a fragile Steam reference'
  Remove-Item -LiteralPath $external.MediaPath
  Assert (@(Get-DynamicWallpaperItems $state | Where-Object Id -eq $external.Id).Count -eq 0) 'Deleted Steam source remains visible'
  Assert ((Get-DynamicWallpaperItem $state $local.Item.Id).IsAvailable) 'Deleting Steam source damaged local copy'
  Assert (Test-DreamSkinExternalSourceMissing $state) 'Missing active Steam source was not detected'
  Assert ((Get-DynamicWallpaperStatus $state).Paused -and -not (Get-DynamicWallpaperStatus $state).Error) 'Missing source produced a broken current background status'
  'PASS: multi-library discovery, mixed batch, unsafe paths, missing media, deduplication and import isolation'
}finally{
  if([IO.Path]::GetFullPath($root).StartsWith([IO.Path]::GetTempPath(),[StringComparison]::OrdinalIgnoreCase) -and (Test-Path $root)){Remove-Item -LiteralPath $root -Recurse -Force}
}
