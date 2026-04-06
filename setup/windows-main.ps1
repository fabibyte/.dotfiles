[CmdletBinding()]
param(
    [string]$ResumeLogPath
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

function ConvertTo-NativeArgumentString {
    param([string[]]$ArgumentList)

    if (-not $ArgumentList -or $ArgumentList.Count -eq 0) {
        return ''
    }

    $quotedArgs = foreach ($argument in $ArgumentList) {
        if ($null -eq $argument) {
            '""'
            continue
        }

        if ($argument -notmatch '[\s"]') {
            $argument
            continue
        }

        $escaped = $argument -replace '(\\*)"', '$1$1\"'
        $escaped = $escaped -replace '(\\+)$', '$1$1'
        '"' + $escaped + '"'
    }

    return ($quotedArgs -join ' ')
}

function Invoke-CommandLogged {
    param(
        [string]$Description,
        [string]$FilePath,
        [string[]]$ArgumentList = @(),
        [switch]$AllowFailure
    )

    if (-not $FilePath) {
        throw 'Invoke-CommandLogged requires a file path to execute.'
    }

    $utf8Encoding = New-Object System.Text.UTF8Encoding($false)
    $logWriter = New-Object System.IO.StreamWriter($Script:LogFileActive, $true, $utf8Encoding)

    try {
        & $FilePath @ArgumentList 2>&1 | ForEach-Object {
            $logText = $_.ToString() -replace "`0", ''
            $logWriter.WriteLine($logText)
            $logWriter.Flush()
            $_
        } | Out-Host

        $exitCode = $LASTEXITCODE
    }
    finally {
        $logWriter.Dispose()
    }

    if (-not $AllowFailure -and $exitCode -ne 0) {
        throw "$Description failed with exit code $exitCode"
    }

    return $exitCode
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
            $null = Invoke-CommandLogged -Description 'WSL platform installation' -FilePath 'wsl' -ArgumentList @('--install', '--no-distribution')
                
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
            $null = Invoke-CommandLogged -Description "WSL distro installation ($DistroName)" -FilePath 'wsl' -ArgumentList @('--install', '-d', $DistroName, '--no-launch')
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
        $wslScriptDir = (wsl -d $DistroName -e wslpath -u $ScriptRoot).Trim()
        if ($LASTEXITCODE -ne 0 -or -not $wslScriptDir) { throw "Failed to convert ScriptRoot ($ScriptRoot) to WSL path (Exit Code: $LASTEXITCODE)" }

        $wslDotfilesFolder = (wsl -d $DistroName -e wslpath -u $DotfilesFolder).Trim()
        $wslLogFile = (wsl -d $DistroName -e wslpath -u $LogFileActive).Trim()

        $bashCmd = "DOTFILES_FOLDER='$wslDotfilesFolder' DOTFILES_LOG_FILE='$wslLogFile' bash '$wslScriptDir/arch-wsl-main.sh'"
        wsl -d $DistroName -e bash -c $bashCmd
        if ($LASTEXITCODE -ne 0) { throw "Dotfiles setup inside WSL failed with exit code $LASTEXITCODE" }
        Write-Success 'Dotfiles setup completed inside WSL.'
    }
}

