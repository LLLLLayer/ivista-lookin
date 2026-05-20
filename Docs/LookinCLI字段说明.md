# LookinCLI 字段说明

本文档说明 `ivista-lookin --json` 输出中适合脚本依赖的字段。字段来自当前 CLI 的公开输出格式；未在本文档说明的内部字段不建议作为稳定契约使用。

## 通用约定

- JSON 输出写入 stdout，警告和错误写入 stderr。
- 缺失、未返回或不适用的字段使用 `null`。
- 坐标和尺寸使用 iOS point，不是物理 pixel。
- `frame` 统一表示为 `{ "x": number, "y": number, "width": number, "height": number }`。
- `oid` 是 LookinServer 在当前连接或当前 `.lookin` 快照中的对象标识。它适合在一次排查流程内传给 `--oid`，不应长期持久化。
- `read <file.lookin>` 输出的是离线快照内容，不能反映当前运行中 App 的最新 UI 状态。

## App 字段

`apps --json` 返回数组，每个元素代表一个可连接端点。

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `status` | string | `ok` 表示可用；`serverVersionError` 表示发现端点但 LookinServer 协议版本不兼容。 |
| `error` | string/null | `status` 非 `ok` 时的错误信息。 |
| `transport` | string/null | 连接来源，当前主要是 `simulator` 或 `usb`。 |
| `port` | number | LookinServer 连接端口。 |
| `deviceID` | string/null | 真机或设备通道 ID；仅发现到设备 ID 时出现。 |
| `name` | string/null | App 展示名。 |
| `bundleIdentifier` | string/null | App bundle id，后续命令通常传给 `--bundle-id`。 |
| `device` | string/null | 设备描述。 |
| `os` | string/null | iOS 系统描述。 |
| `deviceType` | string | `simulator`、`ipad` 或 `iphone`。 |
| `screen` | object | 屏幕信息，包含 `width`、`height`、`scale`。 |
| `serverVersion` | number | LookinServer 协议版本号。 |
| `serverReadableVersion` | string/null | LookinServer 可读版本号。 |
| `swiftEnabledInLookinServer` | boolean | LookinServer 是否启用 Swift 支持。 |

示例：

```bash
ivista-lookin apps --json | jq '.[] | {bundleIdentifier, transport, deviceID, status}'
```

## 通用 app 对象

多数在线命令的 JSON 根对象包含 `app`：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `app.name` | string/null | App 展示名。 |
| `app.bundleIdentifier` | string/null | App bundle id。 |
| `app.device` | string/null | 设备描述。 |
| `app.os` | string/null | iOS 系统描述。 |

## 对象标识字段

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `oid` | number/null | 当前对象的主要标识。`tree`、`find` 中通常是节点正在展示的对象 ID。 |
| `viewOid` | number/null | 节点关联的 UIView 对象 ID。 |
| `layerOid` | number/null | 节点关联的 CALayer 对象 ID。 |
| `hostViewControllerOid` | number/null | 节点关联的 UIViewController 对象 ID。 |
| `requestedOid` | number | 用户传入的 `--oid`。 |
| `detailOid` | number | CLI 用来拉取详情或截图的对象 ID，可能和 `requestedOid` 不同。 |
| `targetOid` | number/null | `set` 实际写入目标对象 ID。 |

`tree`、`find`、`inspect` 和 `attrs` 都可以用 `viewOid`、`layerOid` 或 `hostViewControllerOid` 继续下钻；CLI 会在节点的 view、layer、controller 对象中匹配传入的 `--oid`。

## 层级节点字段

`tree --json` 的根对象：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `filter` | string/null | 当前 `--filter` 值。 |
| `focusOid` | number/null | 当前 `--oid` 聚焦节点。 |
| `items` | array | 顶层节点数组。 |

