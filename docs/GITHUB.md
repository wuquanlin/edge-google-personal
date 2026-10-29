# 上传 GitHub 与发布

建议仓库名：`edge-google-personal`。

可用简介：`个人版 Edge 的 Google 默认搜索守护：本地扩展、Windows 登录任务及实际默认搜索验证。`

## 上传源码

1. 新建你自己的 GitHub 仓库。项目包已经包含 README、MIT LICENSE 和 `.gitignore`，无需在建仓库时再生成同名文件。
2. 解压 `EdgeGooglePersonal-1.0.0-source.zip`，进入 `edge-google-personal` 文件夹。
3. 把这个文件夹**里面的内容**提交到仓库根目录：包括 `README.md`、`LICENSE`、`EdgeGooglePersonal`、`tests`、`docs`、`scripts` 以及点号开头的配置文件。源码 ZIP 本身应作为下载产物，而不是仓库里唯一的源码文件。

也可以在解压后的仓库根目录执行：

```text
git init
git add .
git commit -m "Release Edge Google Personal 1.0.0"
git branch -M main
```

然后使用新建仓库页面提供的 remote 地址执行推送。请使用你自己的仓库 URL；本包没有写入任何人的账户、仓库地址或凭据。

## 创建 1.0.0 Release

标签可用 `v1.0.0`，标题可用 `Edge Google 搜索守护 1.0.0`。将 `RELEASE_NOTES.md` 内容作为发布说明，附上：

- `EdgeGooglePersonal-1.0.0-windows.zip`：普通 Windows 用户下载并解压安装。
- `EdgeGooglePersonal-1.0.0-source.zip`：完整源码、文档、测试和打包脚本。
- `SHA256SUMS.txt`：这两个下载包的校验值。

注意 GitHub 网页创建 Release、上传产物、推送仓库属于你的发布步骤；整理本地分享包不代表已经上传或发布。

## 检查下载文件

Windows PowerShell 可执行：

```powershell
Get-FileHash -Algorithm SHA256 -LiteralPath .\EdgeGooglePersonal-1.0.0-windows.zip
```

与 `SHA256SUMS.txt` 的对应值比较。校验和用于检查文件一致性，本项目没有附加数字签名。

## 后续重新打包

```text
node tests/test-personal-guard.mjs
node tests/test-release.mjs
python3 scripts/build_release.py
```

Windows 上 Python 命令可换成 `py -3 scripts\build_release.py`。Windows PowerShell 5.1 测试也应在对应环境运行，命令见 README。不要从实际安装目录直接全量压缩发布：该目录在使用后会含个人配置、日志和请求。仓库中的 `.gitignore` 及构建白名单用于避免收集这些状态。
