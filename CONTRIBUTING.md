# 参与贡献

> **一句话**：本仓是 AX3000T 上 OpenWrt 本体运维的参考实现；本文件只讲怎么提 Issue / PR、
> 改动前要守哪些规矩。

先说边界：这里只管**路由器本体这一层**——网络守护、开机自启、故障恢复，以及这些脚本
改过的系统状态。ShellCrash / mihomo 本体、订阅、分流规则、LuCI 控制台、AI 模型接入
各有归属，不在本仓范围内（分工见 [docs/UPSTREAM.md](docs/UPSTREAM.md)）。

## 提 Issue

- **守护失灵 / 恢复报错 / 开机不生效** → 用「问题反馈（Bug）」模板。
  请务必带上**设备与固件版本、脚本路径与调用方式、相关日志**：

  ```sh
  tail -50 /tmp/ShellCrash/guardian.log
  tail -50 /root/recover-last.log
  logread | tail -50
  ```

- **想要新的守护项或更省事的运维方式** → 用「功能建议」模板。
  先说场景（什么情况下、现在要几步、哪一步容易漏），再说期望的效果。

反馈前先查 [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)；机制与红线见
[docs/PITFALLS.md](docs/PITFALLS.md)，日常命令见 [docs/OPERATIONS.md](docs/OPERATIONS.md)。

## 提 Pull Request

1. 从 `main` 开分支，一条改动一个分支。
2. 设备相关的值**一律外置**：SSID、IP、节点名、路径用环境变量或占位符，
   不要把真实值写进脚本、示例或文档。规则见 [docs/SECRETS.md](docs/SECRETS.md)。
3. 提交前至少跑过：

   ```sh
   python3 tools/check-docs.py
   python3 tools/check-secrets.py
   python3 tools/check-vault-not-staged.py --all
   find . -name '*.sh' -not -path './vault/*' -not -path './.work/*' \
     -not -path './third-party/*' -print0 | xargs -0 -n1 sh -n
   ```

4. PR 描述里写清「改了什么、为什么、怎么验的」。
   **真机没验就明说没验**——这些脚本会直接改路由器状态，没验证的改动不要描述成已验证。

## 几条硬规矩

| 规矩 | 在哪定义 |
|---|---|
| 脚本会改设备状态：执行前备份，先 `check` 再完整修复 | [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) |
| 凭据与设备标识不入库，占位符不是真实值 | [docs/SECRETS.md](docs/SECRETS.md) |
| 每条规则只在一篇文档里定义，别处只留链接 | [docs/DOC-RULES.md](docs/DOC-RULES.md) |
| 版本号只在发版时进位，规则按对象拆行 | [docs/VERSIONING.md](docs/VERSIONING.md) |
| 用户可感知的改动要进 [CHANGELOG.md](CHANGELOG.md) | [docs/MAINTENANCE.md](docs/MAINTENANCE.md) |
| 不要改 `third-party/` 里的上游内容 | [docs/UPSTREAM.md](docs/UPSTREAM.md) |

## 免责声明

提交 Issue / PR 即表示你已知悉：脚本会直接修改路由器上的系统状态，执行前应自行备份；
本仓结论只在特定固件、订阅与时间点验证过，换环境后必须重新验证；使用本仓造成的任何
后果由使用者自行承担。全文见 [README](README.md#免责声明)。
