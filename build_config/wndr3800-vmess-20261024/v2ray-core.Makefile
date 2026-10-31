# SPDX-License-Identifier: GPL-3.0-only
#
# WNDR3800 uses the final V2Fly v4 release because the v5 all-protocol
# binary cannot fit in the router's 14.25 MiB U-Boot image limit.
include $(TOPDIR)/rules.mk

PKG_NAME:=v2ray-core
PKG_VERSION:=4.45.2
PKG_RELEASE:=1

PKG_SOURCE:=v2ray-linux-mips32.zip
PKG_SOURCE_URL:=https://github.com/v2fly/v2ray-core/releases/download/v$(PKG_VERSION)
PKG_HASH:=572d8b0ba81d728f3834fba470e8a56e0cc460f8ad9e4c0a3fb20fcdd0410c6f

PKG_LICENSE:=MIT
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=V2Fly contributors

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)
PKG_UNPACK=unzip -o "$(DL_DIR)/$(PKG_SOURCE)" v2ray -d "$(PKG_BUILD_DIR)"

include $(INCLUDE_DIR)/package.mk

define Package/v2ray-core
  SECTION:=net
  CATEGORY:=Network
  TITLE:=V2Ray VMess/transparent-proxy core (WNDR3800 mips32)
  URL:=https://www.v2fly.org
  DEPENDS:=@TARGET_ath79 +ca-bundle
endef

define Package/v2ray-core/description
  Official final V2Fly v4 release for big-endian MIPS32 ath79 targets.
  Includes a compatibility wrapper for SSR Plus "v2ray run -config".
endef

define Build/Compile
endef

define Package/v2ray-core/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/v2ray $(1)/usr/bin/v2ray.real
	$(INSTALL_BIN) ./files/v2ray-wrapper $(1)/usr/bin/v2ray
endef

$(eval $(call BuildPackage,v2ray-core))
