# 凭据与安全须知

> **一句话**：这套脚本需要哪些凭据、分别从哪里读、换设备时怎么轮换 ——
> 本篇**只写位置与读取方式，不写任何值**。

---

## 1. 原则

本仓库是**脱敏后的参考实现**，不保存任何可直接使用的凭据：

- 文档里出现的是 `<REDACTED-...>` 或 `<YOUR-...>` 占位符；
- 脚本从**环境变量**或**设备侧真源**读取；
- `.gitignore` 排除私钥、订阅原文、本机口令文件与工作区。

**占位符不是真实值** —— 拿 `<REDACTED-root-pw>` 去登录一定失败，那不是 bug，是设计。

---

## 2. 凭据清单与读取方式

| 凭据 | 谁在读 | 读取方式 | 真源 |
|---|---|---|---|
| root 口令 | `recovery/local-tools/askpass.sh` | 环境变量 `ROUTER_PASSWORD` → `recovery/local-tools/.router-password` → `$HOME/.router-password` | 设备 `/etc/shadow`（哈希） |
| mihomo 控制 API secret | `guardian/guardian.sh` | 设备上直接读 `/etc/ShellCrash/configs/ShellCrash.cfg` 的 `secret=` 行 | 该配置文件 |
| mihomo 地址 / 端口 | PC 侧诊断脚本（兄弟仓） | 环境变量 `MIHOMO_HOST` / `MIHOMO_PORT` / `MIHOMO_API` | 设备控制 API |
| 节点 UUID / 订阅 token | 不由本仓读取 | 由 ShellCrash 从订阅生成 | 机场订阅面板 / `config/yamls/proxies.yaml`（不入库） |
| SSH 主机私钥、HTTPS 私钥、WireGuard 私钥 | 设备自身 | — | `/etc/dropbear/`、`/etc/uhttpd.key`、`/etc/wg/`，**不入库** |

### 2.1 root 口令

`askpass.sh` 按顺序找三个来源，第一个非空即用：

1. 环境变量 `ROUTER_PASSWORD`
2. `recovery/local-tools/.router-password`（单行文本，已被 `.gitignore` 排除）
3. `$HOME/.router-password`

三者都没有 → **报错退出（exit 1）**，绝不吐出一个空的或错的口令。

```sh
export ROUTER_PASSWORD='...'          # 临时用
# 或
printf '%s\n' '...' > recovery/local-tools/.router-password
```

### 2.2 mihomo 控制 API secret

设备侧真源是 `/etc/ShellCrash/configs/ShellCrash.cfg` 的 `secret=` 行。
`guardian/guardian.sh` 在设备上直接读它，不落盘、不需要副本。

PC 侧跨仓诊断脚本从环境变量 `MIHOMO_SECRET` 读；未设置就明确报错，不会拿着空 secret
去请求、再收到一个含义不明的 401。

```sh
export MIHOMO_SECRET="$(ssh root@"$ROUTER_IP" \
  'grep -m1 "^secret=" /etc/ShellCrash/configs/ShellCrash.cfg | cut -d= -f2- | tr -d "\x27\x22"')"
```

### 2.3 节点与订阅凭据

本仓**不含**机场订阅、节点 UUID、订阅 token。它们由 ShellCrash 在设备上从订阅生成，
真实副本只在设备 `/etc/ShellCrash/` 与你的密码管理器里。

---

## 3. 换设备 / 公开 Fork 前的检查清单

```sh
# 1) 确认没有把凭据文件带进去
git ls-files | grep -Ei '\.(key|crt|pem|p12|pfx)$|askpass\.sh|subscription|proxies\.yaml$'

# 2) 确认忽略规则生效
git status --ignored --short | grep -E '^!!' | head -20

# 3) 扫一遍将要提交的内容
python tools/check-secrets.py
```

逐条确认：

- [ ] root 口令只存在于环境变量或本机忽略文件，**没有写进任何跟踪文件**；
- [ ] mihomo secret 只在设备侧配置文件里，仓库里是占位符或读取逻辑；
- [ ] 节点 UUID、订阅 token、机场域名没有出现在文档、脚本或配置模板里；
- [ ] `vault/`、`.work/`、`*.key`、`*.crt`、`*.pem` 均未入库；
- [ ] 原始设备证据（日志、抓包、UCI 转储、状态快照）**不在公开树里**。

---

## 4. 轮换顺序

1. 先用 SSH 密钥登录验证可用，再改 root 口令；
2. 改 root 口令后，同步更新 WiFi PSK（如果两者相同）；
3. 轮换 mihomo secret 后，重新导出 `MIHOMO_SECRET`，否则表现为「API 静默 Unauthorized」；
4. 换订阅时顺带轮换订阅 token；
5. 轮换后重跑一次自检（见 [TROUBLESHOOTING.md](TROUBLESHOOTING.md)）。

---

## 5. 相关文档

| 要查什么 | 去哪 |
|---|---|
| 当前配置值、访问入口 | [OPERATIONS.md](OPERATIONS.md) |
| 排障步骤（含鉴权异常的定位） | [TROUBLESHOOTING.md](TROUBLESHOOTING.md) |
| 备份与回退 | [MAINTENANCE.md](MAINTENANCE.md) |
| 忽略规则 | 仓库根 `.gitignore` |
