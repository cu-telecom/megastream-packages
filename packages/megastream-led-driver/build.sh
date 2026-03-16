PKG_NAME="megastream-led-driver"
PKG_VER=""  # empty = use git tag
PKG_ARCH="all"
PKG_DESC="WireGuard keepalive and port status LED driver for OpenWrt"
PKG_LICENSE="MIT"
PKG_DEPENDS="wireguard-tools"

package() {
    install -Dm755 "$PKGROOT/megastream-led-driver.sh"   "$PKGDIR/usr/bin/megastream-led-driver"
    install -Dm755 "$PKGROOT/megastream-led-driver.init" "$PKGDIR/etc/init.d/megastream-led-driver"
}