function Invoke-WSLSyncthingDecryption {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [string]$DistroName,
        [string]$DotfilesFolder
    )

    if ($PSCmdlet.ShouldProcess($DistroName, 'Decrypt Syncthing key inside WSL')) {
        Write-Info 'Decrypting Syncthing key...'
        $wslDotfilesFolder = (wsl -d $DistroName -e wslpath -u $DotfilesFolder).Trim()
        $decryptAction = {
            $bashCmd = "cd '$wslDotfilesFolder/syncthing' && openssl aes-256-cbc -d -salt -pbkdf2 -iter 100000 -in 'key.pem.enc' -out 'key.pem'  >/dev/null 2>&1"
            wsl -d $DistroName -e bash -c $bashCmd
            if ($LASTEXITCODE -ne 0) {
                return $false
            }

            return $true
        }
        $cleanupAction = {
            param($Attempt, $MaxAttempts, $LastError)
            wsl -d $DistroName -e bash -c "rm -f '$wslDotfilesFolder/syncthing/key.pem'"
        }

        Invoke-WithRetries -Description 'Syncthing key decryption' -MaxAttempts 3 -Action $decryptAction -OnRetry $cleanupAction
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
        $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`" -ResumeLogPath `"$Script:LogFileActive`""
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
    param()

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

    $primary = @(
        '7zip.7zip'
    )
    $additional = @(
        'voidtools.Everything.Alpha'
    )

    Write-Info "Remove garbage ..."
    foreach ($package in $preinstalledPackagesToRemove) {
        Write-Info "Removing package: $package"
    }
    $null = winget remove --all --exact --silent --nowarn --purge --force --disable-interactivity --accept-source-agreements --source winget $preinstalledPackagesToRemove > $null 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "winget remove preinstalled apps failed with exit code $LASTEXITCODE"
    }
    Write-Success "Garbage removed..."

    Write-Info 'Installing updates...'
    #winget update --all --silent --disable-interactivity --accept-package-agreements --accept-source-agreements
    Write-Success "Updates installed..."

    Write-Info 'Installing winget applications...'

    if ($PSCmdlet.ShouldProcess('Primary Winget Apps', 'Install')) {
        Write-Info 'Installing primary winget apps...'
        foreach ($package in $primary) {
            Write-Info "Installing primary package: $package"
        }
        #$null = winget install --exact --silent --disable-interactivity --accept-package-agreements --accept-source-agreements $primary > $null 2>&1
        #if ($LASTEXITCODE -ne 0) {
        #    throw "winget install primary apps failed with exit code $LASTEXITCODE"
        #}
        Write-Success "Installed primary winget apps..."
    }

    $response = Read-LoggedHost "Do you want to install optional winget apps (gaming and additional tools)? (y/n)"
    if ($response -match '^y|yes$') {
        if ($PSCmdlet.ShouldProcess('Optional Winget Apps', 'Install')) {
            Write-Info 'Installing optional winget apps...'
            foreach ($package in $additional) {
                Write-Info "Installing optional package: $package"
            }
            #$null = winget install --exact --silent --disable-interactivity --accept-package-agreements --accept-source-agreements $additional > $null 2>&1
            #if ($LASTEXITCODE -ne 0) {
            #    throw "winget install optional apps failed with exit code $LASTEXITCODE"
            #}
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

                    $null = Invoke-CommandLogged -Description "Remote script install for $($app.Name)" -FilePath 'powershell' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $remoteScriptPath)
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

$ScheduledTaskCommands = @(
    @{ Name = 'WSL-Script_Logon'; Action = New-ScheduledTaskAction -Execute 'C:\Windows\System32\wscript.exe' -Argument '%USERPROFILE%\.dotfiles\wezterm\wezterm.vbs'; Trigger = New-ScheduledTaskTrigger -AtLogon -User $env:USERNAME; RunLevel = 'Highest' },
    @{ Name = 'Syncthing_Logon'; Action = New-ScheduledTaskAction -Execute 'syncthing' -Argument '--no-console --no-browser'; Trigger = New-ScheduledTaskTrigger -AtLogon -User $env:USERNAME; RunLevel = 'Highest' },
    @{ Name = 'Backup-Script_Daily'; Action = New-ScheduledTaskAction -Execute 'C:\Windows\System32\wscript.exe' -Argument '%USERPROFILE%\.dotfiles\backup\backup.vbs'; Trigger = New-ScheduledTaskTrigger -Daily -At 8pm; RunLevel = 'Highest' }
)

# Program flow
Invoke-RunAsAdmin
Initialize-Logging

try {
    Write-Info "Version: 1.5.6"
    Install-WSLPlatform -RebootTaskName $RebootTaskName -ScriptPath $PSCommandPath
    $null = Install-WSLDistroIfMissing -DistroName $WslDistroName

    Install-WingetApps
    # Install-NonWingetApps -NonWingetApps $NonWingetApps

    Invoke-WSLDotfilesSetup -DistroName $WslDistroName -DotfilesFolder $DotfilesFolder -LogFileActive $LogFileActive -ScriptRoot $PSScriptRoot
    Invoke-WSLSyncthingDecryption -DistroName $WslDistroName -DotfilesFolder $DotfilesFolder

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
    $null = Read-LoggedHost 'Press Enter to close'
}
