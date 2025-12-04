# Homelab Battery Monitor

Automated power management for homelab environments. Uses a notebook with battery as a controller to manage server shutdown/startup during power outages.

## How It Works

When AC power fails, the notebook (running on battery) waits 10 minutes, then shuts down configured servers via SSH. When power returns, it waits 5 minutes and wakes servers using Wake-on-LAN.

## Architecture

```
Notebook (Controller)        UPS/Nobreak
- Wall outlet powered        - Servers (managed)
- Has battery backup         - Switch
- Runs monitor script        - Access Points
                             
```

The notebook must be plugged directly to the wall outlet, not the UPS. This allows it to detect power failures independently.

## Prerequisites

**Controller notebook:**
- Linux (Debian-based tested)
- Connected directly to wall outlet
- ACPI support for battery detection

**Target servers:**
- SSH root access with key authentication
- Wake-on-LAN enabled in BIOS
- Network interface supports WoL

## Quick Installation

Run the setup script as root:

```bash
git clone https://github.com/YOUR-USERNAME/homelab-battery-monitor.git
cd homelab-battery-monitor
chmod +x setup.sh
./setup.sh
```

The script will:
1. Install required packages (acpi, wakeonlan, openssh-client)
2. Generate SSH keys if needed
3. Prompt for target server IPs and MAC addresses
4. Configure log rotation
5. Install and start the monitoring service

After setup completes, copy SSH keys to each server:

```bash
ssh-copy-id root@SERVER_IP
```

## Manual Installation

If not using setup.sh, follow these steps:

**1. Install packages on controller:**
```bash
apt update
apt install acpi wakeonlan openssh-client
```

**3. Configure SSH keys on controller:**
```bash
ssh-keygen -t rsa -b 4096 -N "" -f /root/.ssh/id_rsa
ssh-copy-id root@SERVER_IP
```

**2. Install ethtool on each server:**
```bash
apt update
apt install ethtool
```

**4. Enable Wake-on-LAN on each server:**
```bash
# Enable WoL
ethtool -s eth0 wol g

# Make it persistent
echo 'ethtool -s eth0 wol g' >> /etc/rc.local
chmod +x /etc/rc.local
```


**5. Edit battery-monitor.sh and configure your servers:

```bash
declare -A OTHER_NODES
OTHER_NODES["10.10.10.30"]="84:47:09:0c:83:2d"
OTHER_NODES["10.10.10.31"]="84:47:09:0c:83:2e"
```

Format: IP="MAC_ADDRESS"

Find MAC addresses on each server:
```bash
ip link show | grep "link/ether"
```

**6. Install logrotate configuration:**
```bash
cp battery-monitor /etc/logrotate.d/battery-monitor
chmod 644 /etc/logrotate.d/battery-monitor
```

**7. Install the service:**
```bash
cp battery-monitor.sh /usr/local/bin/
chmod +x /usr/local/bin/battery-monitor.sh
cp battery-monitor.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable battery-monitor.service
systemctl start battery-monitor.service
```

## Monitoring

View logs:
```bash
tail -f /var/log/battery-shutdown.log
```

Check service status:
```bash
systemctl status battery-monitor.service
```

Log rotation is configured automatically (daily rotation, keeps 7 days, max 10MB per file).

## Troubleshooting

**Battery not detected:**
```bash
acpi -a  # Should show on-line/off-line
```

**SSH fails:**
```bash
ssh root@SERVER_IP  # Test connection
```

**Wake-on-LAN not working:**
```bash
# On server, verify WoL enabled:
ethtool eth0 | grep Wake-on
# Should show: Wake-on: g

# Enable if needed:
ethtool -s eth0 wol g
```
