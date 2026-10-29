# Edge Google 搜索守护（个人版）

让个人版 Microsoft Edge 通过本地扩展将地址栏默认搜索引擎设为 Google，并在每次 Windows 登录后验证实际默认搜索目标。

Personal Microsoft Edge default-search guard: an unpacked extension declares Google as the default search provider; a per-user Windows sign-in task requests a real default-search API check.

**当前版本：1.0.0。** 扩展公钥、扩展 ID、PowerShell 脚本及浏览器运行代码均保留自已完成重启验证的实现。公开版整理了文档、测试和打包工具，没有改写正在使用的守护逻辑。

## 安装

需要 Windows、Windows PowerShell 5.1 和 Microsoft Edge，并且该 Edge 配置文件允许手动加载解压缩扩展。日常安装与运行不需要 Node.js 或 Python。

1. 下载 `EdgeGooglePersonal-1.0.0-windows.zip`，完整解压。
2. 把解压出的 `EdgeGooglePersonal` 文件夹放到你自己的 Documents 中等长期保留、当前用户可写的位置。**先选好位置，再安装；安装后不要移动或删除。** 不要从 ZIP 内直接运行。
3. 在 Edge 中切换到希望使用的配置文件，然后双击 `Install.cmd`。使用普通用户权限运行即可。脚本会选择 Edge 最近使用的配置文件，并输出其目录名；请确认它是你要使用的那个配置文件。
4. 在同一配置文件的 Edge 地址栏手动输入 `edge://extensions/`，打开“开发人员模式”，选择“加载解压缩的扩展”，选中上述文件夹里的 **`Extension`** 子目录。
5. 如 Edge 要求确认更改搜索引擎，确认启用“Google 搜索守护（个人版）”。
6. 打开该扩展的弹窗，等待显示“已验证：默认搜索请求发往 Google”。正常情况下，Edge 运行时约一分钟内处理请求。首次未加载扩展时，安装脚本提示 `not-loaded` 属于正常的安装中间状态。

从 GitHub 源码安装时，运行入口位于仓库的 `EdgeGooglePersonal` 子目录。没有安装迁移需求的现有使用者无需重新安装；不要直接覆盖、移动已经注册的运行目录。

## 日常使用

| 入口 | 用途 |
| --- | --- |
| `Install.cmd` | 注册当前用户登录任务，并选择 Edge 最近使用的配置文件 |
| `Verify.cmd` | 创建新的本地验证请求；最终结果看扩展弹窗 |
| `Check.cmd` | 检查任务与磁盘中的扩展状态，不代表实际搜索已验证 |
| `Uninstall.cmd` | 删除属于该目录安装的登录任务；还需在 Edge 中手动移除扩展 |
| 扩展弹窗“现在实际校验” | 手动进行一次默认搜索检查 |
| 扩展弹窗“导出结果” | 导出扩展保存的最近一次结果 |

绿色 `OK` 表示最近一次实际检查通过；`!` 表示没有通过，详情见弹窗。结果里的 `checkedAt` 和 `requestId` 用来判断时间与请求是否对应。旧的成功记录不能证明新的登录请求已通过。

如果系统阻止后台启动 Edge，请正常打开目标配置文件再等待检查。任务退出码 `0`、日志里的 `Pending` 或 `present-not-live-verified` 都不能单独证明实际搜索成功。

## 工作方式

- 当前用户登录 20 秒后，任务 `Codex-EdgeGooglePersonal` 调用 `Guard.ps1 -Mode Request`，原子更新本地 `Extension/login-request.json`。
- 扩展使用 `chrome_settings_overrides.search_provider` 声明 Google 为默认引擎。
- 收到新请求后，扩展创建自己的后台标签页，调用 `chrome.search.query`，由浏览器当前默认引擎生成导航。
- 只有导航符合 HTTPS、精确域名 `www.google.com`、默认 HTTPS 端口、路径 `/search`、随机测试词完全一致，才通过检查。它没有预先构造 Google 搜索地址来冒充默认引擎证据。
- 检查结束后关闭自建标签页。第一次失败会持久化重试标记并尝试重载自身一次；第二次仍失败就记录失败，不无限重载。
- 每分钟轮询的是本地请求文件；已经完成的同一请求不会重复搜索。

