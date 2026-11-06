# AGENTS —— 机器协议

> **一句话**：三条硬规矩 —— **设备值一律外置**、**改路由器先备份再验证**、**shell 必须 LF**。
> 系统层结论与事故链见 `docs/PITFALLS.md`，操作步骤见 `docs/OPERATIONS.md`。

## 1. 设备值一律外置

不许写进源码、文档、示例、日志、提交信息：

| 类别 | 例子 | 放哪 |
| --- | --- | --- |
| 网络标识 | WiFi SSID、IPv6 PD 前缀、LAN 地址 | `vault/`（gitignored） |
| 节点/出口 | 节点名、出口 IP、机场名 | 同上 |
| 凭据 | SSH 口令、token | 环境变量 |
| 本机路径 | `C:\Users\<你>` | 相对路径或 `~` 推导 |

占位符：`<REDACTED-…>`（凭据）、`<REPLACE-…>`（待填值）。脚本读取顺序：环境变量 → 配置 → 占位符默认。

## 2. 硬红线（都出过事故）

- `init.d` 必须 **disabled** —— 双实例是 OOM 与断网的正因。
- `/tmp` 封顶 48 MiB（tmpfs 在内存里），57 MB 内核包灌进去会直接打崩路由器。
- 闪存写预算有限：别写循环日志、别频繁 echo 到 flash。
- 部署三步：**备份 → md5 校验 → 受控重启**；长驻进程（mihomo）禁止会话内自动重启，流量可能正经过它。
- 升级走 `owut` 前先读 `docs/MAINTENANCE.md`；离线恢复配方在 `recovery/`。

## 3. 目录

- `system/` — 开机自启、网络守护、`router-health/`；`system/archive/` 放退役脚本
- `guardian/` — 巡检与自愈
- `recovery/` — 离线恢复配方与本地工具
- `baseline/` — 设备基线快照
- `vault/` — 真值配置与备份（gitignored）
- `tools/` — `check-docs.py`、`check-secrets.py`、`check-vault-not-staged.py`、图标脚本
- `.work/private-evidence/` — 私有证据，不进库
- `.work/private-history.bundle` — 私有完整历史镜像，与 private-evidence 同由 `/.work/` 排除，不发布、不恢复进公开分支

## 4. 验证

- 改脚本：路由器上 `sh -n` 语法过一遍，再在目标机上跑；busybox 的 `awk`/`sed`/`grep` 参数与 GNU 不同。
- shell 脚本必须 **LF**，CRLF 在 busybox 下直接报错。
- 改文档跑 `python tools/check-docs.py`；改配置/脚本跑 `check-secrets.py` 与 `check-vault-not-staged.py`。
- 修复任何故障后，把结论补进 `docs/PITFALLS.md`（踩坑正本）。

## 5. 边界

- `third-party/` 是 vendored 上游，一个字节都不动。
- 通用版在兄弟仓 `OpenwrtOpsToolkit`：同一套逻辑、设备值抽成配置项；两边改动要对齐，分工见 `docs/UPSTREAM.md` §7。
- 本仓只管路由器本体：ShellCrash / mihomo 配置在 `ShellcrashRules`，控制台在 `OpenwrtConsole`，网关在 `ZcodeAIModels`。
