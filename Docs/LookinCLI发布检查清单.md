# LookinCLI 发布检查清单

本文档用于每次发布 LookinCLI zip 前做最后验收。目标是确认产物可以脱离 Lookin.app 单独运行，并且基础命令、打包布局、动态库路径和真机链路都符合预期。

## 1. 构建环境

确认当前分支和工作区：

```bash
git branch --show-current
git status --short
```

发布前工作区应当干净，或者只包含明确要随本次发布提交的变更。

确认依赖已安装：

```bash
pod install
```

## 2. Release 构建和打包

运行：

```bash
./Scripts/build-lookin-cli.sh
```

期望产物：

```text
build/LookinCLI/lookin-cli-macos-universal/
build/LookinCLI/lookin-cli-macos-universal.zip
```

默认产物是 universal binary。如果只构建单架构，package 名称会根据 `lipo -archs` 自动变成对应架构。

## 3. Zip 内容

检查 zip 清单：

```bash
zipinfo -1 build/LookinCLI/lookin-cli-macos-universal.zip | head -80
```

必须包含：

```text
lookin-cli-macos-universal/lookin
lookin-cli-macos-universal/Frameworks/LookinShared.framework/
lookin-cli-macos-universal/Frameworks/ReactiveObjC.framework/
lookin-cli-macos-universal/LICENSE
lookin-cli-macos-universal/README.md
lookin-cli-macos-universal/install.sh
```

不应包含：

```text
__MACOSX/
DerivedData/
Lookin.app
```

## 4. 二进制和动态库路径

确认架构：

```bash
lipo -archs build/LookinCLI/lookin-cli-macos-universal/lookin
```

universal 产物应输出：

```text
x86_64 arm64
```

确认 rpath：

```bash
otool -l build/LookinCLI/lookin-cli-macos-universal/lookin | rg -A2 LC_RPATH
```

必须包含：

```text
@executable_path/Frameworks
```

确认没有开发机临时路径：

```bash
otool -L build/LookinCLI/lookin-cli-macos-universal/lookin | rg 'DerivedData|Lookin.app|/Applications' || true
```

期望无输出。

## 5. 签名验证

MVP 内部验证使用 ad-hoc signing：

```bash
codesign --verify --deep --strict build/LookinCLI/lookin-cli-macos-universal/lookin
```

正式公开发布时，应改用 Developer ID 签名并 notarize。

## 6. 解压即运行

验证 zip 解压后的二进制可以直接运行：

```bash
TMP_ZIP="$(mktemp -d)"
unzip -q build/LookinCLI/lookin-cli-macos-universal.zip -d "$TMP_ZIP"
"$TMP_ZIP/lookin-cli-macos-universal/lookin" --version
rm -rf "$TMP_ZIP"
```

期望能输出 LookinCLI 版本、协议版本和当前架构。

## 7. 临时安装验证

不要直接写入本机 `/usr/local`。先用临时目录模拟安装：

```bash
TMP_INSTALL="$(mktemp -d)"
INSTALL_PREFIX="$TMP_INSTALL/prefix" BIN_DIR="$TMP_INSTALL/bin" SUDO= \
  build/LookinCLI/lookin-cli-macos-universal/install.sh \
  build/LookinCLI/lookin-cli-macos-universal
"$TMP_INSTALL/bin/lookin" --version
rm -rf "$TMP_INSTALL"
```

期望安装脚本成功创建 symlink，并且安装后的 `lookin` 可运行。

## 8. 本地 Smoke Test

使用 package 内的二进制跑本地 smoke：

```bash
SKIP_DEVICE_TESTS=1 \
./Scripts/smoke-lookin-cli.sh build/LookinCLI/lookin-cli-macos-universal
```

覆盖：

1. `lookin --version`
2. `lookin --help`
3. `lookin tree --help`
4. `lookin find --help`
5. `lookin set --help`
6. `lookin doctor`

## 9. App 连接 Smoke Test

如果当前有可连接 App，运行：

```bash
./Scripts/smoke-lookin-cli.sh build/LookinCLI/lookin-cli-macos-universal
```

如果要强制指定真机 App：

```bash
BUNDLE_ID=com.example.demo \
TRANSPORT=usb \
QUERY=UILabel \
REQUIRE_APP=1 \
./Scripts/smoke-lookin-cli.sh build/LookinCLI/lookin-cli-macos-universal
```

