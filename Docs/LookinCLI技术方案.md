# LookinCLI 技术方案

本文档描述 LookinCLI 的工程实现方案。它和 `LookinCLI设计预期.md` 配套使用：设计预期定义产品边界和命令面，本文档定义 target、模块、依赖、实现顺序和发布验证。

## 结论

LookinCLI 第一版建议使用 Objective-C 实现。

原因：

1. 现有 LookinClient 主要是 Objective-C。
2. 连接层、请求层、模型层已经是 Objective-C 和 ReactiveObjC。
3. `LookinShared` 暴露的协议对象、模型和 Peertalk 代码都是 Objective-C。
4. Objective-C 可以最少桥接、最快复用现有代码。
5. 对官方 PR 更友好，因为改动风格贴近原项目。

Swift 可以后续局部引入，但 Phase 0 和 Phase 1 不建议先 Swift 化。

## 总体架构

长期结构：

```text
LookinShared
  官方已有：协议常量、模型、Peertalk、序列化对象

LookinCore
  App 发现
  连接管理
  请求封装
  hierarchy 拉取
  detail 拉取
  属性修改
  方法调用
  统一错误模型

LookinClient
  原 macOS App
  AppKit UI
  3D 预览
  Dashboard
  测距和交互

LookinCLI
  main
  command parser
  app selector
  JSON/text renderer
  exit code
  release packaging
```

第一阶段可以先不创建完整 `LookinCore` target，避免一开始重构过大。先新增 `LookinCLI` target，并在 CLI 内部建立轻量 core-like 模块。等 `apps` 和 `tree` 跑通后，再把稳定的非 UI 能力抽到 `LookinCore`。

## Target 设计

新增一个 macOS Command Line Tool target：

```text
Target: LookinCLI
Product: lookin
Language: Objective-C
Deployment Target: macOS 11.0，或跟随 LookinClient
```

`LookinCLI` 不应使用 `LookinClient_PrefixHeader.pch`。现有 PCH 注入了大量 AppKit UI 类型、ViewController、`NSApp`、UI helper 和 category，不适合命令行 target。

建议新增独立 PCH：

```text
LookinCLI/LookinCLI_PrefixHeader.pch
```

只包含：

```objc
#import <Foundation/Foundation.h>
#import <ReactiveObjC/ReactiveObjC.h>
#import "LookinDefines.h"
```

如果某些输出功能需要 `NSImage` 或 `NSColor`，在对应 `.m` 文件里局部引入 AppKit，不放进全局 PCH。

## 依赖策略

Phase 0/1 依赖：

```text
LookinShared
ReactiveObjC
Foundation
AppKit，仅当需要 NSImage/NSColor/NSBitmapImageRep 时局部使用
```

避免依赖：

```text
AppCenter
Sparkle
Lookin.app bundle
LookinClient ViewController
LookinClient WindowController
LookinClient toolbar/menu/preference UI
```

`Podfile` 后续需要新增 target：

```ruby
target 'LookinCLI' do
  platform :osx, '11.0'
  pod 'ReactiveObjC', '3.1.0'
  pod 'LookinShared', :git=>'https://github.com/QMUI/LookinServer.git', :branch => 'develop'
end
```

`LookinCLI` 不应依赖 `AppCenter` 和 `Sparkle`。

## 目录建议

