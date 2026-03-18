#!/bin/sh
# ZTP config update script
# Fetches config from server, applies only changed packages, restarts affected services

DRY_RUN=0
[ "$1" = "--test" ] && DRY_RUN=1

SERVER=$(uci get ztp.config.server 2>/dev/null || echo "http://192.168.1.1/config")
MAC=$(cat /sys/class/net/$(uci get network.wan.device)/address | tr -d ':' | awk '{print toupper($0)}')
CONFIG_URL="${SERVER}/${MAC}"

ETAG=$(uci get ztp.config.etag 2>/dev/null)
TMP_CONFIG="/tmp/ztp_pending.uci"
TMP_HEADERS="/tmp/ztp_headers.txt"

MAX_TRIES=10
RETRY_INTERVAL=60

[ "$DRY_RUN" = "1" ] && logger -s -t ztp "Running in test mode, no changes will be applied"
logger -s -t ztp "Starting. URL: $CONFIG_URL ETag: ${ETAG:-(none)}"

# ---------------------------------------------------------------------------
# Functions
# ---------------------------------------------------------------------------

fetch_config() {
    logger -s -t ztp "Fetching config..."
    HTTP_CODE=$(curl -s \
        --max-time 30 \
        -o "$TMP_CONFIG" \
        -D "$TMP_HEADERS" \
        -w "%{http_code}" \
        ${ETAG:+-H "If-None-Match: $ETAG"} \
        "$CONFIG_URL")
    logger -s -t ztp "HTTP response: $HTTP_CODE"
}

extract_package() {
    local pkg="$1"
    awk "
        /^package ${pkg}\$/ { found=1; print; next }
        /^package /         { if (found) exit }
        found               { print }
    " "$TMP_CONFIG"
}

restart_for_package() {
    local pkg="$1"
    case "$pkg" in
        network)  /etc/init.d/network restart ;;
        firewall) /etc/init.d/firewall restart ;;
        dhcp)     /etc/init.d/dnsmasq restart ;;
        system)   /etc/init.d/system restart ;;
        wireless) wifi reload ;;
        *)        [ -x "/etc/init.d/$pkg" ] && /etc/init.d/$pkg restart ;;
    esac
}

# ---------------------------------------------------------------------------
# Fetch config from server with retries
# ---------------------------------------------------------------------------

tries=0
while [ "$tries" -lt "$MAX_TRIES" ]; do
    fetch_config
    case "$HTTP_CODE" in
        200|304) break ;;
        *)
            tries=$((tries + 1))
            logger -s -t ztp "Unexpected response $HTTP_CODE, attempt $tries/$MAX_TRIES, retrying in ${RETRY_INTERVAL}s"
            [ "$tries" -lt "$MAX_TRIES" ] && sleep "$RETRY_INTERVAL"
            ;;
    esac
done

case "$HTTP_CODE" in
    304)
        logger -s -t ztp "Config up to date"
        exit 0
        ;;
    200)
        ;;
    *)
        logger -s -t ztp "Failed after $MAX_TRIES attempts, last response: $HTTP_CODE"
        exit 1
        ;;
esac

# ---------------------------------------------------------------------------
# Diff per-package to determine which services need restarting
# ---------------------------------------------------------------------------

logger -s -t ztp "Checking for changes..."

CHANGED_PKGS=""
for pkg in $(grep '^package ' "$TMP_CONFIG" | awk '{print $2}'); do
    [ "$pkg" = "ztp" ] && continue

    current=$(uci export "$pkg" 2>/dev/null)
    incoming=$(extract_package "$pkg")

    if [ "$current" != "$incoming" ]; then
        CHANGED_PKGS="$CHANGED_PKGS $pkg"
        logger -s -t ztp "Changed: $pkg"
        diff <(echo "$current") <(echo "$incoming") >&2
    else
        logger -s -t ztp "Unchanged: $pkg"
    fi
done

# ---------------------------------------------------------------------------
# Apply config (skipped in test mode)
# ---------------------------------------------------------------------------

if [ "$DRY_RUN" = "1" ]; then
    logger -s -t ztp "Test mode: would apply changes to packages:${CHANGED_PKGS:- none}"
    exit 0
fi

logger -s -t ztp "Importing config..."
uci import < "$TMP_CONFIG"

# Save new ETag into ztp state (overrides whatever the server sent for ztp.config.etag)
NEW_ETAG=$(grep -i '^etag:' "$TMP_HEADERS" | tr -d '\r' | awk '{print $2}')
if [ -n "$NEW_ETAG" ]; then
    logger -s -t ztp "Saving ETag: $NEW_ETAG"
    uci set ztp.config.etag="$NEW_ETAG"
    uci commit ztp
