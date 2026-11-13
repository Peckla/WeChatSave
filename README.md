# WeChatSave

受 [Dukou](https://github.com/qzz0518/Dukou) 启发，WeChatSave 独立实现了一个轻量的 macOS 共享扩展，用于将微信导出的原始 ZIP 保存到指定目录。

## 从源码构建并运行

项目目前供个人使用，采用源码分发。有需要的用户请拉取代码并在自己的 Mac 上编译。构建默认采用本机临时签名，无需付费 Apple Developer Program 会员、Developer ID 证书或 Apple 公证。

需要 macOS 14 或以上、Git，以及包含 Swift 编译器的 Xcode Command Line Tools 或 Xcode。还没安装工具时，先执行并完成安装：

```sh
xcode-select --install
```

在你想存放代码的目录执行。如果使用 DevMesh，请先进入此 Project 的 `GitRepo/` 目录。

```sh
git clone --branch dev https://github.com/Peckla/WeChatSave.git
cd WeChatSave
./build.sh
open dist/WeChatSave.app
```

脚本会编译当前 Mac 架构（Apple Silicon 或 Intel）的主应用及内嵌共享扩展。产物为仓库内的 `dist/WeChatSave.app`。

## 更新

先用 ⌘Q 退出 WeChatSave，再在仓库目录执行：

```sh
git switch dev
git pull --ff-only
./build.sh
open dist/WeChatSave.app
```

## 使用

1. 打开构建好的 WeChatSave 后，在 macOS「系统设置」中搜索「共享」扩展并启用 **Save WeChat ZIP**。
2. 在微信 4.1.13 或以上版本中多选聊天记录，选择「合并转发」→「转发到其他应用」→ **Save WeChat ZIP**。
3. 首次选择目录时，建议保存到项目的 `Export/`。勾选「记住此目录」后，后续分享可点击「保存」直接写入该目录，或点击「选择目录…」另选位置。取消勾选可改回每次选择目录。遇到同名 ZIP 时自动追加编号。

如果已启用扩展但微信菜单还没出现入口，用 ⌘Q 完全退出微信，再重新打开。可先用 Finder 分享一个本地 ZIP 测试入口和保存行为。

分享扩展通过 macOS 的目录选择器获得写入权限，并通过 macOS 安全作用域书签记住目录。构建目录与微信分享时选择的保存目录相互独立。

## 文件命名

分享窗口可以填写会话名，也可以为单个 ZIP 输入自定义文件名。留空时使用窗口预览的自动文件名。

```text
项目群_2026-03-25_0939--2026-03-25_0942.zip
```

日期和时分分别取最早、最晚的消息。同一分钟也保留起止两端。未填写会话名时使用「微信聊天」；读不到消息时间时，两端使用本机导出时间。
