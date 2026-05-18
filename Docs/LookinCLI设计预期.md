# LookinCLI 设计预期

本文档描述 ivista fork 中 LookinCLI 的目标、边界、命令设计和开发阶段。它不是最终用户手册，而是后续实现和拆分 PR 的依据。

工程实现细节见 `LookinCLI技术方案.md`。

## 背景

Lookin 目前主要通过 macOS App 使用。App 提供了连接 iOS App、查看 UI 层级、3D 预览、查看和修改属性、调用方法、导出快照等能力。

CLI 的目标不是完整复刻 AppKit 界面，而是把其中适合自动化、脚本化、CI 集成和文本分析的能力暴露出来。GUI 仍然适合交互式观察，CLI 更适合获取结构化信息和批量操作。

## 目标

LookinCLI 希望支持以下场景：

1. 在终端中发现当前可调试的 iOS App。
2. 拉取某个 App 的 UI 层级，并以文本或 JSON 输出。
3. 查询指定节点的属性、对象信息和截图。
4. 导出 `.lookin` 快照文件，方便离线分析和留档。
5. 在明确指定目标对象时，修改属性或调用无参数方法。
6. 作为脚本接口供测试、排查、自动化巡检使用。

## 非目标

第一阶段不追求替代以下 GUI 能力：

1. 3D 可视化预览。
2. 鼠标选择、拖拽、缩放、自由旋转等交互。
3. 测距面板和 hover 测距体验。
4. AppKit 偏好设置窗口。
5. 教程、帮助链接、Sparkle 更新、AppCenter 统计。
6. 完整 Dashboard UI 复刻。

这些能力可以长期留在 LookinClient 中。LookinCLI 只替代其中适合命令行表达的核心能力。

## 当前实现状态

已实现：

1. `lookin --help`
2. `lookin --version`
3. `lookin doctor`
4. `lookin apps [--json] [--bundle-id <bundle-id>] [--transport simulator|usb] [--port <port>] [--device-id <id>]`
5. `lookin tree --bundle-id <bundle-id> [--json] [--depth N] [--filter <text>] [--oid <oid>] [--transport simulator|usb] [--port <port>] [--device-id <id>]`
6. `lookin find --bundle-id <bundle-id> <query> [--json] [--limit N] [--transport simulator|usb] [--port <port>] [--device-id <id>]`
7. `lookin inspect --bundle-id <bundle-id> --oid <oid> [--json] [--transport simulator|usb] [--port <port>] [--device-id <id>]`
8. `lookin attrs --bundle-id <bundle-id> --oid <oid> [--group <filter>] [--json] [--transport simulator|usb] [--port <port>] [--device-id <id>]`
9. `lookin screenshot --bundle-id <bundle-id> --oid <oid> --out <path> [--type group|solo] [--json] [--transport simulator|usb] [--port <port>] [--device-id <id>]`
10. `lookin export --bundle-id <bundle-id> --out <file.lookin> [--compression <0.01-1>] [--json] [--transport simulator|usb] [--port <port>] [--device-id <id>]`
11. `lookin selectors --bundle-id <bundle-id> (--class <class-name> | --oid <oid>) [--with-args] [--filter <text>] [--json] [--transport simulator|usb] [--port <port>] [--device-id <id>]`
12. `lookin call --bundle-id <bundle-id> --oid <oid> --selector <selector> [--json] [--transport simulator|usb] [--port <port>] [--device-id <id>]`
13. `lookin eval --bundle-id <bundle-id> --oid <oid> <property-or-method> [--json] [--transport simulator|usb] [--port <port>] [--device-id <id>]`
14. `lookin console --bundle-id <bundle-id> --oid <oid> [--transport simulator|usb] [--port <port>] [--device-id <id>]`
15. `lookin set --bundle-id <bundle-id> --oid <oid> --attr <identifier> --value <value> [--dry-run] [--json] [--transport simulator|usb] [--port <port>] [--device-id <id>]`

下一步：

1. 操作类命令的更多类型覆盖和测试。
2. Release zip 在干净机器上的独立安装验收。
3. Homebrew tap / formula。

## 与现有 macOS App 的能力映射

