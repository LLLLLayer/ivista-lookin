# LookinCLI 签名与公证

当前公开包使用 Apple Developer ID 签名，Homebrew 可以安装和运行。更正式的公开分发还应提交 notarization。

## 目标状态

1. 使用 `Developer ID Application` 证书签名 `ivista-lookin` 和 bundled frameworks。
2. 使用 hardened runtime。
3. 将 release zip 提交到 Apple notary service。
4. Homebrew formula 指向已公证的 release asset。

## 前置条件

需要 Apple Developer Program 账号和以下凭证之一：

```bash
NOTARYTOOL_PROFILE=<keychain-profile>
```

或：

```bash
APPLE_ID=<apple-id-email>
APPLE_TEAM_ID=<team-id>
APPLE_APP_SPECIFIC_PASSWORD=<app-specific-password>
```

签名机还需要安装 Developer ID Application 证书。可用下面命令确认：

```bash
security find-identity -v -p codesigning
```

## Developer ID 签名打包

```bash
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
Scripts/build-lookin-cli.sh
```

`Scripts/package-lookin-cli.sh` 在检测到 `CODESIGN_IDENTITY` 时会使用 Developer ID 签名并启用 hardened runtime；未设置时继续使用 ad-hoc 签名，适合本地开发和 CI smoke。

Homebrew 安装时会把文件复制到 Cellar。为避免安装后的 Mach-O 签名与 bundled frameworks 出现 library validation 冲突，formula 会在安装阶段对 `ivista-lookin` 和 `Frameworks/*.framework` 做一次一致的 ad-hoc 重签名，并清除 runtime flag。直接下载 release zip 的用户仍使用 Developer ID 签名包。

## 公证

```bash
Scripts/notarize-lookin-cli.sh build/LookinCLI/ivista-lookin-macos-universal.zip
```

如果使用 keychain profile：

```bash
xcrun notarytool store-credentials ivista-lookin-notary \
  --apple-id "$APPLE_ID" \
  --team-id "$APPLE_TEAM_ID" \
  --password "$APPLE_APP_SPECIFIC_PASSWORD"

NOTARYTOOL_PROFILE=ivista-lookin-notary \
Scripts/notarize-lookin-cli.sh build/LookinCLI/ivista-lookin-macos-universal.zip
```

## 关于 stapling

`.zip` 可以提交 notarization，但不能被 staple。Gatekeeper 会在线查询 notarization 结果。若要离线也能验证，应新增 `.dmg` 或 `.pkg` 分发格式并对其执行：

```bash
xcrun stapler staple <artifact.dmg>
```

## 当前结论

`v0.1.4` 已使用 Developer ID 签名发布，但尚未 notarize。拿到 notarytool 凭证后，可以不改源码直接提交 release zip；若要支持 stapling，应新增 `.dmg` 或 `.pkg` 分发格式。
