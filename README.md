# Home-SIEM
Files I'm using to help set up/deploy a SIEM on my home network.

#### 1. `Win-deploy-wazuh.ps1`
- **PowerShell script to run on Windows endpoints** (as admin) to install the Wazuh agent. Additional __Sysmon64__ deployment/configuration for higher-value logging telemetry
> Usage:
> 1. Edit the `$Manager` IP var.
> 2. In an Administrator window, run `pwsh -ExecutionPolicy Bypass -File .\Win-deploy-wazuh.ps1 -AgentName '<YOUR_DEVICE_AGENT_NAME>'`





#### 2. `Mac-deploy-wazuh.sh`
- **Bash script to run on MacOS endpoints** to install the Wazuh agent. Unified logs, auth events, and FIM work out of the box without additional overhead.
> Usage:
> 1. Edit the `CUSTOM_MANAGER_IP` & `CUSTOM_AGENT_NAME` vars.
> 2. Run `sudo bash Mac-deploy-wazuh.sh`

## Resources used:
- [Deploying Wazuh agents on Windows endpoints](https://documentation.wazuh.com/current/installation-guide/wazuh-agent/wazuh-agent-package-windows.html)
- [Sysmon: How to install, upgrade, and uninstall](https://www.jamesgibbins.com/sysmon-install/)
