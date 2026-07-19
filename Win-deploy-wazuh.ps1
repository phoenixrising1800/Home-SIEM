# Win-deploy-wazuh.ps1: Wazuh agent installation + Sysmon deployment for monitoring Windows endpoints on a home network.
#   Prerequisites: Residential network (optionally supported by Tailscale) with an endpoint set-up as a Wazuh/SIEM "Manager"
#   Author: Nixy
#   Note: Run in ADMIN PowerShell, e.g. "pwsh -ExecutionPolicy Bypass -File .\Win-deploy-wazuh.ps1 -AgentName 'desktop-office'"
param(
        [Parameter(Mandatory=$true)][string]$AgentName,
        [string]$Manager = "<WAZUH_MANAGER_IP>", # CHANGE ME
        [string]$WazuhVersion = "4.14.6",
        [string]$MsiName = "wazuh-agent-$WazuhVersion-1.msi"
)

$ErrorActionPreference = "Stop"

# --- Preflight ---
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
         ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw " > Run in ADMIN PowerShell:  pwsh -ExecutionPolicy Bypass -File .\Win-deploy-wazuh.ps1 -AgentName 'desktop-office'"
}
if (-not (Test-Connection $Manager -Count 2 -Quiet)) {
    throw " > Cannot reach manager $Manager - is Tailscale running and signed in on the Wazuh manager node, or is the manager IP unreachable/down?"
}
if (Get-Service WazuhSvc -ErrorAction SilentlyContinue) { 
    Write-Host " > Existing Wazuh agent found - uninstalling first (MSI params are ignored on reinstall)..."
        $app = Get-CimInstance Win32_Product -Filter "Name LIKE 'Wazuh%'"
        if ($app) {  
            # Find true version of currently installed agent
            $tempVer = $app.Version
            $tempMsiName = "wazuh-agent-$tempVer-1.msi"
            # Search for installer MSI in particular folders it may be in
            $folders = @(
                "$env:TEMP",
                "$HOME\Downloads"
            )
            $found = Get-ChildItem -Path $folders -Filter $tempMsiName -File -Recurse -ErrorAction SilentlyContinue
            Write-Host " > Found Wazuh agent version: " -NoNewLine 
            Write-Host "$tempVer" 
            Write-Host " > Uninstaller located: " -NoNewLine
            Write-Host "$found"
            if (-not $found) {
                throw "File '$tempMsiName' not found. Please locate a copy of the agent installer to remove the current agent."
            }
            # Kick-off uninstallation
            Try { 
                Start-Process msiexec.exe -Wait -ArgumentList "/x $tempMsiName" -ErrorAction $ErrorActionPreference
            } Catch {
                Write-Host $_.Exception.Message
                Write-Host $_.ScriptStackTrace
                exit
            }
            Write-Host " > Uninstaller executed. Run this program once again to install fresh agent." 
        }
}
Write-Host " > AgentName is set to: " -NoNewLine 
Write-Host -Object $AgentName

# --- Wazuh agent ---
Write-Host " > Downloading Wazuh agent $WazuhVersion..."
$NewMsiInstaller = "$HOME\Downloads\$MsiName"
Invoke-WebRequest "https://packages.wazuh.com/4.x/windows/wazuh-agent-$WazuhVersion-1.msi" -OutFile $NewMsiInstaller
Write-Host " > Installing agent (manager: $Manager, name: $AgentName)..."; Write-Host 
Start-Process msiexec.exe -Wait -ArgumentList "/i `"$NewMsiInstaller`" /q WAZUH_MANAGER=`"$Manager`" WAZUH_AGENT_NAME=`"$AgentName`""

# Verify the address actually applied (the 0.0.0.0 failure mode)
$conf = Get-Content 'C:\Program Files (x86)\ossec-agent\ossec.conf' -Raw
if ($conf -notmatch [regex]::Escape("<address>$Manager</address>")) {
    throw " > Manager address did not apply - check and edit ossec.conf manually."
}

NET START WazuhSvc
$app = Get-CimInstance Win32_Product -Filter "Name LIKE 'Wazuh%'"
if (-not ($app -and ($app.Version -eq $WazuhVersion))) { 
    throw "An error occurred. Couldn't validate the agent is installed."
}

# --- Sysmon ---
Write-Host "---------------------------------------"
$sysmonDir = "C:\Sysmon"
$sysmonExePath = Join-Path $sysmonDir "Sysmon64.exe"
$cfgPath = Join-Path $sysmonDir "sysmonconfig-export.xml"
$cfgUrl = "https://raw.githubusercontent.com/SwiftOnSecurity/sysmon-config/master/sysmonconfig-export.xml"

