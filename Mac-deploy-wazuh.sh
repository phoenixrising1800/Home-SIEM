# Mac-deploy-wazuh.sh: Wazuh agent installation + Sysmon deployment for monitoring MacOS endpoints on a home network.
#   Prerequisites: Residential network (optionally supported by Tailscale) with an endpoint set-up as a Wazuh/SIEM "Manager"
#   Author: Nixy
#   Note: This is for "Apple Silicon" devices, not Intel. (Ref: https://documentation.wazuh.com/current/installation-guide/wazuh-agent/wazuh-agent-package-macos.html)
#!/bin/sh
set -eu

# Vars
CUSTOM_MANAGER_IP='<WAZUH_MANAGER_IP>'
CUSTOM_AGENT_NAME='<YOUR_AGENT_NAME>'

# Use temp dir for installation
cd "$(mktemp -d)"

# Quick input check
case "$CUSTOM_MANAGER_IP" in
  '<'*) echo "Edit CUSTOM_MANAGER_IP before running." >&2; exit 1 ;;
esac

# Currently version 4.14.6 as of 7/19/2026 but this can change. Refer to the MacOS installation guide for the latest.
curl -O https://packages.wazuh.com/4.x/macos/wazuh-agent-4.14.6-1.arm64.pkg

# Commit agent settings for agent pkg install
echo "WAZUH_MANAGER='$CUSTOM_MANAGER_IP' && WAZUH_AGENT_NAME='$CUSTOM_AGENT_NAME'" > /tmp/wazuh_envs && sudo installer -pkg wazuh-agent-4.14.6-1.arm64.pkg -target /

# Start the Wazuh agent to complete the installation process
sudo launchctl bootstrap system /Library/LaunchDaemons/com.wazuh.agent.plist
