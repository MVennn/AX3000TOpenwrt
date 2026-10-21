# 上游行为对照（OpenWrt / LuCI）

> **一句话**：本仓脚本依赖的 OpenWrt 与 LuCI 上游行为，每一条都注明**上游源码路径**，
> 让你能直接去上游核对 —— 而不是信本仓的一句话。

本篇是**文档，不是 vendor**。OpenWrt 与 LuCI 的源码都**没有**被复制进本仓
（体积远超门槛，见 [../third-party/README.md](../third-party/README.md)），
本仓只保存与之相关的配置片段、脚本与文档。

---

## 0. 上游版本基线

本仓对应的设备固件基线见 [HARDWARE.md](HARDWARE.md) §2：**OpenWrt 25.12.6**
（内核 6.12.112，`r33311-981c978eff`）。本篇所有上游路径都按下列引用给出：

| 上游 | 引用点 | 仓库 / 分支 | 说明 |
|---|---|---|---|
| OpenWrt | tag `v25.12.6` | https://github.com/openwrt/openwrt | 与设备上的固件版本一一对应 |
| LuCI | 分支 `openwrt-25.12` | https://github.com/openwrt/luci | 25.12 系列的 LuCI 分支 |
| rpcd | commit `d99f703e4035d03fbcfbada3cb697db346c2b984` | https://github.com/openwrt/rpcd | 版本由 `package/system/rpcd/Makefile` 的 `PKG_SOURCE_VERSION` 锁定 |
| ubus | commit `24864e7840b3a02a9ef76284a373f6b2f00b8a9b` | https://github.com/openwrt/ubus | 同上，`package/system/ubus/Makefile` |
| firewall4 | commit `b6e5157527d361f99ad52eaa6da273cb0f2dfd59` | https://github.com/openwrt/firewall4 | 同上，`package/network/config/firewall4/Makefile` |

> OpenWrt 主仓只放打包脚本，**真正的 C 源码在各自的独立仓**（`project/ubus.git`、
> `project/rpcd.git`、`project/firewall4.git`）。所以「上游源码路径」分两层：
> `package/...` 里的打包脚本，和独立仓里的源码文件。本篇两条都给。

核对办法：把 URL 换成
`https://raw.githubusercontent.com/openwrt/openwrt/v25.12.6/<路径>` 即可取到原文。

---

## 1. `/etc/rc.local` 的执行时机

**本仓依赖的结论**：`/etc/rc.local` 由 `/etc/init.d/done` 调用，
`done` 的 `START=95` ⇒ 开机时它的排序在 **S95**，
所以 **`rc.local` 在 S99 之前跑** —— 这正是本仓
[system/rc.local](../system/rc.local) 第一行注释
「create runtime dir before S99shellcrash」成立的原因。

| 上游源码路径（tag `v25.12.6`） | 关键内容 |
|---|---|
| `package/base-files/files/etc/init.d/done` | `START=95`；`boot()` 里 `[ -f /etc/rc.local ] && { sh /etc/rc.local }` |
| `package/base-files/files/etc/rc.local` | 上游默认内容：`# Put your custom commands here that should be executed once the system init finished.` + `exit 0` |
| `package/base-files/files/etc/rc.common` | `enable()` 生成 `/etc/rc.d/S${START}${name}` 软链 ⇒ `done` ⇒ `S95done` |
| `package/base-files/Makefile` | 第 205 行创建 `/etc/rc.d` 目录 |
| `package/base-files/files/lib/upgrade/keep.d/base-files-essential` | 第 11 行 `/etc/rc.local` ⇒ sysupgrade 不会丢 |
| `package/base-files/Makefile` | `/etc/rc.local` 登记为 `base-files` 的 conffile |

**由此推出的三条硬约束**（本仓脚本必须遵守）：

1. **`rc.local` 是在 S95 这一档跑的**，不是「所有 init 脚本之后」。
   `led` 是 S96、ShellCrash 是 S99 ⇒ 放在 `rc.local` 里的动作**早于**它们。
2. **它是 `sh /etc/rc.local` 调起的**，不是当可执行文件跑 ⇒ 不需要 exec 位，
   但**必须以 `exit 0` 收尾**（上游默认文件就是这个样子）。
3. **`rc.local` 里的每一步都要能重复执行**（幂等）—— 机器可能重启多次，
   同一段代码会跑很多遍。本仓用的是 `nft list table ... || nft -f ...` 这种
   「先查在不在」的写法。

---

## 2. `/etc/init.d/` 的约定

