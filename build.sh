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

    # Decode and normalise the signing key. The SDK generates private-key.pem /
    # public-key.pem as make file targets; pre-placing them here prevents make
    # from regenerating a random key during the first package compile step.
    if [ -n "${SIGNING_KEY:-}" ]; then
        _raw="$WORK/key-build-raw.pem"
        printf '%s' "$SIGNING_KEY" | base64 -d > "$_raw"
        # Normalise to traditional EC format (BEGIN EC PRIVATE KEY) in case the
        # secret was stored as PKCS8; write to both the WORK dir (safe from SDK)
        # and the SDK dir under the names the SDK actually uses.
        openssl ec -in "$_raw" -out "$WORK/key-build.pem" 2>/dev/null
        cp "$WORK/key-build.pem" "$sdk_dir/private-key.pem"
        openssl ec -in "$sdk_dir/private-key.pem" -pubout -out "$sdk_dir/public-key.pem" 2>/dev/null
        cp "$sdk_dir/public-key.pem" "$DIST/megastream.pub"
        rm -f "$_raw"
        echo "=== Signing key fingerprint (should match /etc/apk/keys/megastream.pem on device) ==="
        openssl ec -pubin -in "$DIST/megastream.pub" -text -noout 2>/dev/null
    fi

    (
        cd "$sdk_dir"

        # Prepare toolchain state
        make defconfig

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

        # Generate an unsigned repository index.
        make package/index V=s

        # Sign the index directly with apk mkndx using our key stored outside sdk_dir.
        # The SDK's own signing (CONFIG_SIGNED_PACKAGES / scripts/gen_key.sh) generates
        # a fresh random key every build; we bypass it entirely by regenerating the index
        # ourselves with our stable key.
        if [ -n "${SIGNING_KEY:-}" ]; then
            for adb_dir in bin/packages/"$arch"/*/; do
                [ -d "$adb_dir" ] || continue
                # Check at least one .apk exists in this subdir
                found=0
                for _apk in "$adb_dir"*.apk; do [ -f "$_apk" ] && found=1 && break; done
                [ "$found" = 1 ] || continue
                echo "=== Signing ${adb_dir}packages.adb ==="
                # shellcheck disable=SC2086
                staging_dir/host/bin/apk mkndx \
                    --sign-key "$WORK/key-build.pem" \
                    --output "${adb_dir}packages.adb" \
                    "$adb_dir"*.apk
            done
        fi
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