#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_PATH="/usr/local/bin/battery-monitor.sh"
SERVICE_PATH="/etc/systemd/system/battery-monitor.service"

echo "========================================="
echo "Battery Monitor Setup"
echo "========================================="
echo ""

if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root"
    exit 1
fi

echo "Step 1: Installing required packages..."
apt update
apt install -y acpi wakeonlan openssh-client nut nut-client

echo ""
echo "Step 2: Setting up SSH keys..."
if [ ! -f /root/.ssh/id_rsa ]; then
    echo "Generating SSH key pair..."
    ssh-keygen -t rsa -b 4096 -N "" -f /root/.ssh/id_rsa
    echo "SSH key generated at /root/.ssh/id_rsa"
else
    echo "SSH key already exists, skipping generation"
fi

echo ""
echo "Step 3: Configure UPS monitoring (NUT)"
echo ""
read -p "UPS name (e.g., apc@localhost or apc@192.168.1.100): " ups_name
if [ -z "$ups_name" ]; then
    ups_name="apc@localhost"
fi

read -p "NUT username: " nut_user
if [ -z "$nut_user" ]; then
    nut_user="upsmon"
fi

read -sp "NUT password: " nut_pass
echo ""

echo "MODE=netclient" > /etc/nut/nut.conf

cat > /etc/nut/upsmon.conf << EOF
MONITOR $ups_name 1 $nut_user $nut_pass slave
MINSUPPLIES 1
SHUTDOWNCMD "/sbin/shutdown -h now"
POLLFREQ 5
POLLFREQALERT 5
HOSTSYNC 15
DEADTIME 15
RBWARNTIME 43200
NOCOMMWARNTIME 300
FINALDELAY 5
EOF

chmod 640 /etc/nut/upsmon.conf
chown root:nut /etc/nut/upsmon.conf

systemctl restart nut-client 2>/dev/null || true

echo "Testing UPS connection..."
if upsc "$ups_name" ups.status &>/dev/null; then
    echo "UPS connection successful!"
else
    echo "Warning: Could not connect to UPS. Please verify the UPS server configuration."
fi

echo ""
echo "Step 4: Configure target nodes"
echo "Enter the IP addresses and MAC addresses of servers to manage"
echo "Press Enter with empty IP to finish"
echo ""

declare -A nodes

while true; do
    read -p "Server IP (or Enter to finish): " ip
    if [ -z "$ip" ]; then
        break
    fi

    read -p "MAC address for $ip: " mac
    if [ -z "$mac" ]; then
        echo "Error: MAC address cannot be empty"
        continue
    fi

    nodes["$ip"]="$mac"
    echo "Added: $ip -> $mac"
    echo ""
done

if [ ${#nodes[@]} -eq 0 ]; then
    echo "Error: No nodes configured. At least one node is required."
    exit 1
fi

echo ""
echo "Step 5: Creating configuration file..."
cp "$SCRIPT_DIR/battery-monitor.sh" "$INSTALL_PATH"

# Update UPS name in the script
sed -i "s|UPS_NAME=\"apc@localhost\"|UPS_NAME=\"$ups_name\"|" "$INSTALL_PATH"

config_line="declare -A OTHER_NODES"
for ip in "${!nodes[@]}"; do
    config_line="${config_line}\nOTHER_NODES[\"${ip}\"]=\"${nodes[$ip]}\""
done

sed -i "/^declare -A OTHER_NODES/,/^$/c\\${config_line}\n" "$INSTALL_PATH"

chmod +x "$INSTALL_PATH"
echo "Installed to $INSTALL_PATH"

echo ""
echo "Step 6: Installing logrotate configuration..."
cp "$SCRIPT_DIR/battery-monitor" /etc/logrotate.d/battery-monitor
chmod 644 /etc/logrotate.d/battery-monitor
echo "Logrotate configured at /etc/logrotate.d/battery-monitor"

echo ""
echo "Step 7: Installing ups-status utility..."
cp "$SCRIPT_DIR/ups-status" /usr/local/bin/ups-status
chmod +x /usr/local/bin/ups-status

# Update UPS name in ups-status
sed -i "s|UPS=\"apc@localhost\"|UPS=\"$ups_name\"|" /usr/local/bin/ups-status

# Add to /etc/profile for login display
if ! grep -q "ups-status" /etc/profile; then
    echo 'ups-status' >> /etc/profile
    echo "ups-status added to /etc/profile"
fi

echo ""
echo "Step 8: Installing systemd service..."
cp "$SCRIPT_DIR/battery-monitor.service" "$SERVICE_PATH"
systemctl daemon-reload
systemctl enable battery-monitor.service
systemctl start battery-monitor.service

echo ""
echo "========================================="
echo "Installation complete!"
echo "========================================="
echo ""
echo "Service status:"
systemctl status battery-monitor.service --no-pager -l

echo ""
echo "Next steps:"
echo "1. Copy SSH keys to each server:"
for ip in "${!nodes[@]}"; do
    echo "   ssh-copy-id root@$ip"
done
echo ""
echo "2. Test SSH connection to each server:"
for ip in "${!nodes[@]}"; do
    echo "   ssh root@$ip 'echo Connection OK'"
done
echo ""
echo "3. Enable Wake-on-LAN on each server:"
for ip in "${!nodes[@]}"; do
    echo "   ssh root@$ip 'ethtool -s eth0 wol g'"
done
echo ""
echo "4. Monitor logs:"
echo "   tail -f /var/log/battery-shutdown.log"
echo ""
echo "Setup complete. Service is running."
