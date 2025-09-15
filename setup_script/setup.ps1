#$ErrorActionPreference = "Stop"
Write-Host "v11"

function Refresh-Path {
    $machinePath = [System.Environment]::GetEnvironmentVariable("Path","Machine")
    $userPath    = [System.Environment]::GetEnvironmentVariable("Path","User")
    $env:Path = "$machinePath;$userPath"
}

function Test-IsAdministrator {
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $pr = New-Object System.Security.Principal.WindowsPrincipal($id)
    return $pr.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdministrator)) {
    $scriptText = $MyInvocation.MyCommand.Definition
    $b64Script = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($scriptText))

    Write-Host "`nRestart as Administrator ..."
    Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile","-ExecutionPolicy","Bypass","-EncodedCommand",$b64Script -Verb RunAs
    exit
}


Write-Host "What type of apps should be installed:"
Write-Host "You can specify multiple."
Write-Host "Just press Enter to choose none."
Write-Host "games (g)"
Write-Host "school (s)"
Write-Host "athome (a)"
$apps = Read-Host
$games = $apps.Contains("g")
$school = $apps.Contains("s")
$athome = $apps.Contains("a")

winget install Git.MinGit
winget install wez.wezterm
Refresh-Path

if (-not (Test-Path -Path "$env:USERPROFILE\.dotfiles" -PathType Container)) {
    Write-Host "`nFetch config files ..."
    git clone "https://github.com/fabibyte/.dotfiles.git" "$env:USERPROFILE\.dotfiles"
}


# Write-Host "`nWinget import standard apps ..."
# winget import "$env:USERPROFILE\.dotfiles\setup_script\winget\winget_standard"
# Write-Host "Winget import dev apps ..."
# winget import "$env:USERPROFILE\.dotfiles\setup_script\winget\winget_dev"
# Write-Host "Winget import tool apps ..."
# winget import "$env:USERPROFILE\.dotfiles\setup_script\winget\winget_tools"
#
# if ($games) {
#     Write-Host "Winget import game apps ..."
#     winget import "$env:USERPROFILE\.dotfiles\setup_script\winget\winget_games"
# }
#
# if ($school) {
#     Write-Host "Winget import school apps ..."
#     winget import "$env:USERPROFILE\.dotfiles\setup_script\winget\winget_school"
# }
#
# if ($athome) {
#     Write-Host "Winget import athome apps ..."
#     winget import "$env:USERPROFILE\.dotfiles\setup_script\winget\winget_athome"
# }


Write-Host "`nInstall not-winget programs ..."
$downloadsFolder = Join-Path $env:USERPROFILE "Downloads"

$applications = @(
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
    @{
        Name = "vmr";
        Type = "RemoteScript";
        Uri = "https://scripts.vmr.dpdns.org/windows"
        Enabled = $true
    }
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

foreach ($app in $applications) {
    if (-not $app.Enabled) { continue }

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

wsl --install
wsl --install Ubuntu
Refresh-Path


Write-Host "`nLink config files ..."
$links = @(
    @{ Path = "$env:USERPROFILE\.wezterm.lua"; Target = "$env:USERPROFILE\.dotfiles\wezterm\.wezterm.lua" },
    @{ Path = "$env:USERPROFILE\.ssh\config"; Target = "$env:USERPROFILE\.dotfiles\.ssh\config" }
)

foreach ($link in $links) {
    Write-Host "$($link.Target) --> $($link.Path)"
    New-Item -ItemType SymbolicLink -Path $link.Path -Target $link.Target -Force > $null
}

Write-Host "`nCopy ssh keys ..."
Copy-Item -Path "$env:USERPROFILE\.dotfiles\.ssh\id_fabi.pub" -Destination "$env:USERPROFILE\.ssh\id_fabi.pub"
&"$env:USERPROFILE\.dotfiles\openssl.exe" aes-256-cbc -d -pbkdf2 -in "$env:USERPROFILE\.dotfiles\.ssh\id_fabi.enc" -out "$env:USERPROFILE\.ssh\id_fabi"

$winPubKey = "$env:USERPROFILE\.dotfiles\.ssh\id_fabi.pub"
$wslPubKey = wsl wslpath "'$winPubKey'"
$wslCommand = @"
mkdir -p ~/.ssh
grep -qxFf '$wslPubKey' ~/.ssh/authorized_keys 2>/dev/null || cat '$wslPubKey' >> ~/.ssh/authorized_keys
"@
wsl -d Ubuntu -e sh -c "$wslCommand"


Write-Host "`nImport task scheduler tasks ..."
$credential = Get-Credential -UserName "$env:USERNAME" -Message "Enter password for $env:USERNAME"

$scheduledTasks = @(
    @{
        Name = "WSL-Script Logon";
        XmlPath = "$env:USERPROFILE\.dotfiles\task_scheduler\WSL-Script_Logon.xml"
    }
)

foreach ($task in $scheduledTasks) {
    Unregister-ScheduledTask -TaskName $task.Name -Confirm:$false -ErrorAction SilentlyContinue
    $taskXmlContent = Get-Content -Path $task.XmlPath | Out-String
    Register-ScheduledTask -TaskName $task.Name -Xml $taskXmlContent -User $credential.UserName -Password $credential.Password
}

Write-Host "`nSetup wsl ..."
wsl -d Ubuntu -e "./install.sh"

Read-Host
