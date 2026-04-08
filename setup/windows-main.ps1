[CmdletBinding()]
param(
    [string]$ResumeLogPath,
    [Nullable[bool]]$InstallOptionalWingetApps,
    [Nullable[bool]]$SetupSyncthing,
    [Nullable[bool]]$SetupBackupTask
)

$ErrorActionPreference = 'Stop'

function Invoke-RunAsAdmin {
    $current = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($current)

    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        if (-not $PSCommandPath) {
            throw 'Cannot determine script path for elevation. Please run the script from a file.'
        }

        $arg = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath)
        if ($ResumeLogPath) {
            $arg += '-ResumeLogPath'
            $arg += $ResumeLogPath
        }
        if ($null -ne $InstallOptionalWingetApps) {
            $arg += '-InstallOptionalWingetApps'
            $arg += $InstallOptionalWingetApps
        }
        if ($null -ne $SetupSyncthing) {
            $arg += '-SetupSyncthing'
            $arg += $SetupSyncthing
        }
        if ($null -ne $SetupBackupTask) {
            $arg += '-SetupBackupTask'
            $arg += $SetupBackupTask
        }

        # Remove any potential nulls (safe argument list)
        $arg = $arg | Where-Object { $_ -ne $null }

        Start-Process -FilePath 'powershell.exe' -ArgumentList $arg -Verb RunAs
        exit
    }
}

$DotfilesFolder = Join-Path $env:USERPROFILE '.dotfiles'

if ($ResumeLogPath) {
    $Script:LogFileActive = $ResumeLogPath
}
else {
    $Timestamp = (Get-Date).ToString('yyyyMMdd_HHmmss')
    $Script:LogFileActive = Join-Path $DotfilesFolder "setup_$Timestamp.log"
}

function Initialize-Logging {
    if (-not (Test-Path $DotfilesFolder)) {
        $null = New-Item -ItemType Directory -Path $DotfilesFolder -Force
    }

    if (-not (Test-Path $LogFileActive)) {
        $null = New-Item -ItemType File -Path $LogFileActive -Force
    }
}

function Write-Log {
    param(
        [ValidateSet('INFO', 'SUCCESS', 'WARNING', 'ERROR')][string]$Level,
        [string]$Message
    )

    $colorMap = @{
        INFO    = 'Cyan'
        SUCCESS = 'Green'
        WARNING = 'Yellow'
        ERROR   = 'Red'
    }

    $color = $colorMap[$Level]
    $timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $formatted = "[$timestamp] [$Level] $Message"

    Add-Content -Path $Script:LogFileActive -Value $formatted -Encoding utf8
    Write-Host $formatted -ForegroundColor $color
}

function Write-Info { param([string]$Message) Write-Log -Level INFO -Message $Message }
function Write-Success { param([string]$Message) Write-Log -Level SUCCESS -Message $Message }
function Write-WarningLog { param([string]$Message) Write-Log -Level WARNING -Message $Message }
function Write-ErrorLog { param([string]$Message) Write-Log -Level ERROR -Message $Message }

function Read-LoggedHost {
    param([string]$Prompt)

    if ($Prompt) {
        Add-Content -Path $Script:LogFileActive -Value $Prompt -Encoding utf8
    }

    return Read-Host $Prompt
}

function Get-SetupPreferenceValue {
    param(
        [Nullable[bool]]$CurrentValue,
        [string]$Prompt
    )

    if ($null -ne $CurrentValue) {
        return [bool]$CurrentValue
    }

    $response = Read-LoggedHost $Prompt
    return ($response -match '^(?i:y|yes)$')
}

function ConvertTo-BooleanString {
    param([bool]$Value)

    if ($Value) {
        return 'true'
    }

    return 'false'
}

function Write-ProcessOutput {
    param(
        [string[]]$Lines,
        [switch]$Silent
    )

    if (-not $Lines) {
        return
    }

    foreach ($line in $Lines) {
        $text = $line -replace "`0", ''
        if ([string]::IsNullOrWhiteSpace($text)) {
            continue
        }

        Add-Content -Path $Script:LogFileActive -Value $text -Encoding utf8
        if (-not $Silent) {
            Write-Host $text
        }
    }
}

