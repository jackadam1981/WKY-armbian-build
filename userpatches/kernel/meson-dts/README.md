# MMC 设备顺序修复补丁说明

## 问题描述
玩客云 (WS-1608) 设备在默认配置下，SD 卡被识别为 `mmcblk0`，而 eMMC 被识别为 `mmcblk1`，这与预期的顺序相反。

## 预期结果
- `mmcblk0`: eMMC (931.4G)
- `mmcblk1`: SD 卡 (7.3G)

## 解决方案
通过修改设备树文件 (Device Tree Source) 中的别名 (aliases) 部分，明确指定 MMC 设备的顺序。

### 补丁详解

**文件**: `arch/arm/boot/dts/meson8-onecloud.dts`

**修改内容**:
在设备树根节点 `/` 中添加 `aliases` 部分：

```devicetree
aliases {
    mmc0 = &sdhc_a;  /* EMMC */
    mmc1 = &sdhc_b;  /* SD Card */
};
```

- `sdhc_a`: S805 芯片的 SDHCI 控制器 A，通常连接 eMMC
- `sdhc_b`: S805 芯片的 SDHCI 控制器 B，通常连接 SD 卡读卡器

## 工作原理

1. **设备树别名** (Device Tree Aliases) 用于为设备分配逻辑设备号
2. Linux 内核启动时读取这些别名，按照指定的顺序初始化 MMC 设备
3. `mmc0` 别名确保第一个 SDHCI 控制器 (`sdhc_a` - eMMC) 被识别为 `mmcblk0`
4. `mmc1` 别名确保第二个 SDHCI 控制器 (`sdhc_b` - SD 卡) 被识别为 `mmcblk1`

## 使用方法

本补丁已放置在 `userpatches/kernel/meson-dts/` 目录中。

Armbian 编译系统会在编译内核时自动应用此目录中的所有补丁。

### 编译步骤

```bash
# 使用 GitHub Actions 编译
# 1. 仓库已包含此补丁
# 2. 编译时会自动应用

# 或者本地编译（如果有 Armbian build 环境）
./compile.sh
```

## 验证方法

编译并刷入镜像后，启动系统并运行：

```bash
lsblk
```

输出应该显示：
```
mmcblk0      179:0    0 931.4G  0 disk 
└─mmcblk0p1  179:1    0 931.4G  0 part /
mmcblk1      179:16   0   7.3G  0 disk 
├─mmcblk1p1  179:17   0   256M  0 part (可选)
└─mmcblk1p2  179:18   0     7G  0 part (可选)
```

或者查看 MMC 设备详细信息：

```bash
cat /proc/partitions
```

## 技术细节

- **芯片**: Amlogic S805
- **设备**: 玩客云 WS-1608
- **设备树文件**: `meson8-onecloud.dts`
- **补丁类型**: Device Tree Source (DTS) 修改
- **Armbian 分支**: 适用于 current 和 edge 分支

## 参考资料

- [Device Tree Specification](https://devicetree-specification.readthedocs.io/)
- [Linux kernel MMC subsystem](https://www.kernel.org/doc/html/latest/filesystems/ext4/index.html)
- [Amlogic Meson SoC support](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/arch/arm/boot/dts?h=v5.15)