**本仓依赖的结论**：`/etc/init.d/<name>` 是 `#!/bin/sh /etc/rc.common` 的壳；
`START=`/`STOP=` 决定排序；`enable`/`disable` 管理 `/etc/rc.d/S??<name>` 软链；
`USE_PROCD=1` 时由 procd 接管实例管理。

| 上游源码路径（tag `v25.12.6`） | 关键内容 |
|---|---|
| `package/base-files/files/etc/rc.common` | 全部命令框架：`start/stop/restart/reload/enable/disable/enabled`；`enable()` 建 `S<START>` 软链、`disable()` 删 `S??`/`K??`；`USE_PROCD` 分支把 start/stop/reload 改写成 procd 调用 |
| `package/base-files/files/etc/init.d/boot` | `START=10`；建 `/var/lock`、`/var/log`、`/var/run`、`/var/state`、`/var/tmp`、`/tmp/.uci`，软链 `/run -> /var/run`、`/run/lock -> /var/lock`，跑 `/sbin/kmodloader` 与 `uci_apply_defaults` |
| `package/base-files/files/etc/init.d/done` | `START=95`；跑 `/etc/rc.local` |
| `package/base-files/files/etc/init.d/umount` | `STOP=90` |
| `package/system/procd/files/procd.sh` | procd API 全文：`procd_open_service` / `procd_set_param` / `procd_close_service` / `procd_running` / `procd_kill` / `procd_send_signal`；每个动作最终落到 `ubus call service ...` |
| `package/system/procd/files/service` | `/etc/service` 命令的实现：遍历 `/etc/init.d/*` 查 `enabled`，再 `ubus call service list "{'verbose':true,'name':'...'}"` 判运行态 |
| `package/base-files/Makefile` | `/etc/rc.d` 目录的创建位置 |

### 2.1 `base-files` 里的启动档位（参考设备可见的全量）

| init 脚本 | 档位 |
|---|---|
| `sysfixtime` | `START=00` |
| `boot` | `START=10` |
| `system` | `START=10` |
| `sysctl` | `START=11` |
| `gpio_switch` | `START=94` |
| `done` | `START=95` ← **跑 `rc.local`** |
| `led` | `START=96` |
| `umount` | `STOP=90` |

### 2.2 本仓用到 `/etc/init.d/` 的地方

| 本仓脚本 | 用到的上游行为 | 上游源码路径 |
|---|---|---|
| [system/archive/bootfix.sh](../system/archive/bootfix.sh) | `/etc/init.d/cron restart`；`/etc/init.d/shellcrash enabled`（返回码 1 = 已禁用） | `package/base-files/files/etc/rc.common`（`restart` / `enabled`）、`package/system/procd/files/service` |
| [recovery/recover-now.sh](../recovery/recover-now.sh) | `/etc/init.d/dnsmasq restart`、`/etc/init.d/firewall restart` | `package/network/services/dnsmasq/files/dnsmasq.init`、`package/network/config/firewall4/Makefile` → 上游 `openwrt/firewall4` 的 `root/etc/init.d/firewall` |
| [guardian/guardian.sh](../guardian/guardian.sh) | 注释里写明「维护前先停守护」用的是 `/etc/init.d/cron restart` | `package/base-files/files/etc/rc.common` |

### 2.3 `/var` 为什么是软链（`VAR_RUNTIME_DIRS` 兜底的由来）

`package/base-files/Makefile` 里：

```make
ifneq ($(CONFIG_TARGET_ROOTFS_PERSIST_VAR),y)
	rm -f $(1)/var
	$(LN) tmp $(1)/var
else
	mkdir -p $(1)/var
	$(LN) /tmp/run $(1)/var/run
endif
```

**没开 `CONFIG_TARGET_ROOTFS_PERSIST_VAR` 时，`/var` 是指向 `tmp` 的相对软链** ——
参考设备就是这样。所以 `/var/etc`、`/var/lib` 这些目录**在 tmpfs 上**，重启即失；
而 dnsmasq 依赖 `-C /var/etc/dnsmasq.conf.*`（`package/network/services/dnsmasq/files/dnsmasq.init`）。

⇒ 本仓 [system/rc.local](../system/rc.local) 里那段 `mkdir -p /var/etc /var/lib ...`
就是针对这一条上游行为打的补丁。细节见 [TROUBLESHOOTING.md](TROUBLESHOOTING.md) 里
「`/var/etc/dnsmasq.conf.*` 不存在」那条。

---

