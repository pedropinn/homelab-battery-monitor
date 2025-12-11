# Homelab Battery Monitor

Automated power management for homelab environments. Uses a notebook with battery as a controller to manage server shutdown/startup during power outages, with UPS monitoring via NUT.

## How It Works

When AC power fails, the notebook (running on battery) monitors both time elapsed and UPS battery level. Servers are shut down when either condition is met:
- **10 minutes** on battery power OR **UPS battery drops to 70%** 

When power returns, it waits 3 minutes and wakes servers using Wake-on-LAN.

## Architecture

```
┌─────────────────────┐     ┌─────────────────────┐
│  Notebook           │     │  UPS (APC 1500VA)   │
│  (Controller)       │     │                     │
│                     │     │  ┌─────────────┐    │
│  - Wall outlet      │     │  │ Servers     │    │
│  - Own battery      │ NUT │  │ Switch      │    │
│  - Monitor script ──┼─────┼──│ Access Pts  │    │
│                     │     │  └─────────────┘    │
└─────────────────────┘     └─────────────────────┘
```

The notebook must be plugged directly to the wall outlet, not the UPS. This allows it to detect power failures independently and monitor the UPS via NUT (Network UPS Tools).

## Prerequisites

**Controller notebook:**
- Linux (Debian-based tested)
- Connected directly to wall outlet
- ACPI support for battery detection
- Network access to UPS server (NUT)

**UPS Server (where UPS is connected):**
- NUT server configured and running
- `upsd` listening on network
- User credentials configured in `/etc/nut/upsd.users`

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
1. Install required packages (acpi, wakeonlan, openssh-client, nut, nut-client)
2. Generate SSH keys if needed
3. Configure NUT client for UPS monitoring
4. Prompt for target server IPs and MAC addresses
5. Configure log rotation
6. Install `ups-status` utility (runs on login)
7. Install and start the monitoring service

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
OTHER_NODES=(
    "root,10.10.10.30,84:47:09:0c:83:2d"
    "admin,10.10.10.31,84:47:09:0c:83:2e"
)
```

Format: USER,IP,MAC

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
tail -f /var/log/battery-monitor/monitor.log
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

**UPS not detected:**
```bash
# Test connection to UPS
upsc apc@localhost

# Check NUT client status
systemctl status nut-client
```

## UPS Server Configuration

The UPS must be connected to a server running NUT. Configure the server to allow remote monitoring:

**On the UPS server, edit `/etc/nut/upsd.users`:**
```
[upsmon]
    password = YOUR_PASSWORD
    upsmon slave
```

**Edit `/etc/nut/upsd.conf` to allow network access:**
```
LISTEN 0.0.0.0 3493
```

**Restart NUT server:**
```bash
systemctl restart nut-server
```

## Utilities

**ups-status** - Displays current UPS and notebook battery status. Automatically shown on login.
```bash
ups-status
```
