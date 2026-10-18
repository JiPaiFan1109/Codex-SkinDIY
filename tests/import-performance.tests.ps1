$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
. "$repo/scripts/media.ps1";Initialize-DynamicMedia $repo
. "$repo/scripts/wallpaper-library.ps1"
function Assert($c,$m){if(-not $c){throw $m}}
$root=Join-Path ([IO.Path]::GetTempPath()) ('fast-import-'+[guid]::NewGuid().ToString('N'))
try{
 $source=Join-Path $repo 'docs/media/earth-demo.mp4'
 $hash=(Get-FileHash $source).Hash
 $timer=[Diagnostics.Stopwatch]::StartNew()
 $first=Import-DynamicWallpaper $source Video $root
 $timer.Stop();$firstMs=$timer.ElapsedMilliseconds
 Assert ((Get-FileHash $first.Item.MediaPath).Hash -eq $hash) 'Compatible MP4 was unnecessarily transcoded'
 $original=${function:New-DynamicPreparedMedia}
 function New-DynamicPreparedMedia {throw 'Duplicate import reached expensive media preparation'}
 try{$timer.Restart();$second=Import-DynamicWallpaper $source Video $root;$timer.Stop()}finally{Set-Item Function:New-DynamicPreparedMedia $original}
 Assert ($second.AlreadyExists -and $second.Item.Id -eq $first.Item.Id) 'Early duplicate check failed'
 "PASS: lossless compatible MP4 import ${firstMs}ms, duplicate $($timer.ElapsedMilliseconds)ms"
}finally{if([IO.Path]::GetFullPath($root).StartsWith([IO.Path]::GetTempPath(),[StringComparison]::OrdinalIgnoreCase) -and (Test-Path $root)){Remove-Item -LiteralPath $root -Recurse -Force}}
