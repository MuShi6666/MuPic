$adb = 'C:\Users\mushi\AppData\Local\Android\Sdk\platform-tools\adb.exe'
# Select 复位 (reconstruct) tool
& $adb shell input tap 333 1697
Start-Sleep -Seconds 1
# Drag across the distorted region to erase impulses
& $adb shell input swipe 300 560 560 680 700
Start-Sleep -Seconds 2
& $adb shell screencap -p /sdcard/_shot.png
& $adb pull /sdcard/_shot.png 'C:\Users\mushi\StudioProjects\untitled\_shot_recon.png'
Write-Output 'done'
