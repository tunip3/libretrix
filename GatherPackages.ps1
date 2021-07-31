$selectedConfig = "Debug"
$targetVersion = "0.1.0"
$generatedPackagesDir = "GeneratedPackages"

Get-ChildItem -Path $generatedPackagesDir | Remove-Item
Get-ChildItem -Recurse -File -Include "*$targetVersion.nupkg" | Where-Object { $_.FullName -like "*$selectedConfig*" } | Copy-Item -Destination $generatedPackagesDir -Force
$nugetPath = Join-Path $env:USERPROFILE ".nuget"
$nugetPath = Join-Path $nugetPath "packages"
$folders = Get-ChildItem -Path $nugetPath -Filter "libretrix*" -Directory
foreach($i in $folders) {
    $target = Get-ChildItem -Path $i.FullName -Filter "*$targetVersion*" -Directory
    if($target -ne $null) {
        Remove-Item $target.FullName -Recurse -Force
    }  
}