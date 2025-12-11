#!/bin/bash

set -e

echo "========================================="
echo "Battery Monitor Uninstall"
echo "========================================="
echo ""

if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root"
    exit 1
fi

echo "Step 1: Stopping and disabling service..."
systemctl stop battery-monitor.service 2>/dev/null || true
systemctl disable battery-monitor.service 2>/dev/null || true
rm -f /etc/systemd/system/battery-monitor.service
systemctl daemon-reload
echo "Service removed"

echo ""
echo "Step 2: Removing battery-monitor script..."
rm -f /usr/local/bin/battery-monitor.sh
echo "Script removed"

echo ""
echo "Step 3: Removing ups-status utility..."
rm -f /usr/local/bin/ups-status
sed -i '/ups-status/d' /etc/profile 2>/dev/null || true
echo "ups-status removed"

echo ""
echo "Step 4: Removing logrotate configuration..."
rm -f /etc/logrotate.d/battery-monitor
echo "Logrotate configuration removed"

echo ""
echo "Step 5: Stopping NUT services..."
systemctl stop nut-monitor 2>/dev/null || true
systemctl stop nut-server 2>/dev/null || true
upsdrvctl stop 2>/dev/null || true
echo "NUT services stopped"

echo ""
echo "Step 6: Removing NUT configuration..."
rm -f /etc/nut/nut.conf
rm -f /etc/nut/ups.conf
rm -f /etc/nut/upsd.conf
rm -f /etc/nut/upsd.users
rm -f /etc/nut/upsmon.conf
echo "NUT configuration removed"

echo ""
echo "Step 7: Cleaning up state and log directories..."
rm -rf /var/lib/battery-monitor
rm -rf /var/log/battery-monitor
echo "State and log directories removed"

echo ""
echo "========================================="
echo "Uninstall complete!"
echo "========================================="
echo ""
echo "Note: The following were NOT removed:"
echo "  - Installed packages (acpi, wakeonlan, nut, nut-client, nut-server)"
echo "  - SSH keys (/root/.ssh/id_rsa)"
echo ""
echo "To remove packages manually:"
echo "  apt remove acpi wakeonlan nut nut-client nut-server"
