$ErrorActionPreference = 'Stop'

function Invoke-RunAsAdmin {
    $current = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($current)

    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        if (-not $PSCommandPath) {
            throw 'Cannot determine script path for elevation. Please run the script from a file.'
        }

        $arg = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath)

        # Remove any potential nulls (safe argument list)
        $arg = $arg | Where-Object { $_ -ne $null }

        Start-Process -FilePath 'powershell.exe' -ArgumentList $arg -Verb RunAs
        exit
    }
}

# Setup logging variables
$DotfilesFolder = Join-Path $env:USERPROFILE '.dotfiles'
$Timestamp = (Get-Date).ToString('yyyyMMdd_HHmmss')
$LogFileTemp = Join-Path $env:WINDIR "Temp\setup_$Timestamp.log"
$LogFileFinal = Join-Path $DotfilesFolder ("setup_$Timestamp.log")

$WslDotfilesFolder = "/mnt/c/Users/$env:USERNAME/.dotfiles"
$WslLogFileTemp = "/mnt/c/Windows/Temp/setup_$Timestamp.log"
$WslLogFileFinal = "$WslDotfilesFolder/setup_$Timestamp.log"

$LogFileActive = $null

function Initialize-Logging {
    if ((Test-Path $DotfilesFolder) -and (Test-Path "$DotfilesFolder\.git")) {
        $Script:LogFileActive = $LogFileFinal
    }
    else {
        $Script:LogFileActive = $LogFileTemp
    }

    $logDir = Split-Path $LogFileActive -Parent
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }

    if (-not (Test-Path $LogFileActive)) {
        New-Item -ItemType File -Path $LogFileActive -Force | Out-Null
    }
}

function Complete-Logging {
    if (-not (Test-Path $DotfilesFolder)) {
        return
    }

    if ($LogFileActive -eq $LogFileTemp) {
        if (Test-Path $LogFileFinal) {
            $Script:LogFileActive = $LogFileFinal
        }
        elseif (Test-Path $LogFileTemp) {
            $finalDir = Split-Path $LogFileFinal -Parent
            if (-not (Test-Path $finalDir)) {
                New-Item -ItemType Directory -Path $finalDir -Force | Out-Null
            }

            Get-Content -Path $LogFileTemp | Add-Content -Path $LogFileFinal
            Remove-Item -Path $LogFileTemp -ErrorAction SilentlyContinue
            
            $Script:LogFileActive = $LogFileFinal
            Write-Info "Merged temp log into: $LogFileFinal"
        }
        else {
            $Script:LogFileActive = $LogFileFinal
        }
    }
}

function Write-Log {
    param(
        [ValidateSet('INFO', 'SUCCESS', 'WARNING', 'ERROR')][string]$Level,
        [string]$Message
    )

    if (-not $LogFileActive) {
        Initialize-Logging
    }

    $esc = [char]27
    $colorMap = @{
        INFO    = "$esc[36m"
        SUCCESS = "$esc[32m"
        WARNING = "$esc[33m"
        ERROR   = "$esc[31m"
        RESET   = "$esc[0m"
    }

    $color = $colorMap[$Level]
    $timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $formatted = "[$Level] $Message"

    Add-Content -Path $LogFileActive -Value "[$timestamp] $formatted"
    Write-Output "${color}${formatted}$($colorMap['RESET'])"
}

function Write-Info { param([string]$Message) Write-Log -Level INFO -Message $Message }
function Write-Success { param([string]$Message) Write-Log -Level SUCCESS -Message $Message }
function Write-WarningLog { param([string]$Message) Write-Log -Level WARNING -Message $Message }
function Write-ErrorLog { param([string]$Message) Write-Log -Level ERROR -Message $Message }

function Install-WSLPlatform {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [string]$RebootTaskName,
        [string]$ScriptPath
    )

    $isInstalled = $true
    try {
        $null = wsl --status 2>&1
    }
    catch {
        $isInstalled = $false
    }

    if (-not $isInstalled) {
        if ($PSCmdlet.ShouldProcess('WSL', 'Install platform')) {
            Write-Info 'WSL platform is not installed; installing now (platform only)...'
            wsl --install --no-distribution
                
            Register-RebootTask -TaskName $RebootTaskName -ScriptPath $ScriptPath
            Write-Info 'Rebooting to continue setup...'
            Restart-Computer
        }
    }
}

