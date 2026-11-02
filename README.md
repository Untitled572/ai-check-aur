# AUR PKGBUILD AI 审查工具

在 `paru -Syu` 构建 AUR 包之前，通过 opencode 调用 **MiMo 2.6 Flash** 审查 PKGBUILD 和本地安装脚本，发现风险时阻止该包安装。

## 模型与依赖

- Arch Linux、paru、Bash、GNU coreutils、`jq`。
- 安装 [opencode](https://opencode.ai)，通过 `opencode auth login` 配置 Xiaomi API Key。
- 小米官方 API 模型 ID 为 **`mimo-v2.6-flash`**，在 opencode 中使用 **`xiaomi/mimo-v2.6-flash`**。
- 模型名称来源：[小米官方模型发布记录](https://mimo.mi.com/docs/en-US/updates/model)；调用格式来源：[opencode CLI 文档](https://opencode.ai/docs/cli/)。这不是 free 模型，费用由小米账户承担。

程序在本次调用的配置中显式注册此模型，解决旧模型目录未收录新模型时的 `Model unavailable`，不修改全局 opencode 配置。其他模型以本机 `opencode models` 输出为准。

## 安装或更新

在项目目录中以普通用户运行：

```bash
./install.sh
```

也可选择不需要 sudo 的用户安装：

```bash
./install.sh --user
```

用户安装将程序放到 `~/.local/bin/ai-check-pkgbuild`，并让 paru 的钩子使用此文件的绝对路径，因此不会误调用 `/usr/local/bin` 下的旧副本。切换安装位置时自动备份 paru 配置为 `paru.conf.bak`。

脚本仅在复制主程序到 `/usr/local/bin/ai-check-pkgbuild` 时使用 sudo。不要用 `sudo ./install.sh`，以免配置和缓存安装到 root 的用户目录。

安装脚本会：

1. 更新主程序，创建用户缓存目录。
2. 安装 `~/.config/ai-check-aur/config.env`；已有配置完整保留。
3. 将现有 `xiaomi/mimo-v2.5` 配置迁移为 `xiaomi/mimo-v2.6-flash`，原配置保存为 `config.env.bak`；其他自定义模型保留。
4. 在 paru 配置的 `[bin]` 节添加 `PreBuildCommand = ai-check-pkgbuild`。尊重 `PARU_CONF` 和 `XDG_CONFIG_HOME`。新建用户配置时复制系统 paru 配置，保留原有设置。

若已有其他有效 `PreBuildCommand`，脚本会提示冲突并退出，请自行将两个检查串联；不会将其他钩子误报为已接入 AI 审查。

## 配置

配置文件默认位于 `~/.config/ai-check-aur/config.env`，遵循 `XDG_CONFIG_HOME`。直接运行项目内的脚本时，优先使用脚本旁的 `config.env`。配置是可信的 Bash 文件；程序不会执行 PKGBUILD 来读取配置。

```bash
AI_CHECK_ENABLED=true
AI_CHECK_MODEL="xiaomi/mimo-v2.6-flash"
AI_CHECK_TIMEOUT=60
AI_CHECK_FAIL_ACTION=skip
AI_CHECK_ERROR_ACTION=block
```

| 配置项 | 默认值 | 说明 |
|---|---|---|
| `AI_CHECK_ENABLED` | `true` | `false` 时直接跳过 AI 审查 |
| `AI_CHECK_MODEL` | `xiaomi/mimo-v2.6-flash` | opencode 的 `provider/model` 标识 |
| `AI_CHECK_TIMEOUT` | `60` | 正整数秒；超时后终止调用，5 秒后强制结束未退出的进程 |
| `AI_CHECK_FAIL_ACTION` | `skip` | 模型明确返回 `FAIL: ...` 时的行为 |
| `AI_CHECK_ERROR_ACTION` | `block` | 缺少依赖、调用失败、超时、空响应或无法解析时的行为 |

`AI_CHECK_FAIL_ACTION` 的可选值：

- `block`：显示风险详情，返回 1，阻止该包。
- `skip`：显示跳过及风险详情，返回 1，阻止该包。
- `warn`：显示风险详情，返回 0，允许安装。

`block` 和 `skip` 都通过非零退出码通知 paru 失败。是否继续构建其他包由 paru 的依赖关系和 `FailFast` 设置决定，钩子无法自行决定退出整个升级还是继续。

`AI_CHECK_ERROR_ACTION` 的可选值：

- `block`：返回 1，阻止未完成审查的包（默认）。
- `warn`：打印警告并返回 0，保留旧版出错时放行的行为。

无效配置始终返回 1，避免拼写错误导致静默放行。环境变量优先于配置文件：

```bash
AI_CHECK_ENABLED=false paru -Syu
AI_CHECK_FAIL_ACTION=block paru -Syu
AI_CHECK_ERROR_ACTION=warn paru -Syu
AI_CHECK_MODEL=xiaomi/mimo-v2.6-flash paru -Syu
```

`paru --skipreview` 只跳过 paru 自身的人工审阅流程，仍会执行 `PreBuildCommand`。临时跳过本工具请使用 `AI_CHECK_ENABLED=false`。

### 代理

可直接在运行 paru 时设置环境变量：

```bash
https_proxy=http://127.0.0.1:7890 http_proxy=http://127.0.0.1:7890 paru -Syu
```

或按 [paru 官方配置文档](https://github.com/Morganamilo/paru/blob/master/man/paru.conf.5)，在 paru 配置的 `[env]` 节设置：

```ini
[env]
https_proxy = http://127.0.0.1:7890
http_proxy = http://127.0.0.1:7890
```

## 审查流程

1. 从当前包目录读取 PKGBUILD、顶层 `*.install`，以及 `.SRCINFO` 中 `install = ...` 指向的本地脚本。不执行它们，不读取包目录外的安装脚本。
2. 根据审查内容、模型和审查器版本计算 SHA-256 缓存键。命中已通过的相同内容时跳过调用。
3. 在私有临时目录中运行 opencode，禁止工具调用，避免加载包目录提供的项目配置和指令。通过标准输入传入文本，支持超过单个命令行参数大小限制的 PKGBUILD。
4. 解析 `--format json` 中完成的助手文本；仅精确的 `PASS` 放行并缓存，`FAIL: <描述>` 按策略处理。推理文本、工具输出、错误事件、截断或矛盾结论均不作为通过依据。
5. 删除临时文件，记录审计日志。

主要检查远程脚本执行、无完整性校验的二进制执行、敏感文件修改、数据外泄和后门。正常源码下载、VCS 源使用 `SKIP`、缺少 PGP 公钥本身不判定为恶意。

审查范围限于提供的文本，不会下载并检查所有上游源码，也不会自动收集 PKGBUILD 动态计算出的任意文件路径；AI 结论不能保证包安全。人工审阅仍有必要。

## 日志与缓存

默认目录为 `~/.cache/ai-check-aur/`，遵循 `XDG_CACHE_HOME`：

```text
ai-check-aur/
├── cache       # 已通过的内容、模型和审查器摘要
└── audit.log   # PASS / FAIL / SKIP / ERROR
```

即使包名和版本相同，只要审查内容、模型或审查器发生变化，就会重新审查。旧版 `包名:版本` 缓存不会命中新格式。风险和错误不会写入通过缓存。

## 验证

离线集成测试通过模拟 opencode 和 sudo 验证审查及安装流程，不调用真实模型、不写入系统安装目录：

```bash
bash -n ai-check-pkgbuild install.sh
python3 -m unittest discover -s tests -v
```

测试依赖 Python 3；运行主程序不需要 Python。

## 卸载

```bash
sudo rm /usr/local/bin/ai-check-pkgbuild
# 如使用 --user 安装：rm ~/.local/bin/ai-check-pkgbuild
rm -rf "${XDG_CACHE_HOME:-$HOME/.cache}/ai-check-aur"
rm -rf "${XDG_CONFIG_HOME:-$HOME/.config}/ai-check-aur"
# 手动删除 paru 配置中的 PreBuildCommand 行
```
