#!/bin/bash
 
BATTERY_WAIT_TIME=300      # 5 minutes on battery before shutting down other nodes
BATTERY_CRITICAL_LEVEL=15  # Battery % to shutdown this notebook
POWER_WAIT_TIME=180        # 3 minutes with power before waking up other nodes
CHECK_INTERVAL=30          # Check every 30 seconds
BATTERY_LOG_INTERVAL=60    # Log battery every 1 minute
SHUTDOWN_VERIFY_TIME=60    # 1 minutes to verify nodes shutdown

STATE_FILE="/tmp/battery_state"
WAKEUP_DONE_FILE="/tmp/wakeup_done"
SHUTDOWN_DONE_FILE="/tmp/shutdown_done"
LOG_FILE="/var/log/battery-shutdown.log"

declare -A OTHER_NODES
OTHER_NODES["10.10.10.30"]="84:47:09:0c:83:2d"


LAST_BATTERY_LOG=0

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

is_on_battery() {
    acpi -a | grep -q "off-line"
}

get_battery_level() {
    acpi -b | grep -oP '\d+(?=%)' | head -1
}

is_host_online() {
    ping -c 1 -W 2 "$1" &>/dev/null
}


has_nodes_offline() {
    for node_ip in "${!OTHER_NODES[@]}"; do
        if ! is_host_online "$node_ip"; then
            return 0  
        fi
    done
    return 1 
}

shutdown_local_vms() {
    for vmid in $(qm list 2>/dev/null | awk 'NR>1 {print $1}'); do
        qm shutdown $vmid --timeout 60 &
    done
    
    for ctid in $(pct list 2>/dev/null | awk 'NR>1 {print $1}'); do
        pct shutdown $ctid &
    done
    
    sleep 60
}

shutdown_other_nodes() {
    for node_ip in "${!OTHER_NODES[@]}"; do
        if is_host_online "$node_ip"; then
            log_message "Node $node_ip shutting down"
            ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no root@"$node_ip" "shutdown -h now" 2>/dev/null &
        fi
    done
    
    sleep 15
    
    echo "shutdown_time=$(date +%s)" > "$SHUTDOWN_DONE_FILE"
    echo "verification_logged=no" >> "$SHUTDOWN_DONE_FILE"
    for node_ip in "${!OTHER_NODES[@]}"; do
        echo "node_${node_ip//./_}=pending" >> "$SHUTDOWN_DONE_FILE"
    done
}

verify_nodes_shutdown() {
    if [ ! -f "$SHUTDOWN_DONE_FILE" ]; then
        return
    fi
    
    source "$SHUTDOWN_DONE_FILE"
    local current_time=$(date +%s)
    local elapsed=$((current_time - shutdown_time))
    
    if [ $elapsed -lt $SHUTDOWN_VERIFY_TIME ]; then
        return
    fi
    
    for node_ip in "${!OTHER_NODES[@]}"; do
        local var_name="node_${node_ip//./_}"
        local status="${!var_name}"
        
        if [ "$status" = "pending" ]; then
            if ! is_host_online "$node_ip"; then
                log_message "Node $node_ip shut down"
                sed -i "s/node_${node_ip//./_}=pending/node_${node_ip//./_}=down/" "$SHUTDOWN_DONE_FILE"
            fi
        fi
    done
    
    if [ "$verification_logged" = "no" ]; then
        local all_verified=true
        for node_ip in "${!OTHER_NODES[@]}"; do
            local var_name="node_${node_ip//./_}"
            source "$SHUTDOWN_DONE_FILE"
            local status="${!var_name}"
            if [ "$status" = "pending" ]; then
                all_verified=false
                break
            fi
        done
        
        if [ "$all_verified" = true ]; then
            sed -i "s/verification_logged=no/verification_logged=yes/" "$SHUTDOWN_DONE_FILE"
        fi
    fi
}

