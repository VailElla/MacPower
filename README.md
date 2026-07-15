<p align="center">
  <img src="Resources/GovernorIcon-RBY-Ring.png" width="128" height="128" alt="Governor 图标">
</p>

<h1 align="center">Governor</h1>

<p align="center">
  根据用户空闲时间与最近 15 秒平均 CPU 使用率，自动切换 macOS 电源模式的菜单栏工具。
</p>

<p align="center"><strong>v0.1.1 · Language preference and rebrand · build 2</strong></p>

> [!IMPORTANT]
> 由 `script/package_test_release.sh` 生成的 v0.1.1 发布资产是明确标记为 `UNNOTARIZED` 的测试包。它们使用 ad-hoc 签名、未经 Apple 公证，不是 Developer ID 签名或受信任发行包，macOS 首次直接打开时会被 Gatekeeper 阻止。不得将这些测试资产描述为受信任的 GitHub Release。

## 功能

- 在 Low Power、Automatic 与 High Power 之间自动选择可用模式。
- 以最近 15 秒平均 CPU 使用率作为负载依据，不使用瞬时值。
- 用户长时间无操作且负载不高时进入 Low Power；恢复操作后立即重新评估。
- High Power 不可用时自动回退到 Automatic，不按机型名称猜测能力。
- 可选择在进入 Low Power 前保存内建屏幕亮度，退出后按设定等待时间恢复。
- 活跃和空闲状态使用独立检测间隔，默认单位均为秒；活跃时可选毫秒、秒或分钟，空闲时可选毫秒或秒。
- 设置窗口可选择 `English` 或 `中文`。首次启动默认英文；检测到系统首选语言为中文时，首次默认中文。用户手动选择后会保存，不会因之后的系统语言变化而被覆盖。
- 可在设置窗口一键恢复规则与选项的默认值，且不改变当前自动化开关状态。
- 检测到用户在系统设置或其他软件中手动更改模式时，可按设置选择是否暂停自动控制。
- 关闭自动化或正常退出时，在安全条件满足后恢复接管前模式。

## 首版规则

| 场景 | 结果 |
|---|---|
| CPU 大于 60% | High Power；当前环境不支持时使用 Automatic |
| CPU 不高于 60%，达到设定空闲时间 | Low Power |
| CPU 不高于 60%，用户仍在操作 | Automatic |
| 用户手动修改系统模式 | 默认继续自动化；开启“手动切换后暂停自动化”时暂停并等待用户点击“恢复自动” |
| 权限、读取或切换失败 | 停止继续写入并在菜单栏显示原因 |

默认连续无操作时间为 5 分钟。活跃时默认每 5 秒检测，空闲时默认每 1 秒检测；检测间隔范围为 100 毫秒至 3600 秒。亮度恢复默认开启、等待时间默认 0 毫秒，可输入 0–1000 毫秒。

## 系统要求

- macOS 13 或更高版本
- 支持系统 `pmset` 电源模式接口的 Mac（High Power 是否可用由系统实时检测）
- Swift 6.2 或更高版本（从源码构建时）
- 开启自动化时，需要管理员权限读取和更改系统电源模式

## 从源码构建

Governor 是 Swift Package Manager 管理的 SwiftUI 菜单栏应用。运行统一脚本会停止旧进程、构建、生成 `dist/Governor.app`、应用 ad-hoc 开发签名并启动；该本地应用包不适合上传或分发：

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

为保证旧版本用户的偏好与应用容器能随升级保留，生成包的 bundle ID 继续使用 `com.ella.MacPower`；所有可见应用名、二进制名和发布资产名称均为 Governor。

从 MacPower 升级时，先退出旧应用并将 `/Applications/MacPower.app` 移到废纸篓，再安装 `Governor.app`；不要让两个应用同时保留或运行。Governor 会继续读取原有偏好。

## 测试

```bash
./script/run_tests.sh
```

测试覆盖决策边界、15 秒 CPU 窗口、手动修改后的可选暂停、失败停止、模式与亮度恢复、并发切换保护，以及语言初始值和持久化行为。系统依赖在测试中由 test doubles 替代，不会更改当前 Mac 的真实电源模式或屏幕亮度；发行脚本测试会验证缺少签名或公证配置时不会开始构建或生成归档。

## 免费测试包（UNNOTARIZED）

没有 Apple Developer Program 会员资格时，可生成明确标记为 `UNNOTARIZED` 的拖动安装 DMG 和备用 ZIP：

```bash
./script/package_test_release.sh
```

