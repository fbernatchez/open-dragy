param(
  [Parameter(Position = 0)]
  [ValidateSet(
    "ping", "status", "satellites", "sky", "map",
    "gsv_on", "gsv_off", "dashboard", "logs", "install", "launch"
  )]
  [string]$Cmd = "status"
)

$ErrorActionPreference = "Stop"
$Adb = "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\Google.PlatformTools_Microsoft.Winget.Source_8wekyb3d8bbwe\platform-tools\adb.exe"
if (-not (Test-Path $Adb)) { $Adb = "adb" }

$Pkg = "com.fb_engineering.open_dragy.debug"
$Action = "$Pkg.DEBUG_CMD"
$Activity = "$Pkg/com.fb_engineering.open_dragy.MainActivity"
$Flutter = "D:\_PROJEKTY\Stepa\flutter\bin\flutter.bat"
$Root = "d:\_PROJEKTY\Stepa\OpenDragy\OpenDragy"

function Invoke-DebugCmd([string]$name) {
  # Prefer broadcast (app already running); also fire start with extra as fallback.
  & $Adb shell am broadcast -a $Action --es cmd $name | Out-Host
  & $Adb shell am start -n $Activity --es cmd $name | Out-Host
}

switch ($Cmd) {
  "install" {
    Push-Location $Root
    & $Flutter build apk --debug
    if ($LASTEXITCODE -ne 0) { Pop-Location; exit $LASTEXITCODE }
    & $Adb install -r -t -g "$Root\build\app\outputs\flutter-apk\app-debug.apk"
    Pop-Location
  }
  "launch" {
    & $Adb shell monkey -p $Pkg -c android.intent.category.LAUNCHER 1 | Out-Host
  }
  "logs" {
    & $Adb logcat -c
    & $Adb logcat -v time OpenDragy:D flutter:I *:S
  }
  "ping" { Invoke-DebugCmd "ping" }
  "status" { Invoke-DebugCmd "status" }
  "satellites" { Invoke-DebugCmd "satellites" }
  "sky" { Invoke-DebugCmd "sky" }
  "map" { Invoke-DebugCmd "map" }
  "gsv_on" { Invoke-DebugCmd "gsv_on" }
  "gsv_off" { Invoke-DebugCmd "gsv_off" }
  "dashboard" { Invoke-DebugCmd "dashboard" }
}
