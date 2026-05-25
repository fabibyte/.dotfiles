class Logger {
    static [string]$LogFileActive

    static [void] Init([string]$NewLogFileBasePath, [string]$ResumeLogFilePath) {
        $resolvedLogPath = ""

        if ($ResumeLogFilePath) {
            $resolvedLogPath = $ResumeLogFilePath
        }
        else {
            $timestamp = (Get-Date).ToString('yyyyMMdd_HHmmss')
            $resolvedLogPath = Join-Path $NewLogFileBasePath "setup_$timestamp.log"
        } 

        if (-not (Test-Path $resolvedLogPath)) {
            $null = New-Item -ItemType File -Path $resolvedLogPath -Force
        }

        [Logger]::LogFileActive = $resolvedLogPath
    }

    static [void] Write([string]$Level, [string]$Message) {
        if ($Level -notin @('INFO', 'SUCCESS', 'WARNING', 'ERROR')) {
            throw "Unsupported log level: $Level"
        }

        $colorMap = @{
            INFO    = 'Cyan'
            SUCCESS = 'Green'
            WARNING = 'Yellow'
            ERROR   = 'Red'
        }

        $color = $colorMap[$Level]
        $timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        $formatted = "[$timestamp] [$Level] $Message"

        if ([Logger]::LogFileActive) {
            Add-Content -Path [Logger]::LogFileActive -Value $formatted -Encoding utf8
        }

        Write-Host $formatted -ForegroundColor $color
    }

    static [void] WriteInfo([string]$Message) {
        [Logger]::Write('INFO', $Message)
    }

    static [void] WriteSuccess([string]$Message) {
        [Logger]::Write('SUCCESS', $Message)
    }

    static [void] WriteWarning([string]$Message) {
        [Logger]::Write('WARNING', $Message)
    }

    static [void] WriteError([string]$Message) {
        [Logger]::Write('ERROR', $Message)
    }

    static [string] ReadLoggedHost([string]$Prompt) {
        if ($Prompt -and [Logger]::LogFileActive) {
            Add-Content -Path [Logger]::LogFileActive -Value $Prompt -Encoding utf8
        }

        return Read-Host $Prompt
    }
}

function Remove-NullArguments([object[]]$Arguments = @()) {
    $filteredArguments = @()

    for ($index = 0; $index -lt $Arguments.Count; $index++) {
        $argument = $Arguments[$index]
        $nextArgument = if ($index + 1 -lt $Arguments.Count) { $Arguments[$index + 1] } else { 'NoNextArgument' }

        if ($null -eq $argument) {
            continue
        }

        if ($argument -is [string] -and $argument.StartsWith('-') -and $null -eq $nextArgument) {
            $index++
            continue
        }

        $filteredArguments += $argument
    }

    return $filteredArguments
}

function Invoke-RunAsAdmin([string]$ScriptPath, [string]$ResumeLogPath) {
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)

    if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        if (-not $ScriptPath) {
            throw 'No scriptPath provided.'
        }

        $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $ScriptPath, '-ResumeLogPath', $ResumeLogPath)
        $finalArgs = Remove-NullArguments -Arguments $arguments
        Start-Process -FilePath 'powershell.exe' -ArgumentList $finalArgs -Verb RunAs
        exit
    }
}

function Invoke-SuppressedNativeCommand([string]$FilePath, [string[]]$ArgumentList = @()) {
    if (-not $FilePath) {
        throw 'Invoke-SuppressedNativeCommand requires a file path to execute.'
    }

    $isPath = [IO.Path]::IsPathRooted($FilePath) -or ($FilePath -match '[\\/]')
    if ($isPath) {
        if (-not (Test-Path -LiteralPath $FilePath)) {
            throw "Native command not found: $FilePath"
        }
    }
    elseif (-not (Get-Command -Name $FilePath -CommandType Application -ErrorAction SilentlyContinue)) {
        throw "Native command not found: $FilePath"
    }

    try {
        & $FilePath @ArgumentList *> $null
    }
    catch {
        return $LASTEXITCODE
    }

    return $LASTEXITCODE
}

