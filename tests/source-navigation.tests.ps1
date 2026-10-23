$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
. "$repo/scripts/media.ps1";Initialize-DynamicMedia $repo
. "$repo/scripts/wallpaper-library.ps1"
. "$repo/scripts/skin-manager.ps1"
function Assert($c,$m){if(-not $c){throw $m}}
$root=Join-Path ([IO.Path]::GetTempPath()) ('source-tabs-'+[guid]::NewGuid().ToString('N'))
try{
 $project=Join-Path $root 'renamed collection/nested project';[IO.Directory]::CreateDirectory($project)|Out-Null
 Copy-Item "$repo/docs/images/earth-preview.png" "$project/art.png"
 [IO.File]::WriteAllText("$project/project.json",'{"type":"image","file":"art.png","title":"Engine art"}')
 $state=Join-Path $root 'state'
 $batch=Import-DynamicWallpaperEngine -Roots @((Split-Path $project)) -StateRoot $state
 $items=@(Get-DynamicWallpaperItems $state)
 Assert ($items[0].Sources -contains 'WallpaperEngine') 'Engine origin was not persisted'
 Assert (@(Get-DynamicVisibleWallpapers $items All Local).Count -eq 0) 'Engine item leaked into manual library'
 Assert (@(Get-DynamicVisibleWallpapers $items Image WallpaperEngine).Count -eq 1) 'Engine item missing in engine tab'
 $manual=Import-DynamicWallpaper "$project/art.png" Image $state
 Assert (-not $manual.AlreadyExists -and -not $manual.Item.External -and $manual.Item.MediaPath -ne $items[0].MediaPath) 'Local import must own a separate copy from the Steam reference'
 $items=@(Get-DynamicWallpaperItems $state)
 Assert (@(Get-DynamicVisibleWallpapers $items All Local).Count -eq 1 -and @(Get-DynamicVisibleWallpapers $items All WallpaperEngine).Count -eq 1) 'Explicit manual import did not retain both memberships'
 $single=Import-DynamicWallpaperEngine -Roots @($project) -StateRoot $state
 Assert ($single.Existing -eq 1) 'Directly chosen project folder was not recognized'
 $install=Join-Path $root 'steam/steamapps/common/Renamed Wallpaper App'
 [IO.Directory]::CreateDirectory("$install/projects/myprojects")|Out-Null
 [IO.File]::WriteAllText((Join-Path $root 'steam/steamapps/appmanifest_431960.acf'),'"AppState" { "installdir" "Renamed Wallpaper App" }')
 Assert (@(Get-DynamicWallpaperEngineRoots -SteamRoots @((Join-Path $root 'steam'))) -contains "$install/projects/myprojects".Replace('/','\')) 'Renamed install directory in Steam manifest was ignored'
 'PASS source separation, shared membership, project-folder selection and renamed app discovery'
}finally{if(Test-Path $root){Remove-Item -LiteralPath $root -Recurse -Force}}