```text
LookinCLI/
  main.m
  LookinCLI_PrefixHeader.pch

  Core/
    LKCLIVersionProvider.h/.m
    LKCLIConnectionService.h/.m
    LKCLIAppDiscoveryService.h/.m
    LKCLIAppSelector.h/.m
    LKCLIHierarchyService.h/.m
    LKCLIDetailFetcher.h/.m
    LKCLIAsync.h/.m
    LKCLIExitCode.h
    LKCLIErrorPresenter.h/.m

  Commands/
    LKCLICommand.h
    LKCLICommandContext.h/.m
    LKCLIHelpCommand.h/.m
    LKCLIVersionCommand.h/.m
    LKCLIDoctorCommand.h/.m
    LKCLIAppsCommand.h/.m
    LKCLIInspectCommand.h/.m
    LKCLITreeCommand.h/.m

  Parsing/
    LKCLIArgumentParser.h/.m
    LKCLIOptions.h/.m
    LKCLIAppSelector.h/.m

  Rendering/
    LKCLIJSONWriter.h/.m
    LKCLITableRenderer.h/.m
    LKCLITreeTextRenderer.h/.m
    LKCLITreeJSONRenderer.h/.m

  Support/
    LKCLIStdIO.h/.m
```

命名先用 `LKCLI` 前缀，保持和现有 `LK` 风格接近，同时避免和 GUI 类混淆。

## 可复用现有代码

可以优先复用或轻量改造：

```text
LookinClient/Connection/LKConnectionRequest
LookinClient/Connection/LKConnectionManager
LookinClient/Connection/LKAppsManager
LookinClient/Connection/LKInspectableApp
LookinClient/Other/LKVersionComparer
LookinClient/Other/LKServerVersionRequestor，CLI 中可选
```

但不建议直接复用：

```text
LKStaticAsyncUpdateManager
LKHierarchyDataSource
LKStaticHierarchyDataSource
LKDashboardViewController
LKConsoleDataSource
LKExportManager 的 UI 保存面板部分
LKHelper
```

这些类混合了 UI、偏好设置、AppCenter、窗口错误提示或 App bundle 假设。

## 连接层方案

现有连接流程：

```text
LKConnectionManager
  tryToConnectAllPorts
  requestWithType:data:channel:

LKAppsManager
  fetchAppInfosWithImage:localInfos:

LKInspectableApp
  fetchHierarchyData
  fetchHierarchyDetailWithTaskPackages
  submitInbuiltModification
  invokeMethodWithOid
```

CLI 第一版可以复用相同流程，但建议加一层命令行服务：

```objc
@interface LKCLIAppDiscoveryService : NSObject
- (NSArray<LKInspectableApp *> *)fetchAppsWithImages:(BOOL)needImages
                                               error:(NSError **)error;
@end
```

内部仍可调用 `LKAppsManager` 的 RAC API，然后通过 `LKCLIAsync` 等待完成。

需要改造点：

1. `LKInspectableApp fetchHierarchyData` 当前依赖 `[LKHelper lookinReadableVersion]`。CLI 应改为可注入 version provider，或在 CLI 内写一个不依赖 `LKHelper` 的 wrapper。
2. `LKConnectionManager init` 会调用 `LKServerVersionRequestor preload`。这对 CLI 不是必要能力，后续建议让该行为可关闭，或把版本预取移动到 GUI 层。
3. 错误文案里使用 `NSLocalizedString` 可以保留，但 CLI 输出层需要把错误格式化到 stderr。

## 异步等待方案

现有请求以 `RACSignal` 返回。CLI 命令需要同步退出码，因此需要统一封装：

```objc
@interface LKCLIAsyncResult<__covariant ObjectType> : NSObject
@property(nonatomic, strong, nullable) ObjectType value;
@property(nonatomic, strong, nullable) NSError *error;
@property(nonatomic, assign) BOOL timedOut;
@end

@interface LKCLIAsync : NSObject
+ (LKCLIAsyncResult *)waitForSignal:(RACSignal *)signal timeout:(NSTimeInterval)timeout;
@end
```

实现思路：

1. 订阅 signal。
2. 收集 `next` 值。
3. 等待 `completed` 或 `error`。
4. 使用 `dispatch_semaphore` 或 `NSRunLoop` 保持当前进程不提前退出。
5. timeout 后取消订阅并返回 timeout error。

注意：Peertalk 和 RAC 可能依赖 run loop/callback，因此如果 semaphore 等待导致回调无法执行，应改用短周期 `NSRunLoop` 驱动。

