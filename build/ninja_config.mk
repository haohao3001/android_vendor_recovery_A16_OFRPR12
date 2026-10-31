# OrangeFox (OF_*/FOX_*) -> Soong 变量桥
#
# 为什么需要：Soong 看不见普通 Make 变量。bootable/recovery/fox_common.go 的
# foxVar() 只认两个来源：(1) twrpVarsPlugin 命名空间里的 SOONG_CONFIG_* 键，
# (2) 进程环境变量。设备树 .mk 里 `OF_SCREEN_H := 2374` 这类写法两者都不是，
# 于是整批丢失（现象：-DOF_SCREEN_H 完全不出现，OF_FL_PATH1 退化成空串兜底）。
#
# 为什么放在这个路径：本文件由 build/make/core/ninja_config.mk:39 的
#   include $(wildcard vendor/*/build/ninja_config.mk)
# 在 build/make/core/config.mk:1320 引入，时机正好落在合法窗口内：
#   config.mk:419   envsetup.mk -> product_config.mk(351) / board_config.mk(368)
#                   （此刻 OF_*/FOX_* 的值已就绪）
#   config.mk:476   vendor/twrp/config/BoardConfigTWRP.mk -> BoardConfigSoong.mk
#                   :64 注册 twrpVarsPlugin；:66 会清空该命名空间的名字列表，
#                   所以必须在那之后注入，否则名字会被抹掉
#   config.mk:1320  ninja_config.mk  <- 本文件
#   config.mk:1321  soong_config.mk  <- 写 out/soong/soong.<product>.variables
#
# 好处：build/make 与 vendor/twrp 两个上游项目保持 100% 干净（repo sync / 升级
# 不会冲突或覆盖），本文件归属 vendor/recovery。
#
#
# 注意：add_soong_config_var 用 := 立即展开；值里出现 '#' 会被当注释 —— 这是
# 该宏的固有限制（TW_* 走同一条路，同理）。

# ── 编译期必需值的默认值 ─────────────────────────────────────────────────────
# 下列宏在 C++ 里是【无 #ifdef 保护】地使用的，且全树（设备树 .mk / vendorsetup.sh /
# BoardConfig）都没有给值；foxVar() 取到空串就跳过该 -D，源码随即报
# "use of undeclared identifier"。取值与 vendor/recovery/OrangeFox_vendor.sh:37/310-317
# 的打包逻辑保持一致，保证二进制里的字符串与打包出的 zip 名一致。
# 设备树里用同名的普通赋值（:= / =）即可覆盖这里的 ?= 默认值。
#
#   FOX_BUILD           data.cpp:585  twrp-functions.cpp:1864,2421,2433
#   FOX_BUILD_TYPE      data.cpp:586,1013  twrp-functions.cpp:1863,2436,2437
#   OF_CURRENT_BRANCH   twrp-functions.cpp:2424
#   OF_FLASHLIGHT_ENABLE data.cpp:965（本机 device tree 已给 OF_FL_PATH1，故默认开启）
#   OF_SPLASH_MAX_SIZE  data.cpp:966（主题 customization.xml:2031 用它做 "splash 不得大于 X Kb" 校验）
FOX_INTERNAL_RELEASE ?= R12.0
FOX_BUILD_TYPE ?= Unofficial
FOX_BUILD ?= $(FOX_INTERNAL_RELEASE)$(if $(FOX_MAINTAINER_PATCH_VERSION),_$(FOX_MAINTAINER_PATCH_VERSION),)
# 分支名优先取 bootable/recovery 的 git 分支，取不到（无 git / 无 .git）退回 release 串，
# 保证 twrp-functions.cpp:2424 的无保护使用永远有定义。想要固定值就在设备树里覆盖。
OF_CURRENT_BRANCH ?= $(shell git -C bootable/recovery rev-parse --abbrev-ref HEAD 2>/dev/null || echo $(FOX_INTERNAL_RELEASE))
OF_FLASHLIGHT_ENABLE ?= 1
# 占位默认值（4 MB，单位 KB，主题用 `du -s` 比较）：够大以不误伤正常 splash，
# 仍能拦住离谱的大图。要真实限制请在设备树里覆盖 OF_SPLASH_MAX_SIZE。
OF_SPLASH_MAX_SIZE ?= 4096

FOX_SOONG_VARS := $(shell sed -n \
    -e 's/.*{"\(\(OF\|FOX\)_[A-Z0-9_]*\)".*/\1/p' \
    -e 's/.*foxVar(ctx, "\(\(OF\|FOX\)_[A-Z0-9_]*\)").*/\1/p' \
    bootable/recovery/fox_common.go | sort -u)
FOX_SOONG_VARS += PRODUCT_PLATFORM

$(call add_soong_config_var,twrpVarsPlugin,$(FOX_SOONG_VARS))