function Get-WslUnixPath([string]$DistroName, [string]$WindowsPath) {
    try {
        $output = @(& wsl.exe -d $DistroName -e wslpath -u $WindowsPath 2>&1 | ForEach-Object { "$_" })
    }
    catch {
        $exitCode = $LASTEXITCODE
        $combinedOutput = $output -join [Environment]::NewLine

        if ($combinedOutput) {
            throw "WSL path conversion for $WindowsPath failed with exit code $exitCode. Output: $combinedOutput"
        }

        throw "WSL path conversion for $WindowsPath failed with exit code $exitCode"
    }

    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "WSL path conversion for $WindowsPath failed with exit code $exitCode"
    }

    $wslPath = ($output -join "`n").Trim()
    if (-not $wslPath) {
        throw "Failed to convert Windows path to WSL path: $WindowsPath"
    }

    return $wslPath
}

function Invoke-WithRetries([string]$Description, [int]$MaxAttempts = 3, [scriptblock]$Action) {
    if (-not $Action) {
        throw 'Invoke-WithRetries requires an action to execute.'
    }

    $lastError = $null

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            $result = & $Action
            if ($result -ne $false) {
                return
            }

            $lastError = "$Description failed."
        }
        catch {
            $lastError = $_.Exception.Message
        }

        if ($attempt -lt $MaxAttempts) {
            $remaining = $MaxAttempts - $attempt
            [Logger]::WriteWarning("$Description failed. $remaining attempt(s) remaining.")
        }
    }

    throw "$Description failed after $MaxAttempts attempts. Last error: $lastError"
}

function Register-ScheduledTasks([array]$ScheduledTasks) {
    [Logger]::WriteInfo("Creating scheduled tasks...")

    foreach ($scheduledTask in $ScheduledTasks) {
        Unregister-ScheduledTaskIfPresent -TaskName $scheduledTask.Name
        $null = Register-ScheduledTask -TaskName $scheduledTask.Name -Action $scheduledTask.Action -Trigger $scheduledTask.Trigger -RunLevel $scheduledTask.RunLevel
        [Logger]::WriteSuccess("Registered scheduled task: $($scheduledTask.Name)")
    }
}

function Unregister-ScheduledTaskIfPresent([string]$TaskName) {
    if (-not (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue)) {
        return
    }

    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}