function Install-WSLDistroIfMissing {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param([string]$DistroName)

    $installed = $false
    $listOutput = wsl --list --quiet 2>&1
    if ($listOutput | ForEach-Object { "$_".Trim() } | Where-Object { $_ -ieq $DistroName }) {
        $installed = $true
    }

    if (-not $installed) {
        if ($PSCmdlet.ShouldProcess($DistroName, 'Install WSL distro')) {
            Write-Info "Installing WSL distro: $DistroName"
            wsl --install -d $DistroName --no-launch
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
        [string]$WslDotfilesFolder,
        [string]$WslLogFileFinal,
        [string]$WslLogFileTemp,
        [string]$ScriptRoot
    )

    if ($PSCmdlet.ShouldProcess($DistroName, 'Run dotfiles setup inside WSL')) {
        Write-Info 'Running dotfiles setup inside WSL...'
        $wslScriptDir = (wsl -d $DistroName -e wslpath -u $ScriptRoot).Trim()
        if ($LASTEXITCODE -ne 0 -or -not $wslScriptDir) { throw "Failed to convert ScriptRoot ($ScriptRoot) to WSL path (Exit Code: $LASTEXITCODE)" }

        $bashCmd = "DOTFILES_FOLDER='$WslDotfilesFolder' DOTFILES_LOG_FILE='$WslLogFileFinal' DOTFILES_TEMP_LOG_FILE='$WslLogFileTemp' bash '$wslScriptDir/arch-wsl-main.sh'"
        wsl -d $DistroName -e bash -c $bashCmd
        if ($LASTEXITCODE -ne 0) { throw "Dotfiles setup inside WSL failed with exit code $LASTEXITCODE" }
        # wsl --shutdown
        Write-Success 'Dotfiles setup completed inside WSL.'
    }
}

function Invoke-WSLSyncthingDecryption {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [string]$DistroName,
        [string]$DotfilesWslPath
    )

    if ($PSCmdlet.ShouldProcess($DistroName, 'Decrypt Syncthing key inside WSL')) {
        Write-Info 'Decrypting Syncthing key...'
        $bashCmd = "cd '$DotfilesWslPath/syncthing' && openssl aes-256-cbc -d -salt -pbkdf2 -iter 100000 -in 'key.pem.enc' -out 'key.pem'"
        wsl -d $DistroName -e bash -c $bashCmd
        if ($LASTEXITCODE -ne 0) { throw "Syncthing key decryption failed with exit code $LASTEXITCODE" }
        Write-Success 'Syncthing key decrypted.'
    }
}

function Register-RebootTask {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [string]$TaskName,
        [string]$ScriptPath
    )

    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        if ($PSCmdlet.ShouldProcess($TaskName, 'Unregister old scheduled task')) {
            Write-Info "Removing old scheduled task: $TaskName"
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        }
    }

    if ($PSCmdlet.ShouldProcess($TaskName, 'Register reboot scheduled task')) {
        $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""
        $trigger = New-ScheduledTaskTrigger -AtLogon -User $env:USERNAME
        Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -RunLevel 'Highest'

        Write-Info "Scheduled task registered: $TaskName"
    }
}

function Remove-RebootTask {
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
        New-Item -ItemType Directory -Path $tgtDir -Force | Out-Null
    }

    New-Item -ItemType SymbolicLink -Path $Tgt -Target $Src -Force | Out-Null
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

function Register-SetupScheduledTask {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [array]$ScheduledTaskCommands
    )

    Write-Info "Creating scheduled tasks..."

    foreach ($task in $ScheduledTaskCommands) {
        if (Get-ScheduledTask -TaskName $task.Name -ErrorAction SilentlyContinue) {
            Write-Info "Scheduled task already exists: $($task.Name)"
            continue
        }

        if (-not $PSCmdlet.ShouldProcess($task.Name, 'Register scheduled task')) {
            continue
        }

        $null = Register-ScheduledTask -TaskName $task.Name -Action $task.Action -Trigger $task.Trigger -RunLevel $task.RunLevel
        Write-Success "Registered scheduled task: $($task.Name)"
    }
}