| macOS App 能力 | 主要代码 | CLI 映射 |
| --- | --- | --- |
| 扫描模拟器和 USB 真机端口 | `LKConnectionManager`, `LKAppsManager` | `lookin apps` |
| 获取 App 信息和版本校验 | `LKAppsManager`, `LKConnectionManager` | `lookin apps --json`, `lookin inspect` |
| 拉取 UI 层级 | `LKInspectableApp fetchHierarchyData` | `lookin tree`, `lookin inspect --json` |
| 异步补全截图和属性详情 | `LKStaticAsyncUpdateManager` | `lookin attrs`, `lookin screenshot`, `lookin export` |
| 展开、折叠、搜索层级 | `LKHierarchyDataSource`, `LKHierarchyView` | `lookin tree --depth`, `--filter`, `--oid` |
| 查看对象和基础属性 | `fetchObjectWithOid`, `fetchAttrGroupListWithOid` | `lookin inspect --oid ...` |
| 异步补全属性详情 | `LKStaticAsyncUpdateManager` | `lookin attrs --oid ...` |
| 修改属性 | `submitInbuiltModification`, `submitCustomModification` | `lookin set ...` |
| 控制台查看对象属性/调用无参方法 | `LKConsoleDataSource`, `invokeMethodWithOid` | `lookin eval ...`, `lookin console ...`, `lookin call ...` |
| 导出 `.lookin` 文件 | `LKExportManager` | `lookin export ...` |
| 导出单节点截图 | `LKExportManager exportScreenshotWithDisplayItem` | `lookin screenshot ...` |
| 打开 `.lookin` 离线文件 | `LKReadViewController` | `lookin read ...`，后续阶段 |

## 建议架构

长期结构建议如下：

```text
LookinCore
  连接和协议请求
  App 发现
  hierarchy 拉取
  detail 拉取
  属性修改
  方法调用
  统一错误模型

LookinClient
  macOS AppKit UI
  3D 预览
  Dashboard
  测距和交互

LookinCLI
  命令解析
  目标 App 选择
  文本和 JSON 输出
  文件导出
  退出码和 stderr/stdout 约定
```

第一阶段可以先复用 `LookinClient` 中现有的非 UI 类，避免大规模重构。等命令跑通后，再把可复用能力逐步抽到 `LookinCore`。这样更容易保持官方可合并性。

## 独立安装预期

LookinCLI 应支持独立安装和独立升级，不要求用户安装或升级 Lookin macOS App。

这里需要区分两类依赖：

1. 不依赖用户升级 Lookin.app：这是 CLI 的目标。CLI 应作为单独二进制或单独包发布，自己携带运行所需依赖。
2. 仍依赖目标 iOS App 集成 LookinServer：这是 Lookin 通信模型决定的。CLI 只能连接已经集成并运行兼容 LookinServer 的 iOS App。

因此，Phase 1 应尽量只使用现有 LookinServer 已支持的协议请求，例如 App 发现、Hierarchy 拉取和基础详情获取。只要目标 App 当前已经能被 Lookin macOS App 连接，CLI 就应该能连接它，而不要求业务方因为 CLI 额外升级 LookinServer。

独立安装需要避免以下设计：

1. 不从 `/Applications/Lookin.app` 读取二进制、资源或私有路径。
2. 不假设 Lookin.app 已经安装。
3. 不把 CLI 的运行依赖藏在 App bundle 内。
4. 不在第一阶段新增必须升级 LookinServer 才能使用的协议。

推荐分发方式：

```text
Phase 1: 从 Xcode workspace 构建 LookinCLI target，产出 lookin 可执行文件。
Phase 2: 提供 zip 或 pkg，包含 lookin 和必要动态 frameworks。
Phase 3: 提供 Homebrew tap，支持 brew install ivista-lookin-cli。
Phase 4: 若官方接受，进入官方 release 或 brew formula。
```

如果 CLI 后续需要新增 Server 端协议，应按兼容模式设计：

1. 先检测 LookinServer 版本。
2. 对旧版本降级到已有能力。
3. 对必须新协议的命令给出明确错误，例如 “requires LookinServer >= x.y.z”。
4. 不影响 `apps`、`tree`、`export` 等基础命令。

### 可行性调研结论

基于当前 LookinClient 和 LookinServer 代码，LookinCLI 独立安装是可行的。

结论依据：

