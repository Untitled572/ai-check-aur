# AUR PKGBUILD AI 审查工具

在 `paru -Syu` 构建每个 AUR 包之前，自动调用 opencode 免费 AI 模型审查 PKGBUILD，发现安全风险时阻止安装。

## 工作原理

```
paru -Syu
  └─ 下载 PKGBUILD
      └─ paru 调用 PreBuildCommand → ai-check-pkgbuild
          ├─ 读取配置 ~/.config/ai-check-aur/config.env
          ├─ 读取 PKGBUILD
          ├─ 调用 opencode run --model <配置的模型>
          ├─ PASS → 放行，写入缓存
          └─ FAIL → 按配置操作（block/skip/warn）
```

## 前置条件

- Arch Linux（已安装 paru）
- [opencode](https://opencode.ai)（已安装，v1.17+）
- opencode 已配置可用的 free 模型（默认 `opencode/deepseek-v4-flash-free`）

## 安装

```bash
git clone <项目地址> && cd ai-check-aur
sudo ./install.sh
```

安装脚本会自动：
1. 复制 `ai-check-pkgbuild` 到 `/usr/local/bin/`
2. 创建缓存目录 `~/.cache/ai-check-aur/`
3. 在 `~/.config/ai-check-aur/` 安装配置文件
4. 在 `~/.config/paru/paru.conf` 中添加配置

## 配置

配置文件位于 `~/.config/ai-check-aur/config.env`：

```bash
# 是否启用审查（true/false）
AI_CHECK_ENABLED=true

# 使用的模型
AI_CHECK_MODEL="opencode/deepseek-v4-flash-free"

# 超时时间（秒）
AI_CHECK_TIMEOUT=60

# 审查失败后操作
# block = 显示风险详情，阻止安装（exit 1）
# skip  = 仅跳过该包，继续下一个（exit 1）
# warn  = 打印警告，允许安装（exit 0）
AI_CHECK_FAIL_ACTION=skip
```

### 配置项说明

| 项 | 可选值 | 默认值 | 说明 |
|---|---|---|---|
| `AI_CHECK_ENABLED` | `true` / `false` | `true` | 设为 false 可全局禁用审查 |
| `AI_CHECK_MODEL` | opencode 模型名 | `opencode/deepseek-v4-flash-free` | AI 模型 |
| `AI_CHECK_TIMEOUT` | 秒数 | `60` | 单次审查超时时间 |
| `AI_CHECK_FAIL_ACTION` | `block` / `skip` / `warn` | `skip` | 失败后操作 |

### 失败操作说明

- **block**：显示完整风险详情，阻止该包安装（exit 1）
- **skip**：仅显示 `[ai-check] 已跳过: <包名>`，继续处理下一个包（exit 1）
- **warn**：打印警告信息，但允许继续安装（exit 0）

### 可用模型

- `opencode/deepseek-v4-flash-free`
- `opencode/mimo-v2.5-free`
- `opencode/nemotron-3-ultra-free`
- `opencode/north-mini-code-free`
- `opencode/big-pickle`

### 代理配置

在 `~/.config/paru/paru.conf` 的 `[bin]` 节添加：

```ini
[bin]
PreBuildCommand = ai-check-pkgbuild
env = https_proxy=http://127.0.0.1:7890
env = http_proxy=http://127.0.0.1:7890
```

### 环境变量优先级

环境变量优先于配置文件。可以临时覆盖配置：

```bash
AI_CHECK_ENABLED=false paru -Syu          # 临时禁用审查
AI_CHECK_FAIL_ACTION=block paru -Syu      # 临时切换为阻止模式
AI_CHECK_MODEL=opencode/deepseek-v4-flash-free paru -Syu  # 临时切换模型
```

## 使用

正常执行 `paru -Syu` 即可。每个 AUR 包构建前会看到：

```
[ai-check] 正在审查 claude-code ...
[ai-check] claude-code: 通过审查
```

发现问题时（取决于 `AI_CHECK_FAIL_ACTION` 设置）：

```
[ai-check] 发现安全风险: malicious-tool
────────────────────────────────────────────
FAIL: source 使用了不可信的 pastebin 链接...
────────────────────────────────────────────
```

临时跳过审查：

```bash
paru --skipreview -Syu
```

## 审查要点

1. `source=()` 中是否包含不可信 URL（pastebin、raw gist、短链接、未知 IP）
2. 是否在 `build()`/`package()` 中执行 `curl | bash`
3. 是否下载并执行预编译二进制且无完整性校验
4. `validpgpkeys` 是否缺失或可疑
5. `install` 脚本是否包含危险操作（修改系统文件、添加后门）
6. 隐藏后门代码（外联、修改 authorized_keys 等）
7. 依赖是否包含可疑包

## 日志与缓存

```
~/.cache/ai-check-aur/
├── cache       # 已通过审查的包列表（pkgbase:version）
└── audit.log   # 审计日志（PASS/FAIL/SKIP/ERROR）
```

缓存按 `包名:版本号` 精确匹配，同一轮升级中重复的包自动跳过 AI 调用。

## 边界情况

| 场景 | 行为 |
|------|------|
| `AI_CHECK_ENABLED=false` | 直接放行所有包 |
| opencode 未安装 | 放行，stderr 警告 |
| API 调用失败/超时 | 放行，记录日志 |
| AI 返回无法解析 | 放行，记录日志 |
| 缓存命中 | 直接跳过 |

## 卸载

```bash
sudo rm /usr/local/bin/ai-check-pkgbuild
rm -rf ~/.cache/ai-check-aur
rm -rf ~/.config/ai-check-aur
# 手动删除 paru.conf 中的 PreBuildCommand 行
```

## 文件结构

```
ai-check-aur/
├── ai-check-pkgbuild    # 主脚本
├── config.env           # 默认配置模板
├── install.sh           # 安装脚本
├── requirements.md      # 需求文档
└── README.md            # 本文件
```