## 3. LuCI 的 CGI 约定

**本仓依赖的结论**：LuCI 的入口是设备上的 `/www/cgi-bin/luci`，
它按 CGI 约定读环境变量与标准输入，再交给 dispatcher 分发；
25.12 系列的 dispatcher 是 **ucode** 实现（旧版是 Lua，契约一致）。

| 上游源码路径（分支 `openwrt-25.12`） | 关键内容 |
|---|---|
| `modules/luci-base/htdocs/cgi-bin/luci` | CGI 入口。`#!/usr/bin/env ucode`；读 `CONTENT_LENGTH` 环境变量决定请求体长度，从 **stdin** 读 body，写 **stdout**；末尾 `req.close()` |
| `modules/luci-base/ucode/dispatcher.uc` | 分发器本体：路由 → ACL 校验（`apply_tree_acls` / `check_acl_depends`）→ 渲染；登录与会话见 §4 |
| `modules/luci-base/ucode/http.uc` | HTTP 请求/响应原语（`luci.http`） |
| `modules/luci-base/ucode/runtime.uc` | `luci.runtime`：dispatcher 的运行时入口 |
| `modules/luci-base/ucode/sys.uc` | `luci.sys`：系统信息 ubus 调用 |
| `modules/luci-base/ucode/uhttpd.uc` | uhttpd 集成层 |
| `modules/luci-base/ucode/template/csrftoken.ut` | **CSRF token 模板** —— LuCI 的写操作靠它防跨站请求 |
| `modules/luci-lua-runtime/luasrc/dispatcher.lua` | 旧版 Lua dispatcher，契约与 ucode 版一致 |
| `modules/luci-lua-runtime/luasrc/sys.lua` | 旧版 `luci.sys` |
| `modules/luci-base/root/usr/share/rpcd/acl.d/luci-base.json` | rpcd 侧的 ACL：`luci-base` 组能读哪些 ubus 方法、能写哪些 uci 包 |
| `modules/luci-base/root/usr/share/acl.d/luci-base.json` | ubus 侧的 ACL |
| `modules/luci-base/root/usr/share/rpcd/ucode/luci` | `luci` 这个 ubus 对象的实现（`getFeatures` 等） |
| `modules/luci-base/root/usr/share/luci/menu.d/luci-base.json` | 菜单树 —— 界面上看到哪些页 |

**由此推出的三条**：

1. **CGI 的输入是「环境变量 + stdin」**：请求体长度靠 `CONTENT_LENGTH`，
   边界靠 `CONTENT_LENGTH` 之外还得看 uhttpd 的行为。
   任何仿 CGI 的东西（兄弟仓 `OpenwrtConsole` 的 `deploy/*.cgi`）都要照这个约定走。
2. **写操作要带 CSRF token**，token 由 `csrftoken.ut` 模板生成。
3. **能不能写某个配置，取决于 rpcd ACL**（`acl.d/*.json`），而不是取决于页面按钮。
   LuCI 被 `apk del luci-app-*` 卸掉后，ACL 跟着一起没了。

> 兄弟仓 `OpenwrtConsole` 的 CGI 契约正本在它自己的
> `docs/CGI-CONTRACT.md`，本篇只记录 LuCI 上游的**约定**，不重复本仓的接口定义。

---

## 4. ubus 会话机制

**本仓依赖的结论**：登录态不是 cookie，是 **ubus session id**；
session 由 rpcd 的 `session` ubus 对象管理，id 靠 `ubus_rpc_session` 参数传递；
LuCI 的 dispatcher 就是靠 `session` 对象完成「登录 → 取 ACL → 放行」。

### 4.1 rpcd 侧

| 上游源码路径（commit `d99f703`） | 关键内容 |
|---|---|
| `session.c` | `session` ubus 对象的全部实现：`rpc_session_create()` 生成 sid 并返回 `ubus_rpc_session` 与 `timeout`；`rpc_handle_login` 校验凭据；`rpc_handle_access` 返回该会话被授予的 ACL 列表 |
| `session.c` 里的 `session_methods` | 方法表：`create` / `login` / `destroy` / `grant` / `revoke` / `access` / `set` / `get` |
| `session.c` 里的 `*_policy` | 参数名一律是 **`ubus_rpc_session`**（见 `sid_policy` / `set_policy` / `get_policy` / `perm_policy`） |
| `include/rpcd/session.h` | 会话接口头文件 |
| `unauthenticated.json` | 未认证用户允许调用的方法清单 |
| `main.c` / `plugin.c` | rpcd 主程序与插件加载 |
| OpenWrt 侧：`package/system/rpcd/files/rpcd.init` | `START=12`、`USE_PROCD=1`；socket 路径取 `uci get rpcd.@rpcd[0].socket`，超时取 `uci get rpcd.@rpcd[0].timeout` |
| OpenWrt 侧：`package/system/rpcd/files/rpcd.config` | rpcd 自身的 UCI 配置默认值 |

