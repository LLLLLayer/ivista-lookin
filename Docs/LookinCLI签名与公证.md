# LookinCLI 签名与公证

当前公开包默认使用 ad-hoc 签名，Homebrew 可以安装和运行。更正式的公开分发应使用 Apple Developer ID 签名并提交 notarization。

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

`Scripts/package-lookin-cli.sh` 在检测到 `CODESIGN_IDENTITY` 时会使用 Developer ID 签名；未设置时继续使用 ad-hoc 签名，适合本地开发和 CI smoke。

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

`v0.1.4` 仍可以先按 ad-hoc 签名发布；Developer ID 签名和 notarization 的脚本、文档路径已经准备好。拿到 Apple Developer 凭证后，可以不改源码直接切换到正式签名发布流程。

