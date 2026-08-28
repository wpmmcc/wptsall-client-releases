# WebUI / Desktop：OTA、交叉编译、GitHub 打包与在线安装

当前范围见 [CURRENT-FOCUS.md](../CURRENT-FOCUS.md)。Desktop 与 WebUI 均走“本机编译签名 kit、公开 runner 只验签/打包/安装测试”的边界；OS 证书（Apple Developer ID / Windows Authenticode）仍不作为当前门禁。

## 信任边界

```
本机（受信）                              公开仓 wpmmcc/wptsall-client-releases
─────────────────────────────            ─────────────────────────────────
cargo 交叉编译 kit-webui-*.tar.gz        只下载【已签名】kit
minisign 私钥签名 kit + SUMS             pack-kit-to-release.sh 再打一份用户 tar
私钥不离开本机                           用 install-webui.sh 对 **kit + .minisig** 做安装测试
```

Runner **不编 Rust、不碰私钥**。用户验签对象永远是本机签过的 `kit-webui-{platform}.tar.gz`，不是 runner 重打包后的 tar（哈希会变）。

没有 Apple / Microsoft 证书也能：

- 在线安装（minisign）
- OTA（同一把公钥，编进二进制）

证书只影响「系统认不认这个程序」，不影响这条更新链。

## 文件名与 URL

| 项 | 值 |
|----|-----|
| 公开仓 | `wpmmcc/wptsall-client-releases` |
| kit tag | `kits-webui-v{version}` |
| kit | `kit-webui-{platform}.tar.gz` |
| 签名 | 同名 `.minisig` |
| 汇总 | `RELEASE-SHA256SUMS-webui.txt` + `.minisig` |
| `{platform}` | `linux-x86_64` `linux-aarch64` `windows-x86_64` `windows-aarch64` `darwin-x86_64` `darwin-aarch64` |

manifest（给客户端 `/api/v1/client/releases` 用）模板：

```
download_url_template:  .../kits-webui-v{version}/kit-webui-{platform}.tar.gz
signature_url_template: .../kits-webui-v{version}/RELEASE-SHA256SUMS-webui.txt.minisig
```

客户端把 `{version}`、`{platform}`（以及旧字段 `{target}` = cargo triple）替换掉。OTA **先验 kit 的 minisign，再解出 `bin/wptsall-client` 替换进程**，不会把 tar.gz 当成可执行文件。

## 本机交叉编译

```bash
source install-client/security/config.env
export WPTSALL_RELEASE_SALT="$(date -u +%Y%m%dT%H%M%SZ)-$(openssl rand -hex 8)"
bash install-client/cross-compile/host-cross-kits-webui.sh
bash install-client/security/scripts/sign-kits-batch.sh "$WPTSALL_VERSION"
```

单平台：`make-kit-webui.sh` + `WPTSALL_FORCE_OS` / `WPTSALL_FORCE_ARCH` / `WPTSALL_CARGO_TARGET`。

每版多样性：`WPTSALL_RELEASE_DIVERSIFY=1`（默认）写入 `.wptsall_relid`。当前磁盘上的 2.1.0 kit 若是钩子启用前打的，**下次重编**才会带 relid；功能不依赖重打。

## 用户在线安装

Linux / macOS（需本机有 `minisign`）：

```bash
curl -fsSL https://raw.githubusercontent.com/wpmmcc/wptsall-client-releases/main/install.sh \
  | sh -s -- --version 2.1.0
```

Windows：`install.ps1` / `installers/install-webui.ps1`。

脚本拉的是 `kits-webui-v*` 上的 **signed kit**，验签失败则拒绝安装。调试才允许 `--allow-unsigned`。

本地/CI 可用目录当「Release」：

```bash
WPTSALL_DOWNLOAD_BASE=http://127.0.0.1:8765 \
  bash install-client/installers/install-webui.sh --version 2.1.0 --prefix /tmp/w --no-service
```

## GitHub runner

1. 把脚本同步到公开仓：

```bash
bash install-client/packaging/webui/sync-public-repo.sh /path/to/wptsall-client-releases
# git commit && git push
```

2. 上传 kit 并触发工作流：

```bash
bash install-client/cross-compile/host-cross-kits-webui.sh --publish --dispatch
# 或已有 kit：
bash install-client/packaging/webui/publish-kit.sh --version 2.1.0 --dispatch
```

`pack-and-test.yml` 默认 `type=webui`：矩阵 6 平台下载 kit、验 minisign、再打包；随后用 `install-webui.sh`/`install-webui.ps1` 对 **本地 HTTP 上的 signed kit** 做安装冒烟（不依赖 `publish`）。

Desktop 可 dispatch `type=desktop`：矩阵 6 平台下载/验签/打包；Windows `install-test-desktop-ps1` 会在 `windows-latest` 与 `windows-11-arm` 上运行 signed install，并篡改 kit 验证必须拒绝。当前 green evidence：`wpmmcc/wptsall-client-releases` run `33195890726`。

## 本机全面测试

```bash
source install-client/security/config.env
bash install-client/tests/webui/run-local-suite.sh
```

覆盖：全部 webui kit 验签、目录结构/源码泄漏、pack、`install-webui.sh`、mock OTA（`99.0.0` 拉当前 kit）、HARDENING/OBFUSCATION 元数据。

Rust 解包/URL：

```bash
cd libs/client-runtime-core && cargo test --lib updater
```

## OTA 行为（WebUI）

1. `GET /api/update-check` → 服务端 `GET {WPTSALL_SERVER_BASE}/api/v1/client/releases`
2. `POST /api/perform-update` → 下载 kit → `{url}.minisig` 验签 → 可选 SUMS → `tar` 解出二进制 → `perform_self_replace`
3. systemd 单元名与安装脚本一致：`wptsall-client`；macOS LaunchAgent：`cc.wpmm.wptsall-client`
4. 无 systemd 时仍 `mv` 替换（运行中 ELF 换 inode 合法）；有单元则 stop/start
5. **禁止回滚**：候选版本不得低于已安装版本（旧用户仍可继续用、可升级）

官网需把 `releases/manifest-{ver}.json` 的 `products.client-wpplugin` 字段同步到 `/api/v1/client/releases`。