### 4.2 ubus 侧

| 上游源码路径（commit `24864e7`） | 关键内容 |
|---|---|
| `ubusd.c` / `ubusd_main.c` | ubus 守护进程主体 |
| `ubusd_obj.c` | 对象注册与查找（`ubus call <object> <method> '<json>'` 的落点） |
| `ubusd_proto.c` | ubus 线路协议 |
| `ubusd_acl.c` / `ubusd_acl.h` | **ubus ACL 引擎** —— 读 `/usr/share/acl.d/*.json` |
| `libubus.c` / `libubus-obj.c` / `libubus-req.c` | 客户端库 |
| OpenWrt 侧：`package/system/ubus/Makefile` | `PKG_SOURCE_VERSION:=24864e78…`（把上游版本钉死在这里） |

### 4.3 LuCI 侧怎么用会话

`modules/luci-base/ucode/dispatcher.uc`（分支 `openwrt-25.12`）里：

- `session_setup(user, pass, path)` → `ubus.call("session", "login", {...})`，
  成功后拿到 `login.ubus_rpc_session`；
- `session_retrieve(sid)` → `ubus.call("session", "get", { ubus_rpc_session: sid })`
  取值、`ubus.call("session", "access", { ubus_rpc_session: sid })` 取 ACL；
- 登录成功后还会 `ubus.call("session", "set", { ubus_rpc_session: sid, values: { token: randomid(16) } })`
  写一个随机 token，供后续请求比对。

**⇒ 一句话**：LuCI 的「登录态」= `ubus_rpc_session` + `session` 对象里存的值；
权限判定落在 `session.access` 返回的 ACL 上。兄弟仓 `OpenwrtConsole`
要写 OpenWrt 配置，走的是同一套 rpcd/ubus 授权模型。

---

## 5. 本仓脚本 → 上游行为的落点总表

| 本仓文件 | 依赖的上游行为 | 上游源码路径 |
|---|---|---|
| [system/rc.local](../system/rc.local) | `rc.local` 由 S95 的 `done` 调用、早于 S99 | `package/base-files/files/etc/init.d/done`、`package/base-files/files/etc/rc.common` |
| [system/rc.local](../system/rc.local) | `rc.local` 需以 `exit 0` 收尾、可重复执行 | `package/base-files/files/etc/rc.local` |
| [system/rc.local](../system/rc.local) | `/var` 是指向 `tmp` 的软链（未开 `CONFIG_TARGET_ROOTFS_PERSIST_VAR`） | `package/base-files/Makefile` |
| [system/archive/bootfix.sh](../system/archive/bootfix.sh) | `/etc/init.d/cron restart`、`/etc/init.d/shellcrash enabled` 的返回码语义 | `package/base-files/files/etc/rc.common`、`package/system/procd/files/service` |
| [recovery/recover-now.sh](../recovery/recover-now.sh) | `/etc/init.d/dnsmasq restart` 的配置目录依赖 | `package/network/services/dnsmasq/files/dnsmasq.init` |
| [recovery/recover-now.sh](../recovery/recover-now.sh) | `/etc/init.d/firewall restart` = fw4 重生成 nft 规则集 | `package/network/config/firewall4/Makefile` → 上游 `openwrt/firewall4` 的 `root/etc/init.d/firewall`、`root/usr/share/firewall4/main.uc` |
| [recovery/recover-now.sh](../recovery/recover-now.sh) | `ifup wan` 的接口配置来自 UCI；首启时网络配置会被 uci-defaults 迁移 | `package/system/uci/files/lib/config/uci.sh`、`package/base-files/files/etc/uci-defaults/11_network-migrate-bridges`、`package/base-files/files/etc/uci-defaults/12_network-generate-ula`、`package/base-files/files/etc/uci-defaults/14_network-generate-duid`（由 `/etc/init.d/boot` 的 `uci_apply_defaults` 执行） |
| [guardian/guardian.sh](../guardian/guardian.sh) | `ubus call service list` 的服务状态查询语义 | `package/system/procd/files/service`、`package/system/procd/files/procd.sh` |
| [guardian/guardian.sh](../guardian/guardian.sh) | `/etc/rc.local` 派发开机验收的机制 | `package/base-files/files/etc/init.d/done` |
| [baseline/sysupgrade.conf](../baseline/sysupgrade.conf) | 哪些文件在 sysupgrade 后被保留 | `package/base-files/files/lib/upgrade/keep.d/base-files-essential` |
| [docs/HARDWARE.md](HARDWARE.md) | 固件/内核版本基线 | OpenWrt tag `v25.12.6` |