脚本以 Release 配置构建并应用 ad-hoc 签名，确认 Gatekeeper 不会误把它当作受信任发行版；DMG 内含 `Governor.app`、指向 `/Applications` 的拖动安装快捷方式和安全提示。当前 Apple Silicon 机器上的示例输出为：

- `release/Governor-v0.1.1-UNNOTARIZED-macOS-arm64.dmg`
- `release/Governor-v0.1.1-UNNOTARIZED-macOS-arm64.dmg.sha256`
- `release/Governor-v0.1.1-UNNOTARIZED-macOS.zip`
- `release/Governor-v0.1.1-UNNOTARIZED-macOS.zip.sha256`

下载方应先核对 SHA-256，再打开 DMG，把 `Governor.app` 拖到 `Applications`。首次打开会被 macOS 阻止；只有确认下载来源和校验值可信时，才可在“系统设置 → 隐私与安全性”中选择“仍要打开”。这项手动放行只是在当前 Mac 上增加例外，不能替代 Developer ID 签名或 Apple 公证。

把 DMG、ZIP 和对应的 `.sha256` 文件放在同一目录后运行：

```bash
cd release
shasum -a 256 -c Governor-v0.1.1-UNNOTARIZED-macOS-arm64.dmg.sha256
shasum -a 256 -c Governor-v0.1.1-UNNOTARIZED-macOS.zip.sha256
```

SHA-256 只用于发现传输损坏或文件变化，不能证明发布者身份。`UNNOTARIZED` 测试包不得被描述为“已签名”“已公证”“Developer ID 可信”或“受 Gatekeeper 信任”的正式发行版。

## 可选的维护者签名与公证流程

`script/package_release.sh` 仅供已配置 Developer ID 身份和 Apple 公证 profile 的维护者使用；它不是对 v0.1.1 GitHub Release 资产的信任声明。只有脚本实际完整通过，并在对应发布说明中如实记录签名与公证状态时，才可陈述该独立产物的验证事实。

```bash
export GOVERNOR_SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)'
export GOVERNOR_EXPECTED_TEAM_ID='TEAMID'
export GOVERNOR_NOTARY_PROFILE='governor-notary'
./script/package_release.sh
```

该可选流程会构建、核对 Team ID、提交公证、装订票据并运行 Gatekeeper 评估，随后生成：

- `release/Governor-v0.1.1-macOS.zip`
- `release/Governor-v0.1.1-macOS.zip.sha256`

SHA-256 文件只用于传输完整性检查，不能证明发布者身份。详细的维护者流程见 [RELEASING.md](RELEASING.md)。

## 权限与安全边界

Governor 只调用固定路径 `/usr/bin/pmset`，参数由内部枚举生成，不经过 shell。只有用户明确开启自动化后，软件才会请求一次会话级管理员授权。

启用亮度恢复时，该功能仅作用于系统内建屏幕，并在本机进程内动态解析 macOS 的 `DisplayServices` 亮度接口；它不需要管理员权限。该接口不可用或显示器不支持时会安全跳过，不影响电源模式切换。

当前测试版通过动态解析 Apple 已弃用的 `AuthorizationExecuteWithPrivileges` API 完成本地提权。它适合本地验证，但不是正式分发的最终架构；稳定分发前仍应改为通过 `SMAppService` 注册的特权 helper 或 daemon。

## 已知限制

- 仅支持 macOS 13 及以上版本。
- 从源码构建的 `dist/Governor.app`、免费测试 DMG 和 ZIP 都是 ad-hoc 包，未经 Apple 公证，需要用户手动允许首次打开。
- High Power 只在系统实际报告支持时可选。
- 亮度恢复目前只覆盖内建屏幕；外接显示器的 DDC/CI 亮度不在首版范围内。
- 首版没有电池百分比规则、按应用规则、定时计划、通知、学习功能或高级诊断界面。
- 菜单栏应用使用 `.accessory` 激活策略，不显示 Dock 图标或主窗口。

## 项目结构

```text
Sources/Governor/       菜单栏应用、系统服务与界面
Sources/GovernorCore/   可测试的自动化决策与协调逻辑
Tests/                  核心与服务测试
Resources/              应用图标
script/                 构建、测试与发布打包脚本
VERSION                 版本、构建号和发布标签
RELEASING.md            测试包与可选公证流程
```

## 版本

- 当前版本：`0.1.1`（build `2`）
- 发布标签：`v0.1.1`
- 版本名称：**Language preference and rebrand**

## 开源许可

本项目按 [MIT License](LICENSE) 开源。
