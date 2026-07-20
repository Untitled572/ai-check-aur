# AUR PKGBUILD AI 审查工具 — 需求文档

## 1. 项目概述

利用 paru 的 `PreBuildCommand` 钩子，在构建/升级 AUR 包之前自动调用 opencode 免费 AI 模型审查 PKGBUILD，发现安全风险时阻止安装。

## 2. 实现原理

**入口：** `~/.config/paru/paru.conf` 的 `PreBuildCommand` 选项  
**配置项：** `~/.config/paru/paru.conf` 的 `[bin]` 节下 `PreBuildCommand`  
**钩子脚本：** `/usr/local/bin/ai-check-pkgbuild`  
**AI 模型：** `opencode/deepseek-v4-flash-free`  

paru 在构建每个 AUR 包前执行该脚本，并设置：

- 环境变量 `PKGBASE` → 包名
- 环境变量 `VERSION` → 版本号
- 当前工作目录 → 含 PKGBUILD 的目录

## 3. 脚本逻辑

```
ai-check-pkgbuild
├─ [1] 校验前置条件
│   ├─ opencode 可执行 → 否则放行并警告
│   ├─ PKGBUILD 可读   → 否则放行并警告
│   └─ 检查缓存 ~/.cache/ai-check-aur/cache
│       └─ $PKGBASE:$VERSION 已通过 → exit 0（跳过）
│
├─ [2] 读取 PKGBUILD 内容
│   content=$(cat PKGBUILD)
│
├─ [3] 调用 opencode
│   opencode run \
│     --model opencode/deepseek-v4-flash-free \
│     "审查以下 PKGBUILD..."
│
├─ [4] 解析输出
│   ├─ 输出含 "PASS"（忽略大小写）→ 写入缓存，exit 0
│   ├─ 输出含 "FAIL" 或 "失败" 或 "风险" → 打印警告，exit 1
│   └─ 异常（超时/无输出/格式错误）→ 放行，exit 0，日志记录
│
└─ [5] 日志
    写入 ~/.cache/ai-check-aur/audit.log
    格式: [时间] PKGBASE VERSION → PASS|FAIL|SKIP|ERROR [: 详情]
```

## 4. Prompt 模板（中文）

```
你是一个 Arch Linux 安全审查专家。请严格审查以下 PKGBUILD 文件是否存在安全风险。

检查要点（包括但不限于）：
1. source=() 中是否包含不可信 URL（如 pastebin、raw GitHub gist、短链接、未知 IP）
2. 是否在 build()/package() 中执行 curl/wget 并 pipe 到 shell
3. 是否下载并执行预编译的二进制文件且无完整性校验
4. validpgpkeys 是否缺失、过期、或与实际 source 不匹配
5. install 脚本是否包含危险的 post_install 操作（如修改系统文件、添加定时任务）
6. 是否有隐藏的后门代码（如向远程服务器发送数据、修改 ~/.ssh/authorized_keys 等）
7. 依赖是否包含可疑包

如果完全安全，只输出一行：PASS
如果发现任何风险，只输出一行：FAIL: <具体风险描述>

不要输出任何其他内容。

PKGBUILD：
```
${content}
```
```

## 5. 缓存机制

- **路径：** `~/.cache/ai-check-aur/cache`
- **格式：** 每行 `<pkgbase>:<version>`（已通过审查的记录）

## 6. 配置文件

配置文件 `config.env` 安装到 `~/.config/ai-check-aur/config.env`：

| 配置项 | 可选值 | 默认值 | 说明 |
|---|---|---|---|
| `AI_CHECK_ENABLED` | `true` / `false` | `true` | 是否启用审查 |
| `AI_CHECK_MODEL` | opencode 模型名 | `opencode/deepseek-v4-flash-free` | AI 模型 |
| `AI_CHECK_TIMEOUT` | 秒数 | `60` | 超时时间 |
| `AI_CHECK_FAIL_ACTION` | `block` / `skip` / `warn` | `block` | 失败后操作 |

### 失败操作

- **block**：显示风险详情，阻止安装（exit 1）
- **skip**：仅跳过该包，继续下一个（exit 1）
- **warn**：打印警告，允许安装（exit 0）

## 7. 安装与配置

安装脚本（`install.sh`）：
1. 复制主脚本到 `/usr/local/bin/`
2. 创建缓存目录 `~/.cache/ai-check-aur/`
3. 复制 `config.env` 到 `~/.config/ai-check-aur/config.env`
4. 在 `~/.config/paru/paru.conf` 中添加 `PreBuildCommand`

## 7. 边界情况处理

| 场景 | 行为 |
|------|------|
| `AI_CHECK_ENABLED=false` | 直接放行所有包 |
| opencode 未安装 | 放行，stderr 警告 |
| opencode API 错误 | 放行，记录 ERROR |
| AI 输出不含 PASS/FAIL | 放行，记录 UNPARSABLE |
| 缓存命中 | 直接 exit 0，记录 SKIP |
| 多个 AUR 包批量升级 | 每个包独立审查，互不影响 |
| 用户临时想跳过审查 | `paru --skipreview -Syu` |

## 8. 文件清单

```
ai-check-aur/
├── ai-check-pkgbuild    # 主脚本（可执行）
├── config.env           # 配置文件模板
├── install.sh           # 安装脚本
├── requirements.md      # 本需求文档
└── README.md            # 使用说明
```

## 9. 已知风险

- **PreBuildCommand 退出码行为未确认：** paru 官方手册未明确说明非零退出码是否会中止构建，需实际测试验证。若 paru 忽略退出码，需改为 wrapper 方案（用脚本包装 `paru` 命令代替原生命令）。
