$adb = 'C:\Users\mushi\AppData\Local\Android\Sdk\platform-tools\adb.exe'
& $adb shell input tap 998 1459
Start-Sleep -Seconds 2
& $adb shell screencap -p /sdcard/_shot.png
& $adb pull /sdcard/_shot.png 'C:\Users\mushi\StudioProjects\untitled\_shot.png'
& $adb shell uiautomator dump /sdcard/_ui.xml | Out-Null
& $adb pull /sdcard/_ui.xml 'C:\Users\mushi\StudioProjects\untitled\_ui.xml' | Out-Null
Write-Output 'done'
