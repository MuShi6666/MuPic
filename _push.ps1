$adb = 'C:\Users\mushi\AppData\Local\Android\Sdk\platform-tools\adb.exe'
# Push stroke across the cheek/jaw: drag rightward along the face
& $adb shell input swipe 360 660 520 660 600
Start-Sleep -Seconds 2
& $adb shell screencap -p /sdcard/_shot.png
& $adb pull /sdcard/_shot.png 'C:\Users\mushi\StudioProjects\untitled\_shot_push.png'
Write-Output 'done'