`tree.items[]` 和 `find.matches[]` 中的节点字段：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `oid` | number | 当前展示对象 ID。 |
| `viewOid` | number/null | UIView 对象 ID。 |
| `layerOid` | number/null | CALayer 对象 ID。 |
| `hostViewControllerOid` | number/null | UIViewController 对象 ID。 |
| `className` | string/null | 当前展示对象类名。 |
| `customTitle` | string/null | Lookin 自定义展示标题。 |
| `hidden` | boolean | 节点是否隐藏。 |
| `alpha` | number | 节点透明度。 |
| `keyWindow` | boolean | 是否被标记为 key window。 |
| `frame` | object | 节点 frame，单位是 point。 |
| `children` | array | 子节点。受 `--depth` 限制，达到深度上限时为空数组。 |

`find --json` 额外包含：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `query` | string/null | 搜索文本或 oid。 |
| `limit` | number/null | 当前限制数量。 |
| `count` | number | 返回命中数量。 |
| `matches[].depth` | number | 命中节点在树中的深度。 |
| `matches[].path` | array | 从根到命中节点的类名路径。 |
| `matches[].pathString` | string | 可读路径，使用 ` > ` 连接。 |

示例：

```bash
ivista-lookin find --bundle-id com.example.demo UILabel --json \
  | jq '.matches[] | {oid, className, frame, pathString}'
```

## 对象详情字段

`inspect --json` 和 `attrs --json` 都包含 `displayItem`、`object` 和 `attributes`。

`displayItem` 表示层级节点：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `viewOid` | number/null | UIView 对象 ID。 |
| `layerOid` | number/null | CALayer 对象 ID。 |
| `hostViewControllerOid` | number/null | UIViewController 对象 ID。 |
| `className` | string/null | 展示对象类名。 |
| `customTitle` | string/null | 自定义展示标题。 |
| `hidden` | boolean | 是否隐藏。 |
| `alpha` | number | 透明度。 |
| `keyWindow` | boolean | 是否被标记为 key window。 |
| `frame` | object | frame，单位是 point。 |

`object` 表示当前详情对象：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `oid` | number | 对象 ID。 |
| `className` | string/null | 对象类名。 |
| `memoryAddress` | string/null | 运行时内存地址，仅用于辅助识别。 |
| `classChain` | array | 类继承链或相关类链。 |
| `specialTrace` | string/null | LookinServer 返回的特殊追踪信息。 |

## 属性字段

`attributes` 是属性组数组，结构为：

```text
attributes[]
  sections[]
    attributes[]
```

属性组字段：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `identifier` | string/null | 属性组标识。 |
| `title` | string | 属性组展示名。 |
| `sections` | array | 属性 section 数组。 |

属性 section 字段：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `identifier` | string/null | section 标识。 |
| `attributes` | array | 属性数组。 |

单个属性字段：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `identifier` | string/null | 属性标识。传给 `set --attr` 时优先使用这个字段。 |
| `title` | string | 属性展示名。 |
| `isUserCustom` | boolean | 是否来自 LookinServer 用户自定义属性。 |
| `customSetterID` | string/null | 自定义 setter ID。自定义属性可写时通常依赖它。 |
| `type` | string | 属性类型名称。 |
| `typeCode` | number | Lookin 内部属性类型枚举值。脚本优先使用 `type`，不要依赖 `typeCode` 做跨版本判断。 |
| `value` | any | 机器可读值。结构化类型会尽量输出 object 或 array。 |
| `displayValue` | string | 人类可读值，适合展示，不适合再解析后写回。 |

常见 `type`：

```text
bool, int, long, float, double, string, point, size, rect, edgeInsets, color,
selector, class, enumInt, enumLong, enumString, customObject, json
```

结构化 `value` 约定：

| 类型 | `value` 形状 |
| --- | --- |
| `point` | `{ "x": number, "y": number }` |
| `size` | `{ "width": number, "height": number }` |
| `rect` | `{ "x": number, "y": number, "width": number, "height": number }` |
| `edgeInsets` | `{ "top": number, "left": number, "bottom": number, "right": number }` |
| `color` | 通常是数组或服务端返回的兼容 JSON 值；展示用 `displayValue` 更直接。 |