## App 选择方案

所有需要连接 App 的命令都走 `LKCLIAppSelector`：

```objc
@interface LKCLIAppSelector : NSObject
- (LKCLIConnectedApp *)selectAppFromAppsValue:(id)appsValue
                                    selection:(LKCLIAppSelection *)selection
                                     exitCode:(LKCLIExitCode *)exitCode;
@end
```

选择规则：

1. `--bundle-id` 是设备命令的必填基础选择器。
2. `--transport simulator|usb` 用于区分模拟器和真机。
3. `--port <port>` 用于锁定具体连接端口。
4. `--device-id <id>` 用于锁定 USB 设备。
5. 匹配 0 个 App 返回 `LKCLIExitCodeNoApp`。
6. 匹配多个 App 返回 `LKCLIExitCodeAmbiguousApp`，并提示继续补选择参数。
7. `lookin apps` 可以使用同一组选项进行过滤，但会保留 server version error 记录，方便诊断。

## tree 输出方案

不复用 `LKHierarchyDataSource`。CLI 直接遍历 `LookinHierarchyInfo.displayItems` 和 `LookinDisplayItem.subitems`。

原因：

1. `LKHierarchyDataSource` 包含 NSMenu、NSColor alias 和偏好设置。
2. CLI 不需要 GUI 展开状态。
3. CLI tree 更关注稳定结构化输出。

文本输出字段：

```text
class/title
oid
frame
hidden
alpha
subtitle，存在时显示
```

JSON 输出字段：

```text
oid
title
className
objectType
memoryAddress
frame
bounds
hidden
alpha
children
```

`className` 建议先使用 `LookinObject.rawClassName`。后续如果需要 demangle，再决定是否复用 Swift demangler 或写轻量 ObjC demangle fallback。

## detail 拉取方案

不直接复用 `LKStaticAsyncUpdateManager`，新增 `LKCLIDetailFetcher`。

原因：

1. `LKStaticAsyncUpdateManager` 依赖 `LKStaticHierarchyDataSource`。
2. 它混合了 UI delegate、AppCenter、偏好设置和窗口错误提示。
3. CLI 需要更简单的同步模型和 stderr 进度。

`LKCLIDetailFetcher` 负责：

```text
makeTasksForItems
packageTasks
fetchDetails
applyDetailsToItems
reportProgress
```

仍复用协议对象：

```text
LookinStaticAsyncUpdateTask
LookinStaticAsyncUpdateTasksPackage
LookinDisplayItemDetail
```

这样不需要修改 LookinServer。

任务生成策略：

1. `attrs` 命令只请求 `LookinStaticAsyncUpdateTaskTypeNoScreenshot`，并设置 attrRequest 为 Need。
2. `screenshot` 命令按 `--type group/solo` 请求截图。
3. `export` 命令对所有节点请求 group screenshot；对 expandable 节点请求 solo screenshot；同时请求 attrs。

## JSON 输出方案

使用 `NSJSONSerialization`，不要手拼 JSON。

建议封装：

```objc
@interface LKCLIJSONWriter : NSObject
+ (BOOL)writeJSONObject:(id)object pretty:(BOOL)pretty error:(NSError **)error;
@end
```

约定：

1. stdout 只输出 JSON。
2. stderr 输出进度和错误。
3. `--json` 输出必须可被 `jq` 解析。
4. 所有数值类型保持数值，不转字符串，除非 ObjC 模型本身只能提供字符串。

## 错误和退出码

新增：

```objc
typedef NS_ENUM(NSInteger, LKCLIExitCode) {
    LKCLIExitCodeOK = 0,
    LKCLIExitCodeGeneralError = 1,
    LKCLIExitCodeUsage = 2,
    LKCLIExitCodeNoApp = 3,
    LKCLIExitCodeAmbiguousApp = 4,
    LKCLIExitCodeConnection = 5,
    LKCLIExitCodeServerVersion = 6,
    LKCLIExitCodeObjectNotFound = 7,
    LKCLIExitCodeUnsupported = 8,
};
```