## 验证范围与限制

初始使用环境于 2026-10-29 完成一次真实重启后的登录任务与 Google 搜索目标验证，用户也确认 Edge 设置显示 Google 且由该扩展控制。此次公开打包没有重新执行 Windows 重启或实际浏览器测试，其他机器安装后需要自行验证。

通过只代表默认搜索目标为 Google，**不代表 Google 页面加载成功或网络可达**。尚未完成把真实默认引擎改成 Bing 后的自动恢复回归，也没有证明能对抗其他扩展或程序改写。

其他边界：

- 扩展必须保持启用。脚本不会绕过 Edge 的确认机制强制启用被禁用的扩展。
- 单次安装只针对所选的一个配置文件。当前只有一个固定任务名，不能直接多次安装就宣称支持多个配置文件。
- 不涵盖新标签页网站自身的搜索框；地址栏搜索属于验证范围。
- `Install` 会重新选择 Edge 最近使用的配置文件，不应用于无迁移需求的例行检查。
- 手动校验失败并触发重载后，可能转为处理登录请求，而非续接原手动请求；这是尚未复现的已知候选问题。需要可追踪的新验证时使用 `Verify.cmd`，再核对弹窗结果编号。

完整说明见 [验证记录与维护边界](docs/VERIFICATION.md)。

## 权限与隐私

扩展声明 `search`、`storage`、`alarms` 和 `https://www.google.com/*` 主机权限。没有声明历史记录、Cookie、调试器、脚本注入、扩展管理、全站访问或 Native Messaging 权限。

验证会通过正常浏览器搜索流程发送随机测试词到当前默认搜索提供程序，可能留下浏览器历史记录。扩展不读取真实搜索词。声明中也包含 Google 搜索建议地址；用户日常地址栏交互的数据处理取决于 Edge 及其搜索建议设置。

验证结果保存在扩展的本地存储；`config.json`、登录日志及本地请求保存在安装目录。登录脚本只读所选 Edge 配置文件的 `Secure Preferences` 来识别本扩展的磁盘状态，不修改该受保护文件或企业搜索策略，不保存账户密码。

公开包不包含原使用者的配置、日志、请求文件、浏览器数据库或验证结果。`manifest.json` 中的 `key` 是用于固定 ID 的**公钥**，应保留；包内没有私钥。

## 卸载

1. 从原安装目录运行 `Uninstall.cmd`，删除属于该安装的任务。
2. 在 Edge 扩展管理页面手动移除“Google 搜索守护（个人版）”。

卸载脚本保留文件和日志，便于核对。完成两步后，可以自行删除安装文件夹。

## 开发与打包

以下开发命令适用于完整源码包。JavaScript 测试不依赖第三方 npm 包：

```text
node tests/test-personal-guard.mjs
node tests/test-release.mjs
```

在 Windows PowerShell 5.1 中运行文件处理与状态识别测试：

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-PersonalGuard.ps1
```

测试使用模拟 API 和临时文件，不注册登录任务、不启动 Edge、不重新生成公钥或扩展 ID。它们不能代替真实浏览器验证。

用 Python 3 标准库构建两个 ZIP 和 SHA-256 清单：

```text
python3 scripts/build_release.py
```

Windows 上也可以运行 `py -3 scripts\build_release.py`。产物位于 `dist`，打包脚本采用文件白名单，不收集本机运行状态。发布步骤见 [GitHub 发布指南](docs/GITHUB.md)。

## 许可证

[MIT](LICENSE)。本项目不是 Microsoft 或 Google 的官方产品。