1. LookinServer 端通过固定端口和 Peertalk 接受连接，没有发现绑定 Lookin.app bundle id 的握手逻辑。
2. Server 端请求分发只校验 request type，例如 `Ping`、`App`、`Hierarchy`、`HierarchyDetails`、`InvokeMethod`，不校验客户端是否来自 Lookin.app。
3. 现有 Client 端连接逻辑主要依赖 `LookinShared`、`ReactiveObjC` 和系统 framework，不依赖 `/Applications/Lookin.app`。
4. `LookinShared` podspec 声明支持 macOS，且包含 shared model、协议常量和 Peertalk 代码，可以被 CLI target 链接。
5. 当前协议已经覆盖 CLI MVP 所需能力：发现 App、拉取层级、拉取详情、导出截图、调用无参数方法、修改属性。

需要注意的边界：

1. CLI 可以不要求用户升级 Lookin.app，但仍要求目标 iOS App 已经集成兼容的 LookinServer。
2. 当前协议版本由 `LOOKIN_SUPPORTED_SERVER_MIN/MAX` 控制。对协议版本不兼容的旧 LookinServer，CLI 也无法天然连接，除非额外实现旧协议兼容层。
3. 第一版应尽量只使用现有 request type，避免要求业务方为了 CLI 升级 LookinServer。
4. 如果未来新增 Server 协议，必须做版本检测和降级提示。

工程上不建议直接复用整个 `LookinClient` target：

1. 现有 `LookinClient_PrefixHeader.pch` 注入了大量 AppKit UI 类型和 UI helper，不适合作为 CLI 预编译头。
2. `LKStaticAsyncUpdateManager` 混合了 detail 任务生成、UI delegate、偏好设置、AppCenter 统计和窗口错误提示，CLI 应抽出轻量 detail service。
3. `LKHierarchyDataSource` 包含 NSMenu、NSColor alias、偏好设置等 GUI 逻辑，CLI 的 tree 输出可以直接遍历 `LookinDisplayItem`。
4. `LKConnectionManager` 初始化时会预取线上 LookinServer 最新版本，这对 CLI 不是必须能力，建议改成可关闭或移动到 GUI 层。
5. `LKHelper lookinReadableVersion` 从 main bundle 读取版本，CLI 应有自己的 version provider。

建议的最小可独立安装形态：

```text
lookin
Frameworks/
  LookinShared.framework
  ReactiveObjC.framework
```

或使用 Homebrew 的 `libexec` 布局：

```text
bin/lookin -> ../libexec/lookin
libexec/lookin
libexec/Frameworks/*.framework
```

如果后续希望安装更轻，可以评估静态链接或 SwiftPM 化，但这不是 MVP 阻塞项。

## 用户安装体验

最终用户应该能在不安装 Lookin.app 的情况下单独获得 `lookin` 命令。

### Homebrew 安装

这是最终推荐体验：

```bash
brew install LLLLLayer/tap/lookin-cli
lookin --version
lookin apps
```

如果未来进入官方或 Homebrew core，命令可以变成：

```bash
brew install lookin-cli
```

Homebrew 安装后的文件布局建议：

```text
$(brew --prefix)/bin/lookin -> ../Cellar/lookin-cli/<version>/bin/lookin
$(brew --prefix)/Cellar/lookin-cli/<version>/bin/lookin
$(brew --prefix)/Cellar/lookin-cli/<version>/libexec/Frameworks/*.framework
```

### GitHub Release 安装

在 Homebrew tap 之前，优先提供 GitHub Release zip：

```text
lookin-cli-macos-arm64.zip
lookin-cli-macos-x86_64.zip
lookin-cli-macos-universal.zip
```

用户使用方式：

```bash
curl -L https://github.com/LLLLLayer/ivista-lookin/releases/download/v0.1.0/lookin-cli-macos-arm64.zip -o lookin-cli.zip
unzip lookin-cli.zip
./lookin --version
./lookin apps
```

压缩包内容建议：

```text
lookin
Frameworks/
  LookinShared.framework
  ReactiveObjC.framework
LICENSE
README.md
install.sh
```

当前实现采用 `@executable_path/Frameworks`。zip 解压后应可直接运行，不需要把文件放入 `/Applications`，也不需要安装 Lookin.app。若未来采用 Homebrew `libexec` 结构，需要在 formula 或打包阶段继续固定 rpath。

### 手动安装

Release zip 解压后也应支持手动安装：

```bash
./install.sh
lookin --version
```

默认安装布局：

```text
/usr/local/bin/lookin -> /usr/local/ivista-lookin-cli/lookin
/usr/local/ivista-lookin-cli/lookin
/usr/local/ivista-lookin-cli/Frameworks/*.framework
```

不使用 sudo 的本地安装：

