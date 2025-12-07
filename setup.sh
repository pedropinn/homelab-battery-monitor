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
apt install -y acpi wakeonlan openssh-client nut nut-client nut-server

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
echo "Step 3: Detecting and configuring UPS..."

# Check for USB UPS
if lsusb | grep -qi "american power conversion\|051d"; then
    echo "APC UPS detected via USB"
else
    echo "Warning: No APC UPS detected. Make sure USB cable is connected."
fi

# Configure NUT as standalone
echo "MODE=standalone" > /etc/nut/nut.conf

# Configure UPS driver
cat > /etc/nut/ups.conf << 'EOF'
[apc]
    driver = usbhid-ups
    port = auto
    desc = "APC Back-UPS"
EOF

# Configure upsd server
cat > /etc/nut/upsd.conf << 'EOF'
LISTEN 127.0.0.1 3493
EOF

# Configure upsd users
cat > /etc/nut/upsd.users << 'EOF'
[admin]
    password = admin
    actions = SET
    instcmds = ALL

[upsmon]
    password = upsmon
    upsmon master
EOF

# Configure upsmon
cat > /etc/nut/upsmon.conf << 'EOF'
MONITOR apc@localhost 1 upsmon upsmon master
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

# Set permissions
chown root:nut /etc/nut/ups.conf /etc/nut/upsd.conf /etc/nut/upsd.users /etc/nut/upsmon.conf
chmod 640 /etc/nut/upsd.users /etc/nut/upsmon.conf
chmod 644 /etc/nut/nut.conf /etc/nut/ups.conf /etc/nut/upsd.conf

# Start NUT services
echo "Starting NUT services..."
upsdrvctl start
systemctl restart nut-server
systemctl restart nut-monitor

# Test connection
echo "Testing UPS connection..."
sleep 10
if upsc apc@localhost ups.status &>/dev/null; then
    echo "UPS connection successful!"
    echo "  Battery: $(upsc apc@localhost battery.charge 2>/dev/null)%"
    echo "  Status: $(upsc apc@localhost ups.status 2>/dev/null)"
else
    echo "Warning: Could not connect to UPS. Check 'systemctl status nut-server'"
fi

echo ""
echo "Step 4: Configure target nodes"
echo "Enter nodes in format: IP,MAC (e.g., 10.10.10.30,84:47:09:0c:83:2d)"
echo "Press Enter with empty input to finish"
echo ""

nodes=()

while true; do
    read -p "Node (IP,MAC or Enter to finish): " node_input
    if [ -z "$node_input" ]; then
        break
    fi

    # Validate format
    if ! echo "$node_input" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+,[0-9a-fA-F:]+$'; then
        echo "Error: Invalid format. Use IP,MAC (e.g., 10.10.10.30,84:47:09:0c:83:2d)"
        continue
    fi

    nodes+=("$node_input")
    echo "Added: $node_input"
    echo ""
done

if [ ${#nodes[@]} -eq 0 ]; then
    echo "Error: No nodes configured. At least one node is required."
    exit 1
fi

echo ""
echo "Step 5: Creating configuration file..."
cp "$SCRIPT_DIR/battery-monitor.sh" "$INSTALL_PATH"

# Build the nodes array configuration
nodes_config="OTHER_NODES=("
for node in "${nodes[@]}"; do
    nodes_config="${nodes_config}\n    \"${node}\""
done
nodes_config="${nodes_config}\n)"

sed -i "/^OTHER_NODES=(/,/^)/c\\${nodes_config}" "$INSTALL_PATH"

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
for node in "${nodes[@]}"; do
    ip=$(echo "$node" | cut -d',' -f1)
    echo "   ssh-copy-id root@$ip"
done
echo ""
echo "2. Test SSH connection to each server:"
for node in "${nodes[@]}"; do
    ip=$(echo "$node" | cut -d',' -f1)
    echo "   ssh root@$ip 'echo Connection OK'"
done
echo ""
echo "3. Enable Wake-on-LAN on each server:"
for node in "${nodes[@]}"; do
    ip=$(echo "$node" | cut -d',' -f1)
    echo "   ssh root@$ip 'ethtool -s eth0 wol g'"
done
echo ""
echo "4. Monitor logs:"
echo "   tail -f /var/log/battery-monitor.log"
echo ""
echo "Setup complete. Service is running."
