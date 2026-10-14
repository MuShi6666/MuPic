$adb = 'C:\Users\mushi\AppData\Local\Android\Sdk\platform-tools\adb.exe'
& $adb shell screencap -p /sdcard/_shot.png
& $adb pull /sdcard/_shot.png 'C:\Users\mushi\StudioProjects\untitled\_shot.png'
Write-Output 'done'