```bash
INSTALL_PREFIX="$HOME/.local/ivista-lookin-cli" BIN_DIR="$HOME/.local/bin" SUDO= ./install.sh
```

手动安装不应要求复制 Lookin.app，也不应要求把文件放入 `/Applications`。

### 从源码构建

开发者可以从源码构建：

```bash
git clone git@github.com:LLLLLayer/ivista-lookin.git
cd ivista-lookin
git switch ivista/cli
pod install
xcodebuild -workspace Lookin.xcworkspace -scheme LookinCLI -configuration Release build
```

当前提供构建脚本：

```bash
./Scripts/build-lookin-cli.sh
./build/LookinCLI/lookin-cli-macos-universal/lookin --version
```

只打包已有 build product：

```bash
PRODUCT_DIR="$PWD/DerivedData/LookinCLIRelease/Build/Products/Release" ./Scripts/package-lookin-cli.sh
```

### 使用前提

用户安装 CLI 后，还需要满足以下运行前提：

1. 目标 iOS App 已经集成 LookinServer，且运行在 Debug 或内部调试环境。
2. 不要在 App Store Release 包里集成 LookinServer。
3. 目标 App 处于前台，未被断点暂停，主线程没有长时间阻塞。
4. 模拟器场景下，Mac 能连接本机 LookinServer 监听端口。
5. 真机场景下，USB 连接和 Peertalk/usbmuxd 通道可用。

用户预期使用流程：

```bash
lookin apps
lookin tree --bundle-id com.example.demo
lookin tree --bundle-id com.example.demo --json > hierarchy.json
lookin find --bundle-id com.example.demo UIButton --limit 20
lookin tree --bundle-id com.example.demo --filter UIButton
lookin tree --bundle-id com.example.demo --oid 130 --depth 2
lookin inspect --bundle-id com.example.demo --oid 130
lookin attrs --bundle-id com.example.demo --oid 130 --json
lookin screenshot --bundle-id com.example.demo --oid 130 --out button.png
lookin export --bundle-id com.example.demo --out demo.lookin
lookin tree --bundle-id com.example.demo --transport usb
lookin export --bundle-id com.example.demo --port 47165 --out demo.lookin
lookin selectors --bundle-id com.example.demo --oid 130
lookin call --bundle-id com.example.demo --oid 130 --selector description
lookin eval --bundle-id com.example.demo --oid 130 frame --json
lookin console --bundle-id com.example.demo --oid 130
lookin set --bundle-id com.example.demo --oid 130 --attr l_f_f --value '0,0,120,44' --dry-run
```

如果没有找到 App，CLI 应提示用户检查：

1. 目标 App 是否正在运行并处于前台。
2. 目标 App 是否集成了 LookinServer。
3. LookinServer 是否只在 Debug 配置下被编译。
4. iOS App 是否被 Xcode 断点暂停。
5. 真机是否已通过 USB 连接。

### 版本和兼容性命令

CLI 应提供基础自检命令：

```bash
lookin --version
lookin doctor
```

`lookin --version` 输出 CLI 版本、构建架构和协议版本：

```text
LookinCLI 0.1.0
Protocol 7
Architecture arm64
```

`lookin doctor` 检查本机运行环境：

```text
LookinCLI: ok
LookinShared: ok
ReactiveObjC: ok
Simulator ports: 47164-47169
USB support: available
```

`doctor` 不应连接或修改目标 App，只做本机侧检查。

### 发布验收标准

每个可下载版本发布前应满足：

1. 在一台未安装 Lookin.app 的 Mac 上，Release zip 解压后可运行 `./lookin --version`。
2. `lookin apps` 可以发现模拟器中集成 LookinServer 的 Demo App。
3. `lookin tree --json` 输出合法 JSON。
4. `otool -L lookin` 不出现指向开发机 DerivedData、Pods build 临时目录或 `/Applications/Lookin.app` 的依赖。
5. 动态库 rpath 固定在可随包移动的位置，例如 `@executable_path/Frameworks` 或 `@loader_path`。
6. arm64 和 x86_64 包分别验证；若发布 universal 包，需要同时验证两种架构。

## 命令设计

命令名暂定为 `lookin`。如果与未来官方产物冲突，可以在 fork 内使用 `ivista-lookin` 作为二进制名，但代码中的 CLI target 仍建议叫 `LookinCLI`。

### apps

列出当前可连接的 App。

