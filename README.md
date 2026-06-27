# AUR PKGBUILD AI 审查工具

在 `paru -Syu` 构建每个 AUR 包之前，自动调用 opencode 免费 AI 模型审查 PKGBUILD，发现安全风险时阻止安装。

## 工作原理

```
paru -Syu
  └─ 下载 PKGBUILD
      └─ paru 调用 PreBuildCommand → ai-check-pkgbuild
          ├─ 读取 PKGBUILD
          ├─ 调用 opencode run --model opencode/deepseek-v4-flash-free
          ├─ PASS → 放行，写入缓存
          └─ FAIL → 打印风险详情，exit 1（阻止构建）
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
3. 在 `~/.config/paru/paru.conf` 中添加配置

## 配置

安装后 `~/.config/paru/paru.conf` 内容如下：

```ini
[options]
CleanAfter

[bin]
PreBuildCommand = ai-check-pkgbuild
```

### 切换 AI 模型

编辑 `/usr/local/bin/ai-check-pkgbuild`，修改 `MODEL` 变量：

```bash
MODEL="opencode/deepseek-v4-flash-free"
```

## 使用

不需要额外操作，正常执行 `paru -Syu` 即可。每个 AUR 包构建前会看到：

```
[ai-check] 正在审查 claude-code ...
[ai-check] claude-code: 通过审查
```

发现问题时：

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
| opencode 未安装 | 放行，stderr 警告 |
| API 调用失败/超时 | 放行，记录日志 |
| AI 返回无法解析 | 放行，记录日志 |
| 缓存命中 | 直接跳过 |

## 卸载

```bash
sudo rm /usr/local/bin/ai-check-pkgbuild
rm -rf ~/.cache/ai-check-aur
# 手动删除 paru.conf 中的 PreBuildCommand 行
```

## 文件结构

```
ai-check-aur/
├── ai-check-pkgbuild    # 主脚本
├── install.sh           # 安装脚本
├── requirements.md      # 需求文档
└── README.md            # 本文件
```
