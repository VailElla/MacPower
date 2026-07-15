# Governor 维护者发布流程

本文件区分两类资产：`UNNOTARIZED` 免费测试包，以及仅在维护者实际配置并完成验证后才可能生成的签名与公证包。v0.1.1 由测试打包脚本生成的资产不是 Developer ID 可信发行包；发布说明不得作出相反表述。

## 免费测试包（UNNOTARIZED）

没有 Apple Developer Program 会员资格时，只能生成明确标记且未经公证的拖动安装 DMG 和备用 ZIP：

```bash
./script/package_test_release.sh
```

当前 Apple Silicon 机器上的示例输出为：

- `release/Governor-v0.1.1-UNNOTARIZED-macOS-arm64.dmg`
- `release/Governor-v0.1.1-UNNOTARIZED-macOS-arm64.dmg.sha256`
- `release/Governor-v0.1.1-UNNOTARIZED-macOS.zip`
- `release/Governor-v0.1.1-UNNOTARIZED-macOS.zip.sha256`

DMG 内含 `Governor.app`、指向 `/Applications` 的快捷方式和安全提示。脚本会确认应用保持 ad-hoc 签名、Gatekeeper 不接受该包、校验和匹配，并挂载 DMG、重新解压 ZIP 验证内容。

从 MacPower 升级时，发布说明和 DMG 内的说明必须要求用户先退出旧应用并移除 `/Applications/MacPower.app`，再安装 `Governor.app`；不得建议两个应用并存或同时运行。Governor 保留旧 bundle ID 和偏好键以延续配置。

若将这些文件上传到 GitHub Release，发布说明必须明确写出：

> These are UNNOTARIZED test assets. They are ad hoc signed, have not been notarized by Apple, and are not Developer ID-trusted releases. macOS will require the user to choose Open Anyway after verifying the download source and SHA-256 checksum.

不得删除文件名中的 `UNNOTARIZED`，也不得把 SHA-256 描述为发布者身份证明。首次运行需要用户在“系统设置 → 隐私与安全性”中手动选择“仍要打开”；这项本机例外不代表 Apple 公证或 Developer ID 信任。

## 可选的签名与公证流程

下面的流程与免费测试包相互独立，不能自动降级到 ad-hoc 签名。它只描述维护者在具备必要资质时如何生成和核验一个独立产物，不能用于描述未走完该流程的 GitHub Release。

### 前置条件

- 有效的 Apple Developer Program 账户，以及与目标团队匹配的 Developer ID Application 证书。
- 本机钥匙串中可用的签名身份；可用 `security find-identity -p codesigning -v` 确认。
- 使用 Apple 推荐方式在钥匙串中创建的 `notarytool` profile。不要把 Apple ID、App 专用密码、API 私钥或证书导出到仓库。
- 已检查 [VERSION](VERSION)、[CHANGELOG.md](CHANGELOG.md) 和待发布的 Git 提交。

### 生成并核验

在干净工作树中运行：

```bash
export GOVERNOR_SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)'
export GOVERNOR_EXPECTED_TEAM_ID='TEAMID'
export GOVERNOR_NOTARY_PROFILE='governor-notary'
./script/package_release.sh
```

脚本会依次以 Release 配置构建、核对 Team ID、拒绝 ad-hoc 签名、提交 Apple 公证、装订票据、运行 `stapler validate` 与 `spctl --assess`，然后创建并重验：

- `release/Governor-v0.1.1-macOS.zip`
- `release/Governor-v0.1.1-macOS.zip.sha256`

输出目录 `release/` 已被 Git 忽略。只有上述命令完整成功并将实际状态写入对应 Release 文案后，才可上传该独立 ZIP 和同名 `.sha256` 文件；不能以脚本存在或文档说明替代实际验证。

## 下载方复核

对于通过完整签名与公证流程生成的独立 ZIP，发布说明应给出实际的十位 Team ID。下载方可运行：

```bash
./script/verify_release.sh \
  release/Governor-v0.1.1-macOS.zip \
  TEAMID \
  release/Governor-v0.1.1-macOS.zip.sha256
```

SHA-256 仅检测传输损坏或意外变更；它不验证发布者身份。`UNNOTARIZED` 测试资产只能按本文件第一节的警告发布。
