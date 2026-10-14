$adb = "C:\Users\mushi\AppData\Local\Android\Sdk\platform-tools\adb.exe"
& $adb -s emulator-5554 shell wm size
& $adb -s emulator-5554 shell wm density
Add-Type -AssemblyName System.Drawing
$img = [System.Drawing.Image]::FromFile("C:\Users\mushi\StudioProjects\untitled\_shot.png")
Write-Output ("PNG {0}x{1}" -f $img.Width, $img.Height)
$img.Dispose()
