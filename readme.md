# 玩客云 WS-1608 ARMBIAN 编译项目

本项目通过 GitHub Actions 为 S805 芯片的玩客云 WS-1608 编译 ARMBIAN 系统。

## 功能特性

- 使用 GitHub Actions 自动编译 ARMBIAN 镜像
- 支持手动触发和自动触发
- 可自定义编译参数（板型、分支、发行版）
- 自动上传构建产物和日志

## 使用方法

### 自动触发

工作流会在以下情况自动触发：
- 推送到 `main` 或 `master` 分支
- 创建 Pull Request 到 `main` 或 `master` 分支

### 手动触发

1. 进入 GitHub 仓库的 Actions 页面
2. 选择 "Build Armbian for WS-1608" 工作流
3. 点击 "Run workflow"
4. 可选择以下参数：
   - **Board**: 板型名称（默认: `onecloud`）
   - **Branch**: ARMBIAN 分支
     - `current`: 稳定分支，经过充分测试，推荐用于生产环境（默认）
     - `edge`: 开发分支，包含最新功能和更新，但可能不够稳定
   - **Release**: 基础发行版
     - `bullseye`: Debian 11，稳定可靠（默认）
     - `bookworm`: Debian 12，较新的稳定版本
     - `jammy`: Ubuntu 22.04 LTS，长期支持版本

### 下载构建产物

编译完成后：
1. 在 Actions 页面找到对应的运行记录
2. 在 "Artifacts" 部分下载构建的镜像文件
3. 镜像文件通常为 `.img` 格式，可能包含 `.sha` 校验文件

### 刷入镜像

下载镜像后，请参考 [刷入指南.md](刷入指南.md) 了解如何将镜像刷入到玩客云设备。

## 编译参数说明

- **BOARD**: 目标板型，玩客云通常使用 `onecloud`
- **BRANCH**: ARMBIAN 分支
  - `current`: 稳定分支（推荐）
  - `edge`: 开发分支（最新功能）
- **RELEASE**: 基础发行版
  - `bullseye`: Debian 11
  - `bookworm`: Debian 12
  - `jammy`: Ubuntu 22.04 LTS

## 注意事项

- 编译过程可能需要 1-3 小时，请耐心等待
- GitHub Actions 免费账户有运行时间限制
- 构建产物会保留 30 天，日志保留 7 天
- 如果编译失败，请查看构建日志排查问题

## S805 U-Boot 最小底包

[S805-uboot-hinas.img](Tools/S805-uboot-hinas.img) 是开启 **U 盘优先引导** 的 U-Boot，也可称为 **最小底包**，用于从 U 盘启动并安装各种系统（如 ARMBIAN、OpenWrt 等）。刷入此底包后，设备会优先从 U 盘启动，便于安装或更换系统。

## USB Burning Tool（含超时补丁）

使用 USB Burning Tool 刷入 `.burn.img` 时，常会遇到烧录卡在 97% 的超时错误。原因如下：

- 固件烧录后设备需计算 SHA1 校验值
- 大分区（如 root/system）校验时间可能超过 150 秒默认限制
- 容易在校验阶段超时并报错

**本仓库提供含超时补丁的版本**：

- [Amlogic USB Burning Tool v2.2.0 （含超时补丁）](Tools/Amlogic%20USB%20Burning%20Tool%20v2.2.0%20%EF%BC%88%E5%90%AB%E8%B6%85%E6%97%B6%E8%A1%A5%E4%B8%81%EF%BC%89.zip)

**安装步骤**：

1. 安装 USB Burning Tool 主程序（.exe）
2. 将 `UsbRomDrv.dll` 复制到安装目录（如 `D:\Program Files (x86)\Amlogic\USB_Burning_Tool`）并覆盖原文件

## 相关链接

- [刷入指南](flashing-guide.md) - 详细的镜像刷入教程
- [ARMBIAN 官方仓库](https://github.com/armbian/build)
- [ARMBIAN 文档](https://docs.armbian.com/)