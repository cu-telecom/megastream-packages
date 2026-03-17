#!/bin/sh
set -eu

VERSION="${VERSION:-25.12.0}"
FEED_NAME="${FEED_NAME:-megastream}"
DIST="$(pwd)/dist"
WORK="$(pwd)/.work"

# target subtarget arch
TARGETS="${TARGETS:-\
ath79 generic mips_24kc
}"

# Run inside a Debian container if not already in one with the needed tools
if ! command -v curl >/dev/null 2>&1 || ! command -v tar >/dev/null 2>&1 || ! command -v make >/dev/null 2>&1 || ! command -v zstd >/dev/null 2>&1; then
    exec docker run --rm \
        -v "$(pwd):/work" \
        -w /work \
        debian:bookworm \
        sh -euxc '
            apt-get update
            apt-get install -y ca-certificates curl git make python3 rsync unzip zstd file gawk grep sed findutils bash xz-utils openssl
            /work/build.sh "$@"
        ' sh "$@"
fi

mkdir -p "$DIST" "$WORK"

find_sdk_url() {
    target="$1"
    subtarget="$2"
    base="https://downloads.openwrt.org/releases/${VERSION}/targets/${target}/${subtarget}/"

    page="$(curl -fsSL "$base")"
    sdk="$(printf '%s\n' "$page" | grep -oE "openwrt-sdk-[^\"]+Linux-x86_64\.tar\.zst" | head -n1)"

    if [ -z "$sdk" ]; then
        echo "Could not find SDK in $base" >&2
        exit 1
    fi

    printf '%s%s\n' "$base" "$sdk"
}

build_one_target() {
    target="$1"
    subtarget="$2"
    arch="$3"

    sdk_url="$(find_sdk_url "$target" "$subtarget")"
    sdk_file="$WORK/$(basename "$sdk_url")"
    sdk_dir="$WORK/sdk-${target}-${subtarget}"

    echo "=== Building for $target/$subtarget ($arch) ==="
    echo "SDK: $sdk_url"

    rm -rf "$sdk_dir"

    curl -fL "$sdk_url" -o "$sdk_file"

    # Derive the extracted directory name from the tarball filename (avoids broken-pipe
    # from "tar -tf | head -n1" which causes set -e to abort under some sh implementations).
    # Do NOT mkdir $sdk_dir before the mv — if the destination already exists as a directory,
    # mv nests the source inside it instead of renaming, putting scripts/ one level too deep.
    extracted="$(basename "${sdk_file%.tar.zst}")"
    tar --zstd -xf "$sdk_file" -C "$WORK"
    mv "$WORK/$extracted" "$sdk_dir"

    # Suppress the default feeds — an empty feeds.conf prevents the SDK from
    # pulling in every upstream feed during make defconfig.
    : > "$sdk_dir/feeds.conf"

    # Copy local package recipes directly into package/$FEED_NAME/.
    # The SDK always classifies these as the "base" feed internally; the output
    # lands in bin/packages/$arch/base/ regardless of directory naming.
    mkdir -p "$sdk_dir/package/$FEED_NAME"
    for pkgdir in packages/*; do
        [ -d "$pkgdir" ] || continue
        [ -f "$pkgdir/Makefile" ] || continue
        rsync -a "$pkgdir/" "$sdk_dir/package/$FEED_NAME/$(basename "$pkgdir")/"
    done

    # Derive package version from the current git tag (e.g. v1.2 -> 1.2).
    # Falls back to 0.0 if no tag is present (e.g. local dev builds).
    pkg_version="$(git describe --tags --exact-match 2>/dev/null | sed 's/^v//' || echo 0.0)"

    # If a signing key is provided, install it into the SDK and enable signed packages.
    # The public key is derived from the private key and copied to dist/ so users can
    # trust it by placing it in /etc/apk/keys/ on their device.
    if [ -n "${SIGNING_KEY:-}" ]; then
        printf '%s' "$SIGNING_KEY" | base64 -d > "$sdk_dir/key-build.pem"
        openssl ec -in "$sdk_dir/key-build.pem" -pubout -out "$sdk_dir/key-build.pub" 2>/dev/null
        cp "$sdk_dir/key-build.pub" "$DIST/megastream.pub"
        echo "=== Signing key fingerprint (should match /etc/apk/keys/megastream.pem on device) ==="
        openssl ec -pubin -in "$sdk_dir/key-build.pub" -text -noout 2>/dev/null
    fi

    (
        cd "$sdk_dir"

        # Seed CONFIG_SIGNED_PACKAGES before defconfig so that it is preserved.
        if [ -n "${SIGNING_KEY:-}" ]; then
            echo 'CONFIG_SIGNED_PACKAGES=y' > .config
        fi

        # Prepare toolchain state
        make defconfig

        # Re-install our signing key AFTER defconfig. The SDK's defconfig calls
        # scripts/gen_key.sh which generates a random key-build.pem, overwriting
        # whatever we placed there earlier. Re-writing here ensures make package/index
        # signs with the key that corresponds to the megastream.pub on the device.
        if [ -n "${SIGNING_KEY:-}" ]; then
            printf '%s' "$SIGNING_KEY" | base64 -d > key-build.pem
            openssl ec -in key-build.pem -pubout -out key-build.pub 2>/dev/null
        fi

        # Build selected packages or all local packages
        if [ "$#" -gt 3 ]; then
            shift 3
            for pkg in "$@"; do
                make "package/$FEED_NAME/$pkg/compile" PKG_VERSION="$pkg_version" V=s
            done
        else
            for pkgdir in package/"$FEED_NAME"/*; do
                [ -d "$pkgdir" ] || continue
                pkg="$(basename "$pkgdir")"
                make "package/$FEED_NAME/$pkg/compile" PKG_VERSION="$pkg_version" V=s
            done
        fi

        # Generate and sign the APK repository index (packages.adb).
        # With CONFIG_SIGNED_PACKAGES=y and key-build.pem in place, this calls
        # apk mkndx --sign-key internally — the same code path as the official
        # OpenWrt feed, ensuring the key ID format matches what apk update expects.
        make package/index V=s
    )

    outdir="$DIST/$arch"
    mkdir -p "$outdir"

    # Collect built APKs from anywhere under bin/packages/$arch/ — the SDK
    # places packages in a subdirectory determined by its internal feed logic
    # (typically "base"), not necessarily $FEED_NAME.
    find "$sdk_dir/bin/packages/$arch" -maxdepth 2 -type f \
        \( -name '*.apk' -o -name 'packages.adb' -o -name 'packages.adb.*' -o -name 'index.json' \) \
        -exec cp {} "$outdir/" \;

    echo "Output copied to $outdir"
}

for row in $TARGETS; do
    :
done

# Parse TARGETS three fields at a time
set -- $TARGETS
while [ "$#" -ge 3 ]; do
    target="$1"
    subtarget="$2"
    arch="$3"
    shift 3
    build_one_target "$target" "$subtarget" "$arch" "$@"
done

echo "Feed ready in $DIST/"