function Register-RebootTask([string]$ScriptPath, [string]$LogPath) {
    $scriptCmd = "& '$ScriptPath' -ResumeLogPath '$LogPath'"
    $argString = "-NoProfile -ExecutionPolicy Bypass -Command `"$scriptCmd`""
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $argString
    $trigger = New-ScheduledTaskTrigger -AtLogon -User $env:USERNAME

    $scheduledTasks = @(
        @{ Name = "ContinueSetupAfterReboot"; Action = $action; Trigger = $trigger; RunLevel = 'Highest' }
    )

    Register-ScheduledTasks -ScheduledTasks $scheduledTasks
}

function Unregister-RebootTask {
    Unregister-ScheduledTaskIfPresent -TaskName "ContinueSetupAfterReboot"
}

function Install-WSLPlatform([string]$ScriptPath, [string]$LogPath) {
    if (-not (Get-Command 'wsl.exe' -ErrorAction SilentlyContinue)) {
        $isInstalled = $false
    }
    else {
        try {
            $null = & wsl.exe --status 2>$null
            $isInstalled = ($LASTEXITCODE -eq 0)
        }
        catch {
            $isInstalled = $false
        }
    }

    if (-not $isInstalled) {
        [Logger]::WriteInfo('WSL platform is not installed; installing now (platform only)...')
        & wsl.exe --install --no-distribution
        if ($LASTEXITCODE -ne 0) {
            throw "WSL platform installation failed with exit code $LASTEXITCODE"
        }
                
        Register-RebootTask -ScriptPath $ScriptPath -LogPath $LogPath
        [Logger]::WriteInfo('Rebooting to continue setup...')
        $null = Restart-Computer
    }
}

function Install-WSLDistroIfMissing([string]$DistroName) {
    $installed = $false

    try {
        $listOutput = @(& wsl.exe --list --quiet 2>&1 | ForEach-Object { "$_" })
        $listExitCode = $LASTEXITCODE

        if ($listExitCode -eq 0 -and ($listOutput | ForEach-Object { "$_".Trim() } | Where-Object { $_ -ieq $DistroName })) {
            $installed = $true
        }
    }
    catch {
        throw "WSL distro check for ($DistroName) failed with exit code $LASTEXITCODE"
    }

    if (-not $installed) {
        [Logger]::WriteInfo("Installing WSL distro: $DistroName")
        $wslArgs = @('--install', '-d', $DistroName, '--no-launch')
        $wslExitCode = Invoke-SuppressedNativeCommand -FilePath 'wsl.exe' -ArgumentList $wslArgs
        if ($wslExitCode -ne 0) {
            throw "WSL distro installation ($DistroName) failed with exit code $LASTEXITCODE"
        }
        return $true
    }

    [Logger]::WriteInfo("WSL distro '$DistroName' already installed.")
    return $false
}

function Invoke-WSLDotfilesSetup([string]$DistroName, [string]$DotfilesFolder, [string]$LogPath, [string]$ScriptPath) {
    [Logger]::WriteInfo('Running dotfiles setup inside WSL...')

    $wslScriptDir = Get-WslUnixPath -DistroName $DistroName -WindowsPath $ScriptPath
    $wslDotfilesFolder = Get-WslUnixPath -DistroName $DistroName -WindowsPath $DotfilesFolder
    $wslLogFile = Get-WslUnixPath -DistroName $DistroName -WindowsPath $LogPath

    & wsl.exe -d $DistroName -e env "DOTFILES_FOLDER=$wslDotfilesFolder" "DOTFILES_LOG_FILE=$wslLogFile" bash "$wslScriptDir"
    if ($LASTEXITCODE -ne 0) {
        throw "Dotfiles setup inside WSL failed with exit code $LASTEXITCODE"
    }
    [Logger]::WriteSuccess('Dotfiles setup completed inside WSL.')
}

function Invoke-WSLDecryption([string]$Description, [string]$DistroName, [string]$InputPath, [string]$OutputPath) {
    if (Test-Path -LiteralPath $OutputPath) {
        [Logger]::WriteInfo("$Description output already exists: $OutputPath")
        return
    }

    $wslInputPath = Get-WslUnixPath -DistroName $DistroName -WindowsPath $InputPath
    $wslOutputPath = Get-WslUnixPath -DistroName $DistroName -WindowsPath $OutputPath

    $decryptAction = {
        & wsl.exe -d $DistroName -e openssl aes-256-cbc -d -salt -pbkdf2 -iter 100000 -in "$wslInputPath" -out "$wslOutputPath"
        if ($LASTEXITCODE -ne 0) {
            & wsl.exe -d $DistroName -e rm -rf "$wslOutputPath"
            return $false
        }

        return $true
    }

    Invoke-WithRetries -Description $Description -MaxAttempts 3 -Action $decryptAction
    [Logger]::WriteSuccess('Decryption successful.')
}

function New-Symlink([string]$SourcePath, [string]$TargetPath) {
    if ((-not $SourcePath) -or (-not $TargetPath)) {
        [Logger]::WriteError("New-Symlink requires -SourcePath and -TargetPath arguments")
        return
    }

    if (-not (Test-Path -Path $SourcePath)) {
        [Logger]::WriteWarning("Source does not exist: $SourcePath")
        return
    }

    if (Test-Path -LiteralPath $TargetPath) {
        $targetItem = Get-Item -LiteralPath $TargetPath -Force
        $targetIsLink = ($targetItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0

        if ($targetIsLink) {
            $currentTargetPath = $targetItem.Target 2>$null
            if ($currentTargetPath -and $currentTargetPath -eq $SourcePath) {
                [Logger]::WriteInfo("Symlink already correct: $TargetPath -> $SourcePath")
                return
            }

            Remove-Item -LiteralPath $TargetPath -Force
        }
        else {
            [Logger]::WriteWarning("Target exists and is not a symlink; skipping: $TargetPath")
            return
        }
    }

    $targetDirectory = Split-Path -Parent $TargetPath
    if (-not (Test-Path $targetDirectory)) {
        $null = New-Item -ItemType Directory -Path $targetDirectory -Force
    }

    $null = New-Item -ItemType SymbolicLink -Path $TargetPath -Target $SourcePath -Force
    [Logger]::WriteSuccess("Linked $TargetPath -> $SourcePath")
}

function New-SymlinkTree([string]$SourceDirectory, [string]$TargetDirectory) {
    if (-not (Test-Path -Path $SourceDirectory -PathType Container)) {
        [Logger]::WriteWarning("Source directory does not exist: $SourceDirectory")
        return
    }

    Get-ChildItem -Path $SourceDirectory -File -Recurse | ForEach-Object {
        $relativePath = $_.FullName.Substring($SourceDirectory.TrimEnd('\').Length + 1)
        $targetFilePath = Join-Path $TargetDirectory $relativePath
        New-Symlink -SourcePath $_.FullName -TargetPath $targetFilePath
    }
}

function Remove-WingetApps([string[]]$AppsToRemove) {
    [Logger]::WriteInfo('Removing unwanted winget applications...')
    foreach ($package in $AppsToRemove) {
        [Logger]::WriteInfo("Removing package: $package")
        $removeArgs = @('remove', '--all', '--exact', '--silent', '--nowarn', '--purge', '--force', '--disable-interactivity', '--accept-source-agreements', '--source', 'winget', $package)
        $removeExitCode = Invoke-SuppressedNativeCommand -FilePath 'winget.exe' -ArgumentList $removeArgs
        if ($removeExitCode -ne 0) {
            [Logger]::WriteWarning("winget remove exited with code $removeExitCode for package: $package.")
        }
    }
    [Logger]::WriteInfo('Unwanted winget application removal complete.')
}

function Update-WingetApps() {
    [Logger]::WriteInfo('Installing updates...')
    $updateArgs = @('update', '--all', '--silent', '--disable-interactivity', '--accept-package-agreements', '--accept-source-agreements')
    $updateExitCode = Invoke-SuppressedNativeCommand -FilePath 'winget.exe' -ArgumentList $updateArgs

    if ($updateExitCode -eq 0) {
        [Logger]::WriteSuccess("Updates installed...")
    }
    else {
        [Logger]::WriteWarning("winget update exited with code $updateExitCode. Continuing setup.")
    }
}

function Install-WingetApps([string[]]$AppsToInstall) {
    [Logger]::WriteInfo('Installing winget applications...')
    foreach ($package in $AppsToInstall) {
        [Logger]::WriteInfo("Installing package: $package")
        $installArgs = @('install', '--exact', '--silent', '--disable-interactivity', '--accept-package-agreements', '--accept-source-agreements', $package)
        $installExitCode = Invoke-SuppressedNativeCommand -FilePath 'winget.exe' -ArgumentList $installArgs
        if ($installExitCode -ne 0) {
            [Logger]::WriteWarning("winget install exited with code $installExitCode for package: $package.")
        }
    }
    [Logger]::WriteSuccess("Installed winget apps...")
}

Export-ModuleMember -Function Invoke-RunAsAdmin, Register-ScheduledTasks, Unregister-RebootTask, Install-WSLPlatform, Install-WSLDistroIfMissing, Invoke-WSLDotfilesSetup, Invoke-WSLDecryption, New-Symlink, New-SymlinkTree, Remove-WingetApps, Update-WingetApps, Install-WingetApps
