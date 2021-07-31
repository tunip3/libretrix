[string]$AppveyorApiUri = "https://ci.appveyor.com/api"
[string]$BuildBotUri = "https://buildbot.libretro.com/nightly"

class CoreInfo {
    [bool]$Skip

    [string]$Name

    [string]$AppveyorUri

    [string]$BuildbotUri_Win32_x86
    [string]$BuildbotUri_Win32_x64
    [string]$BuildbotUri_macOS_x86
    [string]$BuildbotUri_macOS_x64
    [string]$BuildbotUri_iOS
    [string]$BuildbotUri_Android_x86
    [string]$BuildbotUri_Android_x64
    [string]$BuildbotUri_Android_arm
    [string]$BuildbotUri_Android_armv7a
    [string]$BuildbotUri_Android_armv8a
}

function MakeDirectory([string]$Path) {
    if(!(Test-Path -Path $Path )){
        New-Item -ItemType directory -Path $Path
    }
}

function DownloadAndExtratTo([string]$Uri, [string]$DestDirectory) {
    MakeDirectory -Path $DestDirectory
    $zipPath = Join-Path $DestDirectory -ChildPath "temp.zip";

    $client = new-object System.Net.WebClient
    $client.DownloadFile($Uri,$zipPath)
    Expand-Archive $zipPath -DestinationPath $DestDirectory -Force

    Remove-Item $zipPath
}

function RenameTarget([string]$Folder, [string]$Extension, [string]$NewName) {
    $existingFilePath = Join-Path -Path $Folder -ChildPath ("{0}{1}" -f $NewName,$Extension)
    if(Test-Path -Path $existingFilePath) {
        Remove-Item -Path $existingFilePath
    }

    $extString = "*" + $Extension
    $target = Get-ChildItem -Path $Folder -File -Filter $extString | Select-Object -First 1
    $destName = $NewName + $Extension
    Rename-Item -Path $target.FullName -NewName $destName
}

function DownloadCoreTarget([CoreInfo]$Core, [string]$DestFolder, [string]$ArchMoniker, [string]$DownloadUri, [string]$TargetExtension) {
    Write-Output ("Downloading {0} from {1}" -f $ArchMoniker,$DownloadUri)

    $targetFolder = Join-Path -Path $DestFolder -ChildPath $ArchMoniker
    MakeDirectory -Path $targetFolder

    DownloadAndExtratTo -Uri $DownloadUri -DestDirectory $targetFolder
    RenameTarget -Folder $targetFolder -Extension $TargetExtension -NewName $Core.Name
}

function DownloadJobArtifact([CoreInfo]$Core, $Jobs, [string]$DestFolder, [string]$PlatformMoniker, [string]$DestPlatformMoniker, [string]$TargetExtension) {
    $targetJob =  $Jobs | Where-Object {$_.name -like "*$PlatformMoniker*"}
    $jobId = $targetJob.jobId
    $artifacts = Invoke-RestMethod -Method Get -Uri "$AppveyorApiUri/buildjobs/$jobId/artifacts"
    $artifacts = $artifacts | Where-Object {$_.fileName -like "*$TargetExtension"} | Sort-Object { $_.fileName.length } 
    $targetArtifact = $artifacts | Select-Object -Index 0

    if($targetArtifact -eq $null) {
        Write-Output "No artifact found for $PlatformMoniker"
        return;
    }

    $targetFolder = Join-Path $DestFolder -ChildPath $DestPlatformMoniker
    MakeDirectory -Path $targetFolder
    $targetPath = Join-Path $targetFolder -ChildPath "temp.dll"

    $artifactFileName = $targetArtifact.fileName
    $downloadUri="$AppveyorApiUri/buildjobs/$jobId/artifacts/$artifactFileName"
    Write-Output ("Downloading {0} from {1}" -f $DestPlatformMoniker,$downloadUri)
    try {
        Invoke-WebRequest -Method Get -Uri $downloadUri -OutFile $targetPath -UseBasicParsing
        RenameTarget -Folder $targetFolder -Extension $TargetExtension -NewName $Core.Name
    }
    catch {
        Remove-Item $targetPath -Force
    } 
}

