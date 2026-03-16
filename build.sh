#!/bin/sh
set -e

DIST="$(pwd)/dist"
TMPBASE=$(mktemp -d)
trap 'rm -rf "$TMPBASE"' EXIT

# Derive version from git tag (e.g. v1.0.0 -> 1.0.0-r0, v1.0.0-3-gabcdef -> 1.0.0-r3)
_tag=$(git describe --tags --always 2>/dev/null | sed 's/^v//' || echo "0.0.0")
GIT_VER=$(echo "$_tag" | sed 's/-\([0-9]*\)-g[0-9a-f]*$/-r\1/')
echo "$GIT_VER" | grep -q '\-r' || GIT_VER="${GIT_VER}-r0"

build_package() {
    PKGROOT="$(cd "$1" && pwd)"

    PKG_NAME="" PKG_VER="" PKG_ARCH="all" PKG_DESC="" PKG_LICENSE="" PKG_DEPENDS="" PKG_URL=""
    unset -f package 2>/dev/null || true

    . "$PKGROOT/build.sh"

    [ -z "$PKG_VER" ] && PKG_VER="$GIT_VER"

    STAGEDIR="$TMPBASE/$PKG_NAME/stage"
    CTRLDIR="$TMPBASE/$PKG_NAME/control"
    mkdir -p "$STAGEDIR" "$CTRLDIR"

    PKGDIR="$STAGEDIR"
    (cd "$PKGROOT" && package)

    SIZE=$(find "$STAGEDIR" -type f -exec wc -c {} + 2>/dev/null | awk 'END{print $1+0}')

    {
        printf 'pkgname = %s\n'  "$PKG_NAME"
        printf 'pkgver = %s\n'   "$PKG_VER"
        printf 'arch = %s\n'     "$PKG_ARCH"
        printf 'size = %s\n'     "$SIZE"
        printf 'pkgdesc = %s\n'  "$PKG_DESC"
        printf 'url = %s\n'      "${PKG_URL:-}"
        printf 'builddate = %s\n' "$(date +%s)"
        printf 'packager = Custom\n'
        printf 'license = %s\n'  "$PKG_LICENSE"
        for dep in $PKG_DEPENDS; do
            printf 'depend = %s\n' "$dep"
        done
    } > "$CTRLDIR/.PKGINFO"

    [ -f "$PKGROOT/post-install" ] && \
        install -m755 "$PKGROOT/post-install" "$CTRLDIR/.post-install"

    CTRL_TGZ="$TMPBASE/$PKG_NAME/control.tar.gz"
    DATA_TGZ="$TMPBASE/$PKG_NAME/data.tar.gz"
    APK_FILE="$DIST/${PKG_NAME}-${PKG_VER}.apk"

    mkdir -p "$DIST"
    (cd "$CTRLDIR" && tar czf "$CTRL_TGZ" .)
    (cd "$STAGEDIR" && tar czf "$DATA_TGZ" .)
    cat "$CTRL_TGZ" "$DATA_TGZ" > "$APK_FILE"

    CHECKSUM="Q1$(openssl sha1 -binary "$CTRL_TGZ" | base64)"
    CSIZE=$(wc -c < "$APK_FILE")

    {
        printf 'C:%s\n' "$CHECKSUM"
        printf 'P:%s\n' "$PKG_NAME"
        printf 'V:%s\n' "$PKG_VER"
        printf 'A:%s\n' "$PKG_ARCH"
        printf 'S:%s\n' "$CSIZE"
        printf 'I:%s\n' "$SIZE"
        printf 'T:%s\n' "$PKG_DESC"
        printf 'U:%s\n' "${PKG_URL:-}"
        printf 'L:%s\n' "$PKG_LICENSE"
        printf 'o:%s\n' "$PKG_NAME"
        printf 'm:Custom\n'
        printf 't:%s\n' "$(date +%s)"
        [ -n "$PKG_DEPENDS" ] && printf 'D:%s\n' "$PKG_DEPENDS"
        printf '\n'
    } > "${APK_FILE}.index"

    echo "Built: $APK_FILE"
}

# Build specified packages or all
if [ $# -gt 0 ]; then
    for pkg in "$@"; do
        build_package "$pkg"
    done
else
    for pkgdir in packages/*/; do
        [ -f "$pkgdir/build.sh" ] && build_package "$pkgdir"
    done
fi

# Regenerate APKINDEX from all sidecar index files in dist/
echo "Generating APKINDEX.tar.gz..."
: > "$TMPBASE/APKINDEX"
for idx in "$DIST"/*.apk.index; do
    [ -f "$idx" ] && cat "$idx" >> "$TMPBASE/APKINDEX"
done
tar czf "$DIST/APKINDEX.tar.gz" -C "$TMPBASE" APKINDEX

[ -f index.html ] && cp index.html "$DIST/index.html"

echo "Feed ready in $DIST/"