错误输出统一走：

```objc
LKCLIErrorPresenter
```

普通文本：

```text
error: no inspectable app found
hint: make sure the target app is running in foreground and integrates LookinServer
```

JSON 错误可后续支持：

```json
{
  "error": {
    "code": "no_app",
    "message": "no inspectable app found"
  }
}
```

## 命令解析方案

第一版可以手写轻量 parser，避免引入大型依赖。

支持：

```text
lookin --help
lookin --version
lookin doctor
lookin apps [--json] [--bundle-id ...] [--transport simulator|usb] [--port ...] [--device-id ...]
lookin inspect --bundle-id ... --oid ... [--json] [--transport simulator|usb] [--port ...] [--device-id ...]
lookin attrs --bundle-id ... --oid ... [--group ...] [--json] [--transport simulator|usb] [--port ...] [--device-id ...]
lookin screenshot --bundle-id ... --oid ... --out ... [--type group|solo] [--json] [--transport simulator|usb] [--port ...] [--device-id ...]
lookin export --bundle-id ... --out ... [--compression 0.01-1] [--json] [--transport simulator|usb] [--port ...] [--device-id ...]
lookin tree --bundle-id ... [--depth N] [--json] [--transport simulator|usb] [--port ...] [--device-id ...]
lookin selectors --bundle-id ... (--class ... | --oid ...) [--with-args] [--filter ...] [--json] [--transport simulator|usb] [--port ...] [--device-id ...]
lookin call --bundle-id ... --oid ... --selector ... [--json] [--transport simulator|usb] [--port ...] [--device-id ...]
```

如果后续命令复杂度显著上升，再评估是否引入 argument parser 库。

## 打包和发布方案

Release zip 内容：

```text
lookin
Frameworks/
  LookinShared.framework
  ReactiveObjC.framework
LICENSE
README.md
```

构建后处理：

```bash
otool -L lookin
install_name_tool -add_rpath @executable_path/Frameworks lookin
codesign --force --deep --sign - lookin Frameworks/*.framework
```

正式发布时应使用 Developer ID 签名和 notarization；MVP 可以先 ad-hoc 签名用于内部验证。

发布验收：

1. 在未安装 Lookin.app 的机器上运行 `./lookin --version`。
2. `otool -L lookin` 不包含 DerivedData、Pods build 临时目录、`/Applications/Lookin.app`。
3. `lookin apps` 能发现模拟器 Debug App。
4. `lookin tree --json` 能输出合法 JSON。

## 实现顺序

### Step 1: Target 骨架

1. 修改 Podfile，新增 `LookinCLI` target。
2. 新增 `LookinCLI/main.m`。
3. 新增 `LookinCLI_PrefixHeader.pch`。
4. 新增 `--help`、`--version`、`doctor`。
5. 确认 `LookinClient` scheme 不受影响。

### Step 2: apps

1. 在 CLI 内新增轻量连接扫描器，复用 Peertalk、`LookinConnectionAttachment`、`LookinConnectionResponseAttachment` 和 `LookinAppInfo`。
2. 暂不把 `LKConnectionManager` / `LKAppsManager` / `LKInspectableApp` 直接加入 CLI target，避免把 `LKNavigationManager`、`LKHelper` 等 AppKit/UI 依赖带进命令行工具。
3. 实现 `LKCLISignalRunner`，用 run loop 驱动 RAC/Peertalk 异步回调。
4. 实现 `lookin apps` 文本输出。
5. 实现 `lookin apps --json`。

### Step 2.5: core extraction

1. 当 `apps` 和 `tree` 都跑通后，再评估把稳定的连接请求层从 CLI 内部抽成 `LookinCore`。
2. `LookinCore` 应该只依赖 Foundation、ReactiveObjC、LookinShared。
3. `LookinClient` 和 `LookinCLI` 最终都使用 `LookinCore`，减少长期重复代码。