function Invoke-NativeProcess {
    param(
        [string]$Description,
        [string]$FilePath,
        [string[]]$ArgumentList = @(),
        [switch]$AllowFailure,
        [switch]$Silent
    )

    if (-not $FilePath) {
        throw 'Invoke-NativeProcess requires a file path to execute.'
    }

    $tempDir = Join-Path $env:TEMP ("dotfiles-native-{0}" -f ([guid]::NewGuid()))
    $stdoutPath = Join-Path $tempDir 'stdout.log'
    $stderrPath = Join-Path $tempDir 'stderr.log'
    $stdoutLines = @()
    $stderrLines = @()
    $exitCode = 0

    try {
        $null = New-Item -ItemType Directory -Path $tempDir -Force
        $process = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -Wait -PassThru -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
        $exitCode = $process.ExitCode

        if (Test-Path -LiteralPath $stdoutPath) {
            $stdoutLines = @(Get-Content -LiteralPath $stdoutPath)
        }
        if (Test-Path -LiteralPath $stderrPath) {
            $stderrLines = @(Get-Content -LiteralPath $stderrPath)
        }

        Write-ProcessOutput -Lines $stdoutLines -Silent:$Silent
        Write-ProcessOutput -Lines $stderrLines -Silent:$Silent
    }
    finally {
        if (Test-Path -LiteralPath $tempDir) {
            Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    if (-not $AllowFailure -and $exitCode -ne 0) {
        $combinedOutput = @($stdoutLines + $stderrLines) -join [Environment]::NewLine
        if ($combinedOutput) {
            throw "$Description failed with exit code $exitCode. Output: $combinedOutput"
        }

        throw "$Description failed with exit code $exitCode"
    }

    return [pscustomobject]@{
        ExitCode = $exitCode
        StdOut   = $stdoutLines
        StdErr   = $stderrLines
    }
}

function Get-CombinedProcessOutput {
    param([object]$Result)

    return @($Result.StdOut + $Result.StdErr)
}

function Test-IsExpectedWingetMiss {
    param([object]$Result)

    if (-not $Result -or $Result.ExitCode -eq 0) {
        return $false
    }

    $combinedOutput = (Get-CombinedProcessOutput -Result $Result) -join "`n"
    return $combinedOutput -match 'No (installed )?package found matching input criteria'
}

function Get-WslUnixPath {
    param(
        [string]$DistroName,
        [string]$WindowsPath
    )

    $result = Invoke-NativeProcess -Description "WSL path conversion for $WindowsPath" -FilePath 'wsl.exe' -ArgumentList @('-d', $DistroName, '-e', 'wslpath', '-u', $WindowsPath) -Silent
    $wslPath = (@($result.StdOut) -join "`n").Trim()
    if (-not $wslPath) {
        throw "Failed to convert Windows path to WSL path: $WindowsPath"
    }

    return $wslPath
}

function Escape-BashSingleQuotedString {
    param([string]$Value)

    return $Value.Replace("'", "'\''")
}

function Test-IsInteractiveSession {
    return (-not $ResumeLogPath) -and [Environment]::UserInteractive -and ($Host.Name -eq 'ConsoleHost')
}

function Invoke-WithRetries {
    param(
        [string]$Description,
        [int]$MaxAttempts = 3,
        [scriptblock]$Action,
        [scriptblock]$OnRetry
    )

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

        if ($OnRetry) {
            & $OnRetry $attempt $MaxAttempts $lastError
        }

        if ($attempt -lt $MaxAttempts) {
            $remaining = $MaxAttempts - $attempt
            Write-WarningLog "$Description failed. $remaining attempt(s) remaining."
        }
    }

    throw "$Description failed after $MaxAttempts attempts. Last error: $lastError"
}

function Install-WSLPlatform {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [string]$RebootTaskName,
        [string]$ScriptPath,
        [bool]$InstallOptionalWingetApps,
        [bool]$SetupSyncthing,
        [bool]$SetupBackupTask
    )

    if (-not (Get-Command 'wsl.exe' -ErrorAction SilentlyContinue)) {
        $isInstalled = $false
    }
    else {
        $statusResult = Invoke-NativeProcess -Description 'WSL status check' -FilePath 'wsl.exe' -ArgumentList @('--status') -AllowFailure -Silent
        $isInstalled = ($statusResult.ExitCode -eq 0)
    }

    if (-not $isInstalled) {
        if ($PSCmdlet.ShouldProcess('WSL', 'Install platform')) {
            Write-Info 'WSL platform is not installed; installing now (platform only)...'
            $null = Invoke-NativeProcess -Description 'WSL platform installation' -FilePath 'wsl.exe' -ArgumentList @('--install', '--no-distribution')
                
            Register-RebootTask -TaskName $RebootTaskName -ScriptPath $ScriptPath -InstallOptionalWingetApps $InstallOptionalWingetApps -SetupSyncthing $SetupSyncthing -SetupBackupTask $SetupBackupTask
            Write-Info 'Rebooting to continue setup...'
            Restart-Computer
        }
    }
}