查找可用于 `set` 的字段：

```bash
ivista-lookin attrs --bundle-id com.example.demo --oid 123 --json \
  | jq '.attributes[].sections[].attributes[] | {identifier,title,type,isUserCustom,customSetterID,value,displayValue}'
```

## set 字段

`set --json` 返回写入计划或写入结果。建议先加 `--dry-run` 检查解析结果：

```bash
ivista-lookin set --bundle-id com.example.demo --oid 123 \
  --attr hidden --value true --dry-run --json
```

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `object.oid` | number | 被检查对象 ID。 |
| `object.className` | string/null | 被检查对象类名。 |
| `attribute.identifier` | string/null | 匹配到的属性标识。 |
| `attribute.title` | string | 匹配到的属性展示名。 |
| `attribute.kind` | string | `builtIn` 或 `custom`。 |
| `attribute.customSetterID` | string/null | 自定义 setter ID。 |
| `attribute.type` | string | 属性类型。 |
| `attribute.typeCode` | number | 内部类型枚举值。 |
| `attribute.oldValue` | string | 写入前展示值。 |
| `targetOid` | number/null | 实际写入对象 ID。 |
| `setter` | string/null | 实际调用的 setter selector。 |
| `rawValue` | string/null | CLI 收到的原始字符串。 |
| `parsedValue` | any | CLI 按属性类型解析后的值。 |
| `dryRun` | boolean | 是否只预检不提交。 |
| `submitted` | boolean | 是否已经提交给 LookinServer。 |

注意：

- `set --attr` 支持属性 `identifier`，也会尝试匹配部分常见内建属性名。
- `displayValue` 适合人读；自动化脚本应优先读取 `value`，写入时传符合属性类型的字符串。
- `--dry-run` 成功只说明本地匹配和解析成功，不代表真实提交后 App 一定接受该修改。

## 截图和导出字段

`screenshot --json`：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `object.oid` | number | 截图对象 ID。 |
| `object.className` | string/null | 截图对象类名。 |
| `requestedOid` | number | 用户传入的 `--oid`。 |
| `detailOid` | number | 实际请求截图详情的对象 ID。 |
| `type` | string | `group` 或 `solo`。 |
| `path` | string | 输出图片路径。 |
| `format` | string/null | 图片格式。 |
| `bytes` | number | 输出文件字节数。 |

`export --json`：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `path` | string | `.lookin` 文件输出路径。 |
| `bytes` | number | 文件字节数。 |
| `itemCount` | number | 导出的层级节点数量。 |
| `detailCount` | number | 已补全详情的节点数量。 |
| `compression` | number | 图片压缩质量参数。 |

## 离线 read 字段

`read <file.lookin> summary --json`：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `path` | string | `.lookin` 文件绝对路径。 |
| `serverVersion` | number | 文件记录的 LookinServer 协议版本。 |
| `itemCount` | number | 快照内节点数量。 |
| `app` | object | 快照记录的 App 信息。 |

`read <file.lookin> tree/find/inspect/attrs --json` 复用在线命令的字段结构，但数据来自文件快照，不会连接当前 App。

## selectors 和 call 字段

`selectors --json`：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `className` | string/null | 查询的类名，或通过 `--oid` 解析出的对象类名。 |
| `oid` | number/null | 查询对象 ID。 |
| `hasArguments` | boolean | 是否列出带参数 selector。 |
| `filter` | string/null | selector 文本过滤条件。 |
| `selectors` | array | selector 名称数组。 |

`call --json` 和 `eval --json`：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `oid` | number | 调用目标对象 ID。 |
| `selector` | string/null | 调用的 selector 或属性/方法名。 |
| `returnDescription` | string/null | 返回值描述。 |
| `returnObject` | object/null | 返回值如果是 Lookin 可识别对象，会包含 `oid`、`className`、`memoryAddress`、`classChain`、`specialTrace`。 |

`call` 会直接调用 selector；`eval` 是更轻量的属性/无参方法读取入口。

