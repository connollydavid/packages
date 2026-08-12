#
# Copyright (c) 2026 David Connolly <david@connol.ly>
#
# This is free software, licensed under GPL-2.0-only
#

include $(TOPDIR)/rules.mk

PKG_NAME:=flashprog
PKG_VERSION:=1.5
PKG_RELEASE:=1

PKG_SOURCE:=$(PKG_NAME)-v$(PKG_VERSION).tar.bz2
PKG_SOURCE_URL:=https://flashprog.org/releases
PKG_HASH:=2b2c8356335863c4910bf5ed6b1b05f390f21562676e9c3f5a56bbc8cfb8e444
PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(BUILD_VARIANT)/$(PKG_NAME)-v$(PKG_VERSION)

PKG_MAINTAINER:=David Connolly <david@connol.ly>
PKG_LICENSE:=GPL-2.0-only
PKG_LICENSE_FILES:=COPYING

include $(INCLUDE_DIR)/package.mk
include $(INCLUDE_DIR)/meson.mk

define Package/flashprog-snapshot/Default
  SECTION:=utils
  CATEGORY:=Utilities
  URL:=https://flashprog.org/
endef

define Package/flashprog-snapshot
  $(Package/flashprog-snapshot/Default)
  TITLE:=Flash chip programmer (snapshot build, full)
  DEPENDS:= \
    +TARGET_x86:libpci \
    +libftdi1 \
    +libjaylink \
    +libusb-1.0
  VARIANT:=full
  DEFAULT_VARIANT:=1
  CONFLICTS:=flashprog
endef

define Package/flashprog-spi-snapshot
  $(Package/flashprog-snapshot/Default)
  TITLE:=Flash chip programmer (snapshot build)
  VARIANT:=spi
  CONFLICTS:=flashprog-spi
endef

define Package/flashprog-snapshot/Default/description
  flashprog detects, reads, writes, verifies and erases flash chips. It
  reads and sets the protection and configuration bits of SPI NOR chips.
  This package is offered to OpenWrt in
  https://github.com/openwrt/packages/issues/29591 and carries a name of
  its own until that is settled, and the same paths, so it conflicts with
  the package under review.
endef

Package/flashprog-snapshot/description = $(Package/flashprog-snapshot/Default/description)
Package/flashprog-spi-snapshot/description = $(Package/flashprog-snapshot/Default/description)

FLASHPROG_PROGRAMMERS:= \
	dummy \
	linux_mtd \
	linux_spi \
	group_serial

ifeq ($(BUILD_VARIANT),full)
  FLASHPROG_PROGRAMMERS += \
	group_ftdi \
	group_jlink \
	group_usb

# group_pci adds no programmer; it makes the libpci above required
ifneq ($(CONFIG_TARGET_x86),)
  FLASHPROG_PROGRAMMERS += group_internal group_pci
endif
endif

MESON_ARGS += \
	-Dich_descriptors_tool=disabled \
	-Dprogrammer=$(subst $(space),$(comma),$(strip $(FLASHPROG_PROGRAMMERS)))

define Package/flashprog-snapshot/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/bin/flashprog $(1)/usr/bin/
endef

define Package/flashprog-spi-snapshot/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/bin/flashprog $(1)/usr/bin/flashprog-spi
endef

$(eval $(call BuildPackage,flashprog-snapshot))
$(eval $(call BuildPackage,flashprog-spi-snapshot))