function Install-WSLDistroIfMissing {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param([string]$DistroName)

    $installed = $false
    $listResult = Invoke-NativeProcess -Description 'WSL distro list' -FilePath 'wsl.exe' -ArgumentList @('--list', '--quiet') -AllowFailure -Silent
    if ($listResult.ExitCode -eq 0 -and ($listResult.StdOut | ForEach-Object { "$_".Trim() } | Where-Object { $_ -ieq $DistroName })) {
        $installed = $true
    }

    if (-not $installed) {
        if ($PSCmdlet.ShouldProcess($DistroName, 'Install WSL distro')) {
            Write-Info "Installing WSL distro: $DistroName"
            $null = Invoke-NativeProcess -Description "WSL distro installation ($DistroName)" -FilePath 'wsl.exe' -ArgumentList @('--install', '-d', $DistroName, '--no-launch')
            return $true
        }
    }

    Write-Info "WSL distro '$DistroName' already installed."
    return $false
}

function Invoke-WSLDotfilesSetup {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [string]$DistroName,
        [string]$DotfilesFolder,
        [string]$LogFileActive,
        [string]$ScriptRoot
    )

    if ($PSCmdlet.ShouldProcess($DistroName, 'Run dotfiles setup inside WSL')) {
        Write-Info 'Running dotfiles setup inside WSL...'
        $wslScriptDir = Get-WslUnixPath -DistroName $DistroName -WindowsPath $ScriptRoot
        $wslDotfilesFolder = Get-WslUnixPath -DistroName $DistroName -WindowsPath $DotfilesFolder
        $wslLogFile = Get-WslUnixPath -DistroName $DistroName -WindowsPath $LogFileActive

        $escapedDotfilesFolder = Escape-BashSingleQuotedString -Value $wslDotfilesFolder
        $escapedLogFile = Escape-BashSingleQuotedString -Value $wslLogFile
        $escapedScriptDir = Escape-BashSingleQuotedString -Value $wslScriptDir
        $bashCmd = "DOTFILES_FOLDER='$escapedDotfilesFolder' DOTFILES_LOG_FILE='$escapedLogFile' bash '$escapedScriptDir/arch-wsl-main.sh'"
        $null = Invoke-NativeProcess -Description 'Dotfiles setup inside WSL' -FilePath 'wsl.exe' -ArgumentList @('-d', $DistroName, '-e', 'bash', '-lc', $bashCmd)
        Write-Success 'Dotfiles setup completed inside WSL.'
    }
}

function Invoke-WSLSyncthingDecryption {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [string]$DistroName,
        [string]$DotfilesFolder,
        [bool]$Enabled = $true
    )

    if (-not $Enabled) {
        Write-Info 'Skipping Syncthing key decryption.'
        return
    }

    if ($PSCmdlet.ShouldProcess($DistroName, 'Decrypt Syncthing key inside WSL')) {
        Write-Info 'Decrypting Syncthing key...'
        $wslDotfilesFolder = Get-WslUnixPath -DistroName $DistroName -WindowsPath $DotfilesFolder
        $decryptAction = {
            $escapedSyncthingDir = Escape-BashSingleQuotedString -Value "$wslDotfilesFolder/syncthing"
            $bashCmd = "cd '$escapedSyncthingDir' && openssl aes-256-cbc -d -salt -pbkdf2 -iter 100000 -in 'key.pem.enc' -out 'key.pem' >/dev/null 2>&1"
            $result = Invoke-NativeProcess -Description 'Syncthing key decryption command' -FilePath 'wsl.exe' -ArgumentList @('-d', $DistroName, '-e', 'bash', '-c', $bashCmd) -AllowFailure -Silent
            if ($result.ExitCode -ne 0) {
                return $false
            }

            return $true
        }
        $cleanupAction = {
            param($Attempt, $MaxAttempts, $LastError)
            $escapedKeyPath = Escape-BashSingleQuotedString -Value "$wslDotfilesFolder/syncthing/key.pem"
            $null = Invoke-NativeProcess -Description 'Syncthing key cleanup' -FilePath 'wsl.exe' -ArgumentList @('-d', $DistroName, '-e', 'bash', '-c', "rm -f '$escapedKeyPath'") -AllowFailure -Silent
        }

        Invoke-WithRetries -Description 'Syncthing key decryption' -MaxAttempts 3 -Action $decryptAction -OnRetry $cleanupAction
        Write-Success 'Syncthing key decrypted.'
    }
}