```bash
lookin apps
lookin apps --json
lookin apps --transport usb
lookin apps --bundle-id com.example.demo
```

文本输出建议包含：

```text
NAME        BUNDLE ID              DEVICE        SERVER     STATE
Demo        com.example.demo       iPhone 15     1.2.7      ready
```

JSON 输出建议包含：

```json
[
  {
    "name": "Demo",
    "bundleId": "com.example.demo",
    "deviceName": "iPhone 15",
    "deviceType": "simulator",
    "serverVersion": "1.2.7",
    "state": "ready"
  }
]
```

### inspect

查询某个层级节点对应的对象信息和基础属性。`--oid` 可以来自 `tree` 输出中的 `oid`、`viewOid`、`layerOid` 或 `hostViewControllerOid`。

```bash
lookin inspect --bundle-id com.example.demo --oid 130
lookin inspect --bundle-id com.example.demo --oid 130 --json
lookin inspect --bundle-id com.example.demo --oid 130 --transport usb
```

文本输出建议包含 App 信息、display item 的 view/layer/controller oid、frame、hidden、alpha、对象 class chain 和属性列表。

JSON 输出应保持稳定，根字段建议优先包含：

```text
app, displayItem, object, attributes
```

### tree

输出 UI 层级树。

```bash
lookin tree --bundle-id com.example.demo
lookin tree --bundle-id com.example.demo --depth 3
lookin tree --bundle-id com.example.demo --filter UIButton
lookin tree --bundle-id com.example.demo --oid 123456
lookin tree --bundle-id com.example.demo --json
lookin tree --bundle-id com.example.demo --transport simulator --port 47164
```

`--filter` 会保留命中节点及其祖先，适合在树结构里看上下文；`--oid` 会把输出聚焦到指定 view/layer/controller oid 对应的子树。若只想快速获得命中列表和完整路径，优先使用 `find`。

### find

扁平搜索 UI 层级节点。

```bash
lookin find --bundle-id com.example.demo UIButton
lookin find --bundle-id com.example.demo Submit --limit 10
lookin find --bundle-id com.example.demo --oid 130 --json
```

`find` 会匹配 class name、custom display title、memory address 和 object id。文本输出包含 oid、class、frame 和 path；JSON 输出包含 `count` 和 `matches`，每个 match 复用 tree 的节点字段并附带 `path`、`pathString`、`depth`。

文本输出示例：

```text
UIWindow oid=100 frame={{0,0},{390,844}}
  UIViewControllerWrapperView oid=101 frame={{0,0},{390,844}}
    UIView oid=102 frame={{0,0},{390,844}}
      UIButton oid=130 frame={{24,700},{120,44}} title="Submit"
```

JSON 输出应保持稳定，方便脚本消费。字段建议优先包含：

```text
oid, viewOid, layerOid, hostViewControllerOid, title, className, objectType, frame, bounds, hidden, alpha, children
```

### attrs

查询指定节点的属性详情。

```bash
lookin attrs --bundle-id com.example.demo --oid 130
lookin attrs --bundle-id com.example.demo --oid 130 --group frame
lookin attrs --bundle-id com.example.demo --oid 130 --json
lookin attrs --bundle-id com.example.demo --oid 130 --device-id 42
```

第一阶段只保证读取；属性值格式先复用 LookinShared 的模型，再在 CLI 输出层做稳定映射。`--group` 先按 group identifier 或 title 做大小写不敏感过滤。

### export

导出 `.lookin` 快照文件。

```bash
lookin export --bundle-id com.example.demo --out demo.lookin
lookin export --bundle-id com.example.demo --out demo.lookin --compression 0.5
lookin export --bundle-id com.example.demo --transport usb --out demo.lookin
```

默认行为应尽量接近 macOS App 的导出：包含 hierarchy、属性详情和截图。CLI 当前会拉取每个 layer 的 group screenshot，对可展开节点额外拉取 solo screenshot，并写出可被 Lookin macOS App 打开的 `.lookin` secure archive。

### screenshot

导出指定节点截图。

```bash
lookin screenshot --bundle-id com.example.demo --oid 130 --out button.tiff
lookin screenshot --bundle-id com.example.demo --oid 130 --type group --out button.tiff
lookin screenshot --bundle-id com.example.demo --oid 130 --type solo --out button.tiff
lookin screenshot --bundle-id com.example.demo --oid 130 --transport usb --out button.png
```