如果指定 `OID`，还会额外验证 `tree --oid`、`inspect --json` 和 `attrs --json`。如果同时指定 `SET_ATTR` 和 `SET_VALUE`，还会额外验证 `set --dry-run --json`：

```bash
BUNDLE_ID=com.example.demo \
TRANSPORT=usb \
OID=130 \
SET_ATTR=l_f_f \
SET_VALUE='0,0,120,44' \
REQUIRE_APP=1 \
./Scripts/smoke-lookin-cli.sh build/LookinCLI/lookin-cli-macos-universal
```

## 10. Release Zip 验收

发布前用 zip 做一次从零解压验收：

```bash
./Scripts/verify-lookin-cli-release.sh build/LookinCLI/lookin-cli-macos-universal.zip
```

该脚本会：

1. 输出 `shasum -a 256`。
2. 解压 zip 到临时目录。
3. 检查 `lookin`、`Frameworks/LookinShared.framework`、`Frameworks/ReactiveObjC.framework`、`install.sh` 和 `README.md`。
4. 检查 `@executable_path/Frameworks` rpath。
5. 执行 `codesign --verify --deep`。
6. 使用解压出的二进制运行 `smoke-lookin-cli.sh`。

如果要强制连真机 App：

```bash
BUNDLE_ID=com.example.demo \
TRANSPORT=usb \
REQUIRE_APP=1 \
./Scripts/verify-lookin-cli-release.sh build/LookinCLI/lookin-cli-macos-universal.zip
```

## 11. 手动抽查

建议至少抽查以下命令：

```bash
build/LookinCLI/lookin-cli-macos-universal/lookin apps --json
build/LookinCLI/lookin-cli-macos-universal/lookin tree --bundle-id com.example.demo --depth 1 --json
build/LookinCLI/lookin-cli-macos-universal/lookin find --bundle-id com.example.demo UILabel --limit 5 --json
```

JSON 输出应能被解析：

```bash
build/LookinCLI/lookin-cli-macos-universal/lookin apps --json | jq .
```

## 12. 发布前记录

发布说明中建议记录：

1. Git commit hash。
2. zip 文件名。
3. `shasum -a 256`。
4. 是否使用 ad-hoc signing 或 Developer ID signing。
5. 是否完成 notarization。
6. smoke test 使用的目标 App、transport 和系统版本。

生成 checksum：

```bash
shasum -a 256 build/LookinCLI/lookin-cli-macos-universal.zip
```

## 13. Homebrew Formula

本仓库维护 `Formula/ivista-lookin.rb`，可复制到 `homebrew-lookin` tap 仓库的 `Formula/ivista-lookin.rb`。

更新 formula 的 URL、version 和 sha256：

```bash
./Scripts/update-homebrew-formula.sh \
  v0.1.0 \
  https://github.com/LLLLLayer/ivista-lookin/releases/download/v0.1.0/lookin-cli-macos-universal.zip \
  build/LookinCLI/lookin-cli-macos-universal.zip
```

语法检查：

```bash
ruby -c Formula/ivista-lookin.rb
```

发布到 tap 后，用户安装命令：

```bash
brew install LLLLLayer/lookin/ivista-lookin
lookin --version
```

本地调试 formula 时，可先创建临时 tap，再把 formula 放入 tap 中执行安装和测试。Homebrew 5.1 起不再接受从任意 path 直接安装 formula：

```bash
brew tap-new LLLLLayer/lookin
cp Formula/ivista-lookin.rb "$(brew --repository LLLLLayer/lookin)/Formula/ivista-lookin.rb"
brew install LLLLLayer/lookin/ivista-lookin
brew test LLLLLayer/lookin/ivista-lookin
brew uninstall ivista-lookin
brew untap LLLLLayer/lookin
```

## 14. 当前 MVP 边界

1. CLI 不要求安装 Lookin.app。
2. 目标 iOS App 仍必须集成兼容 LookinServer。
3. 第一版公开 zip 仍是 ad-hoc signing，正式发布前应补 Developer ID signing 和 notarization。
4. 新增 Server 协议前必须考虑旧 LookinServer 兼容性。
