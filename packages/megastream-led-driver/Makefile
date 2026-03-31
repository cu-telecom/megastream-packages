include $(TOPDIR)/rules.mk

PKG_NAME:=megastream-led-driver
PKG_VERSION?=0.0
PKG_RELEASE:=1

PKG_LICENSE:=MIT
PKG_MAINTAINER:=CuTEL

include $(INCLUDE_DIR)/package.mk

define Package/megastream-led-driver
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=WireGuard keepalive and port status LED driver
  URL:=https://github.com/cu-telecom/megastream-packages
  PKGARCH:=all
endef

define Package/megastream-led-driver/description
  WireGuard keepalive and port status LED driver for OpenWrt
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
endef

define Build/Compile
endef

define Package/megastream-led-driver/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(CURDIR)/files/megastream-led-driver.sh $(1)/usr/bin/megastream-led-driver
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) $(CURDIR)/files/megastream-led-driver.init $(1)/etc/init.d/megastream-led-driver
endef

define Package/megastream-led-driver/postinst
#!/bin/sh
$${IPKG_INSTROOT}/etc/init.d/megastream-led-driver enable
[ -n "$${IPKG_INSTROOT}" ] || /etc/init.d/megastream-led-driver start
endef

$(eval $(call BuildPackage,megastream-led-driver))
