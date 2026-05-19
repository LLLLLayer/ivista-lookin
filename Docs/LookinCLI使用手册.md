# LookinCLI 使用手册

本文档面向 LookinCLI 使用者，重点说明如何安装、发现 App、定位节点、查看/修改属性、截图和导出。设计背景和实现细节分别见 `LookinCLI设计预期.md` 和 `LookinCLI技术方案.md`。

## 安装

从源码构建并生成可移动 zip：

```bash
./Scripts/build-lookin-cli.sh
```

生成结果：

```text
build/LookinCLI/ivista-lookin-macos-universal/
build/LookinCLI/ivista-lookin-macos-universal.zip
```

解压 zip 后可以直接运行：

```bash
./ivista-lookin --version
./ivista-lookin apps
```

安装到 `/usr/local/bin/ivista-lookin`：

```bash
./install.sh
```

安装到用户目录，不使用 sudo：

```bash
INSTALL_PREFIX="$HOME/.local/ivista-lookin-cli" BIN_DIR="$HOME/.local/bin" SUDO= ./install.sh
```

LookinCLI 不要求安装 Lookin.app，但目标 iOS App 仍需要集成兼容的 LookinServer，并且处于可连接状态。

Homebrew tap 发布后，推荐安装方式是：

```bash
brew install LLLLLayer/ivista-lookin/ivista-lookin
ivista-lookin --version
```

## 快速自检

```bash
ivista-lookin --version
ivista-lookin doctor
ivista-lookin apps --json
```

从源码开发时，也可以运行 smoke test：

```bash
./Scripts/smoke-lookin-cli.sh
BUNDLE_ID=com.example.demo TRANSPORT=usb ./Scripts/smoke-lookin-cli.sh
```

如果需要指定二进制：

```bash
IVISTA_LOOKIN_BIN=build/LookinCLI/ivista-lookin-macos-universal/ivista-lookin BUNDLE_ID=com.example.demo ./Scripts/smoke-lookin-cli.sh
./Scripts/smoke-lookin-cli.sh build/LookinCLI/ivista-lookin-macos-universal
```

默认情况下，如果没有发现可连接 App，smoke test 会跳过层级相关命令。发布前可以强制要求目标 App 存在：

```bash
REQUIRE_APP=1 BUNDLE_ID=com.example.demo TRANSPORT=usb ./Scripts/smoke-lookin-cli.sh
```

发布 zip 前建议跑 release 验收。该脚本会解压 zip 到临时目录，验证 framework/rpath/codesign，再使用解压出的二进制跑 smoke：

```bash
./Scripts/verify-lookin-cli-release.sh
REQUIRE_APP=1 BUNDLE_ID=com.example.demo TRANSPORT=usb ./Scripts/verify-lookin-cli-release.sh
```

## 发现 App

列出当前可连接的 App：

```bash
ivista-lookin apps
ivista-lookin apps --json
```

真机和模拟器都在线时，可以加选择条件：

```bash
ivista-lookin apps --transport usb
ivista-lookin apps --transport simulator
ivista-lookin apps --bundle-id com.example.demo
ivista-lookin apps --device-id 12
ivista-lookin apps --port 47175
```

后续所有需要连接 App 的命令都建议显式传 `--bundle-id`。如果同一个 bundle id 同时出现在模拟器和真机上，再继续加 `--transport`、`--device-id` 或 `--port`。

## 定位节点

查看层级树：

```bash
ivista-lookin tree --bundle-id com.example.demo
ivista-lookin tree --bundle-id com.example.demo --depth 2
ivista-lookin tree --bundle-id com.example.demo --json > hierarchy.json
```

搜索节点：

```bash
ivista-lookin find --bundle-id com.example.demo UIButton
ivista-lookin find --bundle-id com.example.demo UILabel --limit 20
ivista-lookin find --bundle-id com.example.demo --oid 130 --json
```

`find` 会匹配 class name、custom display title、memory address 和 object id。文本输出包含 `oid`、`class`、`frame` 和完整 path，适合先找目标节点。

保留树上下文：

```bash
ivista-lookin tree --bundle-id com.example.demo --filter UIButton
```

聚焦某个子树：

```bash
ivista-lookin tree --bundle-id com.example.demo --oid 130 --depth 3
```

`tree --filter` 会保留命中节点及其祖先；如果只想得到扁平命中列表，用 `find` 更直接。

