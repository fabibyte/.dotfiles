# check if the script is running as administrator
function Test-IsAdministrator {
    $currentUser = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentUser.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdministrator)) {
    # get the path of the current script
    $scriptPath = $MyInvocation.MyCommand.Definition
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-File", "`"$scriptPath`""
    exit
}


# create symbolic links to configs
$links = @(
    @{ Name = ".wezterm.lua"; Target = "..\wezterm\.wezterm.lua" },
    @{ Name = "wezterm.vbs"; Target = "..\wezterm\wezterm.vbs" }
)

foreach ($link in $links) {
    $targetPath = Join-Path -Path $PSScriptRoot -ChildPath $link.Target
    $linkPath = Join-Path -Path $env:USERPROFILE -ChildPath $link.Name
    New-Item -ItemType SymbolicLink -Path $linkPath -Target $targetPath -Force
}


# import tasks in task scheduler
$credential = Get-Credential -UserName "Fabi" -Message "Enter password for Fabi"

$scheduledTasks = @(
    @{
        Name = "WSL-Script Logon";
        XmlPath = "..\task_scheduler\WSL-Script_Logon.xml"
    }
)

foreach ($task in $scheduledTasks) {
    $taskName = $task.Name
    $fullXmlPath = Join-Path -Path $PSScriptRoot -ChildPath $task.XmlPath
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    $taskXmlContent = Get-Content -Path $fullXmlPath | Out-String
    Register-ScheduledTask -TaskName $taskName -Xml $taskXmlContent -User $credential.UserName -Password $credential.Password
}


# winget imports
winget import ".\winget\winget_standard"
winget import ".\winget\winget_dev"
winget import ".\winget\winget_tools"
winget import ".\winget\winget_games"
winget import ".\winget\winget_misc"
winget import ".\winget\winget_school"


# install programs that cant be installed via winget
$downloadsFolder = Join-Path $env:USERPROFILE "Downloads"

$applications = @(
    @{
        Name = "Honeygain";
        Type = "DirectExe";
        Uri = "https://download.honeygain.com/windows-app/Honeygain_install.exe";
        InstallerFileName = "honeygain.exe"
    },
    @{
        Name = "MSI Center";
        Type = "ZipInstall";
        Uri = "https://download.msi.com/uti_exe/desktop/MSI-Center.zip";
        ZipName = "msi";
    },
    @{
        Name = "vmr";
        Type = "RemoteScript";
        Uri = "https://scripts.vmr.dpdns.org/windows"
    },
    @{
        Name = "WhatsApp";
        Type = "DirectExe";
        Uri = "https://get.microsoft.com/installer/download/9NKSQGP7F2NH?cid=website_cta_psi";
        InstallerFileName = "whatsapp_setup.exe"
    },
    @{
        Name = "Yeelight";
        Type = "DirectExe";
        Uri = "https://yeelight-iot-resources.yeelight.com/app/YeelightStation_Setup_1.5.0.31025.exe";
        InstallerFileName = "yeelight_setup.exe"
    }
)

foreach ($app in $applications) {
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

wsl -e "./install.sh"
