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
        'Power Automate',
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
        'Zen-Team.Zen-Browser',
        'NordSecurity.NordVPN',
        'Google.GoogleDrive',
        'PDFgear.PDFgear',
        'wez.wezterm',
        'WinDirStat.WinDirStat',
        'Google.Chrome',
        'Klocman.BulkCrapUninstaller',
        'EaseUS.TodoBackup',
        'BleachBit.BleachBit',
        'FastCopy.FastCopy',
        'Obsidian.Obsidian',
        'XP89DCGQ3K6VLD', # Microsoft.PowerToys
        'XP9KHM4BK9FZ7Q', # Microsoft.VisualStudioCode
        '9NKSQGP7F2NH', # WhatsApp
        '9NT1R1C2HH7J', # ChatGPT
        '9PLM9XGG6VKS', # Codex
        'MoonlightGameStreamingProject.Moonlight',
        'XPDC2RH70K22MN' # Discord.Discord
    )

    $ScheduledTasks = @(
        @{ Name = 'WSL-Script_Logon'; Action = New-ScheduledTaskAction -Execute 'C:\Windows\System32\wscript.exe' -Argument "$DotfilesFolder\wezterm\wezterm.vbs"; Trigger = New-ScheduledTaskTrigger -AtLogon -User $env:USERNAME; RunLevel = 'Highest' }
    )

    Initialize-Logger -NewLogFileBasePath $DotfilesFolder -ResumeLogFilePath $ResumeLogPath

    if (Invoke-RunAsAdmin -ScriptPath $ScriptFile -ResumeLogPath (Get-LogFileActive)) {
        $PromptOnExit = $false
        return
    }

    Install-WSLPlatform -ScriptPath $ScriptFile -LogPath (Get-LogFileActive)
    Install-WSLDistroIfMissing -DistroName $WslDistroName

    Remove-WingetApps -AppsToRemove $AppsToRemove
    Update-WingetApps
    Install-WingetApps -AppsToInstall $AppsToInstall

    Invoke-WSLDotfilesSetup -DistroName $WslDistroName -DotfilesFolder $DotfilesFolder -LogPath (Get-LogFileActive) -ScriptPath $WslScriptPath

    Write-LogInfo('Copying config files...')
    Copy-Path -SourcePath "$DotfilesFolder\wezterm\.wezterm.lua" -TargetPath "$env:USERPROFILE\.wezterm.lua"
    Invoke-SSHConfiguration -DotfilesFolder $DotfilesFolder

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
        Read-LoggedHost('Press Enter to close')
    }
}
