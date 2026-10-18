# Local media only: scene/web/application projects are never executed.
function Get-DynamicWallpaperEngineRoots {
  param([string[]]$SteamRoots)
  if(-not $SteamRoots){
    $SteamRoots=@(foreach($key in @('HKCU:\Software\Valve\Steam','HKLM:\SOFTWARE\WOW6432Node\Valve\Steam')){
      $entry=Get-ItemProperty $key -ErrorAction SilentlyContinue
      if($entry.SteamPath){$entry.SteamPath};if($entry.InstallPath){$entry.InstallPath}
    })+@("${env:ProgramFiles(x86)}\Steam","$env:ProgramFiles\Steam")
  }
  $libraries=@($SteamRoots)
  foreach($steam in $SteamRoots){
    $vdf=Join-Path $steam 'steamapps/libraryfolders.vdf'
    if(Test-Path -LiteralPath $vdf -PathType Leaf){
      foreach($match in [regex]::Matches([IO.File]::ReadAllText($vdf),'"path"\s*"([^"\r\n]+)"')){$libraries+=$match.Groups[1].Value.Replace('\\','\')}
    }
  }
  @(foreach($library in $libraries|Sort-Object -Unique){
    $manifest=Join-Path $library 'steamapps/appmanifest_431960.acf'
    if(Test-Path -LiteralPath $manifest){
      $match=[regex]::Match([IO.File]::ReadAllText($manifest),'"installdir"\s*"([^"\r\n]+)"')
      if($match.Success -and $match.Groups[1].Value -notmatch '[/\\:]|^\.\.?$'){
        foreach($suffix in @('myprojects','defaultprojects')){
          $custom=Join-Path $library ('steamapps/common/'+$match.Groups[1].Value+'/projects/'+$suffix)
          if(Test-Path -LiteralPath $custom -PathType Container){[IO.Path]::GetFullPath($custom)}
        }
      }
    }
    foreach($relative in @('steamapps/workshop/content/431960','steamapps/common/wallpaper_engine/projects/myprojects','steamapps/common/wallpaper_engine/projects/defaultprojects')){
      $path=Join-Path $library $relative
      if(Test-Path -LiteralPath $path -PathType Container){[IO.Path]::GetFullPath($path)}
    }
  })|Sort-Object -Unique
}
function Get-DynamicWallpaperEngineProjects {
  param([string]$Root,[int]$Depth=0)
  Assert-DreamSkinNoReparseComponents -Path $Root
  if(Test-Path -LiteralPath (Join-Path $Root 'project.json') -PathType Leaf){Get-Item -LiteralPath $Root;return}
  if($Depth -ge 5){return}
  foreach($child in Get-ChildItem -LiteralPath $Root -Directory -ErrorAction Stop){
    if(($child.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){continue}
    Get-DynamicWallpaperEngineProjects $child.FullName ($Depth+1)
  }
}
function Import-DynamicWallpaperEngine {
  param([string[]]$Roots,[string]$StateRoot,[scriptblock]$Report)
  if(-not $Roots){$Roots=@(Get-DynamicWallpaperEngineRoots)}
  $result=[pscustomobject]@{Imported=0;Existing=0;Skipped=0;Failed=0;Details=@();SelectedId=$null;Roots=@($Roots)}
  $visited=@{}
  foreach($root in $Roots|Sort-Object -Unique){
    Assert-DreamSkinNoReparseComponents -Path $root
    foreach($directory in Get-DynamicWallpaperEngineProjects $root){
      if($visited.ContainsKey($directory.FullName)){continue};$visited[$directory.FullName]=$true
      $label=$directory.Name
      try{
        Assert-DreamSkinNoReparseComponents -Path $directory.FullName
        $metadata=Join-Path $directory.FullName 'project.json'
        if(-not (Test-Path -LiteralPath $metadata -PathType Leaf)){continue}
        Assert-DreamSkinNoReparseComponents -Path $metadata
        if((Get-Item -LiteralPath $metadata).Length -gt 1MB){throw '项目描述文件过大。'}
        $project=[IO.File]::ReadAllText($metadata)|ConvertFrom-Json -ErrorAction Stop
        if($project.title){$label=[string]$project.title}
        if([string]$project.type -notin @('video','image')){
          $result.Skipped++;$result.Details+=($label+'：不支持 '+$project.type+' 类型，需要 Wallpaper Engine 渲染。');continue
        }
        $relative=[string]$project.file
        if(-not $relative -or [IO.Path]::IsPathRooted($relative) -or $relative.Contains(':')){throw '媒体路径无效。'}
        $media=[IO.Path]::GetFullPath((Join-Path $directory.FullName $relative))
        if(-not $media.StartsWith($directory.FullName+'\',[StringComparison]::OrdinalIgnoreCase)){throw '媒体路径越出项目目录。'}
        Assert-DreamSkinNoReparseComponents -Path $media
        if(-not (Test-Path -LiteralPath $media -PathType Leaf)){throw '项目媒体文件不存在。'}
        $kind='Image';if($project.type -eq 'video'){$kind='Video'}
        if($Report){& $Report ('正在导入：'+$label)}
        $import=Import-DynamicWallpaper -SourcePath $media -Kind $kind -StateRoot $StateRoot -Report $Report -Source WallpaperEngine
        $result.SelectedId=$import.Item.Id
        if($import.AlreadyExists){$result.Existing++}else{
          $result.Imported++
          try{$null=Rename-DynamicWallpaper $StateRoot $import.Item.Id $label}catch{}
        }
      }catch{$result.Failed++;$result.Details+=($label+'：'+$_.Exception.Message)}
    }
  }
  return $result
}
