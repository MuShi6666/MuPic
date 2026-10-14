$adb = 'C:\Users\mushi\AppData\Local\Android\Sdk\platform-tools\adb.exe'
# Tap undo (top-left) twice to step back through commits
& $adb shell input tap 112 160
Start-Sleep -Seconds 1
& $adb shell input tap 112 160
Start-Sleep -Seconds 2
& $adb shell uiautomator dump /sdcard/_ui.xml | Out-Null
& $adb pull /sdcard/_ui.xml 'C:\Users\mushi\StudioProjects\untitled\_ui.xml' | Out-Null
Write-Output 'done'
