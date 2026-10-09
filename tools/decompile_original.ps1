param(
    [string]$GhidraHome,
    [string]$JavaHome,
    [string]$PythonExecutable = 'python',
    [string]$Executable = 'Original Sub Culture/SC.EXE',
    [string]$OutputDirectory = 'Extracted Original Data/decompilation/output'
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$researchRoot = Join-Path $projectRoot 'Extracted Original Data/decompilation'
if (-not $GhidraHome) {
    $GhidraHome = (Get-ChildItem -LiteralPath $researchRoot -Directory -Filter 'ghidra_*_PUBLIC' |
        Sort-Object Name -Descending | Select-Object -First 1).FullName
}
if (-not $GhidraHome -or -not (Test-Path -LiteralPath (Join-Path $GhidraHome 'support/analyzeHeadless.bat'))) {
    throw 'Supply -GhidraHome with the path to an extracted official Ghidra release.'
}
if ($JavaHome) { $env:JAVA_HOME = $JavaHome }
# Keep Ghidra preferences and analysis output local and excluded from Git.
$env:APPDATA = Join-Path $researchRoot 'appdata'
$env:USERPROFILE = Join-Path $researchRoot 'user'
$projects = Join-Path $researchRoot 'projects'
New-Item -ItemType Directory -Force $projects | Out-Null
if (-not [IO.Path]::IsPathRooted($Executable)) { $Executable = Join-Path $projectRoot $Executable }
if (-not [IO.Path]::IsPathRooted($OutputDirectory)) { $OutputDirectory = Join-Path $projectRoot $OutputDirectory }
$projectName = 'SubCulture_' + [IO.Path]::GetFileNameWithoutExtension($Executable)
$headless = Join-Path $GhidraHome 'support/analyzeHeadless.bat'
$candidates = Join-Path $researchRoot 'function-candidates.txt'
$priorPythonPath = $env:PYTHONPATH
try {
    $env:PYTHONPATH = (Join-Path $projectRoot 'Extracted Original Data/research-deps') + [IO.Path]::PathSeparator + $priorPythonPath
    & $PythonExecutable (Join-Path $PSScriptRoot 'research_executable.py') $Executable --candidates $candidates
    if ($LASTEXITCODE -ne 0) { throw 'Candidate discovery failed. Install pefile and capstone for the supplied Python.' }
} finally { $env:PYTHONPATH = $priorPythonPath }
$startedAt = [DateTime]::UtcNow
& $headless $projects $projectName -import $Executable -overwrite -scriptPath $PSScriptRoot `
    -postScript RecoverOriginalFunctions.java $candidates `
    -postScript ExportOriginalCode.java $OutputDirectory -analysisTimeoutPerFile 240 -max-cpu 2
if ($LASTEXITCODE -ne 0) { throw "Ghidra failed with exit code $LASTEXITCODE" }
$status = Join-Path $OutputDirectory 'export-status.txt'
if (-not (Test-Path -LiteralPath $status) -or (Get-Item -LiteralPath $status).LastWriteTimeUtc -lt $startedAt) {
    throw 'No fresh export completion status was produced.'
}
Get-Content -LiteralPath $status
