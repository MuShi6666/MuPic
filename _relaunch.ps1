$adb = 'C:\Users\mushi\AppData\Local\Android\Sdk\platform-tools\adb.exe'
& $adb shell am force-stop com.mupic.app
Start-Sleep -Seconds 1
& $adb shell am start -n com.mupic.app/.MainActivity
Start-Sleep -Seconds 4
