# SPDX-License-Identifier: GPL-3.0-only
#
# VMess core for Little-Endian MIPS32 (ramips/mt7620 Y1 and Y1s).
include $(TOPDIR)/rules.mk

PKG_NAME:=v2ray-core
PKG_VERSION:=4.45.2
PKG_RELEASE:=1

PKG_SOURCE:=v2ray-linux-mips32le.zip
PKG_SOURCE_URL:=https://github.com/v2fly/v2ray-core/releases/download/v$(PKG_VERSION)
PKG_HASH:=6fae6cb0293be4b64c92b738195f5af5fd2d158c63d69c170a7a6e360cca2faf

PKG_LICENSE:=MIT
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=V2Fly contributors

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)-mips32le
PKG_UNPACK=unzip -o "$(DL_DIR)/$(PKG_SOURCE)" v2ray -d "$(PKG_BUILD_DIR)"

include $(INCLUDE_DIR)/package.mk

define Package/v2ray-core
  SECTION:=net
  CATEGORY:=Network
  TITLE:=V2Ray VMess/transparent-proxy core (MIPS32 LE)
  URL:=https://www.v2fly.org
  DEPENDS:=@TARGET_ramips +ca-bundle
endef

define Package/v2ray-core/description
  Official final V2Fly v4 release for little-endian MIPS32 ramips targets.
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