function DownloadCoreAppveyorArtifacts([CoreInfo]$Core, [string]$DestFolder) {
    $project = Invoke-RestMethod -Method Get -Uri $Core.AppveyorUri
    $jobs = $project.build.jobs

    DownloadJobArtifact -Core $Core -Jobs $jobs -DestFolder $DestFolder -PlatformMoniker "uwp_x86" -DestPlatformMoniker "uap-x86" -TargetExtension ".dll"
    DownloadJobArtifact -Core $Core -Jobs $jobs -DestFolder $DestFolder -PlatformMoniker "uwp_x64" -DestPlatformMoniker "uap-x64" -TargetExtension ".dll"
    DownloadJobArtifact -Core $Core -Jobs $jobs -DestFolder $DestFolder -PlatformMoniker "uwp_arm" -DestPlatformMoniker "uap-arm" -TargetExtension ".dll"
}

function DownloadCore([CoreInfo]$Core, [string]$RootFolder) {
    Write-Output ("Processing {0}" -f $Core.Name)

    $coreRoot = Join-Path -Path $RootFolder -ChildPath ("LibRetriX.{0}" -f $Core.Name)
    $coreRoot = Join-Path -Path $coreRoot -ChildPath "Native"
    MakeDirectory -Path $coreRoot

    DownloadCoreAppveyorArtifacts -Core $Core -DestFolder $coreRoot
    DownloadCoreTarget -Core $Core -DestFolder $coreRoot -ArchMoniker "win-x86" -DownloadUri $Core.BuildbotUri_Win32_x86 -TargetExtension ".dll"
    DownloadCoreTarget -Core $Core -DestFolder $coreRoot -ArchMoniker "win-x64" -DownloadUri $Core.BuildbotUri_Win32_x64 -TargetExtension ".dll"
    DownloadCoreTarget -Core $Core -DestFolder $coreRoot -ArchMoniker "osx-x86" -DownloadUri $Core.BuildbotUri_macOS_x86 -TargetExtension ".dylib"
    DownloadCoreTarget -Core $Core -DestFolder $coreRoot -ArchMoniker "osx-x64" -DownloadUri $Core.BuildbotUri_macOS_x64 -TargetExtension ".dylib"
    DownloadCoreTarget -Core $Core -DestFolder $coreRoot -ArchMoniker "ios" -DownloadUri $Core.BuildbotUri_iOS -TargetExtension ".dylib"
    DownloadCoreTarget -Core $Core -DestFolder $coreRoot -ArchMoniker "android-x86" -DownloadUri $Core.BuildbotUri_Android_x86 -TargetExtension ".so"
    DownloadCoreTarget -Core $Core -DestFolder $coreRoot -ArchMoniker "android-x64" -DownloadUri $Core.BuildbotUri_Android_x64 -TargetExtension ".so"
    DownloadCoreTarget -Core $Core -DestFolder $coreRoot -ArchMoniker "android-arm" -DownloadUri $Core.BuildbotUri_Android_arm -TargetExtension ".so"
    DownloadCoreTarget -Core $Core -DestFolder $coreRoot -ArchMoniker "android-armv7a" -DownloadUri $Core.BuildbotUri_Android_armv7a -TargetExtension ".so"
    DownloadCoreTarget -Core $Core -DestFolder $coreRoot -ArchMoniker "android-armv8a" -DownloadUri $Core.BuildbotUri_Android_armv8a -TargetExtension ".so"
}

