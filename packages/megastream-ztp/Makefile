include $(TOPDIR)/rules.mk

PKG_NAME:=megastream-ztp
PKG_VERSION?=0.0
PKG_RELEASE:=1

PKG_LICENSE:=MIT
PKG_MAINTAINER:=CuTEL

include $(INCLUDE_DIR)/package.mk

define Package/megastream-ztp
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Zero Touch Provisioning for Megastream devices
  URL:=https://github.com/cu-telecom/megastream-packages
  PKGARCH:=all
  DEPENDS:=+curl +diffutils
endef

define Package/megastream-ztp/description
  Zero Touch Provisioning service for Megastream devices. Fetches UCI config
  from a central server, applies only changed packages, and restarts affected
  services automatically.
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
endef

define Build/Compile
endef

define Package/megastream-ztp/install
	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_BIN) $(CURDIR)/files/ztp-update $(1)/usr/sbin/ztp-update
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) $(CURDIR)/files/ztp.init $(1)/etc/init.d/ztp
	$(INSTALL_DIR) $(1)/etc/rc.d
	ln -sf ../init.d/ztp $(1)/etc/rc.d/S99ztp
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) $(CURDIR)/files/ztp.conf $(1)/etc/config/ztp
endef

define Package/megastream-ztp/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || /etc/init.d/ztp start
endef

$(eval $(call BuildPackage,megastream-ztp))
