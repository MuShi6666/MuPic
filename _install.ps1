$adb = 'C:\Users\mushi\AppData\Local\Android\Sdk\platform-tools\adb.exe'
Set-Location -Path 'C:\Users\mushi\StudioProjects\untitled'
& $adb install -r 'build\app\outputs\flutter-apk\app-debug.apk'
& $adb shell am start -n com.mupic.app/.MainActivity