---

## 6. 怎么核对

```bash
# 取 OpenWrt v25.12.6 的某个上游文件原文
curl -sL https://raw.githubusercontent.com/openwrt/openwrt/v25.12.6/package/base-files/files/etc/init.d/done

# 取 LuCI openwrt-25.12 分支的某个上游文件原文
curl -sL https://raw.githubusercontent.com/openwrt/luci/openwrt-25.12/modules/luci-base/ucode/dispatcher.uc

# 取 rpcd / ubus / firewall4 在 OpenWrt 里被钉住的那个 commit 的源码
curl -sL https://raw.githubusercontent.com/openwrt/rpcd/d99f703e4035d03fbcfbada3cb697db346c2b984/session.c
```

本篇引用的每条路径都按上面这种形式可直接取到原文。
若上游改了行为，**先改本篇，再改本仓脚本** —— 顺序反了就会出现
「文档说的和机器做的不是一回事」。

---

## 7. 通用版与参考实现的分工

> **一句话**：本仓的三个脚本是**脱敏后的参考实现**；
> 通用版在公开仓 `OpenwrtOpsToolkit` 的 `openwrt/` ——
> 同一套逻辑，但设备相关的值全部抽成配置项。

### 7.1 为什么保留两份

`guardian/guardian.sh`、`recovery/recover-now.sh`、`system/rc.local` 是设备上实际运行的脚本，
`recovery/local-tools/fix-router.sh` 还按 `../recover-now.sh` 找同目录上一级的恢复脚本，
`recovery/local-tools/recover-run.ps1` 同理。把它们直接替换成通用版会让「文档里的示例」与
「设备上跑的逻辑」对不上，所以本仓保留一份**可读的参考实现**，通用版另存一份。

### 7.2 两边的差异点

| 项 | 本仓（参考实现） | 通用版（`OpenwrtOpsToolkit/openwrt/`） |
|---|---|---|
| 策略组名 | 示例值（`🤖 人工智能` / `🤖 AI网页` / `🤖 干净出口`） | 读配置：`AI_GROUP` / `AI_FALLBACK_GROUP` / `CLEAN_GROUP` |
| 节点名 | 示例值（`🇮🇳 印度-优化` 等；`is_bad_node` 里另有一份坏节点清单） | 读配置：`CLEAN_NODE` / `CL_CANDIDATES` / `AI_BAD_NODES` / `POOL_BLOCKED_NODES` |
| 通用池组名 | 示例值（`🚀 节点选择` / `♻️ 自动选择`） | 读配置：`POOL_GROUP` / `POOL_FALLBACK_GROUP` |
| nft 表路径 | `/etc/<表名>.nft` | `NFT_DIR` + `NFT_TABLES`（含 DNS 劫持的表另走 `NFT_DNS_TABLES`） |
| 自建目录 | `/etc/router-health/` | `ROUTER_HEALTH_DIR` |
| 端口 | `7890` / `7892` / `9999` / `1053` | `PROXY_PORT` / `MIXED_PORT` / `CTRL_PORT` / `DNS_PORT` |
| 配置加载 | 值直接写在脚本里，换设备需手工改 | **环境变量 → `device.conf` → 占位符默认值**；`DEVICE_CONF` 指定路径 |
| 干跑 | `recover-now.sh check` | `guardian.sh --dry-run`、`recover-now.sh check`、`post-sc-update.sh check` |
| API secret | 从 `/etc/ShellCrash/configs/ShellCrash.cfg` 现读 | 同（**两边都不存凭据**） |

### 7.3 改动方向

**先改通用版 → 再同步本仓参考实现**。本仓的改动若涉及**通用逻辑**
（流程、判断顺序、错误处理），必须回到通用版改一遍，否则通用版会慢慢落后。

反向不成立：通用版为「适配更多设备」做的泛化（例如把节点清单变成配置项），
**不必**回灌到本仓 —— 本仓保留示例值反而更直观，也更不容易被一份写错的配置带偏。