fi

# ---------------------------------------------------------------------------
# Install any packages listed in ztp config
# ---------------------------------------------------------------------------

PKGS=$(uci get ztp.config.packages 2>/dev/null)
if [ -n "$PKGS" ]; then
    for pkg in $PKGS; do
        if apk info -e "$pkg" 2>/dev/null; then
            logger -s -t ztp "Package already installed: $pkg"
        else
            logger -s -t ztp "Installing package: $pkg"
            apk update 2>/dev/null
            apk add "$pkg"
        fi
    done
fi

# ---------------------------------------------------------------------------
# Restart only affected services
# ---------------------------------------------------------------------------

for pkg in $CHANGED_PKGS; do
    logger -s -t ztp "Restarting service for: $pkg"
    restart_for_package "$pkg"
done

logger -s -t ztp "Done. Changed packages:${CHANGED_PKGS:- none}"

# ---------------------------------------------------------------------------
# Download and apply any file sections
# ---------------------------------------------------------------------------

uci show ztp 2>/dev/null | grep -o 'ztp\.@file\[[0-9]*\]' | sort -u | while read section; do
    dest=$(uci get ${section}.dest 2>/dev/null)
    delete=$(uci get ${section}.delete 2>/dev/null)

    [ -z "$dest" ] && continue

    if [ "$delete" = "1" ]; then
        if [ -e "$dest" ]; then
            logger -s -t ztp "Deleting: $dest"
            rm -f "$dest"
        else
            logger -s -t ztp "Already absent: $dest"
        fi
        continue
    fi

    url=$(uci get ${section}.url 2>/dev/null)
    mode=$(uci get ${section}.mode 2>/dev/null || echo '0644')
    run=$(uci get ${section}.run 2>/dev/null)

    [ -z "$url" ] && continue

    logger -s -t ztp "Checking file: $dest"
    file_tries=0
    while [ "$file_tries" -lt "$MAX_TRIES" ]; do
        FILE_CODE=$(curl -s --max-time 30 -o /tmp/ztp_file.tmp -w "%{http_code}" "$url")
        case "$FILE_CODE" in
            200) break ;;
            *)
                file_tries=$((file_tries + 1))
                logger -s -t ztp "Download failed (HTTP $FILE_CODE): $url, attempt $file_tries/$MAX_TRIES"
                [ "$file_tries" -lt "$MAX_TRIES" ] && sleep "$RETRY_INTERVAL"
                ;;
        esac
    done

    if [ "$FILE_CODE" != "200" ] || [ ! -s /tmp/ztp_file.tmp ]; then
        logger -s -t ztp "Download failed after $MAX_TRIES attempts: $url"
        rm -f /tmp/ztp_file.tmp
        continue
    fi

    if ! diff -q /tmp/ztp_file.tmp "$dest" > /dev/null 2>&1; then
        logger -s -t ztp "Updating: $dest"
        mv /tmp/ztp_file.tmp "$dest"
        chmod "$mode" "$dest"
        [ "$run" = "1" ] && logger -s -t ztp "Running: $dest" && "$dest"
    else
        logger -s -t ztp "Unchanged: $dest"
        rm /tmp/ztp_file.tmp
    fi
done

# ---------------------------------------------------------------------------
# Self-update (must be last — mv is atomic, new script takes effect next run)
# ---------------------------------------------------------------------------

SCRIPT_URL=$(uci get ztp.config.script_url 2>/dev/null)
if [ -n "$SCRIPT_URL" ]; then
    logger -s -t ztp "Checking for script update..."
    curl -s -o /tmp/ztp-update.new "$SCRIPT_URL"
    if [ -s /tmp/ztp-update.new ]; then
        if ! diff -q /tmp/ztp-update.new /usr/sbin/ztp-update.sh > /dev/null 2>&1; then
            logger -s -t ztp "Updating ztp-update.sh"
            chmod +x /tmp/ztp-update.new
            mv /tmp/ztp-update.new /usr/sbin/ztp-update.sh
            if [ "$(uci get ztp.config.script_run 2>/dev/null)" = "1" ]; then
                logger -s -t ztp "Running updated script"
                /usr/sbin/ztp-update.sh &
            fi
        else
            logger -s -t ztp "Script already up to date"
            rm /tmp/ztp-update.new
        fi
    else
        logger -s -t ztp "Script download failed or empty"
    fi
fi
