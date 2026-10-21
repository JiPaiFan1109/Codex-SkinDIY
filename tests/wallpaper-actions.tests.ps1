$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../scripts/media.ps1')
Initialize-DynamicMedia -InstallRoot (Join-Path $PSScriptRoot '..')
. (Join-Path $PSScriptRoot '../scripts/wallpaper-library.ps1')
function Assert($Condition,$Message){if(-not $Condition){throw $Message}}
function Reject([scriptblock]$Action){$failed=$false;try{& $Action}catch{$failed=$true};Assert $failed 'Expected protected action to fail'}
if(-not (Get-Command Use-DynamicWallpaper -ErrorAction SilentlyContinue)){throw 'Wallpaper actions are not implemented.'}
$root=Join-Path ([IO.Path]::GetTempPath()) ('wallpaper-actions-'+[guid]::NewGuid().ToString('N'))
try {
  [IO.Directory]::CreateDirectory($root)|Out-Null
  Add-Type -AssemblyName System.Drawing
  $source=Join-Path $root 'source.png';$bitmap=New-Object Drawing.Bitmap 8,8
  try{$bitmap.Save($source,[Drawing.Imaging.ImageFormat]::Png)}finally{$bitmap.Dispose()}
  $image=(Import-DynamicWallpaper $source Image $root).Item
  Assert ($image.Transparency -eq 0) 'Legacy wallpaper should default to opaque'
  $image=Set-DynamicWallpaperTransparency $root $image.Id 35
  Assert ((Get-DynamicWallpaperItem $root $image.Id).Transparency -eq 35) 'Transparency did not persist'
  Reject {Set-DynamicWallpaperTransparency $root $image.Id 101}
  Use-DynamicWallpaper $root $image.Id {}|Out-Null
  $theme=Get-Content (Join-Path $root 'active-theme/theme.json') -Raw|ConvertFrom-Json
  Assert ([Math]::Abs($theme.imageOpacity-0.64) -lt 0.0001) ('Legacy transparency migration failed: '+$theme.imageOpacity)
  foreach($level in @(0,50,100)){
    Set-DynamicWallpaperPreviewLevel $root $image.Id $level|Out-Null
    Use-DynamicWallpaper $root $image.Id {}|Out-Null
    $theme=Get-Content (Join-Path $root 'active-theme/theme.json') -Raw|ConvertFrom-Json
    $expectedOpacity=1-[Math]::Max(0.0,($level-50)/50.0)
    Assert ($theme.imageOpacity -eq $expectedOpacity) 'Preview level opacity mapping failed'
    Assert ($theme.imageShade -eq [Math]::Min(1.0,$level/50.0)) 'Preview level shade mapping failed'
  }
  Assert ((Get-DynamicWallpaperStatus $root).CurrentId -eq $image.Id) 'Transparency broke current wallpaper matching'
  Use-DynamicWallpaper $root $image.Id {}|Out-Null
  Assert ((Get-DynamicWallpaperStatus $root).CurrentId -eq $image.Id) 'Current image not recognized'
  Reject {Remove-DynamicWallpaper $root $image.Id}
  $saved=Save-DynamicCurrentWallpaper $root
  Assert ($saved.AlreadyExists -and $saved.Item.Id -eq $image.Id) 'Saving current image duplicated content'
  $videoSource=Join-Path $root 'sample.mp4';[IO.File]::WriteAllBytes($videoSource,[byte[]]@(1,2,3))
  $original=${function:Convert-DynamicVideo}
  try{
    function Convert-DynamicVideo {param($SourcePath,$TargetPath,$Report);[IO.File]::WriteAllBytes($TargetPath,[byte[]]@(4,5,6))}
    $video=(Import-DynamicWallpaper $videoSource Video $root).Item
  }finally{Set-Item Function:Convert-DynamicVideo $original}
  $script:attempts=0
  Reject {Use-DynamicWallpaper $root $video.Id { $script:attempts++;if($script:attempts -eq 1){throw 'cancelled restart'} }}
  Assert ((Get-DynamicWallpaperStatus $root).CurrentId -eq $image.Id) 'Failure lost previous current marker'
  Use-DynamicWallpaper $root $video.Id {}|Out-Null
  Assert ((Get-DynamicWallpaperStatus $root).CurrentId -eq $video.Id) 'Current video not recognized'
  Reject {Remove-DynamicWallpaper $root $video.Id}
  $saved=Save-DynamicCurrentWallpaper $root
  Assert ($saved.AlreadyExists -and $saved.Item.Id -eq $video.Id) 'Saving prepared video transcodes or duplicates it'
  Set-DreamSkinPaused -Paused $true -StateRoot $root|Out-Null
  Assert ((Get-DynamicWallpaperStatus $root).Paused -and -not (Get-DynamicWallpaperStatus $root).CurrentId) 'Pause retained current marker'
  Reject {Remove-DynamicWallpaper $root $video.Id}
  Set-DreamSkinPaused -Paused $false -StateRoot $root|Out-Null
  $cancelled=Restore-DynamicWallpaperAppearance $root {return $false}
  Assert ($cancelled -eq $false) 'Cancellation was reported as restored'
  Assert ((Get-DynamicWallpaperStatus $root).CurrentId -eq $video.Id) 'Cancellation changed the current wallpaper'
  Assert (Test-Path -LiteralPath $video.MediaPath) 'Cancellation deleted saved media'
  Reject {Restore-DynamicWallpaperAppearance $root {throw 'restore failed'}}
  Reject {Remove-DynamicWallpaper $root $video.Id}
  Restore-DynamicWallpaperAppearance $root {Set-DreamSkinPaused -Paused $true -StateRoot $root|Out-Null}
  Remove-DynamicWallpaper $root $video.Id
  Assert (-not (Test-Path -LiteralPath $video.MediaPath)) 'Restored video could not be deleted'
  Use-DynamicWallpaper $root $image.Id {}|Out-Null
  Assert (-not (Test-Path (Join-Path $root 'video-theme.json'))) 'Image left dynamic mode enabled'
  [IO.File]::WriteAllText((Join-Path $root 'video-theme.json'),'{broken')
  Reject {Remove-DynamicWallpaper $root $image.Id}
  Remove-Item -LiteralPath (Join-Path $root 'video-theme.json')
  [IO.File]::WriteAllBytes($image.MediaPath,[byte[]]@(9,9,9))
  Reject {Use-DynamicWallpaper $root $image.Id {}}
  'PASS: active selection, cancellation rollback, reference protection, restore and current-media deduplication'
}finally{if(Test-Path $root){Remove-Item -LiteralPath $root -Recurse -Force}}
