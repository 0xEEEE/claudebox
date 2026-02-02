# Vendor Scripts Manifest

本目录包含所有第三方安装脚本的本地副本，用于防止供应链攻击。

**最后更新**: 2026-01-28
**审计状态**: 已完成全面审计 (构建时无网络请求)

---

## 安全策略

1. **本地化**: 所有远程脚本下载到本地，不再运行时从网络获取
2. **完整性验证**: 使用SHA256校验确保脚本未被篡改
3. **版本锁定**: 记录每个脚本的确切版本
4. **审计要求**: 更新任何脚本前必须进行安全审计
5. **构建隔离**: Docker构建阶段所有依赖均从本地读取（apt除外）

---

## System Assets (系统级依赖)

| 文件 | 来源 | 版本 | 用途 |
|-----|-----|-----|-----|
| `base/system-assets/githubcli-archive-keyring.gpg` | [GitHub CLI](https://cli.github.com) | 2026-01-28 | GitHub CLI APT仓库GPG密钥 |
| `base/system-assets/git-delta_0.17.0_amd64.deb` | [dandavison/delta](https://github.com/dandavison/delta) | 0.17.0 | Git diff工具 (amd64) |
| `base/system-assets/git-delta_0.17.0_arm64.deb` | [dandavison/delta](https://github.com/dandavison/delta) | 0.17.0 | Git diff工具 (arm64) |

---

## Base Scripts (Dockerfile使用)

| 脚本 | 来源 | 固定版本 | 校验和验证 | 用途 |
|-----|-----|---------|-----------|-----|
| `base/zsh-setup-local.sh` | 自定义 (本地化) | N/A | ✅ 脚本校验 | 安装zsh+oh-my-zsh (无网络请求) |
| `base/zsh-assets/ohmyzsh.tar.gz` | [ohmyzsh/ohmyzsh](https://github.com/ohmyzsh/ohmyzsh) | master | ✅ 脚本校验 | Oh-My-Zsh 框架 |
| `base/zsh-assets/powerlevel10k.tar.gz` | [romkatv/powerlevel10k](https://github.com/romkatv/powerlevel10k) | v1.20.0 | ✅ 脚本校验 | Powerlevel10k 主题 |
| `base/uv-install.sh` | [astral.sh](https://astral.sh/uv) | **0.9.26** | ✅ 脚本+二进制 | 安装uv Python包管理器 |
| `base/claude-install.sh` | [claude.ai](https://claude.ai/install.sh) | **2.1.22** | ✅ 脚本+二进制 | 安装Claude Code CLI (native) |

### 版本锁定说明

**claude-install.sh** 和 **uv-install.sh** 已进行版本锁定和校验和硬编码：

1. **固定版本号**: 不再动态获取最新版本，而是使用硬编码的版本号
2. **硬编码校验和**: 各平台的 SHA256 校验和直接写入脚本中
3. **双重验证**: 脚本本身通过 `checksums-base.sha256` 验证，下载的二进制通过内嵌校验和验证

更新步骤：
```bash
# 更新 Claude Code
1. 获取新版本: curl -fsSL "$GCS_BUCKET/latest"
2. 获取 manifest: curl -fsSL "$GCS_BUCKET/$VERSION/manifest.json"
3. 更新 claude-install.sh 中的 PINNED_VERSION 和 CHECKSUMS
4. 重新生成 checksums-base.sha256

# 更新 uv
1. 查看 GitHub releases: https://github.com/astral-sh/uv/releases
2. 下载各平台 .sha256 文件
3. 更新 uv-install.sh 中的 APP_VERSION 和各 case 分支的 _checksum_value
4. 重新生成 checksums-base.sha256
```

---

## Profile Scripts (开发环境Profile使用)

| 脚本 | 来源 | 版本 | 用途 | 网络依赖 |
|-----|-----|-----|-----|----------|
| `profiles/rustup.sh` | [rustup.rs](https://rustup.rs) | 2026-01-28 | 安装Rust工具链 | 运行时下载工具链 |
| `profiles/fvm-install.sh` | [fvm.app](https://fvm.app) | 2026-01-28 | 安装Flutter Version Manager | 运行时下载Flutter SDK |
| `profiles/nvm-install.sh` | [nvm-sh/nvm](https://github.com/nvm-sh/nvm) | v0.39.3 | 安装Node Version Manager | 运行时下载Node.js |
| `profiles/sdkman-install.sh` | [sdkman.io](https://sdkman.io) | 2026-01-28 | 安装SDKMAN (Java工具管理) | 运行时下载Java SDK |

**注意**: Profile脚本本身已本地化，但它们安装的工具（Rust/Flutter/Node/Java）仍需网络下载。这是工具链安装的固有行为。

---

## 校验文件

- `checksums-base.sha256` - Base脚本和assets的SHA256校验和
- `checksums-profiles.sha256` - Profile脚本的SHA256校验和
- `checksums-system.sha256` - 系统级assets的SHA256校验和（GPG密钥、.deb包）

### 验证命令

```bash
# 使用管理工具验证
./scripts/vendor-update.sh verify

# 手动验证 (从 vendor/scripts/base 目录)
cd vendor/scripts/base
sha256sum -c ../checksums-base.sha256     # 验证 base 脚本
sha256sum -c ../checksums-system.sha256   # 验证 system assets

# 验证 profiles 脚本 (从 vendor/scripts/profiles 目录)
cd vendor/scripts/profiles
sha256sum -c ../checksums-profiles.sha256
```

**注意**: 路径设计与 Docker 构建上下文一致，确保 Docker 构建时验证有效。

---

## 管理工具

使用 `scripts/vendor-update.sh` 管理 vendor 脚本：

```bash
# 验证所有校验和
./scripts/vendor-update.sh verify

# 列出所有 vendor 脚本
./scripts/vendor-update.sh list

# 更新特定脚本（会显示diff并要求确认）
./scripts/vendor-update.sh update profiles/rustup.sh

# 对脚本进行安全审计
./scripts/vendor-update.sh audit base/nvm-install.sh

# 重新生成校验和文件
./scripts/vendor-update.sh regenerate
```

---

## 更新流程

### 1. 下载新版本

```bash
./scripts/vendor-update.sh update <script-path>
```

### 2. 安全审计

```bash
# 使用内置审计工具
./scripts/vendor-update.sh audit <script-path>

# 手动审计检查清单：
# - 检查是否有可疑的网络请求
# - 检查是否有不必要的权限提升
# - 检查是否有混淆代码
# - 对比与上一版本的差异
```

### 3. 更新校验和

更新脚本后，管理工具会自动重新生成校验和。

### 4. 更新本文档

- 更新版本号
- 更新"最后更新"日期
- 记录审计结果

---

## 审计清单

更新脚本时需检查：

- [ ] 无硬编码的恶意URL
- [ ] 无可疑的数据外发
- [ ] 无不必要的权限提升(sudo/root)
- [ ] 无混淆或编码的代码段
- [ ] 无可疑的环境变量读取
- [ ] 网络请求都指向官方域名
- [ ] 无后门或反弹shell
- [ ] 无 `curl|sh` 或 `wget|bash` 模式

---

## 已知风险与网络依赖

### Docker构建时 (已消除)

✅ **构建阶段无网络依赖** (除apt外)
- GitHub CLI GPG密钥: 已本地化
- git-delta: 已本地化 (.deb包)
- Oh-My-Zsh: 已本地化 (tarball)
- Powerlevel10k: 已本地化 (tarball)
- Claude Code: 已本地化 (安装脚本，运行时自动更新)
- uv: 已本地化 (安装脚本)

### 运行时网络依赖 (Profile选择时)

以下是Profile安装器的固有行为，无法完全离线：

1. **Rust Profile**: `rustup.sh`运行时会从官方服务器下载Rust工具链
2. **Flutter Profile**: `fvm-install.sh`运行时会下载Flutter SDK
3. **Node.js Profile**: `nvm-install.sh`运行时会下载Node.js版本
4. **Java Profile**: `sdkman-install.sh`运行时会下载Java SDK
5. **Go Profile**: 直接从golang.org下载Go SDK (约100MB)

### claudebox自更新

`claudebox update all`命令会从GitHub下载更新：
- 来源: https://github.com/RchGrav/claudebox
- 已添加安全警告和用户确认
- 建议：手动更新并验证后再执行

### 缓解措施

如需完全离线构建：
1. 预下载所有SDK到内部镜像服务器
2. 配置Profile使用内部镜像
3. 或在有网络环境构建后导出镜像

---

## Docker构建中的验证

在Dockerfile中，所有外部依赖执行前会进行校验和验证：

```dockerfile
# 1. 系统级资源验证（GPG密钥、.deb包）
COPY vendor/scripts/base/system-assets /tmp/system-assets
COPY vendor/scripts/checksums-system.sha256 /tmp/checksums-system.sha256
RUN cd /tmp && sha256sum -c checksums-system.sha256

# 2. Base脚本和assets验证
COPY vendor/scripts/base/zsh-setup-local.sh /tmp/zsh-setup-local.sh
COPY vendor/scripts/base/zsh-assets /tmp/zsh-assets
COPY vendor/scripts/base/uv-install.sh /tmp/uv-install.sh
COPY vendor/scripts/base/claude-install.sh /tmp/claude-install.sh
COPY vendor/scripts/checksums-base.sha256 /tmp/checksums-base.sha256
RUN cd /tmp && sha256sum -c checksums-base.sha256 --ignore-missing

# 3. 验证通过后执行
RUN sh /tmp/zsh-setup-local.sh ...
RUN sh /tmp/uv-install.sh
RUN bash /tmp/claude-install.sh
```

如果任何校验和验证失败，构建将**立即中止**，防止执行被篡改的文件。

---

## 安全事件响应

如果发现脚本被篡改或存在安全问题：

1. **立即停止使用**：暂停所有使用该脚本的构建
2. **调查来源**：确认篡改是否来自上游还是本地
3. **回滚版本**：恢复到已知安全的版本
4. **通知用户**：如果影响到已分发的镜像，通知用户重建
5. **更新校验和**：确保新的安全版本校验和已更新
