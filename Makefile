# To support gonk's build/envsetup.sh
SHELL = bash

-include .config.mk

.DEFAULT: build

MAKE_FLAGS ?= -j16
GONK_MAKE_FLAGS ?=

HEIMDALL ?= heimdall
TOOLCHAIN_HOST = linux-x86
TOOLCHAIN_PATH = ./glue/gonk/prebuilt/$(TOOLCHAIN_HOST)/toolchain/arm-eabi-4.4.3/bin

GONK_PATH = $(abspath glue/gonk)
GONK_TARGET ?= full_$(GONK)-eng

define GONK_CMD # $(call GONK_CMD,cmd)
	cd $(GONK_PATH) && \
	. build/envsetup.sh && \
	lunch $(GONK_TARGET) && \
	export USE_CCACHE="yes" && \
	$(1)
endef

ANDROID_SDK_PLATFORM ?= android-13
GECKO_CONFIGURE_ARGS ?=
WIDGET_BACKEND ?= gonk

CCACHE ?= $(shell which ccache)

# Developers can use this to define convenience rules and set global variabls
# XXX for now, this is where to put ANDROID_SDK and ANDROID_NDK macros
-include local.mk

.PHONY: build
build: gecko gecko-$(WIDGET_BACKEND)-hack gonk

ifeq (qemu,$(KERNEL))
build: kernel bootimg-hack
endif

KERNEL_DIR=boot/kernel-android-$(KERNEL)

ifeq (android,$(WIDGET_BACKEND))
ifndef ANDROID_SDK
$(error Sorry, you need to set ANDROID_SDK in your environment to point at the top-level of the SDK install.  For now.)
endif

ifndef ANDROID_NDK
$(error Sorry, you need to set ANDROID_NDK in your environment to point at the top-level of the NDK install.  For now.)
endif
endif

.PHONY: gecko
# XXX Hard-coded for prof-android target.  It would also be nice if
# client.mk understood the |package| target.
gecko:
	@export ANDROID_SDK=$(ANDROID_SDK) && \
	export ANDROID_SDK_PLATFORM=$(ANDROID_SDK_PLATFORM) && \
	export ANDROID_NDK=$(ANDROID_NDK) && \
	export ANDROID_VERSION_CODE=`date +%Y%m%d%H%M%S` && \
	export MAKE_FLAGS=$(MAKE_FLAGS) && \
	export CONFIGURE_ARGS="$(GECKO_CONFIGURE_ARGS)" && \
	export GONK_PRODUCT="$(GONK)" && \
	ulimit -n 4096 && \
	make -C gecko -f client.mk -s $(MAKE_FLAGS) && \
	make -C gecko/objdir-prof-android package

.PHONY: gonk
gonk: gaia-hack
	@$(call GONK_CMD,make $(MAKE_FLAGS) $(GONK_MAKE_FLAGS))
ifeq (qemu,$(KERNEL))
	@cp glue/gonk/system/core/rootdir/init.rc.gonk $(GONK_PATH)/out/target/product/$(GONK)/root/init.rc
endif

.PHONY: kernel
# XXX Hard-coded for nexuss4g target
# XXX Hard-coded for gonk tool support
kernel:
ifeq (galaxy-s2,$(KERNEL))
	@PATH="$$PATH:$(abspath $(TOOLCHAIN_PATH))" make -C $(KERNEL_PATH) $(MAKE_FLAGS) ARCH=arm CROSS_COMPILE="$(CCACHE) arm-eabi-" modules
	(rm -rf boot/initramfs && cd boot/clockworkmod_galaxys2_initramfs && git checkout-index -a -f --prefix ../initramfs/)
	find "$(KERNEL_DIR)" -name "*.ko" | xargs -I MOD cp MOD "$(PWD)/boot/initramfs/lib/modules"
endif

.PHONY: clean
clean: clean-gecko clean-gonk clean-kernel

.PHONY: clean-gecko
clean-gecko:
	rm -rf gecko/objdir-prof-android

.PHONY: clean-gonk
clean-gonk:
	@$(call GONK_CMD,make clean)

.PHONY: clean-kernel
clean-kernel:
	@PATH="$$PATH:$(abspath $(TOOLCHAIN_PATH))" make -C $(KERNEL_PATH) ARCH=arm CROSS_COMPILE=arm-eabi- clean

