$adb = 'C:\Users\mushi\AppData\Local\Android\Sdk\platform-tools\adb.exe'
# Scroll the tab strip leftward to reveal tabs 8/9 (裁剪 / 液化)
& $adb shell input swipe 950 1460 250 1460 300
Write-Output 'swiped'
