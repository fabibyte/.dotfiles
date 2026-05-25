$ErrorActionPreference = 'Stop'

$archiveUrl = 'https://github.com/fabibyte/.dotfiles/archive/refs/heads/main.zip'
$mainFilePath = 'windows/flow/laptop.ps1'
$dotfilesFolder = Join-Path $env:USERPROFILE '.dotfiles'
$setupRoot = ""
$setupScript = ""

if ($PSCommandPath) {
    $setupRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
    $setupScript = Join-Path $setupRoot $mainFilePath
    
    if (-not (Test-Path $setupScript)) {
        throw "Could not find $setupScript locally."
    }
}
else {
    Write-Host "Running remotely... Downloading dotfiles archive." -ForegroundColor Cyan
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) "dotfiles-bootstrap-$([guid]::NewGuid().ToString('N'))"
    $archivePath = Join-Path $tempRoot 'dotfiles.zip'
    $extractPath = Join-Path $tempRoot 'extract'

    try {
        $null = New-Item -ItemType Directory -Path $tempRoot -Force
        $null = New-Item -ItemType Directory -Path $extractPath -Force

        Invoke-WebRequest -UseBasicParsing -Uri $archiveUrl -OutFile $archivePath
        Expand-Archive -Path $archivePath -DestinationPath $extractPath -Force

        $archiveRoot = Join-Path $extractPath '.dotfiles-main'
        $null = New-Item -ItemType Directory -Path $dotfilesFolder -Force
        Get-ChildItem -LiteralPath $archiveRoot -Force | ForEach-Object {
            Copy-Item -LiteralPath $_.FullName -Destination $dotfilesFolder -Recurse -Force
        }
    }
    finally {
        if (Test-Path -LiteralPath $tempRoot) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    $setupScript = Join-Path (Join-Path $dotfilesFolder 'setup') $mainFilePath
}

$arg = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $setupScript)
& powershell @arg
exit $LASTEXITCODE