function Register-RebootTask {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [string]$TaskName,
        [string]$ScriptPath,
        [bool]$InstallOptionalWingetApps,
        [bool]$SetupSyncthing,
        [bool]$SetupBackupTask
    )

    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        if ($PSCmdlet.ShouldProcess($TaskName, 'Unregister old scheduled task')) {
            Write-Info "Removing old scheduled task: $TaskName"
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        }
    }

    if ($PSCmdlet.ShouldProcess($TaskName, 'Register reboot scheduled task')) {
        $installOptionalWingetAppsArg = ConvertTo-BooleanString -Value $InstallOptionalWingetApps
        $setupSyncthingArg = ConvertTo-BooleanString -Value $SetupSyncthing
        $setupBackupTaskArg = ConvertTo-BooleanString -Value $SetupBackupTask
        $taskArgs = @(
            '-NoProfile',
            '-ExecutionPolicy', 'Bypass',
            '-File', "`"$ScriptPath`"",
            '-ResumeLogPath', "`"$Script:LogFileActive`"",
            '-InstallOptionalWingetApps', $installOptionalWingetAppsArg,
            '-SetupSyncthing', $setupSyncthingArg,
            '-SetupBackupTask', $setupBackupTaskArg
        )
        $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ($taskArgs -join ' ')
        $trigger = New-ScheduledTaskTrigger -AtLogon -User $env:USERNAME
        Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -RunLevel 'Highest'

        Write-Info "Scheduled task registered: $TaskName"
    }
}

function Unregister-RebootTask {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param([string]$TaskName)

    if (-not (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue)) {
        return
    }

    if (-not $PSCmdlet.ShouldProcess($TaskName, 'Remove scheduled task')) {
        return
    }

    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Info "Removed scheduled task: $TaskName"
}

function New-Symlink {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [string]$Src,
        [string]$Tgt
    )

    if (-not $Src -or -not $Tgt) {
        Write-ErrorLog "New-Symlink requires -Src and -Tgt arguments"
        return
    }

    if (-not $PSCmdlet.ShouldProcess($Tgt, "Create or update symbolic link to $Src")) {
        return
    }

    if (-not (Test-Path -Path $Src)) {
        Write-WarningLog "Source does not exist: $Src"
        return
    }

    if (Test-Path -LiteralPath $Tgt) {
        $item = Get-Item -LiteralPath $Tgt -Force
        $isLink = ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0

        if ($isLink) {
            $currentTarget = $item.Target 2>$null
            if ($currentTarget -and $currentTarget -eq $Src) {
                Write-Info "Symlink already correct: $Tgt -> $Src"
                return
            }

            Remove-Item -LiteralPath $Tgt -Force
        }
        else {
            Write-WarningLog "Target exists and is not a symlink; skipping: $Tgt"
            return
        }
    }

    $tgtDir = Split-Path -Parent $Tgt
    if (-not (Test-Path $tgtDir)) {
        $null = New-Item -ItemType Directory -Path $tgtDir -Force
    }

    $null = New-Item -ItemType SymbolicLink -Path $Tgt -Target $Src -Force
    Write-Success "Linked $Tgt -> $Src"
}