# Check Sysmon64 service's registered binary path rather than assuming a fixed location, with a fallback check
function Get-SysmonState {
    $svc = Get-CimInstance Win32_Service -Filter "Name='Sysmon64'" -ErrorAction SilentlyContinue
    $drv = Get-CimInstance Win32_SystemDriver -Filter "Name='SysmonDrv'" -ErrorAction SilentlyContinue
    $exePath = $null
    if ($svc) {
        $exePath = ($svc.PathName -replace '^"?([^"]+\.exe)"?.*$', '$1') # Extract clean path name (without quotes, args, etc.)
    } elseif (Test-Path "C:\Windows\Sysmon64.exe") {
        $exePath = "C:\Windows\Sysmon64.exe" # Fallback: common convention for manual installs
    }
    [PSCustomObject]@{
        ServiceRegistered = [bool]$svc
        ExePath           = $exePath
        ExeExists         = ($exePath -and (Test-Path $exePath))
        Orphaned          = ($svc -or $drv) -and -not ($exePath -and (Test-Path $exePath))
    }
}

# If service/driver registry entries exist but the binary is missing it removes the stale `Services\Sysmon64` / `Services\SysmonDrv` registry keys and throws
function Remove-OrphanedSysmonRegistration {
    Write-Host " > Sysmon service/driver registered but binary missing - cleaning up orphaned registration..."
    Remove-Item "HKLM:\SYSTEM\CurrentControlSet\Services\Sysmon64" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item "HKLM:\SYSTEM\CurrentControlSet\Services\SysmonDrv" -Recurse -Force -ErrorAction SilentlyContinue
    throw " > Removed orphaned Sysmon registry entries. A REBOOT is required before Sysmon can be (re)installed - reboot and re-run this script."
}

# Since Sysmon refuses in-place upgrades ("Uninstall Sysmon before reinstalling"), it now always downloads the latest installer, compares FileVersion against what's installed, 
#   and if they differ, uninstalls first (-u, falling back to the undocumented -u force if the service is still registered afterward) before doing a fresh install.
function Uninstall-Sysmon($exePath) {
    Write-Host " > Uninstalling existing Sysmon (required before upgrade)..."
    & $exePath -u
    Start-Sleep -Seconds 3
    if (Get-Service Sysmon64 -ErrorAction SilentlyContinue) {
        Write-Host " > Standard uninstall left the service registered - retrying with '-u force'..."
        & $exePath -u force
        Start-Sleep -Seconds 3
    }
    if (Get-Service Sysmon64 -ErrorAction SilentlyContinue) {
        Remove-OrphanedSysmonRegistration
    }
}

# Always fetch the latest installer so we can detect version drift and use it for install/upgrade
$zip = "$HOME\Downloads\Sysmon.zip"
$extractDir = "$HOME\Downloads\Sysmon_new"
Write-Host " > Grabbing the latest copy of Sysmon tool..."
Invoke-WebRequest "https://download.sysinternals.com/files/Sysmon.zip" -OutFile $zip
Expand-Archive $zip -DestinationPath $extractDir -Force
$latestVersion = (Get-Item "$extractDir\Sysmon64.exe").VersionInfo.FileVersion

# Figure out existing state, if Sysmon exists and/or needs fresh install, or update config only
$state = Get-SysmonState
if ($state.Orphaned) {
    Remove-OrphanedSysmonRegistration
}
$needsFreshInstall = -not ($state.ServiceRegistered -and $state.ExeExists)
if (-not $needsFreshInstall) {
    $installedVersion = (Get-Item $state.ExePath).VersionInfo.FileVersion
    if ($installedVersion -ne $latestVersion) {
        Write-Host " > Installed Sysmon is v$installedVersion, latest is v$latestVersion - uninstalling before upgrade..."
        Uninstall-Sysmon $state.ExePath
        $needsFreshInstall = $true
    }
}
if ($needsFreshInstall) {
    Write-Host " > Installing Sysmon v$latestVersion + SwiftOnSecurity config..."
    New-Item -ItemType Directory -Path $sysmonDir -Force | Out-Null
    Copy-Item "$extractDir\Sysmon64.exe" $sysmonExePath -Force
    Invoke-WebRequest $cfgUrl -OutFile $cfgPath
    & $sysmonExePath -accepteula -i $cfgPath
    if ($LASTEXITCODE -ne 0) { throw " > Sysmon install failed (exit $LASTEXITCODE)." }
} else {
    Write-Host " > Sysmon already installed (v$installedVersion) - updating config only..."
    Invoke-WebRequest $cfgUrl -OutFile $cfgPath
    & $state.ExePath -c $cfgPath
    if ($LASTEXITCODE -ne 0) { throw " > Sysmon config update failed (exit $LASTEXITCODE)." }
}

# --- Verify ---
Write-Host "---------------------------------------"
Start-Sleep 10
$svc = Get-Service WazuhSvc, Sysmon64
Write-Host " > Service Statuses: "
$svc | Format-Table Name, Status
$log = Get-Content 'C:\Program Files (x86)\ossec-agent\ossec.log' -Tail 5
Write-Host "`n > Last agent log lines:`n$($log -join "`n")"
Write-Host "`n > Done. Check the Wazuh dashboard - '$AgentName' should show Active within ~1 minute."
