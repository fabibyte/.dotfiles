$ErrorActionPreference = 'Stop'

$ArchiveUrl = 'https://github.com/fabibyte/.dotfiles/archive/refs/heads/main.zip'
$FlowScriptRelativePath = 'windows/flow/desktop.ps1'
$DotfilesFolder = Join-Path $env:USERPROFILE '.dotfiles'
$SetupRoot = ''
$FlowScriptPath = ''

if ($PSCommandPath) {
    $SetupRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
    $FlowScriptPath = Join-Path $SetupRoot $FlowScriptRelativePath
    
    if (-not (Test-Path $FlowScriptPath)) {
        throw "Could not find $FlowScriptPath locally."
    }
}
else {
    Write-Host "Running remotely... Downloading dotfiles archive." -ForegroundColor Cyan
    $TempDirectory = Join-Path ([System.IO.Path]::GetTempPath()) "dotfiles-bootstrap-$([guid]::NewGuid().ToString('N'))"
    $ArchivePath = Join-Path $TempDirectory 'dotfiles.zip'
    $ExtractPath = Join-Path $TempDirectory 'extract'

    try {
        $null = New-Item -ItemType Directory -Path $TempDirectory -Force
        $null = New-Item -ItemType Directory -Path $ExtractPath -Force

        Invoke-WebRequest -UseBasicParsing -Uri $ArchiveUrl -OutFile $ArchivePath
        Expand-Archive -Path $ArchivePath -DestinationPath $ExtractPath -Force

        $ArchiveRoot = Join-Path $ExtractPath '.dotfiles-main'
        $null = New-Item -ItemType Directory -Path $DotfilesFolder -Force
        Get-ChildItem -LiteralPath $ArchiveRoot -Force | ForEach-Object {
            Copy-Item -LiteralPath $_.FullName -Destination $DotfilesFolder -Recurse -Force
        }
    }
    finally {
        if (Test-Path -LiteralPath $TempDirectory) {
            Remove-Item -LiteralPath $TempDirectory -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    $FlowScriptPath = Join-Path (Join-Path $DotfilesFolder 'setup') $FlowScriptRelativePath
}

$PowerShellArguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $FlowScriptPath)
& powershell @PowerShellArguments
exit $LASTEXITCODE
