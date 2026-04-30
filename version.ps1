$content = Get-Content pubspec.yaml

foreach ($line in $content) {
    if ($line -match "^version:") {
        $versionLine = $line
    }
}

$version = $versionLine -replace "version: ", ""
$parts = $version.Split("+")
$base = $parts[0]
$build = [int]$parts[1]

$newBuild = $build + 1
$newVersion = "$base+$newBuild"

$content = $content -replace "version: .*", "version: $newVersion"
Set-Content pubspec.yaml $content

Write-Host "Nova versão: $newVersion"

git add pubspec.yaml
git commit -m "chore: versão $newVersion"
git tag -a "v$base" -m "Release $base"
git push origin main
git push origin "v$base"