[CoreInfo[]]$cores = (
    [CoreInfo]@{
        Skip = $true
        Name = "BeetleNGP"
        AppveyorUri = "$AppveyorApiUri/projects/bparker06/beetle-ngp-libretro"
        BuildbotUri_Win32_x86 = "$BuildBotUri/windows/x86/latest/mednafen_ngp_libretro.dll.zip"
        BuildbotUri_Win32_x64 = "$BuildBotUri/windows/x86_64/latest/mednafen_ngp_libretro.dll.zip"
        BuildbotUri_macOS_x86 = "$BuildBotUri/apple/osx/x86/latest/mednafen_ngp_libretro.dylib.zip"
        BuildbotUri_macOS_x64 = "$BuildBotUri/apple/osx/x86_64/latest/mednafen_ngp_libretro.dylib.zip"
        BuildbotUri_iOS = "$BuildBotUri/apple/ios/latest/mednafen_ngp_libretro_ios.dylib.zip"
        BuildbotUri_Android_x86 = "$BuildBotUri/android/latest/x86/mednafen_ngp_libretro_android.so.zip"
        BuildbotUri_Android_x64 = "$BuildBotUri/android/latest/x86_64/mednafen_ngp_libretro_android.so.zip"
        BuildbotUri_Android_arm = "$BuildBotUri/android/latest/armeabi/mednafen_ngp_libretro_android.so.zip"
        BuildbotUri_Android_armv7a = "$BuildBotUri/android/latest/armeabi-v7a/mednafen_ngp_libretro_android.so.zip"
        BuildbotUri_Android_armv8a = "$BuildBotUri/android/latest/arm64-v8a/mednafen_ngp_libretro_android.so.zip"
    },
    [CoreInfo]@{
        Skip = $true
        Name = "BeetlePCEFast"
        AppveyorUri = "$AppveyorApiUri/projects/bparker06/beetle-pce-fast-libretro"
        BuildbotUri_Win32_x86 = "$BuildBotUri/windows/x86/latest/mednafen_pce_fast_libretro.dll.zip"
        BuildbotUri_Win32_x64 = "$BuildBotUri/windows/x86_64/latest/mednafen_pce_fast_libretro.dll.zip"
        BuildbotUri_macOS_x86 = "$BuildBotUri/apple/osx/x86/latest/mednafen_pce_fast_libretro.dylib.zip"
        BuildbotUri_macOS_x64 = "$BuildBotUri/apple/osx/x86_64/latest/mednafen_pce_fast_libretro.dylib.zip"
        BuildbotUri_iOS = "$BuildBotUri/apple/ios/latest/mednafen_pce_fast_libretro_ios.dylib.zip"
        BuildbotUri_Android_x86 = "$BuildBotUri/android/latest/x86/mednafen_pce_fast_libretro_android.so.zip"
        BuildbotUri_Android_x64 = "$BuildBotUri/android/latest/x86_64/mednafen_pce_fast_libretro_android.so.zip"
        BuildbotUri_Android_arm = "$BuildBotUri/android/latest/armeabi/mednafen_pce_fast_libretro_android.so.zip"
        BuildbotUri_Android_armv7a = "$BuildBotUri/android/latest/armeabi-v7a/mednafen_pce_fast_libretro_android.so.zip"
        BuildbotUri_Android_armv8a = "$BuildBotUri/android/latest/arm64-v8a/mednafen_pce_fast_libretro_android.so.zip"
    },
    [CoreInfo]@{
        Skip = $true
        Name = "BeetlePCFX"
        AppveyorUri = "$AppveyorApiUri/projects/bparker06/beetle-pcfx-libretro"
        BuildbotUri_Win32_x86 = "$BuildBotUri/windows/x86/latest/mednafen_pcfx_libretro.dll.zip"
        BuildbotUri_Win32_x64 = "$BuildBotUri/windows/x86_64/latest/mednafen_pcfx_libretro.dll.zip"
        BuildbotUri_macOS_x86 = "$BuildBotUri/apple/osx/x86/latest/mednafen_pcfx_libretro.dylib.zip"
        BuildbotUri_macOS_x64 = "$BuildBotUri/apple/osx/x86_64/latest/mednafen_pcfx_libretro.dylib.zip"
        BuildbotUri_iOS = "$BuildBotUri/apple/ios/latest/mednafen_pcfx_libretro_ios.dylib.zip"
        BuildbotUri_Android_x86 = "$BuildBotUri/android/latest/x86/mednafen_pcfx_libretro_android.so.zip"
        BuildbotUri_Android_x64 = "$BuildBotUri/android/latest/x86_64/mednafen_pcfx_libretro_android.so.zip"
        BuildbotUri_Android_arm = "$BuildBotUri/android/latest/armeabi/mednafen_pcfx_libretro_android.so.zip"
        BuildbotUri_Android_armv7a = "$BuildBotUri/android/latest/armeabi-v7a/mednafen_pcfx_libretro_android.so.zip"
        BuildbotUri_Android_armv8a = "$BuildBotUri/android/latest/arm64-v8a/mednafen_pcfx_libretro_android.so.zip"
    },
    [CoreInfo]@{
        Skip = $true
        Name = "BeetlePSX"
        AppveyorUri = "$AppveyorApiUri/projects/bparker06/beetle-psx-libretro"
        BuildbotUri_Win32_x86 = "$BuildBotUri/windows/x86/latest/mednafen_psx_libretro.dll.zip"
        BuildbotUri_Win32_x64 = "$BuildBotUri/windows/x86_64/latest/mednafen_psx_libretro.dll.zip"
        BuildbotUri_macOS_x86 = "$BuildBotUri/apple/osx/x86/latest/mednafen_psx_libretro.dylib.zip"
        BuildbotUri_macOS_x64 = "$BuildBotUri/apple/osx/x86_64/latest/mednafen_psx_libretro.dylib.zip"
        BuildbotUri_iOS = "$BuildBotUri/apple/ios/latest/mednafen_psx_libretro_ios.dylib.zip"
        BuildbotUri_Android_x86 = "$BuildBotUri/android/latest/x86/mednafen_psx_libretro_android.so.zip"
        BuildbotUri_Android_x64 = "$BuildBotUri/android/latest/x86_64/mednafen_psx_libretro_android.so.zip"
        BuildbotUri_Android_arm = "$BuildBotUri/android/latest/armeabi/mednafen_psx_libretro_android.so.zip"
        BuildbotUri_Android_armv7a = "$BuildBotUri/android/latest/armeabi-v7a/mednafen_psx_libretro_android.so.zip"
        BuildbotUri_Android_armv8a = "$BuildBotUri/android/latest/arm64-v8a/mednafen_psx_libretro_android.so.zip"
    },
    [CoreInfo]@{
        Skip = $true
        Name = "BeetleWSwan"
        AppveyorUri = "$AppveyorApiUri/projects/bparker06/beetle-wswan-libretro"
        BuildbotUri_Win32_x86 = "$BuildBotUri/windows/x86/latest/mednafen_wswan_libretro.dll.zip"
        BuildbotUri_Win32_x64 = "$BuildBotUri/windows/x86_64/latest/mednafen_wswan_libretro.dll.zip"
        BuildbotUri_macOS_x86 = "$BuildBotUri/apple/osx/x86/latest/mednafen_wswan_libretro.dylib.zip"
        BuildbotUri_macOS_x64 = "$BuildBotUri/apple/osx/x86_64/latest/mednafen_wswan_libretro.dylib.zip"
        BuildbotUri_iOS = "$BuildBotUri/apple/ios/latest/mednafen_wswan_libretro_ios.dylib.zip"
        BuildbotUri_Android_x86 = "$BuildBotUri/android/latest/x86/mednafen_wswan_libretro_android.so.zip"
        BuildbotUri_Android_x64 = "$BuildBotUri/android/latest/x86_64/mednafen_wswan_libretro_android.so.zip"
        BuildbotUri_Android_arm = "$BuildBotUri/android/latest/armeabi/mednafen_wswan_libretro_android.so.zip"
        BuildbotUri_Android_armv7a = "$BuildBotUri/android/latest/armeabi-v7a/mednafen_wswan_libretro_android.so.zip"
        BuildbotUri_Android_armv8a = "$BuildBotUri/android/latest/arm64-v8a/mednafen_wswan_libretro_android.so.zip"
    },
    [CoreInfo]@{
        Skip = $true
        Name = "FBAlpha"
        AppveyorUri = "$AppveyorApiUri/projects/bparker06/fbalpha"
        BuildbotUri_Win32_x86 = "$BuildBotUri/windows/x86/latest/fbalpha_libretro.dll.zip"
        BuildbotUri_Win32_x64 = "$BuildBotUri/windows/x86_64/latest/fbalpha_libretro.dll.zip"
        BuildbotUri_macOS_x86 = "$BuildBotUri/apple/osx/x86/latest/fbalpha_libretro.dylib.zip"
        BuildbotUri_macOS_x64 = "$BuildBotUri/apple/osx/x86_64/latest/fbalpha_libretro.dylib.zip"
        BuildbotUri_iOS = "$BuildBotUri/apple/ios/latest/fbalpha_libretro_ios.dylib.zip"
        BuildbotUri_Android_x86 = "$BuildBotUri/android/latest/x86/fbalpha_libretro_android.so.zip"
        BuildbotUri_Android_x64 = "$BuildBotUri/android/latest/x86_64/fbalpha_libretro_android.so.zip"
        BuildbotUri_Android_arm = "$BuildBotUri/android/latest/armeabi/fbalpha_libretro_android.so.zip"
        BuildbotUri_Android_armv7a = "$BuildBotUri/android/latest/armeabi-v7a/fbalpha_libretro_android.so.zip"
        BuildbotUri_Android_armv8a = "$BuildBotUri/android/latest/arm64-v8a/fbalpha_libretro_android.so.zip"
    },
    [CoreInfo]@{
        Skip = $true
        Name = "FCEUMM"
        AppveyorUri = "$AppveyorApiUri/projects/bparker06/libretro-fceumm"
        BuildbotUri_Win32_x86 = "$BuildBotUri/windows/x86/latest/fceumm_libretro.dll.zip"
        BuildbotUri_Win32_x64 = "$BuildBotUri/windows/x86_64/latest/fceumm_libretro.dll.zip"
        BuildbotUri_macOS_x86 = "$BuildBotUri/apple/osx/x86/latest/fceumm_libretro.dylib.zip"
        BuildbotUri_macOS_x64 = "$BuildBotUri/apple/osx/x86_64/latest/fceumm_libretro.dylib.zip"
        BuildbotUri_iOS = "$BuildBotUri/apple/ios/latest/fceumm_libretro_ios.dylib.zip"
        BuildbotUri_Android_x86 = "$BuildBotUri/android/latest/x86/fceumm_libretro_android.so.zip"
        BuildbotUri_Android_x64 = "$BuildBotUri/android/latest/x86_64/fceumm_libretro_android.so.zip"
        BuildbotUri_Android_arm = "$BuildBotUri/android/latest/armeabi/fceumm_libretro_android.so.zip"
        BuildbotUri_Android_armv7a = "$BuildBotUri/android/latest/armeabi-v7a/fceumm_libretro_android.so.zip"
        BuildbotUri_Android_armv8a = "$BuildBotUri/android/latest/arm64-v8a/fceumm_libretro_android.so.zip"
    },
    [CoreInfo]@{
        Skip = $true
        Name = "Gambatte"
        AppveyorUri = "$AppveyorApiUri/projects/bparker06/gambatte-libretro"
        BuildbotUri_Win32_x86 = "$BuildBotUri/windows/x86/latest/gambatte_libretro.dll.zip"
        BuildbotUri_Win32_x64 = "$BuildBotUri/windows/x86_64/latest/gambatte_libretro.dll.zip"
        BuildbotUri_macOS_x86 = "$BuildBotUri/apple/osx/x86/latest/gambatte_libretro.dylib.zip"
        BuildbotUri_macOS_x64 = "$BuildBotUri/apple/osx/x86_64/latest/gambatte_libretro.dylib.zip"
        BuildbotUri_iOS = "$BuildBotUri/apple/ios/latest/gambatte_libretro_ios.dylib.zip"
        BuildbotUri_Android_x86 = "$BuildBotUri/android/latest/x86/gambatte_libretro_android.so.zip"
        BuildbotUri_Android_x64 = "$BuildBotUri/android/latest/x86_64/gambatte_libretro_android.so.zip"
        BuildbotUri_Android_arm = "$BuildBotUri/android/latest/armeabi/gambatte_libretro_android.so.zip"
        BuildbotUri_Android_armv7a = "$BuildBotUri/android/latest/armeabi-v7a/gambatte_libretro_android.so.zip"
        BuildbotUri_Android_armv8a = "$BuildBotUri/android/latest/arm64-v8a/gambatte_libretro_android.so.zip"
    },
    [CoreInfo]@{
        Skip = $true
        Name = "GenesisPlusGX"
        AppveyorUri = "$AppveyorApiUri/projects/bparker06/genesis-plus-gx"
        BuildbotUri_Win32_x86 = "$BuildBotUri/windows/x86/latest/genesis_plus_gx_libretro.dll.zip"
        BuildbotUri_Win32_x64 = "$BuildBotUri/windows/x86_64/latest/genesis_plus_gx_libretro.dll.zip"
        BuildbotUri_macOS_x86 = "$BuildBotUri/apple/osx/x86/latest/genesis_plus_gx_libretro.dylib.zip"
        BuildbotUri_macOS_x64 = "$BuildBotUri/apple/osx/x86_64/latest/genesis_plus_gx_libretro.dylib.zip"
        BuildbotUri_iOS = "$BuildBotUri/apple/ios/latest/genesis_plus_gx_libretro_ios.dylib.zip"
        BuildbotUri_Android_x86 = "$BuildBotUri/android/latest/x86/genesis_plus_gx_libretro_android.so.zip"
        BuildbotUri_Android_x64 = "$BuildBotUri/android/latest/x86_64/genesis_plus_gx_libretro_android.so.zip"
        BuildbotUri_Android_arm = "$BuildBotUri/android/latest/armeabi/genesis_plus_gx_libretro_android.so.zip"
        BuildbotUri_Android_armv7a = "$BuildBotUri/android/latest/armeabi-v7a/genesis_plus_gx_libretro_android.so.zip"
        BuildbotUri_Android_armv8a = "$BuildBotUri/android/latest/arm64-v8a/genesis_plus_gx_libretro_android.so.zip"
    },
    [CoreInfo]@{
        Skip = $true
        Name = "MelonDS"
        AppveyorUri = "$AppveyorApiUri/projects/bparker06/melonDS"
        BuildbotUri_Win32_x86 = "$BuildBotUri/windows/x86/latest/melonds_libretro.dll.zip"
        BuildbotUri_Win32_x64 = "$BuildBotUri/windows/x86_64/latest/melonds_libretro.dll.zip"
        BuildbotUri_macOS_x86 = "$BuildBotUri/apple/osx/x86/latest/melonds_libretro.dylib.zip"
        BuildbotUri_macOS_x64 = "$BuildBotUri/apple/osx/x86_64/latest/melonds_libretro.dylib.zip"
        BuildbotUri_iOS = "$BuildBotUri/apple/ios/latest/melonds_libretro_ios.dylib.zip"
        BuildbotUri_Android_x86 = "$BuildBotUri/android/latest/x86/melonds_libretro_android.so.zip"
        BuildbotUri_Android_x64 = "$BuildBotUri/android/latest/x86_64/melonds_libretro_android.so.zip"
        BuildbotUri_Android_arm = "$BuildBotUri/android/latest/armeabi/melonds_libretro_android.so.zip"
        BuildbotUri_Android_armv7a = "$BuildBotUri/android/latest/armeabi-v7a/melonds_libretro_android.so.zip"
        BuildbotUri_Android_armv8a = "$BuildBotUri/android/latest/arm64-v8a/melonds_libretro_android.so.zip"
    },
    [CoreInfo]@{
        Skip = $true
        Name = "Nestopia"
        AppveyorUri = "$AppveyorApiUri/projects/bparker06/nestopia"
        BuildbotUri_Win32_x86 = "$BuildBotUri/windows/x86/latest/nestopia_libretro.dll.zip"
        BuildbotUri_Win32_x64 = "$BuildBotUri/windows/x86_64/latest/nestopia_libretro.dll.zip"
        BuildbotUri_macOS_x86 = "$BuildBotUri/apple/osx/x86/latest/nestopia_libretro.dylib.zip"
        BuildbotUri_macOS_x64 = "$BuildBotUri/apple/osx/x86_64/latest/nestopia_libretro.dylib.zip"
        BuildbotUri_iOS = "$BuildBotUri/apple/ios/latest/nestopia_libretro_ios.dylib.zip"
        BuildbotUri_Android_x86 = "$BuildBotUri/android/latest/x86/nestopia_libretro_android.so.zip"
        BuildbotUri_Android_x64 = "$BuildBotUri/android/latest/x86_64/nestopia_libretro_android.so.zip"
        BuildbotUri_Android_arm = "$BuildBotUri/android/latest/armeabi/nestopia_libretro_android.so.zip"
        BuildbotUri_Android_armv7a = "$BuildBotUri/android/latest/armeabi-v7a/nestopia_libretro_android.so.zip"
        BuildbotUri_Android_armv8a = "$BuildBotUri/android/latest/arm64-v8a/nestopia_libretro_android.so.zip"
    },
    [CoreInfo]@{
        Skip = $true
        Name = "ParallelN64"
        AppveyorUri = "$AppveyorApiUri/projects/bparker06/parallel-n64"
        BuildbotUri_Win32_x86 = "$BuildBotUri/windows/x86/latest/parallel_n64_libretro.dll.zip"
        BuildbotUri_Win32_x64 = "$BuildBotUri/windows/x86_64/latest/parallel_n64_libretro.dll.zip"
        BuildbotUri_macOS_x86 = "$BuildBotUri/apple/osx/x86/latest/parallel_n64_libretro.dylib.zip"
        BuildbotUri_macOS_x64 = "$BuildBotUri/apple/osx/x86_64/latest/parallel_n64_libretro.dylib.zip"
        BuildbotUri_iOS = "$BuildBotUri/apple/ios/latest/parallel_n64_libretro_ios.dylib.zip"
        BuildbotUri_Android_x86 = "$BuildBotUri/android/latest/x86/parallel_n64_libretro_android.so.zip"
        BuildbotUri_Android_x64 = "$BuildBotUri/android/latest/x86_64/parallel_n64_libretro_android.so.zip"
        BuildbotUri_Android_arm = "$BuildBotUri/android/latest/armeabi/parallel_n64_libretro_android.so.zip"
        BuildbotUri_Android_armv7a = "$BuildBotUri/android/latest/armeabi-v7a/parallel_n64_libretro_android.so.zip"
        BuildbotUri_Android_armv8a = "$BuildBotUri/android/latest/arm64-v8a/parallel_n64_libretro_android.so.zip"
    },
    [CoreInfo]@{
        Skip = $true
        Name = "PicoDrive"
        AppveyorUri = "$AppveyorApiUri/projects/bparker06/picodrive"
        BuildbotUri_Win32_x86 = "$BuildBotUri/windows/x86/latest/picodrive_libretro.dll.zip"
        BuildbotUri_Win32_x64 = "$BuildBotUri/windows/x86_64/latest/picodrive_libretro.dll.zip"
        BuildbotUri_macOS_x86 = "$BuildBotUri/apple/osx/x86/latest/picodrive_libretro.dylib.zip"
        BuildbotUri_macOS_x64 = "$BuildBotUri/apple/osx/x86_64/latest/picodrive_libretro.dylib.zip"
        BuildbotUri_iOS = "$BuildBotUri/apple/ios/latest/picodrive_libretro_ios.dylib.zip"
        BuildbotUri_Android_x86 = "$BuildBotUri/android/latest/x86/picodrive_libretro_android.so.zip"
        BuildbotUri_Android_x64 = "$BuildBotUri/android/latest/x86_64/picodrive_libretro_android.so.zip"
        BuildbotUri_Android_arm = "$BuildBotUri/android/latest/armeabi/picodrive_libretro_android.so.zip"
        BuildbotUri_Android_armv7a = "$BuildBotUri/android/latest/armeabi-v7a/picodrive_libretro_android.so.zip"
        BuildbotUri_Android_armv8a = "$BuildBotUri/android/latest/arm64-v8a/picodrive_libretro_android.so.zip"
    },
    [CoreInfo]@{
        Skip = $true
        Name = "Snes9X"
        AppveyorUri = "$AppveyorApiUri/projects/bparker06/snes9x"
        BuildbotUri_Win32_x86 = "$BuildBotUri/windows/x86/latest/snes9x_libretro.dll.zip"
        BuildbotUri_Win32_x64 = "$BuildBotUri/windows/x86_64/latest/snes9x_libretro.dll.zip"
        BuildbotUri_macOS_x86 = "$BuildBotUri/apple/osx/x86/latest/snes9x_libretro.dylib.zip"
        BuildbotUri_macOS_x64 = "$BuildBotUri/apple/osx/x86_64/latest/snes9x_libretro.dylib.zip"
        BuildbotUri_iOS = "$BuildBotUri/apple/ios/latest/snes9x_libretro_ios.dylib.zip"
        BuildbotUri_Android_x86 = "$BuildBotUri/android/latest/x86/snes9x_libretro_android.so.zip"
        BuildbotUri_Android_x64 = "$BuildBotUri/android/latest/x86_64/snes9x_libretro_android.so.zip"
        BuildbotUri_Android_arm = "$BuildBotUri/android/latest/armeabi/snes9x_libretro_android.so.zip"
        BuildbotUri_Android_armv7a = "$BuildBotUri/android/latest/armeabi-v7a/snes9x_libretro_android.so.zip"
        BuildbotUri_Android_armv8a = "$BuildBotUri/android/latest/arm64-v8a/snes9x_libretro_android.so.zip"
    },
    [CoreInfo]@{
        Skip = $true
        Name = "VBAM"
        AppveyorUri = "$AppveyorApiUri/projects/bparker06/vbam-libretro"
        BuildbotUri_Win32_x86 = "$BuildBotUri/windows/x86/latest/vbam_libretro.dll.zip"
        BuildbotUri_Win32_x64 = "$BuildBotUri/windows/x86_64/latest/vbam_libretro.dll.zip"
        BuildbotUri_macOS_x86 = "$BuildBotUri/apple/osx/x86/latest/vbam_libretro.dylib.zip"
        BuildbotUri_macOS_x64 = "$BuildBotUri/apple/osx/x86_64/latest/vbam_libretro.dylib.zip"
        BuildbotUri_iOS = "$BuildBotUri/apple/ios/latest/vbam_libretro_ios.dylib.zip"
        BuildbotUri_Android_x86 = "$BuildBotUri/android/latest/x86/vbam_libretro_android.so.zip"
        BuildbotUri_Android_x64 = "$BuildBotUri/android/latest/x86_64/vbam_libretro_android.so.zip"
        BuildbotUri_Android_arm = "$BuildBotUri/android/latest/armeabi/vbam_libretro_android.so.zip"
        BuildbotUri_Android_armv7a = "$BuildBotUri/android/latest/armeabi-v7a/vbam_libretro_android.so.zip"
        BuildbotUri_Android_armv8a = "$BuildBotUri/android/latest/arm64-v8a/vbam_libretro_android.so.zip"
    }
)

$rootFolder = Join-Path $PWD.Path -ChildPath "LibretroCores";
$enabledCores = $cores | Where-Object {$_.Skip -ne $true}
foreach ($core in $enabledCores) {
    DownloadCore -Core $core -RootFolder $rootFolder
}