wakeup_other_nodes() {
    for node_ip in "${!OTHER_NODES[@]}"; do
        mac="${OTHER_NODES[$node_ip]}"
        
        if is_host_online "$node_ip"; then
            log_message "Node $node_ip already online"
        else
            log_message "Node $node_ip woken up"
            wakeonlan "$mac"
            sleep 2
        fi
    done
    
    touch "$WAKEUP_DONE_FILE"
    rm -f "$STATE_FILE"
    rm -f "$SHUTDOWN_DONE_FILE"
}

handle_battery_state() {
    local battery_level=$(get_battery_level)
    local current_time=$(date +%s)
    
    if [ -f "$STATE_FILE" ]; then
        source "$STATE_FILE"
    fi
    
    if [ -z "$on_battery" ] || [ "$on_battery" -lt $((current_time - 7200)) ]; then
        on_battery=$current_time
        echo "on_battery=$on_battery" > "$STATE_FILE"
        echo "disconnected_logged=no" >> "$STATE_FILE"
        rm -f "$SHUTDOWN_DONE_FILE"
        rm -f "$WAKEUP_DONE_FILE"
        LAST_BATTERY_LOG=$current_time
        log_message "Power disconnected"
        return
    fi
    
    local elapsed=$((current_time - on_battery))
    
    if [ $elapsed -ge $BATTERY_WAIT_TIME ] && [ ! -f "$SHUTDOWN_DONE_FILE" ]; then
        shutdown_local_vms
        shutdown_other_nodes
        LAST_BATTERY_LOG=0
    elif [ ! -f "$SHUTDOWN_DONE_FILE" ]; then
        local remaining=$((BATTERY_WAIT_TIME - elapsed))
        log_message "Waiting ${BATTERY_WAIT_TIME} seconds to shutdown nodes, elapsed ${elapsed}"
    else
        verify_nodes_shutdown
        
        if [ $LAST_BATTERY_LOG -eq 0 ] || [ $((current_time - LAST_BATTERY_LOG)) -ge $BATTERY_LOG_INTERVAL ]; then
            log_message "Battery at ${battery_level}%"
            LAST_BATTERY_LOG=$current_time
        fi
    fi
    
    if [ "$battery_level" -le "$BATTERY_CRITICAL_LEVEL" ]; then
        log_message "CRITICAL BATTERY: ${battery_level}% - Shutting down this notebook"
        shutdown -h now
        exit 0
    fi
}

handle_power_restored() {
    local current_time=$(date +%s)
    
    if [ -f "$WAKEUP_DONE_FILE" ]; then
        return
    fi
    
    if [ -f "$STATE_FILE" ]; then
        source "$STATE_FILE"
    fi
    
    if [ -n "$on_battery" ]; then
        if has_nodes_offline; then
            echo "on_power=$current_time" > "$STATE_FILE"
            log_message "Power connected"
            rm -f "$SHUTDOWN_DONE_FILE"
        else
            touch "$WAKEUP_DONE_FILE"
            rm -f "$STATE_FILE"
        fi
        return
    fi
    
    if [ -z "$on_power" ]; then
        if has_nodes_offline; then
            echo "on_power=$current_time" > "$STATE_FILE"
            log_message "Power connected"
        else
            touch "$WAKEUP_DONE_FILE"
            rm -f "$STATE_FILE"
        fi
        return
    fi
    
    if [ "$on_power" -lt $((current_time - 7200)) ]; then
        if has_nodes_offline; then
            echo "on_power=$current_time" > "$STATE_FILE"
            log_message "Power connected"
        else
            touch "$WAKEUP_DONE_FILE"
            rm -f "$STATE_FILE"
        fi
        return
    fi
    
    local elapsed=$((current_time - on_power))

    log_message "Waiting ${POWER_WAIT_TIME} seconds, elapsed ${elapsed}"
    
    if [ $elapsed -ge $POWER_WAIT_TIME ]; then
        wakeup_other_nodes
    fi
}

rm -f "$STATE_FILE" "$WAKEUP_DONE_FILE" "$SHUTDOWN_DONE_FILE"

log_message "========================================="
log_message "Battery Monitor started"
log_message "========================================="
while true; do
    if is_on_battery; then
        handle_battery_state
    else
        handle_power_restored
    fi
    
    sleep $CHECK_INTERVAL
done
