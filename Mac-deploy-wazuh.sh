#!/bin/sh
set -eu
# Mac-deploy-wazuh.sh: Wazuh agent installation for monitoring MacOS endpoints on a home network.
#   Prerequisites: Residential network (optionally supported by Tailscale) with an endpoint set-up as a Wazuh/SIEM "Manager"
#   Author: Nixy
#   Note: This is for "Apple Silicon" devices, not Intel. (Ref: https://documentation.wazuh.com/current/installation-guide/wazuh-agent/wazuh-agent-package-macos.html)

# Vars
CUSTOM_MANAGER_IP='<WAZUH_MANAGER_IP>'
CUSTOM_AGENT_NAME='<YOUR_AGENT_NAME>'
CUSTOM_AGENT_VER='4.14.6'

# Quick input check
case "$CUSTOM_MANAGER_IP" in
  '<'*) echo "Edit CUSTOM_MANAGER_IP before running." >&2; exit 1 ;;
esac

# Work in a throwaway directory; delete it on exit, success or failure.
# - The trap ... EXIT fires no matter how the script ends — normal completion, a failure caught by set -e, or Ctrl-C — so the downloaded pkg never lingers. 
#   The single quotes around the trap command are deliberate: they delay expansion of $tmpdir until the trap actually runs, which is the standard idiom 
#   (with double quotes it would also work here since tmpdir is already set, but single quotes are the safer habit).
# - Since the whole script now operates out of $tmpdir, the earlier relative-path concern is gone — installer finds the pkg regardless of where the user launched the script from. 
# - And because the script runs as a child process, there's no need to cd back at the end; the user's shell never moved.
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
cd "$tmpdir"

# Currently version 4.14.6 as of 7/19/2026 but this can change. Refer to the MacOS installation guide for the latest.
curl -f -O https://packages.wazuh.com/4.x/macos/wazuh-agent-4.14.6-1.arm64.pkg

# Commit agent settings for agent pkg install
echo "WAZUH_MANAGER='$CUSTOM_MANAGER_IP' && WAZUH_AGENT_NAME='$CUSTOM_AGENT_NAME'" > /tmp/wazuh_envs && sudo installer -pkg wazuh-agent-4.14.6-1.arm64.pkg -target /

# Clean up temp envs file consumed by Wazuh's installer's postinstall step to scrub the manager IP from disk(?)
#rm -f /tmp/wazuh_envs

# Start the Wazuh agent to complete the installation process and print success msg
sudo launchctl bootstrap system /Library/LaunchDaemons/com.wazuh.agent.plist
echo "Done. Wazuh agent installed and started."
