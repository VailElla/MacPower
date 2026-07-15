# MacPower 维护者发布流程

本文同时记录未经公证的免费测试包和受信任的 Developer ID 发行包。受信任流程故意不提供 ad-hoc 签名回退：任何前置条件缺失都会在构建或上传前失败。

## 免费测试包

没有 Apple Developer Program 会员资格时，只能生成明确标记且未经公证的拖动安装 DMG 和备用 ZIP：

~~~bash
./script/package_test_release.sh
~~~

主要输出为 `release/MacPower-v0.1.0-beta.1-UNNOTARIZED-macOS-arm64.dmg` 及同名 `.sha256` 文件；同时保留 ZIP 备用包。DMG 内含应用、指向 `/Applications` 的快捷方式和安全提示。脚本会确认应用保持 ad-hoc 签名、Gatekeeper 不接受该包、校验和匹配，并挂载 DMG、重新解压 ZIP 验证内容。

DMG 和 ZIP 都不是受信任的正式发行包。发布页面必须明确说明它们未经 Apple 公证，首次运行需要用户在“系统设置 → 隐私与安全性”中手动选择“仍要打开”。不得删除文件名中的 `UNNOTARIZED`，也不得把 SHA-256 描述为发布者身份证明。

下面的 Developer ID 流程与免费测试包相互独立，不能自动降级到 ad-hoc 签名。

## 前置条件

- 有效的 Apple Developer Program 账户，以及与目标团队匹配的 Developer ID Application 证书。
- 本机钥匙串中可用的签名身份；可用 `security find-identity -p codesigning -v` 确认。
- 使用 Apple 推荐方式在钥匙串中创建的 `notarytool` profile。不要把 Apple ID、App 专用密码、API 私钥或证书导出到仓库。
- 已检查 [VERSION](VERSION)、[CHANGELOG.md](CHANGELOG.md) 和待发布的 Git 提交。

## 生成并验证发行包

在干净工作树中运行：

~~~bash
export MACPOWER_SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)'
export MACPOWER_EXPECTED_TEAM_ID='TEAMID'
export MACPOWER_NOTARY_PROFILE='macpower-notary'
./script/package_release.sh
~~~

脚本会依次执行：

1. 以 Release 配置构建 .app。
2. 使用 Developer ID、Hardened Runtime 和可信时间戳签名。
3. 核对签名里的 Team ID，拒绝 ad-hoc 签名。
4. 提交 Apple 公证并等待通过。
5. 装订公证票据，进行 `stapler validate` 与 `spctl --assess` 验证。
6. 创建 ZIP 和 SHA-256 传输完整性文件，再从 ZIP 重新验证签名、团队、公证和 Gatekeeper。

输出目录 `release/` 已被 Git 忽略。只有第 6 步全部成功，才可上传 ZIP 与同名 `.sha256` 文件到 GitHub Release。

## 下载方复核

发布说明应给出发布者的十位 Team ID。下载方可运行：

~~~bash
./script/verify_release.sh \
  release/MacPower-v0.1.0-beta.1-macOS.zip \
  TEAMID \
  release/MacPower-v0.1.0-beta.1-macOS.zip.sha256
~~~

SHA-256 仅检测传输损坏或意外变更；Developer ID 签名、指定 Team ID 和 Apple 公证才用于验证发布者与执行信任。

## 当前状态

本仓库在未配置 Developer ID 身份和公证 profile 前仅发布源码，不上传二进制 GitHub Release。
