# Baut die fertige APK für dein Handy.
#
#   .\build-apk.ps1                         -> APK mit den mitgelieferten Terminen
#   .\build-apk.ps1 -EventsUrl "https://raw.githubusercontent.com/NAME/offene-tueren/main/data/events.json"
#                                           -> APK lädt die Termine täglich frisch aus deinem GitHub-Projekt
#
# Ergebnis: C:\Users\erika\OffeneTueren-arm64.apk
param(
    [string]$EventsUrl = "",
    [string]$Version = ""          # z. B. "1.1.0+2" – bei jedem Update die Zahl nach + erhöhen
)
$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$env:Path = "C:\Users\erika\flutter\bin;$env:Path"

# aktuellen Stand der Termine in die App packen (für den ersten Start ohne Internet)
Copy-Item "$root\data\events.json" "$root\app\assets\events.json" -Force

Push-Location "$root\app"
try {
    $flutterArgs = @("build", "apk", "--release", "--split-per-abi", "--target-platform", "android-arm64")
    if ($EventsUrl) { $flutterArgs += "--dart-define=EVENTS_URL=$EventsUrl" }
    if ($Version) {
        $parts = $Version.Split("+")
        $flutterArgs += @("--build-name", $parts[0])
        if ($parts.Count -gt 1) { $flutterArgs += @("--build-number", $parts[1]) }
    }
    & flutter @args
    if ($LASTEXITCODE -ne 0) { throw "Build fehlgeschlagen" }
    Copy-Item "build\app\outputs\flutter-apk\app-arm64-v8a-release.apk" "C:\Users\erika\OffeneTueren-arm64.apk" -Force
    Write-Host "Fertig: C:\Users\erika\OffeneTueren-arm64.apk"
} finally {
    Pop-Location
}
