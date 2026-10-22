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

---

# 推送前脱敏规则（通用）

> **一句话**：推送前跑一次 `python tools/check-secrets.py`；它拦的是三类东西 ——
> 可用凭据、本机用户目录、真实邮箱。规则对 8 个仓完全一致，一处改全局同步。

---

## 1. 为什么需要这一条

历史教训：本系列仓的脱敏一度靠人记，结果漏过两次 ——

1. **同步脚本把 `--config` 的绝对路径回显进报告**，报告又作为 evidence 提交，
   本机用户目录就这样进了版本库。脚本默认值是按主目录推导的，本身没问题，
   问题出在那两行 `log("已写入 %s" % args.config)`。
2. **没有守卫的仓全靠自觉**。8 个仓里原本只有 2 个有 `tools/check-secrets.py`，
   规则里还不含本机路径。

所以规则固化成本篇 + 一个脚本 + 一个 CI 步骤。脚本是规则的**可执行版本**。

---

## 2. 三类拦截面

| 类别 | 例子 | 为什么拦 |
|---|---|---|
| **P0 可用凭据** | `gh[pousr]_…`、`sk-…`、`oc_sk_…`、`AIza…`、`glpat-…`、`-----BEGIN … PRIVATE KEY`、`AKIA…`、shadow 哈希、订阅 URL 的 token 段、代理节点 URI | 任何人拿到就能直接用 |
| **P1 本机用户目录** | `C:\Users\<名字>\…`（正反斜杠都拦） | 暴露用户名与软件安装布局，是社工的素材 |
| **P1 真实邮箱** | `…@qq.com` / `@163.com` / `@gmail.com` 等 | 暴露个人身份；GitHub noreply 邮箱不含这些域名，不会误伤 |

> **域名清单**：qq / 163 / 126 / gmail / outlook / hotmail / foxmail / sina / sohu。
> 只列国内常用与 Google / Microsoft 系 —— 加更多域名只会增加误报。

---

## 3. 三条放行规则（避免误报）

守卫不是越严越好，误报多了人就学会跳过它。所以明确放行三种情形：

### 3.1 占位符与示例值不算命中

行内含 `REDACTED` / `YOUR-` / `REPLACE-` / `<…>` / `example.com` / `placeholder`
/ `<用户名>` 等字样时，整行跳过。所以写文档时**优先用占位符**，能省掉很多例外。

### 3.2 文档类文件允许「截断形式」的描述性引用

变更说明里需要引用泄漏原文，否则读者不知道该改什么。形如下面的写法放行：

- 用户名位置就是省略号：`C:\Users\...\provider_config.json`
- 用户名用尖括号占位：`C:\Users\<名字>\...`
- 用户名后紧跟 `\...` 截断：`C:\Users\SansK\...`

**完整路径一律不放行。** 这条只对文档类文件生效
（`CHANGELOG.md` / `PROGRESS.md` / `SECURITY.md` / `CONTRIBUTING.md` / `docs/` /
`evidence/` / `memories/`）。

### 3.3 占位用户名不算命中

示例文件里的 `C:/Users/You/...`、`C:/Users/User/...`、`C:/Users/你的用户名/...`
是给用户照着改的模板，不是本机路径。

---

## 4. 白名单：只放「有意为之」

逐行白名单（`LINE_ALLOWLIST`）只放两类情形，**每条必须写清理由**：

- **机制上就该出现** —— 如 `.mailmap` 里的邮箱映射，那是 git 官方的作者身份
  归属机制，邮箱本来就该在里面。
- **确定不是敏感信息** —— 如 Kotlin 协程符号 `$scaleDone$1` 被 shadow 哈希
  正则误判。

加白名单前先问：能不能改用占位符绕开？能的话优先改内容，不要加白名单。

---

## 5. 推送前怎么做

```sh
# 1) 扫已跟踪文件（CI 跑的就是这个，退出码 0 才能推）
python tools/check-secrets.py

# 2) 扫工作树，含未跟踪文件（提交前自查用）
python tools/check-secrets.py --all
```

`--all` 模式**遵循 `.gitignore`** —— 本机配置（如 `config.local.json`）设计上
就不入库，报出来只是噪音。但它仍会扫**未跟踪且未被忽略**的新文件，所以能抓住
「新建了个文件忘了加 .gitignore」这种情况。

**CI 里有「敏感信息扫描」步骤**，推上去会自动跑。本地先跑一遍，别等 CI 报错。

---

## 6. 踩过的坑（写规则/脚本时注意）

1. **Python 单元素元组**：`SKIP_PREFIXES = ("tools/preview/")` 少了尾逗号，
   它不是元组而是字符串，`any(base.startswith(p) for p in "…")` 会逐字符迭代，
   导致所有以首字符开头的路径都被跳过 —— 守卫静默失效，扫描显示"通过"但实际
   什么都没查。必须写 `("tools/preview/",)`。
2. **`printf` 吞转义**：Git Bash 里 `printf 'C:\Users\...'` 把 `\U` 当 unicode
   转义，写出的测试文件内容是坏的，注入测试假通过。写含反斜杠的测试内容要用
   Python 的 `chr(92)`。
3. **replace-text 只匹配字面量**：重写历史时，文档里引用泄漏原文的写法
   （如 `git grep Users.SansK`，没有 `C:\` 前缀）匹配不到，要单独列规则。
4. **模板多行块替换**：按单行字符串替换跨多行的配置块会留下孤儿行导致
   IndentationError；先在源里 `assert` 锚点存在再替换，失败即中止。
5. **守卫脚本自己的注释会被自己的规则拦到** —— 注释里别出现完整路径字面量。

---

## 7. 相关文档

| 要查什么 | 去哪 |
|---|---|
| 凭据从哪读、怎么轮换 | 本篇其余章节 |
| 上报安全问题 | [../SECURITY.md](../SECURITY.md) |
| 提交前自检 | [../CONTRIBUTING.md](../CONTRIBUTING.md) |
| 文档怎么写 | [DOC-RULES.md](DOC-RULES.md) |
