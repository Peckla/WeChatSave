# WeChatSave

WeChatSave 是一个 macOS 原生应用。它通过系统共享菜单接收微信合并转发生成的 ZIP，并将原文件保存到你选择的位置。

## 从源码构建并运行

项目通过 GitHub 提供源码，请在每台 Mac 上自行构建。构建默认采用本机临时签名，无需付费 Apple Developer Program 会员、Developer ID 证书或 Apple 公证。

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

技术参考：[Dukou](https://github.com/qzz0518/Dukou) 的 macOS 共享扩展入口与文件交接。

保存前可填写群名或会话名，应用会记住上次输入。默认文件名固定为 `会话名_YYYY-MM-DD_HHmm--YYYY-MM-DD_HHmm.zip`，两端分别是最早和最晚的消息时间。同一分钟也会写出两端。未填会话名时使用「微信聊天」，无法识别消息时间时，两端都使用本机导出时间。分享单个 ZIP 时也可直接填写完整文件名。