## 查看对象和属性

查看节点摘要：

```bash
ivista-lookin inspect --bundle-id com.example.demo --oid 130
ivista-lookin inspect --bundle-id com.example.demo --oid 130 --json
```

查看属性：

```bash
ivista-lookin attrs --bundle-id com.example.demo --oid 130
ivista-lookin attrs --bundle-id com.example.demo --oid 130 --group frame
ivista-lookin attrs --bundle-id com.example.demo --oid 130 --json
```

常见流程是先用 `find` 找到 oid，再用 `inspect` 或 `attrs` 下钻：

```bash
ivista-lookin find --bundle-id com.example.demo UIButton --limit 5
ivista-lookin inspect --bundle-id com.example.demo --oid 130
ivista-lookin attrs --bundle-id com.example.demo --oid 130 --json
```

## 截图和导出

导出单节点截图：

```bash
ivista-lookin screenshot --bundle-id com.example.demo --oid 130 --out button.png
ivista-lookin screenshot --bundle-id com.example.demo --oid 130 --type solo --out button-solo.png
```

导出 `.lookin` 快照：

```bash
ivista-lookin export --bundle-id com.example.demo --out demo.lookin
ivista-lookin export --bundle-id com.example.demo --compression 0.6 --out demo.lookin
```

截图和导出依赖目标 App 能返回截图数据。若目标节点太大、App 禁用了截图或连接中断，命令会返回明确错误。

## 调用方法和控制台

列出 selector：

```bash
ivista-lookin selectors --bundle-id com.example.demo --oid 130
ivista-lookin selectors --bundle-id com.example.demo --class UIButton --filter title
```

调用无参数 selector：

```bash
ivista-lookin call --bundle-id com.example.demo --oid 130 --selector description
ivista-lookin eval --bundle-id com.example.demo --oid 130 frame --json
```

进入轻量控制台：

```bash
ivista-lookin console --bundle-id com.example.demo --oid 130
```

控制台内支持：

```text
selectors [filter]
use <oid>
help
quit
```

直接输入 getter 或无参数方法名也会发起调用。第一版不支持带参数 selector。

## 修改属性

先 dry run：

```bash
ivista-lookin set --bundle-id com.example.demo --oid 130 --attr l_f_f --value '0,0,120,44' --dry-run
```

确认 target oid、setter 和解析后的值正确后再执行：

```bash
ivista-lookin set --bundle-id com.example.demo --oid 130 --attr l_f_f --value '0,0,120,44'
```

支持 bool、数字、字符串、point、size、rect、insets、color 和 enum 数值。`--attr` 可以传内建属性 identifier，也可以传自定义属性的标题或 `customSetterID`。自定义属性只有在 SDK 暴露了 `customSetterID` 时可写；没有 setter 的属性和复杂对象暂不支持。

查看某个对象有哪些可用字段：

```bash
ivista-lookin attrs --bundle-id com.example.demo --oid 130 --json | jq '.attributes[].sections[].attributes[] | {identifier,title,isUserCustom,customSetterID,type}'
```

## JSON 和脚本

带 `--json` 的命令会把结果写到 stdout，错误写到 stderr，便于脚本消费：

```bash
ivista-lookin apps --json | jq .
ivista-lookin find --bundle-id com.example.demo UIButton --json | jq '.matches[].oid'
ivista-lookin attrs --bundle-id com.example.demo --oid 130 --json > attrs.json
```

建议脚本里始终显式传 `--bundle-id`，并在有歧义时传 `--transport`、`--device-id` 或 `--port`。

## 常见问题

找不到 App：

1. 确认目标 App 正在前台运行。
2. 确认目标 App 集成了 LookinServer。
3. 确认 LookinServer 没有被 Release 配置裁掉。
4. 确认 App 没有停在断点上。
5. 真机场景确认 USB 连接正常。

命中多个 App：

```bash
ivista-lookin apps --json
ivista-lookin tree --bundle-id com.example.demo --transport usb
ivista-lookin tree --bundle-id com.example.demo --device-id 12
ivista-lookin tree --bundle-id com.example.demo --port 47175
```

找到了 oid 但后续 inspect 失败：

1. UI 层级可能已经刷新，重新运行 `find` 或 `tree`。
2. 目标对象可能已经释放。
3. App 可能切到后台或断开连接。
