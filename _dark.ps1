$adb = "C:\Users\mushi\AppData\Local\Android\Sdk\platform-tools\adb.exe"
& $adb -s emulator-5554 shell input tap 917 231
Start-Sleep -Milliseconds 700
& $adb -s emulator-5554 shell input tap 650 610
Start-Sleep -Seconds 2
& $adb -s emulator-5554 shell screencap -p /sdcard/sc.png
& $adb -s emulator-5554 pull /sdcard/sc.png "C:\Users\mushi\StudioProjects\untitled\_shot.png"