function New-SymlinkTree {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [string]$Src,
        [string]$Tgt
    )

    if (-not (Test-Path -Path $Src -PathType Container)) {
        Write-WarningLog "Source directory does not exist: $Src"
        return
    }

    Get-ChildItem -Path $Src -File -Recurse | ForEach-Object {
        $relPath = $_.FullName.Substring($Src.TrimEnd('\').Length + 1)
        $tgtFile = Join-Path $Tgt $relPath
        New-Symlink -Src $_.FullName -Tgt $tgtFile
    }
}

function Register-SetupScheduledTasks {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [array]$ScheduledTaskCommands
    )

    Write-Info "Creating scheduled tasks..."

    foreach ($task in $ScheduledTaskCommands) {
        if (-not $task.Enabled) {
            if (Get-ScheduledTask -TaskName $task.Name -ErrorAction SilentlyContinue) {
                if ($PSCmdlet.ShouldProcess($task.Name, 'Remove disabled scheduled task')) {
                    Unregister-ScheduledTask -TaskName $task.Name -Confirm:$false
                    Write-Info "Removed disabled scheduled task: $($task.Name)"
                }
            }

            Write-Info "Skipping scheduled task: $($task.Name)"
            continue
        }

        $canRegister = $true
        if (Get-ScheduledTask -TaskName $task.Name -ErrorAction SilentlyContinue) {
            if ($PSCmdlet.ShouldProcess($task.Name, 'Replace scheduled task')) {
                Unregister-ScheduledTask -TaskName $task.Name -Confirm:$false
            }
            else {
                $canRegister = $false
            }
        }

        if (-not $canRegister -or -not $PSCmdlet.ShouldProcess($task.Name, 'Register scheduled task')) {
            continue
        }

        $null = Register-ScheduledTask -TaskName $task.Name -Action $task.Action -Trigger $task.Trigger -RunLevel $task.RunLevel
        Write-Success "Registered scheduled task: $($task.Name)"
    }
}

function Test-AppInstalled {
    param(
        [scriptblock]$InstalledCheck
    )

    if (-not $InstalledCheck) {
        return $false
    }

    try {
        return & $InstalledCheck
    }
    catch {
        Write-WarningLog "Installed check failed: $($_.Exception.Message)"
        return $false
    }
}