### Step 3: inspect/tree

1. 实现 `LKCLIAppSelector`。
2. 调用 `fetchHierarchyData`。
3. 实现 tree 文本输出。
4. 实现 tree JSON 输出。
5. 增加 `--depth`、`--filter`、`--oid`。

### Step 4: attrs/screenshot/export

1. 新增 `LKCLIDetailFetcher`。
2. 支持指定 oid 拉取属性。
3. 支持指定 oid 导出截图。
4. 支持全量导出 `.lookin`。

### Step 5: 操作命令

1. `selectors`：调用 `LookinRequestTypeAllSelectorNames`，支持按 class 直接查询，也支持按 oid 先取 `LookinObject.rawClassName` 再查询。
2. `call`：调用 `LookinRequestTypeInvokeMethod`，第一版只允许无参数 selector，直接拒绝包含 `:` 的方法名。
3. `set`
4. 类型转换和写操作安全提示。

### Step 6: 打包

1. 新增 `Scripts/build-lookin-cli.sh`。
2. 新增 `Scripts/package-lookin-cli.sh`。
3. 生成 zip。
4. 验证独立安装。

## 风险清单

| 风险 | 影响 | 应对 |
| --- | --- | --- |
| 现有连接类隐式依赖 GUI helper | CLI 编译失败或运行异常 | 新增 CLI wrapper，逐步移除 `LKHelper` 依赖 |
| RAC/Peertalk 依赖 run loop | CLI 等待时卡住 | `LKCLIAsync` 使用 run loop 驱动而非纯 semaphore |
| 动态库 rpath 指向构建目录 | zip 无法独立运行 | 打包阶段固定 `@executable_path/Frameworks` |
| 旧 LookinServer 协议不兼容 | 用户无法连接旧 App | 明确错误；后续按需实现兼容层 |
| 真机 USB 连接行为复杂 | `apps` 在真机上不稳定 | CLI 设备命令使用跨进程锁串行化；App 发现为空时自动重试一次 |
| JSON 字段随模型变化漂移 | 脚本兼容性差 | 在 renderer 层定义稳定 DTO，不直接 dump ObjC 模型 |

## 当前建议

当前 Phase 0 已完成：`LookinCLI` target、`--help`、`--version`、`doctor`、独立 framework 嵌入和原 `LookinClient` build 验证均已通过。

当前 Phase 0.5 已完成：`lookin apps [--json]` 已打通发现可调试 App 的链路。

当前 Phase 1 基础版已完成：`lookin tree --bundle-id <bundle-id> [--json] [--depth N]` 可按 bundle id 拉取 UI 层级，并输出稳定文本或 JSON。

当前 Phase 1.5 已完成基础链路：设备命令已加跨进程锁和空结果重试，降低真机 USB 并发扫描不稳定；`lookin inspect --bundle-id <bundle-id> --oid <oid> [--json]` 可按 oid 拉取对象信息和基础属性；`lookin attrs --bundle-id <bundle-id> --oid <oid> [--group <filter>] [--json]` 可单独输出属性详情；`lookin screenshot --bundle-id <bundle-id> --oid <oid> --out <path> [--type group|solo] [--json]` 可导出节点截图；`lookin export --bundle-id <bundle-id> --out <file.lookin> [--compression <0.01-1>] [--json]` 可导出离线快照；所有设备命令都支持 `--transport simulator|usb`、`--port <port>` 和 `--device-id <id>` 做 disambiguation。

当前 Phase 2 已开始：`lookin selectors --bundle-id <bundle-id> (--class <class-name> | --oid <oid>) [--with-args] [--filter <text>] [--json]` 可列出 selector；`lookin call --bundle-id <bundle-id> --oid <oid> --selector <selector> [--json]` 可调用无参数方法。后续继续补 `set` 和发布打包。