.PHONY: config-galaxy-s2
config-galaxy-s2: config-gecko-$(WIDGET_BACKEND)
	@echo "KERNEL = galaxy-s2" > .config.mk && \
        echo "KERNEL_PATH = ./boot/kernel-android-galaxy-s2" >> .config.mk && \
	echo "GONK = galaxys2" >> .config.mk && \
	cp -p config/kernel-galaxy-s2 boot/kernel-android-galaxy-s2/.config && \
	cd $(GONK_PATH)/device/samsung/galaxys2/ && \
	echo Extracting binary blobs from device, which should be plugged in! ... && \
	./extract-files.sh && \
	echo OK

.PHONY: config-maguro
config-maguro: config-gecko-$(WIDGET_BACKEND)
	@echo "KERNEL = msm" > .config.mk && \
        echo "KERNEL_PATH = ./boot/msm" >> .config.mk && \
	echo "GONK = maguro" >> .config.mk && \
	cp -p config/msm7627a_sku1-perf_defconfig boot/msm/.config && \
	cd $(GONK_PATH)/device/toro/maguro && \
	echo Extracting binary blobs from device, which should be plugged in! ... && \
	./extract-files.sh && \
	echo OK

.PHONY: config-gecko-android
config-gecko-android:
	@ln -sf ../config/gecko-prof-android gecko/mozconfig

.PHONY: config-gecko-gonk
config-gecko-gonk:
	@ln -sf ../config/gecko-prof-gonk gecko/mozconfig

%.tgz:
	wget https://dl.google.com/dl/android/aosp/$@

NEXUS_S_BUILD = grj90
extract-broadcom-crespo4g.sh: broadcom-crespo4g-$(NEXUS_S_BUILD)-c4ec9a38.tgz
	tar zxvf $< && ./$@
extract-imgtec-crespo4g.sh: imgtec-crespo4g-$(NEXUS_S_BUILD)-a8e2ce86.tgz
	tar zxvf $< && ./$@
extract-nxp-crespo4g.sh: nxp-crespo4g-$(NEXUS_S_BUILD)-9abcae18.tgz
	tar zxvf $< && ./$@
extract-samsung-crespo4g.sh: samsung-crespo4g-$(NEXUS_S_BUILD)-9474e48f.tgz
	tar zxvf $< && ./$@

.PHONY: blobs-nexuss4g
blobs-nexuss4g: extract-broadcom-crespo4g.sh extract-imgtec-crespo4g.sh extract-nxp-crespo4g.sh extract-samsung-crespo4g.sh

.PHONY: config-nexuss4g
config-nexuss4g: blobs-nexuss4g config-gecko-android
	@echo "KERNEL = samsung" > .config.mk && \
        echo "KERNEL_PATH = ./boot/kernel-android-samsung" >> .config.mk && \
	echo "GONK = crespo4g" >> .config.mk && \
	cp -p config/kernel-nexuss4g boot/kernel-android-samsung/.config && \
	make -C $(CURDIR) nexuss4g-postconfig

.PHONY: nexuss4g-postconfig
nexuss4g-postconfig:
	$(call GONK_CMD,make signapk && vendor/samsung/crespo4g/reassemble-apks.sh)

.PHONY: config-qemu
config-qemu: config-gecko-$(WIDGET_BACKEND)
	@echo "KERNEL = qemu" > .config.mk && \
        echo "KERNEL_PATH = ./boot/kernel-android-qemu" >> .config.mk && \
	echo "GONK = generic" >> .config.mk && \
	echo "GONK_TARGET = generic-eng" >> .config.mk && \
	echo "GONK_MAKE_FLAGS = TARGET_ARCH_VARIANT=armv7-a" >> .config.mk && \
	make -C boot/kernel-android-qemu ARCH=arm goldfish_armv7_defconfig && \
	( [ -e $(GONK_PATH)/device/qemu ] || \
		mkdir $(GONK_PATH)/device/qemu ) && \
	echo OK

.PHONY: flash
# XXX Using target-specific targets for the time being.  fastboot is
# great, but the sgs2 doesn't support it.  Eventually we should find a
# lowest-common-denominator solution.
flash: flash-$(GONK)

# flash-only targets are the same as flash targets, except that they don't
# depend on building the image.

.PHONY: flash-only
flash-only: flash-only-$(GONK)

.PHONY: flash-crespo4g
flash-crespo4g: image
	@$(call GONK_CMD,adb reboot bootloader && fastboot flashall -w)

