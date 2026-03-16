# megastream-led-driver

Monitors a WireGuard interface on OpenWrt and drives an LED based on keepalive status.

## Feed Setup

### Adding the feed

Packages are unsigned. The feed URL must point to the directory where `APKINDEX.tar.gz` is served — the contents of `dist/`, not the directory itself.

```sh
echo "https://<your-host>/<path-to-dist-contents>" >> /etc/apk/repositories
```

For example, if `dist/` is your web root: `https://<your-host>/`
If served under a subpath: `https://<your-host>/packages`

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

Output is written to `dist/`. Host the contents of that directory on any web server.

## Device Notes

### Ruckus R500

**Switch:** Atheros AR8xxx via `swconfig`, device `switch0`

**CPU port mapping:**

| Switch Port | Interface | Role |
|---|---|---|
| Port 6 | eth0 | CPU port — WAN |
| Port 0 | eth1 | CPU port — LAN |

**VLAN layout:**

| VLAN | Ports | Purpose |
|---|---|---|
| 1 | 0, 3 | LAN (Port 0 = CPU/eth1, Port 3 = physical LAN) |
| 2 | 5, 6 | WAN (Port 6 = CPU/eth0, Port 5 = physical WAN uplink) |

**Physical port notes:**
- Port 5 faces an upstream switch (100baseT, many MACs learned)
- Port 3 is the active LAN port (gigabit)
- Ports 1, 2, 4 are unused LAN ports

**MAC addresses:**
- eth0 (WAN): `58:b6:33:26:52:70`
- eth1 (LAN): `58:b6:33:26:52:74`