function Install-WingetApps {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [bool]$InstallOptionalApps
    )

    $primary = @(
        '7zip.7zip',
        'voidtools.Everything.Alpha',
        'Mozilla.Firefox',
        'RARLab.WinRAR',
        'Zen-Team.Zen-Browser',
        'NordSecurity.NordVPN',
        'Google.GoogleDrive',
        'PDFgear.PDFgear',
        'WinDirStat.WinDirStat',
        'Google.Chrome',
        'Klocman.BulkCrapUninstaller',
        'wez.wezterm',
        'EaseUS.TodoBackup',
        'Parsec.Parsec',
        'FlorianHeidenreich.Mp3tag',
        'BleachBit.BleachBit',
        'Discord.Discord',
        'FastCopy.FastCopy',
        'Obsidian.Obsidian',
        'Microsoft.VisualStudioCode',
        'Microsoft.PowerToys',
        '9NKSQGP7F2NH'
    )
    $additional = @(
        'Logitech.GHUB',
        'Corsair.iCUE.5',
        'RockstarGames.Launcher',
        'Valve.Steam',
        'Ubisoft.Connect',
        'EpicGames.EpicGamesLauncher',
        'GOG.Galaxy',
        'ElectronicArts.EADesktop',
        'Playnite.Playnite',
        'ItchIo.Itch',
        'Amazon.Games',
        'XPDM5VSMTKQLBJ',
        '9NVMNJCR03XV',
        'Syncthing.Syncthing'
    )
    $preinstalledPackagesToRemove = @(
        'MSIX\Clipchamp.Clipchamp_4.3.10120.0_x64__yxz26nhyzhsrt',
        'MSIX\Microsoft.BingNews_1.0.2.0_x64__8wekyb3d8bbwe',
        'MSIX\Microsoft.BingSearch_1.1.43.0_x64__8wekyb3d8bbwe',
        'MSIX\Microsoft.BingWeather_3.2.10.0_x64__8wekyb3d8bbwe',
        'MSIX\Microsoft.GetHelp_10.2407.22193.0_x64__8wekyb3d8bbwe',
        'MSIX\Microsoft.MicrosoftEdge.Stable_140.0.3485.66_neutral__8wekyb3d8bbwe',
        'MSIX\Microsoft.MicrosoftSolitaireCollection_4.22.3190.0_x64__8wekyb3d8bbwe',
        'MSIX\Microsoft.MicrosoftStickyNotes_4.0.6105.0_x64__8wekyb3d8bbwe',
        'MSIX\Microsoft.PowerAutomateDesktop_1.0.1420.0_x64__8wekyb3d8bbwe',
        'MSIX\Microsoft.StartExperiencesApp_1.1.200.0_x64__8wekyb3d8bbwe',
        'MSIX\Microsoft.StorePurchaseApp_22408.1400.1.0_x64__8wekyb3d8bbwe',
        'MSIX\Microsoft.Todos_0.120.7961.0_x64__8wekyb3d8bbwe',
        'MSIX\Microsoft.WidgetsPlatformRuntime_1.6.2.0_x64__8wekyb3d8bbwe',
        'MSIX\Microsoft.WindowsCamera_2025.2505.2.0_x64__8wekyb3d8bbwe',
        'MSIX\Microsoft.WindowsFeedbackHub_1.2401.20253.0_x64__8wekyb3d8bbwe',
        'MSIX\Microsoft.WindowsSoundRecorder_1.1.5.0_x64__8wekyb3d8bbwe',
        'MSIX\MicrosoftCorporationII.QuickAssist_2.0.35.0_x64__8wekyb3d8bbwe'
    )

    Write-Info "Remove garbage ..."
    foreach ($package in $preinstalledPackagesToRemove) {
        Write-Info "Removing package: $package"
        $removeResult = Invoke-NativeProcess -Description "winget remove ($package)" -FilePath 'winget.exe' -ArgumentList @('remove', '--all', '--exact', '--silent', '--nowarn', '--purge', '--force', '--disable-interactivity', '--accept-source-agreements', '--source', 'winget', $package) -AllowFailure -Silent
        if (Test-IsExpectedWingetMiss -Result $removeResult) {
            Write-Info "Package not present, skipping removal: $package"
            continue
        }
        if ($removeResult.ExitCode -ne 0) {
            throw "winget remove preinstalled app failed for $package with exit code $($removeResult.ExitCode)"
        }
    }
    Write-Success "Garbage removed..."

    Write-Info 'Installing updates...'
    $updateResult = Invoke-NativeProcess -Description 'winget update' -FilePath 'winget.exe' -ArgumentList @('update', '--all', '--silent', '--disable-interactivity', '--accept-package-agreements', '--accept-source-agreements') -AllowFailure -Silent
    if ($updateResult.ExitCode -eq 0) {
        Write-Success "Updates installed..."
    }
    else {
        Write-WarningLog "winget update exited with code $($updateResult.ExitCode). Continuing setup."
    }

    Write-Info 'Installing winget applications...'

    if ($PSCmdlet.ShouldProcess('Primary Winget Apps', 'Install')) {
        Write-Info 'Installing primary winget apps...'
        foreach ($package in $primary) {
            Write-Info "Installing primary package: $package"
            $null = Invoke-NativeProcess -Description "winget install ($package)" -FilePath 'winget.exe' -ArgumentList @('install', '--exact', '--silent', '--disable-interactivity', '--accept-package-agreements', '--accept-source-agreements', $package) -Silent
        }
        Write-Success "Installed primary winget apps..."
    }

    if ($InstallOptionalApps) {
        if ($PSCmdlet.ShouldProcess('Optional Winget Apps', 'Install')) {
            Write-Info 'Installing optional winget apps...'
            foreach ($package in $additional) {
                Write-Info "Installing optional package: $package"
                $null = Invoke-NativeProcess -Description "winget install ($package)" -FilePath 'winget.exe' -ArgumentList @('install', '--exact', '--silent', '--disable-interactivity', '--accept-package-agreements', '--accept-source-agreements', $package) -Silent
            }
            Write-Success "Installed optional winget apps..."
        }
    }
    else {
        Write-Info 'Skipping optional winget apps.'
    }
}

