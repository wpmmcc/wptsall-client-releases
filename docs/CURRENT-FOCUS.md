# 当前范围（2026-08-20 对齐）

## 在做

**WebUI**（`client-wpplugin/`）一条线做到可发、可测：

1. 本机交叉编译 6 平台 kit，minisign 签名（**不要** OS 代码签名证书）
2. OTA：拉 **已签名 kit** → 验签 → 解出 `bin/wptsall-client` → 替换
3. 用户在线安装：`installers/install-webui.sh` / `install-webui.ps1`
4. 公开仓 GitHub Actions：`workflows/pack-and-test.yml`（`type=webui`）打包 + 装脚本冒烟

不购买、不接入 Apple Developer ID / Windows Authenticode。WebUI OTA 只依赖内嵌 minisign 公钥。

## 暂停

- **Tauri Desktop** 交叉编译、官方 updater、desktop pack/install 脚本增强
- OS 证书、公证、SmartScreen
- 每版轮换 minisign 钥、抬高 `min_supported_version` 踢旧用户

相关脚本仍保留在本目录，**不要删**。发版清单先只跑 WebUI：

```bash
source install-client/security/config.env
bash install-client/cross-compile/host-cross-kits-webui.sh
bash install-client/security/scripts/sign-kits-batch.sh "$WPTSALL_VERSION"
bash install-client/tests/webui/run-local-suite.sh
# 上传 kit 并触发公开 runner：
# bash install-client/cross-compile/host-cross-kits-webui.sh --publish --dispatch
```

## 产物与 URL（WebUI）

公开仓：`wpmmcc/wptsall-client-releases`

| 用途 | GitHub tag | 文件 |
|------|------------|------|
| 签名 kit（安装 + OTA） | `kits-webui-v{version}` | `kit-webui-{platform}.tar.gz` + `.minisig` + `RELEASE-SHA256SUMS-webui.txt` |
| runner 二次打包（可选） | `v{version}-webui` | 同内容的用户向 tarball（**不重新签名**；验签仍以 kit 为准） |

`{platform}`：`linux-x86_64` / `linux-aarch64` / `windows-x86_64` / `windows-aarch64` / `darwin-x86_64` / `darwin-aarch64`

详细操作见 [PIPELINE.md](PIPELINE.md)、[docs/WEBUI-OTA-PACK-CI.md](docs/WEBUI-OTA-PACK-CI.md)。