function Test-IsAppInstalled {
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
    param()

    #$primary = '7zip.7zip', 'voidtools.Everything.Alpha', 'Mozilla.Firefox', 'RARLab.WinRAR', 'Zen-Team.Zen-Browser', 'NordSecurity.NordVPN', 'Google.GoogleDrive', 'PDFgear.PDFgear', 'WinDirStat.WinDirStat', 'Google.Chrome', 'Klocman.BulkCrapUninstaller', 'wez.wezterm', 'EaseUS.TodoBackup', 'Parsec.Parsec', 'FlorianHeidenreich.Mp3tag', 'BleachBit.BleachBit', 'Discord.Discord', 'FastCopy.FastCopy', 'Obsidian.Obsidian', 'ZedIndustries.Zed', 'Codeium.Windsurf', 'Microsoft.VisualStudioCode', 'Google.Antigravity', 'Anysphere.Cursor', 'Microsoft.PowerToys', '9NKSQGP7F2NH'
    #$additional = 'Logitech.GHUB', 'Corsair.iCUE.5', 'RockstarGames.Launcher', 'Valve.Steam', 'Ubisoft.Connect', 'EpicGames.EpicGamesLauncher', 'GOG.Galaxy', 'ElectronicArts.EADesktop', 'Playnite.Playnite', 'ItchIo.Itch', 'Amazon.Games', 'XPDM5VSMTKQLBJ', '9NVMNJCR03XV', 'Syncthing.Syncthing'

    $primary = '7zip.7zip'
    $additional = 'voidtools.Everything.Alpha'

    Write-Info "Remove garbage ..."
    winget remove --all --exact --silent --nowarn --disable-interactivity --accept-source-agreements MSIX\Clipchamp.Clipchamp_4.3.10120.0_x64__yxz26nhyzhsrt MSIX\Microsoft.BingNews_1.0.2.0_x64__8wekyb3d8bbwe MSIX\Microsoft.BingSearch_1.1.43.0_x64__8wekyb3d8bbwe MSIX\Microsoft.BingWeather_3.2.10.0_x64__8wekyb3d8bbwe MSIX\Microsoft.GetHelp_10.2407.22193.0_x64__8wekyb3d8bbwe MSIX\Microsoft.MicrosoftEdge.Stable_140.0.3485.66_neutral__8wekyb3d8bbwe MSIX\Microsoft.MicrosoftSolitaireCollection_4.22.3190.0_x64__8wekyb3d8bbwe MSIX\Microsoft.MicrosoftStickyNotes_4.0.6105.0_x64__8wekyb3d8bbwe MSIX\Microsoft.PowerAutomateDesktop_1.0.1420.0_x64__8wekyb3d8bbwe MSIX\Microsoft.StartExperiencesApp_1.1.200.0_x64__8wekyb3d8bbwe MSIX\Microsoft.StorePurchaseApp_22408.1400.1.0_x64__8wekyb3d8bbwe MSIX\Microsoft.Todos_0.120.7961.0_x64__8wekyb3d8bbwe MSIX\Microsoft.WidgetsPlatformRuntime_1.6.2.0_x64__8wekyb3d8bbwe MSIX\Microsoft.WindowsCamera_2025.2505.2.0_x64__8wekyb3d8bbwe MSIX\Microsoft.WindowsFeedbackHub_1.2401.20253.0_x64__8wekyb3d8bbwe MSIX\Microsoft.WindowsSoundRecorder_1.1.5.0_x64__8wekyb3d8bbwe MSIX\MicrosoftCorporationII.QuickAssist_2.0.35.0_x64__8wekyb3d8bbwe

    Write-Info 'Installing updates'
    #winget update --all --silent --disable-interactivity --accept-package-agreements --accept-source-agreements

    Write-Info 'Installing winget applications...'

    if ($PSCmdlet.ShouldProcess('Primary Winget Apps', 'Install')) {
        Write-Info 'Installing primary winget apps...'
        winget install --exact --silent --disable-interactivity --accept-package-agreements --accept-source-agreements $primary
    }

    $response = Read-Host "Do you want to install optional winget apps (gaming and additional tools)? (y/n)"
    if ($response -match '^y|yes$') {
        if ($PSCmdlet.ShouldProcess('Optional Winget Apps', 'Install')) {
            Write-Info 'Installing optional winget apps...'
            winget install --exact --silent --disable-interactivity --accept-package-agreements --accept-source-agreements $additional
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
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

    foreach ($app in $NonWingetApps) {
        if (-not $app.Enabled) { continue }

        if (-not $PSCmdlet.ShouldProcess($app.Name, 'Install non-winget application')) {
            continue
        }

        Write-Info "Processing non-winget app: $($app.Name)"

        if ($app.InstalledCheck -and (Test-IsAppInstalled -InstalledCheck $app.InstalledCheck)) {
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

                    $installerArgs = if ($app.InstallerArgs) { $app.InstallerArgs } else { $null }
                    Write-Info "Running installer..."
                    if ($installerArgs) {
                        Start-Process -FilePath $installerPath -ArgumentList $installerArgs -Wait -NoNewWindow
                    }
                    else {
                        Start-Process -FilePath $installerPath -Wait -NoNewWindow
                    }
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

                    $installerArgs = if ($app.InstallerArgs) { $app.InstallerArgs } else { $null }
                    Write-Info "Running installer from zip: $installerPath"
                    if ($installerArgs) {
                        Start-Process -FilePath $installerPath -ArgumentList $installerArgs -Wait -NoNewWindow
                    }
                    else {
                        Start-Process -FilePath $installerPath -Wait -NoNewWindow
                    }
                }
                'RemoteScript' {
                    Write-Info "Executing remote script from $($app.Uri)"

                    $remoteScriptPath = Join-Path $tempDir "$($app.Name)-remote.ps1"
                    Invoke-WebRequest -Uri $app.Uri -OutFile $remoteScriptPath -UseBasicParsing

                    & powershell -NoProfile -ExecutionPolicy Bypass -File $remoteScriptPath
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
$rebootTaskName = 'ContinueSetupAfterReboot'
$wslDistroName = 'archlinux'

$nonWingetApps = @(
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

$scheduledTaskCommands = @(
    @{ Name = 'WSL-Script_Logon'; Action = New-ScheduledTaskAction -Execute 'C:\Windows\System32\wscript.exe' -Argument '%USERPROFILE%\.dotfiles\wezterm\wezterm.vbs'; Trigger = New-ScheduledTaskTrigger -AtLogon -User $env:USERNAME; RunLevel = 'Highest' },
    @{ Name = 'Syncthing_Logon'; Action = New-ScheduledTaskAction -Execute 'syncthing' -Argument '--no-console --no-browser'; Trigger = New-ScheduledTaskTrigger -AtLogon -User $env:USERNAME; RunLevel = 'Highest' },
    @{ Name = 'Backup-Script_Daily'; Action = New-ScheduledTaskAction -Execute 'C:\Windows\System32\wscript.exe' -Argument '%USERPROFILE%\.dotfiles\backup\backup.vbs'; Trigger = New-ScheduledTaskTrigger -Daily -At 8pm; RunLevel = 'Highest' }
)

# Program flow
Invoke-RunAsAdmin
Initialize-Logging

try {
    Write-Info "Version: 1.3.9"
    Install-WSLPlatform -RebootTaskName $rebootTaskName -ScriptPath $PSCommandPath
    Install-WSLDistroIfMissing -DistroName $wslDistroName | Out-Null
    
    # Install-WingetApps
    # Install-NonWingetApps -NonWingetApps $nonWingetApps

    Invoke-WSLDotfilesSetup -DistroName $wslDistroName -WslDotfilesFolder $WslDotfilesFolder -WslLogFileFinal $WslLogFileFinal -WslLogFileTemp $WslLogFileTemp -ScriptRoot $PSScriptRoot
    Invoke-WSLSyncthingDecryption -DistroName $wslDistroName -DotfilesWslPath "/mnt/c/Users/$env:USERNAME/.dotfiles"

    Write-Info 'Creating symbolic links...'
    New-Symlink -Src "$env:USERPROFILE\.dotfiles\wezterm\.wezterm.lua" -Tgt "$env:USERPROFILE\.wezterm.lua"
    New-SymlinkTree -Src "$env:USERPROFILE\.dotfiles\.ssh" -Tgt "$env:USERPROFILE\.ssh"
    New-SymlinkTree -Src "$env:USERPROFILE\.dotfiles\syncthing" -Tgt "$env:LOCALAPPDATA\Syncthing"

    Register-SetupScheduledTask -ScheduledTaskCommands $scheduledTaskCommands

    Write-Success 'Windows setup completed successfully.'
}
catch {
    Write-ErrorLog "An error occurred: $($_.Exception.Message)"
    Write-ErrorLog "Stack trace: $($_.ScriptStackTrace)"
    throw
}
finally {
    Complete-Logging
    Remove-RebootTask -TaskName $rebootTaskName
    Read-Host 'Press Enter to close'
}
