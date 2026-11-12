# Baut die fertige APK für dein Handy.
#
#   .\build-apk.ps1 -Version "2.0.1+3"      -> neue Version (Zahl nach + bei JEDEM Update erhöhen)
#   .\build-apk.ps1 -DataUrl "https://raw.githubusercontent.com/NAME/REPO/main/data/"
#                                           -> anderer Datenordner (Standard: FishYorkCity67/offene-tueren)
#
# App-Name ändern: app\assets\app_name.txt bearbeiten, dann neu bauen.
# Ergebnis: C:\Users\erika\OffeneTueren-arm64.apk
param(
    [string]$DataUrl = "",
    [string]$Version = ""          # z. B. "2.0.1+3" – bei jedem Update die Zahl nach + erhöhen
)
$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$env:Path = "C:\Users\erika\flutter\bin;$env:Path"

# aktuellen Stand der Daten in die App packen (für den ersten Start ohne Internet)
foreach ($d in "events.json","freizeit.json","jobs.json") { if (Test-Path "$root\data\$d") { Copy-Item "$root\data\$d" "$root\app\assets\$d" -Force } }

Push-Location "$root\app"
try {
    $flutterArgs = @("build", "apk", "--release", "--split-per-abi", "--target-platform", "android-arm64")
    if ($DataUrl) { $flutterArgs += "--dart-define=DATA_BASE_URL=$DataUrl" }
    if ($Version) {
        $parts = $Version.Split("+")
        $flutterArgs += @("--build-name", $parts[0])
        if ($parts.Count -gt 1) { $flutterArgs += @("--build-number", $parts[1]) }
    }
    & flutter @flutterArgs
    if ($LASTEXITCODE -ne 0) { throw "Build fehlgeschlagen" }
    Copy-Item "build\app\outputs\flutter-apk\app-arm64-v8a-release.apk" "C:\Users\erika\OffeneTueren-arm64.apk" -Force
    Write-Host "Fertig: C:\Users\erika\OffeneTueren-arm64.apk"
} finally {
    Pop-Location
}
