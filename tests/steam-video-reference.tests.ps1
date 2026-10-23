$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $repo 'scripts/media.ps1');Initialize-DynamicMedia $repo
. (Join-Path $repo 'scripts/wallpaper-library.ps1')
. (Join-Path $repo 'engine/scripts/video-windows.ps1')
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('steam-video-'+[guid]::NewGuid().ToString('N'))
function Assert($Condition,$Message){if(-not $Condition){throw $Message}}
try{
  [void][IO.Directory]::CreateDirectory($fixture)
  $source=Join-Path $fixture 'steam.mp4'
  Copy-Item (Join-Path $repo 'docs/media/earth-demo.mp4') $source
  $state=Join-Path $fixture 'app'
  $item=(Import-DynamicSteamReference $source Video $state 'Steam video').Item
  Assert ($item.External -and $item.MediaPath -ieq $source) 'Video must reference Steam source'
  Use-DynamicWallpaper $state $item.Id {}|Out-Null
  $config=Read-DreamSkinVideoConfig (Join-Path $state 'video-theme.json')
  Assert ($config.filePath -ieq $source) 'Video playback did not use original source'
  Assert (@(Get-ChildItem $state -Recurse -Filter '*.mp4').Count -eq 0) 'Steam video retained a full copy'
  Remove-Item -LiteralPath $source
  Assert (@(Get-DynamicWallpaperItems $state).Count -eq 0) 'Deleted video remains visible'
  Assert (Test-DreamSkinExternalSourceMissing $state) 'Deleted active video was not detected'
  $bad=Join-Path $fixture 'unsupported.mkv';[IO.File]::WriteAllText($bad,'not a video')
  $rejected=$false;try{Import-DynamicSteamReference $bad Video $state 'Unsupported'|Out-Null}catch{$rejected=$true}
  Assert $rejected 'Unsupported video must not silently create a transcoded copy'
  $image=Join-Path $repo 'docs/images/earth-preview.png'
  $legacyState=Join-Path $fixture 'legacy'
  $legacy=(Import-DynamicWallpaper $image Image $legacyState -Source WallpaperEngine).Item
  $migrated=(Import-DynamicSteamReference $image Image $legacyState 'Legacy').Item
  Assert ($migrated.Id -eq $legacy.Id -and $migrated.External) 'Legacy Steam-only record did not migrate in place'
  Assert (-not (Test-Path -LiteralPath $legacy.MediaPath)) 'Verified legacy duplicate was not removed'
  Assert (Test-Path -LiteralPath $image) 'Migration deleted original Steam media'
  Remove-DynamicWallpaper $legacyState $migrated.Id
  Assert (Test-Path -LiteralPath $image) 'Removing reference deleted original media'
  $sharedState=Join-Path $fixture 'shared'
  $shared=(Import-DynamicWallpaper $image Image $sharedState -Source WallpaperEngine).Item
  $null=Add-DynamicWallpaperSource $sharedState $shared.Id Local
  $reference=(Import-DynamicSteamReference $image Image $sharedState 'Shared').Item
  $kept=Get-DynamicWallpaperItem $sharedState $shared.Id
  Assert ($reference.External -and $reference.Id -ne $shared.Id -and $kept.IsAvailable -and $kept.Sources.Count -eq 1 -and $kept.Sources[0] -eq 'Local') 'Shared legacy copy must remain local alongside the Steam reference'
  'PASS direct video, missing source, unsupported format, legacy migration and source-safe removal'
}finally{
  if([IO.Path]::GetFullPath($fixture).StartsWith([IO.Path]::GetTempPath(),[StringComparison]::OrdinalIgnoreCase)){Remove-Item -LiteralPath $fixture -Recurse -Force}
}
