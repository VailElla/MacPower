# 更新日志

本项目按 [Semantic Versioning](https://semver.org/) 管理版本；测试版通过 Git 标签后缀标识。

## 0.1.0-beta.1 - 2026-07-15

### 初代测试版

- 根据用户空闲时间和最近 15 秒平均 CPU 使用率自动选择电源模式。
- 支持 Low Power、Automatic，以及系统实际支持时的 High Power。
- 可选择从 Low Power 返回 Automatic 或 High Power 后恢复进入前的内建屏幕亮度，并可设置 0–1000 毫秒等待时间（默认 0 毫秒；未恢复时可适当延长）。
- 活跃与空闲状态可分别设置检测间隔，默认 5 秒和 1 秒且默认单位均为秒；活跃时可选毫秒、秒或分钟，空闲时可选毫秒或秒。
- 设置窗口提供“恢复默认设置”操作，重置规则与选项但保留当前自动化开关状态。
- 可配置检测到用户手动修改后是否暂停自动接管，默认继续自动化；暂停时提供“恢复自动”操作。
- 在安全条件满足时恢复接管前模式。
- 权限、读取或切换失败后停止自动写入，避免持续重试。
- 增加菜单栏内的软件版本与测试版标识。
- 提供 SwiftPM 测试、本地 `.app` 构建、ad-hoc 开发签名验证，以及 fail-closed 的发行打包脚本。
- 增加明确标记为 `UNNOTARIZED` 的免费拖动安装 DMG、备用 ZIP、SHA-256 校验和、挂载与解压后的签名复核。
- 发行打包要求 Developer ID、Hardened Runtime、Apple 公证、装订票据与 Gatekeeper 验证；缺少任一维护者配置时不生成可分发压缩包。

### 已知限制

- 当前公开仓库仅发布源码；尚未发布 Developer ID 签名和 Apple 公证的二进制版本。
- 本地管理员授权桥接使用 Apple 已弃用的 `AuthorizationExecuteWithPrivileges` API；稳定分发前需要迁移到受支持的特权 helper 架构。
