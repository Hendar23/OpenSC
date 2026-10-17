$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$testsRoot = (Resolve-Path -LiteralPath (Join-Path $projectRoot 'godot/tests')).Path
$targets = @(Get-ChildItem -LiteralPath $testsRoot -Directory | Where-Object {
    $_.Name -like 'cache-*-fixtures' -or $_.Name -eq 'cache-fixtures'
})
$filesRemoved = 0
$bytesRemoved = 0L
foreach ($target in $targets) {
    $resolved = (Resolve-Path -LiteralPath $target.FullName).Path
    if ([IO.Path]::GetDirectoryName($resolved) -ne $testsRoot -or
        ($target.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "Unsafe test cache target: $resolved"
    }
    $contents = @(Get-ChildItem -LiteralPath $resolved -Recurse -Force)
    if ($contents | Where-Object { ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $_.Name -like 'README*' }) {
        throw "Test cache contains a link or protected README: $resolved"
    }
    $files = @($contents | Where-Object { -not $_.PSIsContainer })
    $filesRemoved += $files.Count
    $bytesRemoved += ($files | Measure-Object -Property Length -Sum).Sum
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
Write-Output ("Removed {0:N0} files from {1} generated test folders; freed {2:N1} MiB." -f $filesRemoved, $targets.Count, ($bytesRemoved / 1MB))