`group` 表示包含子视图的截图，`solo` 表示隐藏子视图后的截图。默认使用 `group`。输出格式按 `--out` 后缀判断：`.png` 输出 PNG，其它后缀默认输出 TIFF。

### selectors

查询某个类可调用的方法列表。

```bash
lookin selectors --bundle-id com.example.demo --class UIView
lookin selectors --bundle-id com.example.demo --oid 130
lookin selectors --bundle-id com.example.demo --oid 130 --filter layout
lookin selectors --bundle-id com.example.demo --class UIView --with-args
lookin selectors --bundle-id com.example.demo --class UIView --json
```

默认只返回无参数方法，因为 `call` 第一阶段只支持无参数调用。`--with-args` 可用于查看带参数 selector，但不会让 `call` 支持参数调用。

### call

调用指定对象的无参数方法。

```bash
lookin call --bundle-id com.example.demo --oid 130 --selector layoutIfNeeded
lookin call --bundle-id com.example.demo --oid 130 --selector recursiveDescription --json
```

安全约束：

1. 第一阶段只支持无参数 selector。
2. 默认需要明确 `--oid`，不做模糊选择。
3. 对可能修改 UI 的方法不额外拦截，但命令文档需要说明风险。
4. 如果 selector 包含 `:`，命令直接返回 unsupported，避免误以为支持传参。

### eval 和 console

`eval` 是 `call` 的控制台友好别名，用来表达“看这个对象的某个属性/变量”。它只接受直接 getter 或无参数方法名，不支持 `a.b` 链式表达式。

```bash
lookin eval --bundle-id com.example.demo --oid 130 frame --json
lookin eval --bundle-id com.example.demo --oid 130 backgroundColor
lookin eval --bundle-id com.example.demo --oid 130 description
```

`console` 是交互式轻量控制台。第一版保持一个目标 App 连接，支持输入直接 getter/无参数方法，并提供内置命令：

```bash
lookin console --bundle-id com.example.demo --oid 130
```

交互命令：

1. `<name>`：调用当前对象的直接 getter 或无参数方法。
2. `selectors [filter]`：列出当前对象 class 的无参数 selector。
3. `use <oid>`：切换当前对象。
4. `help`：显示帮助。
5. `quit`：退出。

### set

修改指定对象属性。

```bash
lookin set --bundle-id com.example.demo --oid 130 --attr l_f_f --value '0,0,120,44'
lookin set --bundle-id com.example.demo --oid 130 --attr vl_v_h --value true
lookin set --bundle-id com.example.demo --oid 130 --attr vl_b_b --value '#ff0000'
lookin set --bundle-id com.example.demo --oid 130 --attr customTitle --value 'hello'
lookin set --bundle-id com.example.demo --oid 130 --attr vl_v_o --value 0.5 --dry-run
```

`set` 会先按 `--oid` 拉取 dashboard 属性，找到 `--attr` 对应的 `LookinAttribute`。`--attr` 可以匹配内建属性 identifier，也可以匹配 custom attr 的 display title 或 `customSetterID`。

1. 内建属性：用 `LookinDashboardBlueprint setterWithAttrID:` 和 `isUIViewPropertyWithAttrID:` 推导 setter 与目标 view/layer oid，然后提交 `LookinRequestTypeInbuiltAttrModification`。
2. 自定义属性：要求属性带有 `customSetterID`，然后提交 `LookinRequestTypeCustomAttrModification`。

支持的值格式：

1. bool：`true/false`、`yes/no`、`1/0`
2. 数字和 enum 数值：`24`、`0.5`
3. string 和 enum string：原样字符串
4. point/size：`x,y`
5. rect/insets：`x,y,width,height` 或 `top,left,bottom,right`
6. color：`#RRGGBB`、`#RRGGBBAA` 或 `r,g,b[,a]`

这是高风险命令，默认要求用户明确传入 `--oid` 和 attr；建议修改前先用 `--dry-run` 查看解析出的 target oid / custom setter id 和新值。没有 setter 的内建属性、没有 `customSetterID` 的 custom attr、以及复杂对象类型会返回 unsupported。

## 目标 App 选择规则

所有需要连接 App 的命令都支持以下选择方式：

```bash
--bundle-id com.example.demo
--transport simulator|usb
--port 47164
--device-id 42
```

当前规则：

