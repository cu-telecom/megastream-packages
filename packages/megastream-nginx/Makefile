include $(TOPDIR)/rules.mk

PKG_NAME:=megastream-nginx
PKG_VERSION?=0.0
PKG_RELEASE:=1

PKG_LICENSE:=MIT
PKG_MAINTAINER:=CuTEL

include $(INCLUDE_DIR)/package.mk

define Package/megastream-nginx
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Megastream nginx configuration
  URL:=https://github.com/cu-telecom/megastream-packages
  PKGARCH:=all
  DEPENDS:=+nginx
endef

define Package/megastream-nginx/description
  Nginx configuration for Megastream autoprov and DDNS proxy
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
endef

define Build/Compile
endef

define Package/megastream-nginx/install
	$(INSTALL_DIR) $(1)/etc/nginx
	$(INSTALL_CONF) $(CURDIR)/files/nginx.conf $(1)/etc/nginx/nginx.conf
endef

define Package/megastream-nginx/postinst
#!/bin/sh
if [ -z "$${IPKG_INSTROOT}" ]; then
    nginx -t 2>/dev/null && /etc/init.d/nginx reload || /etc/init.d/nginx restart
fi
endef

$(eval $(call BuildPackage,megastream-nginx))