.PHONY: flash-only-crespo4g
flash-only-crespo4g:
	@$(call GONK_CMD,adb reboot bootloader && fastboot flashall -w)

define FLASH_GALAXYS2_CMD
adb reboot download 
sleep 20
$(HEIMDALL) flash --factoryfs $(GONK_PATH)/out/target/product/galaxys2/system.img
$(FLASH_GALAXYS2_CMD_CHMOD_HACK)
endef

.PHONY: flash-galaxys2
flash-galaxys2: image
	$(FLASH_GALAXYS2_CMD)

.PHONY: flash-only-galaxys2
flash-only-galaxys2:
	$(FLASH_GALAXYS2_CMD)

.PHONY: bootimg-hack
bootimg-hack: kernel-$(KERNEL)

.PHONY: kernel-samsung
kernel-samsung:
	cp -p boot/kernel-android-samsung/arch/arm/boot/zImage $(GONK_PATH)/device/samsung/crespo/kernel && \
	cp -p boot/kernel-android-samsung/drivers/net/wireless/bcm4329/bcm4329.ko $(GONK_PATH)/device/samsung/crespo/bcm4329.ko

.PHONY: kernel-qemu
kernel-qemu:
	cp -p boot/kernel-android-qemu/arch/arm/boot/zImage \
		$(GONK_PATH)/device/qemu/kernel

kernel-%:
	@

OUT_DIR := $(GONK_PATH)/out/target/product/$(GONK)/system
APP_OUT_DIR := $(OUT_DIR)/app

$(APP_OUT_DIR):
	mkdir -p $(APP_OUT_DIR)

.PHONY: gecko-android-hack
gecko-android-hack: gecko
	mkdir -p $(APP_OUT_DIR)
	cp -p gecko/objdir-prof-android/dist/b2g-*.apk $(APP_OUT_DIR)/B2G.apk
	unzip -jo gecko/objdir-prof-android/dist/b2g-*.apk lib/armeabi-v7a/libmozutils.so -d $(OUT_DIR)/lib
	find glue/gonk/out -iname "*.img" | xargs rm -f

.PHONY: gecko-gonk-hack
gecko-gonk-hack: gecko
	rm -rf $(OUT_DIR)/b2g
	mkdir -p $(OUT_DIR)/lib
	# Extract the newest tarball in the gecko objdir.
	( cd $(OUT_DIR) && \
	  tar xvfz `ls -t $(PWD)/gecko/objdir-prof-android/dist/b2g-*.tar.gz | head -n1` )
	cp $(OUT_DIR)/b2g/libmozutils.so $(OUT_DIR)/lib
	find glue/gonk/out -iname "*.img" | xargs rm -f

.PHONY: gaia-hack
gaia-hack: gaia
	rm -rf $(OUT_DIR)/home
	mkdir -p $(OUT_DIR)/home
	cp -r gaia/* $(OUT_DIR)/home

.PHONY: install-gecko
install-gecko: install-gecko-$(WIDGET_BACKEND)

.PHONY: install-gecko-android
install-gecko-android: gecko
	@adb install -r gecko/objdir-prof-android/dist/b2g-*.apk && \
	adb reboot

.PHONY: install-gecko-gonk
install-gecko-gonk: gecko-gonk-hack
	@adb shell mount -o remount,rw /system && \
	adb push $(OUT_DIR)/b2g /system/b2g && \
	adb push $(OUT_DIR)/lib/libmozutils.so /system/lib/libmozutils.so

# The sad hacks keep piling up...  We can't set this up to be
# installed as part of the data partition because we can't flash that
# on the sgs2.
.PHONY: install-gaia
install-gaia:
	@for i in `ls gaia`; do adb push gaia/$$i /data/local/$$i; done

.PHONY: image
image: build
	@echo XXX stop overwriting the prebuilt nexuss4g kernel

.PHONY: unlock-bootloader
unlock-bootloader:
	@$(call GONK_CMD,adb reboot bootloader && fastboot oem unlock)

# Kill the b2g process on the device.
.PHONY: kill-b2g
kill-b2g:
	adb shell kill `adb shell ps | grep b2g | sed -e 's/ \+/ /g' | cut -f 2 -d ' '`

.PHONY: sync
sync:
	git pull origin master
	git submodule sync
	git submodule update --init
