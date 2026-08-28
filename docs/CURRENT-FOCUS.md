# 当前范围（2026-08-27）— 双客户端同时维护

权威：`docs/architecture/current/DUAL-CLIENTS.md`  
版本 SSOT：`install-client/versions.json`

## 在做（两条线）

### A. WebUI（`client-wpplugin`）

1. 本机交叉 6 平台 `kit-webui-*` + minisign  
2. Kit 含 `bin/` + **`ui/webui/`**；`VERSION-BINARY` / `VERSION-WEBUI`  
3. 安装：`installers/install-webui.sh`；OTA：换 bin /（目标）换 ui  
4. Runner：安装 + 热更新冒烟（**不编 Rust**）

### B. Desktop（`client-desktop`，共享 `wptsall-client` lib）

1. 本机交叉 6 平台 `kit-desktop-*`（同工具链；aarch64 需 GTK sysroot）  
2. Kit 含 `bin/` + **`ui/desktop/`**  
3. 安装：`installers/install-desktop.sh`  
4. Runner：**再打** deb / AppImage / dmg / nsis（不编 Rust、不碰私钥）+ 安装/更新冒烟  

不购买 Apple Developer ID / Windows Authenticode（minisign 链足够安装与 OTA）。

## 公共操作

```bash
source install-client/security/config.env
bash install-client/lib/sync-versions.sh

bash install-client/cross-compile/host-cross-kits-webui.sh
bash install-client/cross-compile/host-cross-kits-desktop.sh

bash install-client/packaging/webui/make-ui-bundle.sh webui
bash install-client/packaging/webui/make-ui-bundle.sh desktop

bash install-client/security/scripts/sign-kits-batch.sh
bash install-client/tests/webui/run-local-suite.sh
# publish → workflows/pack-and-test.yml (type=webui|desktop)
```

## 产物

公开仓：`wpmmcc/wptsall-client-releases`

| 客户端 | kit tag（过渡） | 文件 |
|--------|-----------------|------|
| WebUI | `kits-webui-v{binary}` | `kit-webui-{platform}.tar.gz` + `.minisig` |
| Desktop | `kits-desktop-v{binary}` | `kit-desktop-{platform}.tar.gz` + `.minisig` |
| UI-only | `kits-*-ui-v{webui}` | `webui-ui-*.tar.gz` / `desktop-ui-*.tar.gz` |

详见 [PIPELINE.md](PIPELINE.md)、[DUAL-CLIENTS.md](../docs/architecture/current/DUAL-CLIENTS.md)。
