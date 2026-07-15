<p align="center">
  <img src="Resources/MacPowerIcon-RBY-Ring.png" width="128" height="128" alt="MacPower 图标">
</p>

<h1 align="center">MacPower</h1>

<p align="center">
  根据用户空闲时间与最近 15 秒平均 CPU 使用率，自动切换 macOS 电源模式的菜单栏工具。
</p>

<p align="center"><strong>v0.1.0 · 初代测试版</strong></p>

> [!IMPORTANT]
> 这是预发布测试版本，适合本地测试和代码审阅。项目可以生成明确标记为 `UNNOTARIZED` 的免费测试包，但它使用 ad-hoc 签名、未经 Apple 公证，macOS 会阻止首次直接打开。受信任的发行脚本仍要求 Developer ID 签名、团队 ID 和 Apple 公证配置，缺少任一条件都会拒绝打包。

## 功能

- 在 Low Power、Automatic 与 High Power 之间自动选择可用模式。
- 以最近 15 秒平均 CPU 使用率作为负载依据，不使用瞬时值。
- 用户长时间无操作且负载不高时进入 Low Power。
- 用户恢复操作后立即退出 Low Power，并重新评估负载。
- 可选择在进入 Low Power 前保存内建屏幕亮度，退出后按设定等待时间恢复。
- 活跃和空闲状态使用独立检测间隔，默认单位均为秒；活跃时可选毫秒、秒或分钟，空闲时可选毫秒或秒。
- 可在设置窗口一键恢复所有规则与选项的默认值，且不改变当前自动化开关状态。
- 检测到用户在系统设置或其他软件中手动更改模式时，可按设置选择是否暂停自动控制。
- 关闭自动化或正常退出时，在安全条件满足后恢复接管前模式。
- High Power 不可用时自动回退到 Automatic，不按机型名称猜测能力。

## 首版规则

| 场景 | 结果 |
|---|---|
| CPU 大于 60% | High Power；当前环境不支持时使用 Automatic |
| CPU 不高于 60%，达到设定空闲时间 | Low Power |
| CPU 不高于 60%，用户仍在操作 | Automatic |
| 用户手动修改系统模式 | 默认继续自动化；开启“手动切换后暂停自动化”时暂停并等待用户点击“恢复自动” |
| 权限、读取或切换失败 | 停止继续写入并在菜单栏显示原因 |

默认连续无操作时间为 5 分钟；系统未检测到键盘、鼠标或触控板操作达到该时间后，才会使用空闲时电源模式。活跃时默认每 5 秒检测，空闲时默认每 1 秒检测，默认单位均为秒；活跃时可选毫秒、秒或分钟，空闲时可选毫秒或秒。检测间隔范围为 100 毫秒至 3600 秒。亮度恢复默认开启、等待时间默认 0 毫秒，可输入 0–1000 毫秒；如果没有恢复，可以延长等待时间。“自动退出 High Power”和“手动切换后暂停自动化”默认关闭。自动化首次启动时保持关闭，只有用户明确开启后才会请求管理员授权。

检测间隔低于 1 秒会增加 CPU 唤醒与能耗：当前实现每轮检测都会读取用户活动状态并刷新系统电源模式。除非确实需要亚秒级响应，否则建议保留空闲时 1 秒、活跃时 5 秒的默认值。

## 系统要求

- macOS 13 或更高版本
- 支持系统 `pmset` 电源模式接口的 Mac（High Power 是否可用由系统实时检测）
- Swift 6.2 或更高版本（从源码构建时）
- 开启自动化时，需要管理员权限读取和更改系统电源模式

## 从源码构建

MacPower 是 Swift Package Manager 管理的 SwiftUI 菜单栏应用。运行下面的统一脚本会停止旧进程、构建、生成 `dist/MacPower.app`、应用 ad-hoc 开发签名并启动。该本地应用包不适合上传或分发：

```bash
./script/build_and_run.sh
```

只构建并验证本地开发应用包：

```bash
./script/build_and_run.sh --bundle-only
```

构建后启动并确认进程与签名：

```bash
./script/build_and_run.sh --verify
```

调试与日志模式：

```bash
./script/build_and_run.sh --debug
./script/build_and_run.sh --logs
./script/build_and_run.sh --telemetry
```

## 测试

```bash
./script/run_tests.sh
```

测试覆盖决策边界、15 秒 CPU 窗口、手动修改后的可选暂停、失败停止、模式与亮度恢复和并发切换保护。系统依赖在测试中由 test doubles 替代，不会更改当前 Mac 的真实电源模式或屏幕亮度；同时会验证发行脚本在缺少签名或公证配置时不会开始构建或生成归档。

## 免费测试包（未经 Apple 公证）

没有 Apple Developer Program 会员资格时，可以生成明确标记为 `UNNOTARIZED` 的拖动安装 DMG 和备用 ZIP：

```bash
./script/package_test_release.sh
```

脚本会以 Release 配置构建并应用 ad-hoc 签名，确认 Gatekeeper 不会误把它当作受信任发行版；DMG 内含 `MacPower.app`、指向 `/Applications` 的拖动安装快捷方式和安全提示。脚本还会挂载 DMG 并复核其中的应用与快捷方式：

