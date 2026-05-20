![Preview](https://cdn.lookin.work/public/style/images/independent/homepage/preview_en_1x.jpg "Preview")

# Introduction
You can inspect and modify views in iOS app via Lookin, just like UI Inspector in Xcode, or another app called Reveal.

Official Website：https://lookin.work/

# ivista-lookin CLI

This fork includes `ivista-lookin`, a standalone command-line interface for inspecting iOS apps that integrate LookinServer.

Install:

```bash
brew tap LLLLLayer/ivista-lookin
brew install ivista-lookin
ivista-lookin doctor
```

Recommended first workflow:

```bash
ivista-lookin apps --json
ivista-lookin tree --bundle-id com.example.demo --depth 2
ivista-lookin find --bundle-id com.example.demo UILabel --limit 10
ivista-lookin inspect --bundle-id com.example.demo --oid 123 --json
ivista-lookin attrs --bundle-id com.example.demo --oid 123
```

Common follow-up commands:

```bash
ivista-lookin screenshot --bundle-id com.example.demo --oid 123 --out view.png
ivista-lookin export --bundle-id com.example.demo --out snapshot.lookin
ivista-lookin read snapshot.lookin tree --depth 2
ivista-lookin selectors --bundle-id com.example.demo --oid 123 --filter title
ivista-lookin eval --bundle-id com.example.demo --oid 123 description
ivista-lookin set --bundle-id com.example.demo --oid 123 --attr hidden --value true --dry-run
```

Homebrew tap and user-facing install docs:

https://github.com/LLLLLayer/homebrew-ivista-lookin

Canonical source-bound docs:

- Docs/LookinCLI使用手册.md
- Docs/LookinCLI字段说明.md
- Docs/LookinCLI技术方案.md

# Integration Guide
To use Lookin macOS app, you need to integrate LookinServer (iOS Framework of Lookin) into your iOS project.

> **Warning**
Never integrate LookinServer in Release building configuration.

## via CocoaPods:
### Swift Project
`pod 'LookinServer', :subspecs => ['Swift'], :configurations => ['Debug']`
### Objective-C Project
`pod 'LookinServer', :configurations => ['Debug']`
## via Swift Package Manager:
`https://github.com/QMUI/LookinServer/`

# Repository
LookinServer: https://github.com/QMUI/LookinServer

macOS app: https://github.com/hughkli/Lookin/

# Tips
- How to display custom information in Lookin: https://bytedance.larkoffice.com/docx/TRridRXeUoErMTxs94bcnGchnlb
- How to display more member variables in Lookin: https://bytedance.larkoffice.com/docx/CKRndHqdeoub11xSqUZcMlFhnWe
- How to turn on Swift optimization for Lookin: https://bytedance.larkoffice.com/docx/GFRLdzpeKoakeyxvwgCcZ5XdnTb
- Documentation Collection: https://bytedance.larkoffice.com/docx/Yvv1d57XQoe5l0xZ0ZRc0ILfnWb

# Acknowledgements
https://qxh1ndiez2w.feishu.cn/docx/YIFjdE4gIolp3hxn1tGckiBxnWf

---
# 简介
Lookin 可以查看与修改 iOS App 里的 UI 对象，类似于 Xcode 自带的 UI Inspector 工具，或另一款叫做 Reveal 的软件。

官网：https://lookin.work/

# ivista-lookin CLI

这个 fork 包含独立命令行工具 `ivista-lookin`，用于检查已经集成 LookinServer 的 iOS App。

安装：

```bash
brew tap LLLLLayer/ivista-lookin
brew install ivista-lookin
ivista-lookin doctor
```

推荐第一次使用路径：

```bash
ivista-lookin apps --json
ivista-lookin tree --bundle-id com.example.demo --depth 2
ivista-lookin find --bundle-id com.example.demo UILabel --limit 10
ivista-lookin inspect --bundle-id com.example.demo --oid 123 --json
ivista-lookin attrs --bundle-id com.example.demo --oid 123
```

常用后续命令：

```bash
ivista-lookin screenshot --bundle-id com.example.demo --oid 123 --out view.png
ivista-lookin export --bundle-id com.example.demo --out snapshot.lookin
ivista-lookin read snapshot.lookin tree --depth 2
ivista-lookin selectors --bundle-id com.example.demo --oid 123 --filter title
ivista-lookin eval --bundle-id com.example.demo --oid 123 description
ivista-lookin set --bundle-id com.example.demo --oid 123 --attr hidden --value true --dry-run
```

Homebrew tap 和面向用户的安装文档：

https://github.com/LLLLLayer/homebrew-ivista-lookin

主仓库维护的源码绑定文档：

- Docs/LookinCLI使用手册.md
- Docs/LookinCLI字段说明.md
- Docs/LookinCLI技术方案.md

# 安装 LookinServer Framework
如果这是你的 iOS 项目第一次使用 Lookin，则需要先把 LookinServer 这款 iOS Framework 集成到你的 iOS 项目中。

> **Warning**
记得不要在 AppStore 模式下集成 LookinServer。

## 通过 CocoaPods：

### Swift 项目
`pod 'LookinServer', :subspecs => ['Swift'], :configurations => ['Debug']`
### Objective-C 项目
`pod 'LookinServer', :configurations => ['Debug']`

## 通过 Swift Package Manager:
`https://github.com/QMUI/LookinServer/`

# 源代码仓库

iOS 端 LookinServer：https://github.com/QMUI/LookinServer

macOS 端软件：https://github.com/hughkli/Lookin/

# 技巧
- 如何在 Lookin 中展示自定义信息: https://bytedance.larkoffice.com/docx/TRridRXeUoErMTxs94bcnGchnlb
- 如何在 Lookin 中展示更多成员变量: https://bytedance.larkoffice.com/docx/CKRndHqdeoub11xSqUZcMlFhnWe
- 如何为 Lookin 开启 Swift 优化: https://bytedance.larkoffice.com/docx/GFRLdzpeKoakeyxvwgCcZ5XdnTb
- 文档汇总：https://bytedance.larkoffice.com/docx/Yvv1d57XQoe5l0xZ0ZRc0ILfnWb

# 鸣谢
https://qxh1ndiez2w.feishu.cn/docx/YIFjdE4gIolp3hxn1tGckiBxnWf