function Install-NonWingetApps {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [array]$NonWingetApps
    )

    if (-not $NonWingetApps -or $NonWingetApps.Count -eq 0) {
        return
    }

    Write-Info 'Installing non-winget applications...'

    $tempDir = Join-Path $env:TEMP 'dotfiles-nonwinget'
    $null = New-Item -ItemType Directory -Path $tempDir -Force

    foreach ($app in $NonWingetApps) {
        if (-not $app.Enabled) { continue }

        if (-not $PSCmdlet.ShouldProcess($app.Name, 'Install non-winget application')) {
            continue
        }

        Write-Info "Processing non-winget app: $($app.Name)"

        if ($app.InstalledCheck -and (Test-AppInstalled -InstalledCheck $app.InstalledCheck)) {
            Write-Info "Already installed: $($app.Name)"
            continue
        }

        $installerPath = $null
        $zipPath = $null
        $extractDir = $null

        try {
            switch ($app.Type) {
                'DirectExe' {
                    $installerName = if ($app.InstallerFileName) { $app.InstallerFileName } else { [IO.Path]::GetFileName($app.Uri) }
                    $installerPath = Join-Path $tempDir $installerName

                    Write-Info "Downloading installer to: $installerPath"
                    Invoke-WebRequest -Uri $app.Uri -OutFile $installerPath -UseBasicParsing

                    Write-Info "Running installer..."
                    $installerArgs = @()
                    if ($app.InstallerArgs) {
                        $installerArgs = @($app.InstallerArgs)
                    }
                    $null = Invoke-NativeProcess -Description "Installer for $($app.Name)" -FilePath $installerPath -ArgumentList $installerArgs
                }
                'ZipInstall' {
                    $zipName = if ($app.ZipName) { $app.ZipName } else { [IO.Path]::GetFileNameWithoutExtension($app.Uri) }
                    $zipPath = Join-Path $tempDir "$zipName.zip"
                    $extractDir = Join-Path $tempDir $zipName

                    Write-Info "Downloading zip to: $zipPath"
                    Invoke-WebRequest -Uri $app.Uri -OutFile $zipPath -UseBasicParsing

                    Write-Info "Extracting zip to: $extractDir"
                    Remove-Item -Path $extractDir -Recurse -Force -ErrorAction SilentlyContinue
                    Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force

                    if ($app.InstallerRelativePath) {
                        $installerPath = Join-Path $extractDir $app.InstallerRelativePath
                    }
                    else {
                        $installerPath = (Get-ChildItem -Path $extractDir -Filter '*.exe' -Recurse | Select-Object -First 1).FullName
                    }

                    if (-not $installerPath) { throw "No installer found in $extractDir" }

                    Write-Info "Running installer from zip: $installerPath"
                    $installerArgs = @()
                    if ($app.InstallerArgs) {
                        $installerArgs = @($app.InstallerArgs)
                    }
                    $null = Invoke-NativeProcess -Description "Installer for $($app.Name)" -FilePath $installerPath -ArgumentList $installerArgs
                }
                'RemoteScript' {
                    Write-Info "Executing remote script from $($app.Uri)"

                    $remoteScriptPath = Join-Path $tempDir "$($app.Name)-remote.ps1"
                    Invoke-WebRequest -Uri $app.Uri -OutFile $remoteScriptPath -UseBasicParsing

                    $null = Invoke-NativeProcess -Description "Remote script install for $($app.Name)" -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $remoteScriptPath)
                }
                default {
                    throw "Unknown non-winget app type: $($app.Type)"
                }
            }

            Write-Success "Installed $($app.Name)"
        }
        catch {
            Write-ErrorLog "Failed to install $($app.Name): $($_.Exception.Message)"
        }
        finally {
            if ($installerPath -and (Test-Path $installerPath)) {
                Remove-Item -Path $installerPath -Force -ErrorAction SilentlyContinue
            }
            if ($zipPath -and (Test-Path $zipPath)) {
                Remove-Item -Path $zipPath -Force -ErrorAction SilentlyContinue
            }
            if ($extractDir -and (Test-Path $extractDir)) {
                Remove-Item -Path $extractDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

# Variables
$RebootTaskName = 'ContinueSetupAfterReboot'
$WslDistroName = 'archlinux'

$NonWingetApps = @(
    @{ 
        Name              = 'Honeygain'
        Type              = 'DirectExe'
        Uri               = 'https://download.honeygain.com/windows-app/Honeygain_install.exe'
        InstallerFileName = 'honeygain.exe'
        Enabled           = $true
        InstalledCheck    = {
            $paths = @(
                "$env:ProgramFiles\Honeygain\Honeygain.exe",
                "$env:ProgramFiles(x86)\Honeygain\Honeygain.exe"
            )

            foreach ($path in $paths) {
                if (Test-Path $path) { return $true }
            }

            return $false
        }
    }
)

# Program flow
Invoke-RunAsAdmin
Initialize-Logging

try {
    Write-Info "Version: 1.5.6"
    $Script:InstallOptionalWingetApps = Get-SetupPreferenceValue -CurrentValue $InstallOptionalWingetApps -Prompt 'Do you want to install optional winget apps (gaming and additional tools)? (y/n)'
    $Script:SetupSyncthing = Get-SetupPreferenceValue -CurrentValue $SetupSyncthing -Prompt 'Do you want to set up Syncthing task registration and key decryption? (y/n)'
    $Script:SetupBackupTask = Get-SetupPreferenceValue -CurrentValue $SetupBackupTask -Prompt 'Do you want to set up the backup scheduled task? (y/n)'

    $ScheduledTaskCommands = @(
        @{ Name = 'WSL-Script_Logon'; Action = New-ScheduledTaskAction -Execute 'C:\Windows\System32\wscript.exe' -Argument '%USERPROFILE%\.dotfiles\wezterm\wezterm.vbs'; Trigger = New-ScheduledTaskTrigger -AtLogon -User $env:USERNAME; RunLevel = 'Highest'; Enabled = $true },
        @{ Name = 'Syncthing_Logon'; Action = New-ScheduledTaskAction -Execute 'syncthing' -Argument '--no-console --no-browser'; Trigger = New-ScheduledTaskTrigger -AtLogon -User $env:USERNAME; RunLevel = 'Highest'; Enabled = $Script:SetupSyncthing },
        @{ Name = 'Backup-Script_Daily'; Action = New-ScheduledTaskAction -Execute 'C:\Windows\System32\wscript.exe' -Argument '%USERPROFILE%\.dotfiles\backup\backup.vbs'; Trigger = New-ScheduledTaskTrigger -Daily -At 8pm; RunLevel = 'Highest'; Enabled = $Script:SetupBackupTask }
    )

    Install-WSLPlatform -RebootTaskName $RebootTaskName -ScriptPath $PSCommandPath -InstallOptionalWingetApps $Script:InstallOptionalWingetApps -SetupSyncthing $Script:SetupSyncthing -SetupBackupTask $Script:SetupBackupTask
    $null = Install-WSLDistroIfMissing -DistroName $WslDistroName

    Install-WingetApps -InstallOptionalApps $Script:InstallOptionalWingetApps
    Install-NonWingetApps -NonWingetApps $NonWingetApps

    Invoke-WSLDotfilesSetup -DistroName $WslDistroName -DotfilesFolder $DotfilesFolder -LogFileActive $LogFileActive -ScriptRoot $PSScriptRoot
    Invoke-WSLSyncthingDecryption -DistroName $WslDistroName -DotfilesFolder $DotfilesFolder -Enabled $Script:SetupSyncthing

    Write-Info 'Creating symbolic links...'
    New-Symlink -Src "$env:USERPROFILE\.dotfiles\wezterm\.wezterm.lua" -Tgt "$env:USERPROFILE\.wezterm.lua"
    New-SymlinkTree -Src "$env:USERPROFILE\.dotfiles\.ssh" -Tgt "$env:USERPROFILE\.ssh"
    New-SymlinkTree -Src "$env:USERPROFILE\.dotfiles\syncthing" -Tgt "$env:LOCALAPPDATA\Syncthing"

    Register-SetupScheduledTasks -ScheduledTaskCommands $ScheduledTaskCommands

    Write-Success 'Windows setup completed successfully.'
}
catch {
    Write-ErrorLog "An error occurred: $($_.Exception.Message)"
    Write-ErrorLog "Stack trace: $($_.ScriptStackTrace)"
    throw
}
finally {
    Unregister-RebootTask -TaskName $RebootTaskName
    if (Test-IsInteractiveSession) {
        $null = Read-LoggedHost 'Press Enter to close'
    }
}
