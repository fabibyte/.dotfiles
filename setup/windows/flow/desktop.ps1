using module ./shared.psm1

[CmdletBinding()]
param(
    [string]$ResumeLogPath
)

Import-Module (Join-Path $PSScriptRoot 'shared.psm1')

$ErrorActionPreference = 'Stop'

try {
    $DotfilesFolder = Join-Path $env:USERPROFILE '.dotfiles'
    $ScriptFile = $PSCommandPath
    $WslDistroName = 'archlinux'
    $WslScriptPath = Resolve-Path (Join-Path $PSScriptRoot '..\..\linux\arch\flow\wsl.sh')

    $AppsToRemove = @(
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

    $AppsToInstall = @(
        'Google.AndroidStudio',
        '9NZVDKPMR9RD', # Mozilla.Firefox.MSIX
        '9NN77TCQ1NC8', # FlorianHeidenreich.Mp3tag
        'LizardByte.Sunshine',
        'RARLab.WinRAR',
        'Zen-Team.Zen-Browser',
        'NordSecurity.NordVPN',
        'Google.GoogleDrive',
        'PDFgear.PDFgear',
        'wez.wezterm',
        'WinDirStat.WinDirStat',
        'Google.Chrome',
        'Klocman.BulkCrapUninstaller',
        'Guru3D.Afterburner',
        'EaseUS.TodoBackup',
        'BleachBit.BleachBit',
        'FastCopy.FastCopy',
        'Obsidian.Obsidian',
        'Syncthing.Syncthing',
        'XP89DCGQ3K6VLD', # Microsoft.PowerToys
        'XP9KHM4BK9FZ7Q', # Microsoft.VisualStudioCode
        '9NKSQGP7F2NH', # WhatsApp
        '9NT1R1C2HH7J', # ChatGPT
        '9PLM9XGG6VKS', # Codex
        'Logitech.GHUB',
        'Corsair.iCUE.5',
        'LegacyGames.LegacyGamesLauncher',
        'XP99VR1BPSBQJ2', # EpicGames.EpicGamesLauncher
        'XPDM5VSMTKQLBJ', # Blizzard.BattleNet
        'RockstarGames.Launcher',
        'Valve.Steam',
        'XPDP2QW12DFSFK', # Ubisoft.Connect
        '9NVMNJCR03XV', # MSI Center
        'GOG.Galaxy',
        'ElectronicArts.EADesktop',
        'XPDC2RH70K22MN', # Discord.Discord
        'Playnite.Playnite',
        'ItchIo.Itch',
        'Amazon.Games',
        'AppWork.JDownloader'
    )

    $ScheduledTaskCommands = @(
        @{ Name = 'WSL-Script_Logon'; Action = New-ScheduledTaskAction -Execute 'C:\Windows\System32\wscript.exe' -Argument "$DotfilesFolder\wezterm\wezterm.vbs"; Trigger = New-ScheduledTaskTrigger -AtLogon -User $env:USERNAME; RunLevel = 'Highest' },
        @{ Name = 'Syncthing_Logon'; Action = New-ScheduledTaskAction -Execute 'syncthing' -Argument '--no-console --no-browser'; Trigger = New-ScheduledTaskTrigger -AtLogon -User $env:USERNAME; RunLevel = 'Highest' },
        @{ Name = 'Backup-Script_Daily'; Action = New-ScheduledTaskAction -Execute 'C:\Windows\System32\wscript.exe' -Argument "$DotfilesFolder\backup\backup.vbs"; Trigger = New-ScheduledTaskTrigger -Daily -At 8pm; RunLevel = 'Highest' }
    )

    Invoke-RunAsAdmin -ScriptPath $ScriptFile
    [Logger]::Init($DotfilesFolder, $ResumeLogPath)
    [Logger]::WriteInfo("Version: 2.0")

    Install-WSLPlatform -ScriptPath $ScriptFile -LogPath [Logger]::LogFileActive
    Install-WSLDistroIfMissing -DistroName $WslDistroName

    Remove-WingetApps -AppsToRemove $AppsToRemove
    Update-WingetApps
    Install-WingetApps -AppsToInstall $AppsToInstall

    Invoke-WSLDotfilesSetup -DistroName $WslDistroName -DotfilesFolder $DotfilesFolder -LogPath [Logger]::LogFileActive -ScriptPath $WslScriptPath
    Invoke-WSLDecryption -Description 'Syncthing key decryption' -DistroName $WslDistroName -InputPath "$DotfilesFolder\syncthing\key.pem.enc" -OutputPath "$DotfilesFolder\syncthing\key.pem"

    [Logger]::WriteInfo('Creating symbolic links...')
    New-Symlink -Src "$DotfilesFolder\wezterm\.wezterm.lua" -Tgt "$env:USERPROFILE\.wezterm.lua"
    New-SymlinkTree -Src "$DotFilesFolder\.ssh" -Tgt "$env:USERPROFILE\.ssh"
    New-SymlinkTree -Src "$DotfilesFolder\syncthing" -Tgt "$env:LOCALAPPDATA\Syncthing"

    Register-ScheduledTasks -ScheduledTaskCommands $ScheduledTaskCommands

    [Logger]::WriteSuccess('Windows setup completed successfully.')
}
catch {
    [Logger]::WriteError("An error occurred: $($_.Exception.Message)")
    [Logger]::WriteError("Stack trace: $($_.ScriptStackTrace)")
    throw
}
finally {
    Unregister-RebootTask
    $null = [Logger]::ReadLoggedHost('Press Enter to close')
}
