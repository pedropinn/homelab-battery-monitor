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
echo "Step 5: Removing NUT client configuration..."
rm -f /etc/nut/nut.conf
rm -f /etc/nut/upsmon.conf
systemctl stop nut-client 2>/dev/null || true
echo "NUT configuration removed"

echo ""
echo "Step 6: Cleaning up state files..."
rm -f /tmp/battery_state
rm -f /tmp/wakeup_done
rm -f /tmp/shutdown_done
echo "State files removed"

echo ""
echo "========================================="
echo "Uninstall complete!"
echo "========================================="
echo ""
echo "Note: The following were NOT removed:"
echo "  - Installed packages (acpi, wakeonlan, nut, nut-client)"
echo "  - SSH keys (/root/.ssh/id_rsa)"
echo "  - Log file (/var/log/battery-monitor.log)"
echo ""
echo "To remove packages manually:"
echo "  apt remove acpi wakeonlan nut nut-client"
echo ""
echo "To remove log file:"
echo "  rm /var/log/battery-monitor.log"
