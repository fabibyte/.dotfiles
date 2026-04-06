$ErrorActionPreference = 'Stop'

$baseUrl = 'https://raw.githubusercontent.com/fabibyte/.dotfiles/refs/heads/main/setup'

if (-not $PSCommandPath) {
    Write-Host "Running remotely... Initializing bootstrapper." -ForegroundColor Cyan
    
    $tempDir = Join-Path $env:TEMP ("dotfiles-setup-{0}" -f ([guid]::NewGuid()))
    $null = New-Item -ItemType Directory -Path $tempDir -Force
    
    $filesToFetch = @(
        'windows-main.ps1',
        'arch-wsl-main.sh',
        'shared.sh'
    )
    
    foreach ($file in $filesToFetch) {
        $outPath = Join-Path $tempDir $file
        $fileUrl = "$baseUrl/$file"
        Write-Host "Downloading $fileUrl -> $outPath" -ForegroundColor DarkCyan
        Invoke-WebRequest -UseBasicParsing -Uri $fileUrl -OutFile $outPath
    }
    
    $setupScript = Join-Path $tempDir 'windows-main.ps1'
}
else {
    $setupScript = Join-Path $PSScriptRoot 'windows-main.ps1'
    
    if (-not (Test-Path $setupScript)) {
        throw "Could not find $setupScript locally."
    }
}

$arg = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $setupScript)

& powershell @arg
exit $LASTEXITCODE
