#!/bin/ash

IFACE="wg0"
MAX_AGE=150
INTERVAL=""
WG_INTERVAL=10
LAST_WG_CHECK=0

set_led_path() {
    local path="/sys/class/leds/$1"
    local trigger="$path/trigger"
    local bright="$path/brightness"
    grep -q '\[none\]' "$trigger" 2>/dev/null || echo none > "$trigger" 2>/dev/null
    echo "$2" > "$bright" 2>/dev/null
}

set_led() {
    set_led_path "$WG_LED" "$1"
}

port_link_up() {
    swconfig dev switch0 port "$1" get link 2>/dev/null | grep -q 'link:up'
}

check_eth_interfaces() {
    case "$BOARD" in
        ruckus,r500)
            port_link_up 5 && set_led_path green:wlan-2ghz 1 || set_led_path green:wlan-2ghz 0
            port_link_up 3 && set_led_path green:air 1       || set_led_path green:air 0
            ;;
    esac
}

check_status() {
    now=$(date +%s)
    handshake=$(wg show "$IFACE" dump | awk 'NR==2 {print $5}')

    if [ -z "$handshake" ] || [ "$handshake" = "0" ]; then
        set_led 0
        return 1
    fi

    age=$((now - handshake))

    if [ "$age" -lt "$MAX_AGE" ]; then
        set_led 1
        return 0
    else
        set_led 0
        return 1
    fi
}

# ---- argument parsing ----

while [ $# -gt 0 ]; do
    case "$1" in
        -d|--daemon)
            INTERVAL="$2"
            shift 2
            ;;
        *)
            echo "usage: $0 [-d interval]"
            exit 1
            ;;
    esac
done

# ---- detect board ----

BOARD=$(ubus call system board 2>/dev/null | jsonfilter -e '@.board_name')

case "$BOARD" in
    ruckus,r500) WG_LED="green:power" ;;
    *)           WG_LED="green:radio1" ;;
esac

# ---- run once or daemon ----

if [ -n "$INTERVAL" ]; then
    while true; do
        now=$(date +%s)
        if [ $((now - LAST_WG_CHECK)) -ge $WG_INTERVAL ]; then
            check_status
            LAST_WG_CHECK=$now
        fi
        check_eth_interfaces
        sleep "$INTERVAL"
    done
else
    check_status
    check_eth_interfaces
fi
