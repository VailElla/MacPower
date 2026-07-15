# Governor 维护者发布流程

本文件区分两类资产：`UNNOTARIZED` 免费测试包，以及可登记 v0.2.0 `SMAppService` root Helper 的 Developer ID 签名和公证包。应用可以免费分发；但 Apple 明确要求含 LaunchDaemon 的 app 经过公证，故两类资产的功能边界不同。

## 免费测试包（UNNOTARIZED）

没有 Apple Developer Program 会员资格时，只能生成明确标记且未经公证的拖动安装 DMG 和备用 ZIP：

```bash
./script/package_test_release.sh
```

当前 Apple Silicon 机器上的示例输出为：

- `release/Governor-v0.2.0-UNNOTARIZED-macOS-arm64.dmg`
- `release/Governor-v0.2.0-UNNOTARIZED-macOS-arm64.dmg.sha256`
- `release/Governor-v0.2.0-UNNOTARIZED-macOS.zip`
- `release/Governor-v0.2.0-UNNOTARIZED-macOS.zip.sha256`

DMG 内含 `Governor.app`、指向 `/Applications` 的快捷方式和安全提示。脚本会确认应用保持 ad-hoc 签名、Gatekeeper 不接受该包、Helper 与 `BundleProgram` 布局完整、校验和匹配，并挂载 DMG、重新解压 ZIP 验证内容。

这些资产不能登记 `SMAppService` LaunchDaemon，因此无法提供 v0.2.0 的持久 root Helper 或“首次批准后不再输密码”能力。不要把它们作为该功能的可用预发行版发布；它们只能验证免费资产的打包、校验与拖动安装路径。

从 MacPower 升级时，发布说明和 DMG 内的说明必须要求用户先退出旧应用并移除 `/Applications/MacPower.app`，再安装 `Governor.app`；不得建议两个应用并存或同时运行。Governor 保留旧 bundle ID 和偏好键以延续配置。

若将这些文件上传到 GitHub Release，发布说明必须明确写出：

> These are UNNOTARIZED test assets. They are ad hoc signed, have not been notarized by Apple, and are not Developer ID-trusted releases. They cannot register Governor's SMAppService privileged helper. macOS will require the user to choose Open Anyway after verifying the download source and SHA-256 checksum.

不得删除文件名中的 `UNNOTARIZED`，也不得把 SHA-256 描述为发布者身份证明。首次运行需要用户在“系统设置 → 隐私与安全性”中手动选择“仍要打开”；这项本机例外不代表 Apple 公证或 Developer ID 信任。

## 持久 Helper 的必需签名与公证流程

下面的流程与免费测试包相互独立，不能自动降级到 ad-hoc 签名。它是 v0.2.0 持久 Helper 的必要条件：完成后，用户首次从 `/Applications/Governor.app` 启用自动化时在“登录项”批准 daemon 一次，之后锁屏解锁、退出重开应用以及再次启用都不会再出现管理员密码请求。

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

- `release/Governor-v0.2.0-macOS.zip`
- `release/Governor-v0.2.0-macOS.zip.sha256`

输出目录 `release/` 已被 Git 忽略。只有上述命令完整成功并将实际状态写入对应 Release 文案后，才可上传该独立 ZIP 和同名 `.sha256` 文件；不能以脚本存在或文档说明替代实际验证。

## 下载方复核

对于通过完整签名与公证流程生成的独立 ZIP，发布说明应给出实际的十位 Team ID。下载方可运行：

```bash
./script/verify_release.sh \
  release/Governor-v0.2.0-macOS.zip \
  TEAMID \
  release/Governor-v0.2.0-macOS.zip.sha256
```

SHA-256 仅检测传输损坏或意外变更；它不验证发布者身份。`UNNOTARIZED` 测试资产只能按本文件第一节的警告发布。

## v0.2.0 物理场景测试边界

发布说明必须如实注明：本次验证没有使测试 Mac 睡眠、重启、关机、注销或断网。锁屏解锁、应用退出重开和重启后的 daemon 持久性均由 `SMAppService` 状态机、XPC 代码签名要求和模拟测试覆盖；在拥有公证版并获用户单独批准后，维护者可再进行非破坏性的人工回归，不能把模拟验证写成实机电源生命周期测试。
