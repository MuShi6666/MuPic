$adb = 'C:\Users\mushi\AppData\Local\Android\Sdk\platform-tools\adb.exe'
& $adb shell uiautomator dump /sdcard/_ui.xml | Out-Null
& $adb pull /sdcard/_ui.xml 'C:\Users\mushi\StudioProjects\untitled\_ui.xml' | Out-Null
cmd /c "adb exec-out screencap -p > C:\Users\mushi\StudioProjects\untitled\_shot.png"
Write-Output 'done'