1. 设备命令仍要求显式传 `--bundle-id`，避免在脚本里误选 App。
2. `--transport` 只接受 `simulator` 或 `usb`。
3. `--port` 用于区分同一 transport 下的多个连接端口。
4. `--device-id` 用于区分 USB 设备。
5. 如果匹配多个 App，命令返回 `LKCLIExitCodeAmbiguousApp`，并提示继续加选择参数。
6. `lookin apps` 也支持同一组选项，用于先过滤并确认目标。

后续可以再补 `--name` 和 `--index`，但第一版优先使用更稳定的 bundle id、transport、port 和 device id。

## 输出约定

CLI 应区分 stdout 和 stderr：

1. stdout 只输出命令结果，尤其是 JSON。
2. stderr 输出进度、警告和错误。
3. `--json` 下 stdout 必须是合法 JSON。
4. 默认文本输出面向人阅读，字段可以更紧凑。

建议通用参数：

```bash
--json
--pretty
--timeout 5
--verbose
--quiet
```

## 退出码

建议先定义少量稳定退出码：

| 退出码 | 含义 |
| --- | --- |
| 0 | 成功 |
| 1 | 通用错误 |
| 2 | 参数错误 |
| 3 | 未找到可连接 App |
| 4 | App 选择不唯一 |
| 5 | 连接失败或超时 |
| 6 | LookinServer 版本不兼容 |
| 7 | 目标对象不存在 |
| 8 | 操作被拒绝或不支持 |

## 阶段计划

### Phase 0: 文档和工程骨架

1. 新增 CLI 设计文档。
2. 新增 `LookinCLI` target。
3. 命令入口可运行 `lookin --help` 和 `lookin --version`。
4. 新增 `lookin doctor` 的本机侧检查骨架。
5. 不改动 macOS App 行为。

### Phase 1: 只读基础命令

1. `lookin apps`
2. `lookin inspect`
3. `lookin tree`
4. `lookin find`
5. 稳定 JSON 输出。
6. 覆盖模拟器连接路径。
7. 验证 CLI 不依赖已安装的 Lookin.app。

### Phase 2: 详情和导出

1. `lookin attrs`
2. `lookin export`
3. `lookin screenshot`
4. 处理异步 detail 拉取进度和错误。
5. 产出可移动的 Release zip。（已由 `Scripts/build-lookin-cli.sh` 和 `Scripts/package-lookin-cli.sh` 覆盖）

### Phase 3: 操作类命令

1. `lookin selectors`
2. `lookin call`
3. `lookin eval`
4. `lookin console`
5. `lookin set`
6. 为写操作继续增加类型转换覆盖和测试。
7. 提供 Homebrew tap。

### Phase 4: Core 抽离和官方 PR

1. 将非 UI 的连接、请求、输出模型抽到 `LookinCore`。
2. 保持 `LookinClient` 行为不变。
3. 将 PR 拆小：先无行为变化重构，再新增最小 CLI。

## 官方合并策略

为了提高合并到官方 Lookin 的可能性，建议遵守以下原则：

1. 不在第一版大规模重写现有 AppKit UI。
2. 不把 CLI 输出逻辑写进 ViewController。
3. 不改变现有 `.lookin` 文件格式，除非单独讨论。
4. 不新增大型第三方依赖，除非收益明确。
5. 每个 PR 都能独立解释价值，并尽量保持小颗粒度。

推荐 PR 顺序：

```text
1. docs: describe LookinCLI goals and command surface
2. refactor: isolate app discovery from UI callers
3. refactor: isolate hierarchy fetch service
4. feat(cli): add LookinCLI target and apps command
5. feat(cli): add tree command with JSON output
6. feat(cli): add export command
```

## MVP 验收标准

第一版 MVP 达到以下标准即可认为可用：

1. 在一台启动了集成 LookinServer 的模拟器上，`lookin apps` 能列出目标 App。
2. `lookin tree --json` 输出稳定 JSON，且包含完整层级结构。
3. `lookin tree` 文本输出能让人快速定位 class、oid、frame。
4. 错误场景有明确提示，包括无 App、多个 App、App 后台、版本不兼容、请求超时。
5. 不影响现有 `LookinClient` target 构建和运行。
6. Release zip 可在未安装 Lookin.app 的机器上独立运行。
7. `otool -L lookin` 不包含开发机临时路径或 Lookin.app bundle 路径。

## 当前建议

从 `ivista/cli` 分支开始开发。`Develop` 只用于同步官方。所有 CLI 工作先进入 `ivista/cli`，后续再从中拆出适合官方 review 的小 PR。
