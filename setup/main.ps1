#$ErrorActionPreference = "Stop"

param(
    [switch]$AfterReboot
)


# Functions
$rebootTaskName = "ContinueSetupAfterReboot"

function Refresh-Path {
    $machinePath = [System.Environment]::GetEnvironmentVariable("Path","Machine")
    $userPath    = [System.Environment]::GetEnvironmentVariable("Path","User")
    $env:Path = "$machinePath;$userPath"
}

function Ask-AppTypes {
    Write-Host "What type of apps should be installed:"
    Write-Host "You can specify multiple."
    Write-Host "Just press Enter to choose none."
    Write-Host "games (g)"
    Write-Host "school (s)"
    Write-Host "athome (a)"
    return Read-Host
}

function Get-ConfigFiles {
    if (-not (Test-Path -Path "$env:USERPROFILE\.dotfiles" -PathType Container)) {
        Write-Host "`nInstall git to fetch config files ..."
        winget install Git.MinGit
        Refresh-Path

        Write-Host "`nFetch config files ..."
        git clone "https://github.com/fabibyte/.dotfiles.git" "$env:USERPROFILE\.dotfiles"
    }
}

function Install-WingetApps {
    $games = $apps.Contains("g")
    $school = $apps.Contains("s")
    $athome = $apps.Contains("a")

    Write-Host "Winget import standard apps ..."
    winget import "$env:USERPROFILE\.dotfiles\setup_script\winget\winget_standard"
    Write-Host "`nWinget import dev apps ..."
    winget import "$env:USERPROFILE\.dotfiles\setup_script\winget\winget_dev"
    Write-Host "`nWinget import tool apps ..."
    winget import "$env:USERPROFILE\.dotfiles\setup_script\winget\winget_tools"

    if ($games) {
        Write-Host "`nWinget import game apps ..."
        winget import "$env:USERPROFILE\.dotfiles\setup_script\winget\winget_games"
    }

    if ($school) {
        Write-Host "`nWinget import school apps ..."
        winget import "$env:USERPROFILE\.dotfiles\setup_script\winget\winget_school"
    }

    if ($athome) {
        Write-Host "`nWinget import athome apps ..."
        winget import "$env:USERPROFILE\.dotfiles\setup_script\winget\winget_athome"
    }
}

function Install-NonWingetApps {
    if ($nonWingetApps.Count -gt 0) {
        Write-Host "Install non-winget programs ..."
        $downloadsFolder = Join-Path $env:USERPROFILE "Downloads"

        foreach ($app in $nonWingetApps) {
            if (-not $app.Enabled) { continue }
            Write-Host "Installing $app ..."

            switch ($app.Type) {
                "DirectExe" {
                    $installerPath = Join-Path $downloadsFolder $app.InstallerFileName
                    Invoke-WebRequest -Uri $app.Uri -OutFile $installerPath -UseBasicParsing
                    Start-Process -FilePath $installerPath -Wait
                    Remove-Item $installerPath -Force
                }
                "ZipInstall" {
                    $zipPath = Join-Path $downloadsFolder $app.ZipName ".zip"
                    $unzipPath = Join-Path $downloadsFolder $app.ZipName
                    Invoke-WebRequest -Uri $app.Uri -OutFile $zipPath -UseBasicParsing
                    Expand-Archive -Path $zipPath -DestinationPath $unzipPath -Force
                    $installerExe = Get-ChildItem -Path $unzipPath -Filter "*.exe" -Recurse | Select-Object -First 1
                    Start-Process -FilePath $installerExe.FullName -Wait
                    Remove-Item $zipPath -Force
                    Remove-Item $unzipPath -Recurse -Force
                }
                "RemoteScript" {
                    Invoke-RestMethod $app.Uri | Invoke-Expression
                }
            }
        }
    }
}

function Link-Configs {
    Write-Host "Link config files ..."

    foreach ($link in $links) {
        Write-Host "$($link.Target) --> $($link.Path)"
        New-Item -ItemType SymbolicLink -Path $link.Path -Target $link.Target -Force > $null
    }
}

function Create-ScheduledTasks {
    Write-Host "Create task scheduler tasks ..."

    foreach ($task in $scheduledTaskCommands) {
        if ($task.RunLevel) {
            Register-ScheduledTask -TaskName $task.Name -Action $task.Action -Trigger $task.Trigger -RunLevel $task.RunLevel
            continue
        }
        
        Register-ScheduledTask -TaskName $task.Name -Action $task.Action -Trigger $task.Trigger
    }
}

