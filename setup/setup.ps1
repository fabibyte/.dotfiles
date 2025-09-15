$setupPath = "$env:USERPROFILE\.dotfiles\setup\main.ps1" 

if (Test-Path $setupPath) {
    Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile","-ExecutionPolicy","Bypass","-File",$setupPath -Verb RunAs
    exit
}

$url = "https://raw.githubusercontent.com/fabibyte/.dotfiles/refs/heads/main/setup/main.ps1"
$scriptText = (Invoke-WebRequest -Uri $url).Content
$tempPath = Join-Path $env:TEMP ("setup-main-{0}.ps1" -f ([guid]::NewGuid()))
Set-Content -Path $tempPath -Value $scriptText -Encoding UTF8
Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile","-ExecutionPolicy","Bypass","-File",$tempPath -Verb RunAs
exit
