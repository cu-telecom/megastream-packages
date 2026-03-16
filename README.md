# megastream-packages

A selection of packages for the CuTEL Megastream NTUs

## Packages

### megastream-led-driver

Monitors a WireGuard interface on OpenWrt and drives an LED based on keepalive status.

## Feed Setup

### Adding the feed

```sh
echo "https://cu-telecom.github.io/megastream-packages" > /etc/apk/repositories.d/megastream.list
```

Or, to persist across firmware upgrades:

```sh
cat > /etc/uci-defaults/99-megastream-feed <<'EOF'
#!/bin/sh
echo "https://cu-telecom.github.io/megastream-packages" > /etc/apk/repositories.d/megastream.list
EOF
```

### Installing packages

```sh
apk update --allow-untrusted
apk add --allow-untrusted megastream-led-driver
```

### Building the feed

On your build machine:

```sh
# Build all packages and generate the feed index
./build.sh

# Build a specific package
./build.sh packages/megastream-led-driver
```

Build packages are written to `dist/`. 