function Reboot {
    $scriptPath = "$env:USERPROFILE\.dotfiles\setup\main.ps1" 
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -File `"$scriptPath`" -AfterReboot";
    $trigger = New-ScheduledTaskTrigger -AtLogon -User $env:USERNAME;
    Register-ScheduledTask -TaskName $rebootTaskName -Action $action -Trigger $trigger -RunLevel "HIGHEST"

    Write-Host "Rebooting computer..."
    Restart-Computer -Confirm
}

function Clean-AfterReboot {
    Unregister-ScheduledTask -TaskName $rebootTaskName
}

function Configure-WSL {
    Copy-WezSSHKeys
    wsl -d Ubuntu -e "./install.sh"
}

function Copy-WezSSHKeys {
    Write-Host "`nCopy ssh keys for wezterm ..."
    Copy-Item -Path "$env:USERPROFILE\.dotfiles\.ssh\id_fabi.pub" -Destination "$env:USERPROFILE\.ssh\id_fabi.pub"
    &"$env:USERPROFILE\.dotfiles\setup\openssl.exe" aes-256-cbc -d -pbkdf2 -in "$env:USERPROFILE\.dotfiles\.ssh\id_fabi.enc" -out "$env:USERPROFILE\.ssh\id_fabi"

    $winPubKey = "$env:USERPROFILE\.dotfiles\.ssh\id_fabi.pub"
    $wslPubKey = wsl wslpath "'$winPubKey'"
    $wslCommand = "mkdir -p ~/.ssh && " +
                  "touch ~/.ssh/authorized_keys && " +
                  "grep -qxFf '$wslPubKey' ~/.ssh/authorized_keys || " +
                  "cat '$wslPubKey' >> ~/.ssh/authorized_keys"
    wsl -d Ubuntu -e sh -c "$wslCommand"
}


# Variables
$nonWingetApps = @(
    # @{
    #     Name = "Honeygain";
    #     Type = "DirectExe";
    #     Uri = "https://download.honeygain.com/windows-app/Honeygain_install.exe";
    #     InstallerFileName = "honeygain.exe"
    #     Enabled = $true
    # },
    # @{
    #     Name = "MSI Center";
    #     Type = "ZipInstall";
    #     Uri = "https://download.msi.com/uti_exe/desktop/MSI-Center.zip";
    #     ZipName = "msi";
    #     Enabled = $athome
    # },
    # @{
    #     Name = "WhatsApp";
    #     Type = "DirectExe";
    #     Uri = "https://get.microsoft.com/installer/download/9NKSQGP7F2NH?cid=website_cta_psi";
    #     InstallerFileName = "whatsapp_setup.exe"
    #     Enabled = $true
    # },
    # @{
    #     Name = "Yeelight";
    #     Type = "DirectExe";
    #     Uri = "https://yeelight-iot-resources.yeelight.com/app/YeelightStation_Setup_1.5.0.31025.exe";
    #     InstallerFileName = "yeelight_setup.exe"
    #     Enabled = $athome
    # }
)

$links = @(
    @{ Path = "$env:USERPROFILE\.wezterm.lua"; Target = "$env:USERPROFILE\.dotfiles\wezterm\.wezterm.lua" },
    @{ Path = "$env:USERPROFILE\.ssh\config"; Target = "$env:USERPROFILE\.dotfiles\.ssh\config" }
)

$scheduledTaskCommands= @(
    @{
        Name = "WSL-Script_Logon";
        Action = New-ScheduledTaskAction -Execute "C:\Windows\System32\wscript.exe" -Argument "%USERPROFILE%\.dotfiles\wezterm\wezterm.vbs";
        Trigger = New-ScheduledTaskTrigger -AtLogon -User $env:USERNAME;
    }
)


# Program flow
if (-not $AfterReboot.IsPresent) {
    $apps = Ask-AppTypes
    Get-ConfigFiles
    Write-Host # Insert Space
    #Install-WingetApps $apps # Temp
    winget install wez.wezterm # Temp

    if ($nonWingetApps.Count -gt 0) {
        Write-Host # Insert Space
        Install-NonWingetApps
    }

    Write-Host # Insert Space
    Link-Configs
    Write-Host # Insert Space
    Create-ScheduledTasks
    Write-Host # Insert Space
    wsl --install Ubuntu # Install Ubuntu WSL initially
    Write-Host # Insert Space
    Reboot
}

Clean-AfterReboot
Write-Host # Insert Space
wsl --install Ubuntu # Install Ubuntu WSL continuation
Write-Host # Insert Space
Configure-WSL
Read-Host # stop auto closing to keep output visible
