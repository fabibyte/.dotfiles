[CmdletBinding()]
param(
    [string]$ResumeLogPath
)

Import-Module (Join-Path $PSScriptRoot 'shared.psm1')

$ErrorActionPreference = 'Stop'
$PromptOnExit = $true

try {
    $DotfilesFolder = Join-Path $env:USERPROFILE '.dotfiles'
    $ScriptFile = $PSCommandPath
    $WslDistroName = 'archlinux'
    $WslScriptPath = Resolve-Path (Join-Path $PSScriptRoot '..\..\linux\arch\flow\wsl.sh')

    $AppsToRemove = @(
        'Microsoft Clipchamp',
        'News',
        'Microsoft Bing',
        'MSN Weather',
        'Get Help',
        'Solitaire & Casual Games',
        'Microsoft Sticky Notes',
        'MPower Automate',
        'Start Experiences App',
        'Store Experience Host',
        'Microsoft To Do',
        'Widgets Platform Runtime',
        'Windows Camera',
        'Feedback Hub',
        'Windows Sound Recorder',
        'Quick Assist'
    )

    $AppsToInstall = @(
        # 'Google.AndroidStudio',
        # '9NZVDKPMR9RD', # Mozilla.Firefox.MSIX
        # '9NN77TCQ1NC8', # FlorianHeidenreich.Mp3tag
        # 'LizardByte.Sunshine',
        # 'RARLab.WinRAR',
        # 'Zen-Team.Zen-Browser',
        # 'NordSecurity.NordVPN',
        # 'Google.GoogleDrive',
        # 'PDFgear.PDFgear',
        # 'wez.wezterm',
        # 'WinDirStat.WinDirStat',
        # 'Google.Chrome',
        # 'Klocman.BulkCrapUninstaller',
        # 'Guru3D.Afterburner',
        # 'EaseUS.TodoBackup',
        # 'BleachBit.BleachBit',
        'FastCopy.FastCopy',
        # 'Obsidian.Obsidian',
        # 'Syncthing.Syncthing',
        # 'XP89DCGQ3K6VLD', # Microsoft.PowerToys
        # 'XP9KHM4BK9FZ7Q', # Microsoft.VisualStudioCode
        # '9NKSQGP7F2NH', # WhatsApp
        # '9NT1R1C2HH7J', # ChatGPT
        # '9PLM9XGG6VKS', # Codex
        # 'Logitech.GHUB',
        # 'Corsair.iCUE.5',
        # 'LegacyGames.LegacyGamesLauncher',
        # 'XP99VR1BPSBQJ2', # EpicGames.EpicGamesLauncher
        # 'XPDM5VSMTKQLBJ', # Blizzard.BattleNet
        # 'RockstarGames.Launcher',
        # 'Valve.Steam',
        # 'XPDP2QW12DFSFK', # Ubisoft.Connect
        # '9NVMNJCR03XV', # MSI Center
        # 'GOG.Galaxy',
        # 'ElectronicArts.EADesktop',
        # 'XPDC2RH70K22MN', # Discord.Discord
        # 'Playnite.Playnite',
        # 'ItchIo.Itch',
        # 'Amazon.Games',
        'AppWork.JDownloader'
    )

    $ScheduledTasks = @(
        @{ Name = 'WSL-Script_Logon'; Action = New-ScheduledTaskAction -Execute 'C:\Windows\System32\wscript.exe' -Argument "$DotfilesFolder\wezterm\wezterm.vbs"; Trigger = New-ScheduledTaskTrigger -AtLogon -User $env:USERNAME; RunLevel = 'Highest' },
        @{ Name = 'Syncthing_Logon'; Action = New-ScheduledTaskAction -Execute 'syncthing' -Argument '--no-console --no-browser'; Trigger = New-ScheduledTaskTrigger -AtLogon -User $env:USERNAME; RunLevel = 'Highest' },
        @{ Name = 'Backup-Script_Daily'; Action = New-ScheduledTaskAction -Execute 'C:\Windows\System32\wscript.exe' -Argument "$DotfilesFolder\backup\backup.vbs"; Trigger = New-ScheduledTaskTrigger -Daily -At 8pm; RunLevel = 'Highest' }
    )

    Initialize-Logger -NewLogFileBasePath $DotfilesFolder -ResumeLogFilePath $ResumeLogPath

    if (Invoke-RunAsAdmin -ScriptPath $ScriptFile -ResumeLogPath (Get-LogFileActive)) {
        $PromptOnExit = $false
        return
    }

    Write-LogInfo("Version: 2.7")

    Install-WSLPlatform -ScriptPath $ScriptFile -LogPath (Get-LogFileActive)
    Install-WSLDistroIfMissing -DistroName $WslDistroName

    Remove-WingetApps -AppsToRemove $AppsToRemove
    Update-WingetApps
    Install-WingetApps -AppsToInstall $AppsToInstall

    Invoke-WSLDotfilesSetup -DistroName $WslDistroName -DotfilesFolder $DotfilesFolder -LogPath (Get-LogFileActive) -ScriptPath $WslScriptPath
    Invoke-WSLDecryption -Description 'Syncthing key decryption' -DistroName $WslDistroName -InputPath "$DotfilesFolder\syncthing\key.pem.enc" -OutputPath "$DotfilesFolder\syncthing\key.pem"

    Write-LogInfo('Creating symbolic links...')
    New-Symlink -SourcePath "$DotfilesFolder\wezterm\.wezterm.lua" -TargetPath "$env:USERPROFILE\.wezterm.lua"
    New-SymlinkTree -SourceDirectory "$DotfilesFolder\.ssh" -TargetDirectory "$env:USERPROFILE\.ssh"
    New-SymlinkTree -SourceDirectory "$DotfilesFolder\syncthing" -TargetDirectory "$env:LOCALAPPDATA\Syncthing"

    Register-ScheduledTasks -ScheduledTasks $ScheduledTasks

    Write-LogSuccess('Windows setup completed successfully.')
}
catch {
    Write-LogError("An error occurred: $($_.Exception.Message)")
    Write-LogError("Stack trace: $($_.ScriptStackTrace)")
    throw
}
finally {
    if ($PromptOnExit) {
        Unregister-RebootTask
        $null = Read-LoggedHost('Press Enter to close')
    }
}