- `release/MacPower-v0.1.0-beta.1-UNNOTARIZED-macOS-arm64.dmg`
- `release/MacPower-v0.1.0-beta.1-UNNOTARIZED-macOS-arm64.dmg.sha256`
- `release/MacPower-v0.1.0-beta.1-UNNOTARIZED-macOS.zip`
- `release/MacPower-v0.1.0-beta.1-UNNOTARIZED-macOS.zip.sha256`

当前脚本在本机生成 Apple Silicon `arm64` 产物。下载方应先核对 SHA-256，再打开 DMG，把 `MacPower.app` 拖到 `Applications`。首次打开会被 macOS 阻止；只有确认下载来源和校验值可信时，才可在“系统设置 → 隐私与安全性”中选择“仍要打开”。这项手动放行只是在当前 Mac 上增加例外，不能替代 Developer ID 签名或 Apple 公证。

把 DMG、ZIP 和对应的 `.sha256` 文件放在同一目录后运行：

```bash
cd release
shasum -a 256 -c MacPower-v0.1.0-beta.1-UNNOTARIZED-macOS-arm64.dmg.sha256
shasum -a 256 -c MacPower-v0.1.0-beta.1-UNNOTARIZED-macOS.zip.sha256
```

SHA-256 只用于发现传输损坏或文件变化，不能证明发布者身份。不要将该测试包描述为“已签名”“已公证”或“受 Gatekeeper 信任”的正式发行版。

## 受信任的发行包（仅维护者）

`script/package_release.sh` 只允许生成可验证的 Developer ID 签名和 Apple 公证产物。签名前，将下列值从维护者本机的钥匙串和 Apple Developer 账户配置到环境中；不要把证书、Apple ID 密码、App 专用密码或 API 密钥写入仓库：

~~~bash
export MACPOWER_SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)'
export MACPOWER_EXPECTED_TEAM_ID='TEAMID'
export MACPOWER_NOTARY_PROFILE='macpower-notary'
./script/package_release.sh
~~~

脚本会以 Release 配置构建，校验签名团队、提交公证、装订票据并通过 Gatekeeper 评估，最后生成：

- `release/MacPower-v0.1.0-beta.1-macOS.zip`
- `release/MacPower-v0.1.0-beta.1-macOS.zip.sha256`

SHA-256 文件只用于传输完整性检查，不能证明发布者身份。下载方应同时运行 `script/verify_release.sh ARCHIVE TEAM_ID SHA256_FILE`，它会校验校验和、代码签名、Developer Team ID、装订的公证票据和 Gatekeeper。详细的维护者流程见 [RELEASING.md](RELEASING.md)。

当前 GitHub 仓库尚未发布受信任的二进制 GitHub Release；只有上述流程完整通过后，才可把不含 `UNNOTARIZED` 标记的 ZIP 描述为正式发行包。免费测试 DMG 和 ZIP 必须始终保留 `UNNOTARIZED` 标记及对应警告。

## 权限与安全边界

MacPower 只调用固定路径 `/usr/bin/pmset`，参数由内部枚举生成，不经过 shell。只有用户明确开启自动化后，软件才会请求一次会话级管理员授权。

启用亮度恢复时，该功能仅作用于系统内建屏幕，并在本机进程内动态解析 macOS 的 `DisplayServices` 亮度接口；它不需要管理员权限。该接口不可用或显示器不支持时会安全跳过，不影响电源模式切换。由于它不是公开 SDK 接口，正式分发前需要在目标 macOS 版本上持续做兼容性验证。

当前测试版通过动态解析 Apple 已弃用的 `AuthorizationExecuteWithPrivileges` API 完成本地提权。它适合本地验证，但不是正式分发的最终架构。发行脚本已强制要求 Developer ID 签名、Hardened Runtime、时间戳、Apple 公证、装订与 Gatekeeper 验证；进入稳定版前，仍应改为通过 `SMAppService` 注册的特权 helper 或 daemon。

## 已知限制

- 仅支持 macOS 13 及以上版本。
- 从源码构建的 `dist/MacPower.app`、免费测试 DMG 和 ZIP 都是 ad-hoc 包，未经 Apple 公证，需要用户手动允许首次打开。
- 在配置 Developer ID 身份和 Apple 公证钥匙串 profile 前，不会发布受 Gatekeeper 信任的二进制 GitHub Release。
- High Power 只在系统实际报告支持时可选。
- 亮度恢复目前只覆盖内建屏幕；外接显示器的 DDC/CI 亮度不在首版范围内。
- 首版没有电池百分比规则、按应用规则、定时计划、通知、学习功能或高级诊断界面。
- 菜单栏应用使用 `.accessory` 激活策略，不显示 Dock 图标或主窗口。

## 项目结构

```text
Sources/MacPower/       菜单栏应用、系统服务与界面
Sources/MacPowerCore/   可测试的自动化决策与协调逻辑
Tests/                  核心与服务测试
Resources/              应用图标
script/                 构建、测试与发布打包脚本
VERSION                 版本与预发布标签
RELEASING.md            经签名和公证的维护者发布流程
```

## 版本

- 当前版本：`0.1.0`（build `1`）
- 发布标签：`v0.1.0-beta.1`
- 版本名称：**初代测试版**

## 开源许可

本项目按 [MIT License](LICENSE) 开源。
