$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
. "$repo/scripts/media.ps1";Initialize-DynamicMedia $repo
. "$repo/scripts/wallpaper-library.ps1"
function Assert($c,$m){if(-not $c){throw $m}}
if(-not(Get-Command Switch-DynamicWallpaperOrder -ErrorAction SilentlyContinue)){throw 'Persistent wallpaper swapping is missing'}
$root=Join-Path ([IO.Path]::GetTempPath()) ('wallpaper-order-'+[guid]::NewGuid().ToString('N'))
try{
 Add-Type -AssemblyName System.Drawing
 [IO.Directory]::CreateDirectory($root)|Out-Null
 foreach($n in 1..3){$file=Join-Path $root "$n.png";$b=New-Object Drawing.Bitmap (8+$n),8;try{$b.Save($file,[Drawing.Imaging.ImageFormat]::Png)}finally{$b.Dispose()};Import-DynamicWallpaper $file Image $root|Out-Null}
 $before=@(Get-DynamicWallpaperItems $root);$a=$before[0].Id;$b=$before[2].Id
 Switch-DynamicWallpaperOrder $root $a $b
 $after=@(Get-DynamicWallpaperItems $root)
 Assert ($after[0].Id -eq $b -and $after[2].Id -eq $a -and $after[1].Id -eq $before[1].Id) 'Swap did not exchange only the two target positions'
 $again=@(Get-DynamicWallpaperItems $root)
 Assert ($again[0].Id -eq $b) 'Order did not persist across a fresh read'
 $failed=$false;try{Switch-DynamicWallpaperOrder $root $a ('0'*32)}catch{$failed=$true}
 Assert $failed 'Missing target accepted'
 Assert (@(Get-DynamicWallpaperItems $root)[0].Id -eq $b) 'Rejected swap changed order'
 Switch-DynamicWallpaperOrder $root $a $a
 Assert (@(Get-DynamicWallpaperItems $root).Count -eq 3) 'Self swap lost items'
 'PASS persistent pair swap, untouched intermediate card, invalid target and self drop'
}finally{if(Test-Path $root){Remove-Item -LiteralPath $root -Recurse -Force}}
