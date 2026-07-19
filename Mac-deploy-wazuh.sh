#!/bin/sh
# Mac-deploy-wazuh.sh: Wazuh agent installation + Sysmon deployment for monitoring MacOS endpoints on a home network.
#   Prerequisites: Residential network (optionally supported by Tailscale) with an endpoint set-up as a Wazuh/SIEM "Manager"
#   Author: Nixy
#   Note: This is for "Apple Silicon" devices, not Intel. (Ref: https://documentation.wazuh.com/current/installation-guide/wazuh-agent/wazuh-agent-package-macos.html)

# Vars
CUSTOM_MANAGER_IP='<WAZUH_MANAGER_IP>'
CUSTOM_AGENT_NAME='<YOUR_AGENT_NAME>'

# To deploy the Wazuh agent on your endpoint, edit the WAZUH_MANAGER variable to contain your Wazuh manager IP address or hostname, and run the following commands
curl -O https://packages.wazuh.com/4.x/macos/wazuh-agent-4.14.6-1.arm64.pkg

# Commit agent settings for agent pkg install
echo "WAZUH_MANAGER=$CUSTOM_MANAGER_IP && WAZUH_AGENT_NAME=$CUSTOM_AGENT_NAME" > /tmp/wazuh_envs && sudo installer -pkg wazuh-agent-4.14.6-1.arm64.pkg -target /

# Start the Wazuh agent to complete the installation process
launchctl bootstrap system /Library/LaunchDaemons/com.wazuh.agent.plist
