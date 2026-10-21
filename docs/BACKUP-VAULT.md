# vault/ —— 私有金库（**在仓里，但绝不入库**）

> **一句话**：不可再生的回退材料放这里 —— 私钥备份、升级前的整机快照、argon 主题恢复包；
> `.gitignore` 把它整个排除，CI 里还有一道守卫兜底。

---

## 0. 为什么放在仓里

这几个东西**不可再生**：路由器上只有新版，删了就回不去。
放在仓里（而不是仓外）是为了**跟着设备走** —— 换机器、重装系统、恢复环境时一眼能找到。

但它们**绝不能进版本库**。所以：

| 机制 | 作用 |
|---|---|
| `.gitignore` 的 `/vault/` | 常规排除（另叠了 `*.tar.gz` / `*.key.orig` / `*.crt` 三重保护） |
| `tools/check-vault-not-staged.py` | **兜底** —— 忽略规则被改、被 `git add -f` 绕过时，CI 直接红 |
| 公开仓的历史不可改写 | 一旦提交进去，删文件也删不掉历史 —— 所以只能靠前两道 |

```bash
# 自查
python tools/check-vault-not-staged.py --all
```

---

## 1. 里面有什么

```
vault/backup/
├─ keys/
│  ├─ uhttpd.key.orig            HTTPS 私钥（与设备上的 /etc/uhttpd.key 配对）
│  ├─ uhttpd.crt.orig            对应证书
│  └─ wireguard/wg-client.conf   WireGuard 客户端配置（**含私钥**）
├─ sysupgrade/
│  └─ pre-25.12.6.tar.gz         升级前整机快照（334 条，含 etc/shadow 与 SSH 主机私钥）
└─ themes/
   └─ luci-theme-argon-files.tar.gz   argon 主题恢复包（overlay 上没有别的来源）
```

**已删掉的（可再生）**：`current-20261020.tar.gz`（路由器上有当前 /etc）、
`post-25.12.6.tar.gz`（当前状态在路由器上）、`config-25.12.6.tar.gz`（能再导）、
`router-ca.crt`（能再签）。

---

## 2. 什么时候用

| 场景 | 取哪一份 |
| --- | --- |
| **固件要回退**（升级到 25.12.6 之后出问题） | `sysupgrade/pre-25.12.6.tar.gz` |
| **HTTPS 证书被误换**，浏览器又要重新信任 | `keys/uhttpd.key.orig` + `keys/uhttpd.crt.orig` |
| **WireGuard 连不上**，怀疑私钥被改 | `keys/wireguard/wg-client.conf` |
| **argon 主题丢了** | `themes/luci-theme-argon-files.tar.gz` |

---

## 3. 恢复步骤

```sh
# 整机回滚
tar -xzf vault/backup/sysupgrade/pre-25.12.6.tar.gz -C /tmp/restore
# → 把 /tmp/restore/etc 合并回设备，或走 sysupgrade 流程刷回旧固件

# 换回 HTTPS 证书
scp vault/backup/keys/uhttpd.key.orig root@<路由器IP>:/etc/uhttpd.key
scp vault/backup/keys/uhttpd.crt.orig root@<路由器IP>:/etc/uhttpd.crt
ssh root@<路由器IP> '/etc/init.d/uhttpd restart'
```

---

## 4. 几条硬规矩

1. **不要** `git add -f vault/...` —— CI 会红，且一旦提交进去，删文件也删不掉历史。
2. **不要**把这些内容抄进文档、提交信息或 issue。
3. **私钥泄露 = 立即轮换** —— 删文件不等于失效（见 [SECRETS.md](SECRETS.md)）。
4. 换下来的整机快照**只在需要时用** —— 平时别解压到别处，那会把私钥散落到临时目录。

---

## 5. 相关文档

- [SECRETS.md](SECRETS.md) —— 凭据位置索引（只写位置不写值）
- [../README.md](../README.md) —— 本仓定位与使用入口；目录职责与部署映射见 [DEPLOY.md](DEPLOY.md)
- [../CHANGELOG.md](../CHANGELOG.md) —— 本仓变更台账
