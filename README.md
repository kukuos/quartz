# Obsidian 公网知识库

用 Obsidian 写作，Quartz 生成静态网站，部署在自己的服务器上。

**网站地址：** https://notes.231652.xyz

---

## 目录

- [一分钟上手](#一分钟上手)
- [整体架构](#整体架构)
- [目录说明](#目录说明)
- [写作规范](#写作规范)
- [发布](#发布)
- [服务器部署](#服务器部署)
- [Nginx 与 HTTPS](#nginx-与-https)
- [DNS 设置](#dns-设置)
- [回滚](#回滚)
- [升级 Quartz](#升级-quartz)
- [安全机制](#安全机制)
- [故障排查](#故障排查)

---

## 一分钟上手

1. 打开 Obsidian，在 **`公共/`** 文件夹里写笔记
2. 双击 **`发布到知识库.bat`**（或在本目录执行 `.\publish.ps1`）
3. 等待脚本跑完，访问 https://notes.231652.xyz

只有 `公共/` 里的内容会上网，其余笔记留在本地。

---

## 整体架构

```
Windows：C:\Users\Administrator\Documents\Obsidian Vault\公共\
                    │
                    │  publish.ps1
                    │  ├─ 扫描敏感信息（发现密钥就中止）
                    │  ├─ 追踪笔记引用的附件
                    │  └─ 镜像同步到 content/
                    ▼
            GitHub：kukuos/quartz（分支 v5）
                    │
                    │  publish.ps1 通过 SSH 触发
                    ▼
        服务器：/www/app/quartz  →  deploy.sh
                    │  ├─ git pull
                    │  ├─ Quartz build
                    │  ├─ 校验产物
                    │  └─ 原子切换（失败则保留旧站）
                    ▼
        /www/wwwroot/notes.231652.xyz  →  Nginx
                    ▼
            https://notes.231652.xyz
```

**为什么用 SSH 触发而不是 Webhook：** 个人知识库发布频率低，SSH 方式不需要在服务器上常驻 Web 服务、不需要管理密钥和公网端口，出问题时错误信息直接回显在本地终端。Webhook 更适合多人协作或高频提交的场景。

---

## 目录说明

### 本地（Windows）

| 路径 | 说明 |
| ---- | ---- |
| `C:\Users\Administrator\Documents\Obsidian Vault\` | 你的完整 Vault，**不会**整体上传 |
| `…\Obsidian Vault\公共\` | **只有这里的内容会发布到公网** |
| `…\Obsidian Vault\附件\` | Obsidian 默认附件目录，只有被公开笔记引用到的才会发布 |
| `C:\Users\Administrator\Documents\xm\Quartz-obsidian\` | Quartz 项目工作副本，脚本都在这里 |
| `…\Quartz-obsidian\content\` | 同步产物，**由脚本自动管理，不要手动编辑** |

> `content/` 每次发布都会被清空重建。要改内容请改 `公共/` 里的原始笔记。

### 服务器

| 路径 | 说明 |
| ---- | ---- |
| `/www/app/quartz/` | Quartz 项目与 node_modules |
| `/www/app/quartz/deploy.sh` | 部署脚本 |
| `/www/app/quartz/rollback.sh` | 回滚脚本 |
| `/www/app/quartz/logs/deploy.log` | 部署日志 |
| `/www/app/quartz/backups/` | 历史版本快照（硬链接，几乎不占空间） |
| `/www/wwwroot/notes.231652.xyz/` | 网站根目录，Nginx 只能访问这里 |
| `/www/wwwroot/notes.231652.xyz.prev/` | 上一版本，供快速回滚 |

源码、`node_modules`、`.git`、`package.json` 都在 `/www/app/quartz`，**不在** Nginx 可访问的路径下。

---

## 写作规范

### Frontmatter

全部字段都是可选的，不写也能正常发布。写了会更好看、更利于 SEO：

```yaml
---
title: Docker 部署教程          # 不写则用文件名
description: Docker 常用部署方法  # 不写则自动从正文首段提取
tags:
  - Docker
  - Linux
date: 2026-08-24
---
```

特殊字段：

| 字段 | 作用 |
| ---- | ---- |
| `draft: true` | 该篇不发布（写了一半的草稿用这个） |
| `aliases: [旧标题]` | 生成跳转页，改标题后旧链接不失效 |
| `allow-secrets: true` | 跳过整篇的敏感信息扫描（确认是误报时才用） |
| `password: xxx` | **加密整页**，访客需输入密码才能查看（见下方警告） |

> 你现有笔记里的 `status: draft` **不会**影响发布，只有 `draft: true` 才会。

#### ⚠ 关于 `password` 字段

frontmatter 里写 `password:` 会触发 `encrypted-pages` 插件，把整页内容加密，
页面上只剩一串密文和密码输入框。图片、视频也一起被加密，所以**页面看起来像是
内容丢失了**——如果发现某页变成空白或乱码，先检查是不是误留了这个字段。

更要紧的是：**密码是明文写在笔记里的，会随 `content/` 一起提交到 Git 仓库。**
目前仓库是公开的，等于密码和密文一起公开，加密形同虚设。

所以：

- 想真正保护内容，**别放进 `公共/`** ——这才是可靠的做法
- 要用页面加密，先把仓库改成私有（fork 无法直接转私有，需新建私有仓库）
- 别用真实密码，更别用你在其他地方也在用的密码

### 支持的语法

以下 Obsidian 语法都能正常渲染：

| 语法 | 示例 |
| ---- | ---- |
| WikiLink | `[[Docker]]` |
| 别名链接 | `[[Docker\|Docker 教程]]` |
| 图片嵌入 | `![[docker.png]]` |
| 笔记嵌入 | `![[某篇笔记]]` |
| 标准 Markdown 图片 | `![说明](./images/test.png)` |
| Callout | `> [!note] 提示` |
| 高亮 | `==重点==` |
| 数学公式 | `$E=mc^2$` |
| Mermaid 图表 | ` ```mermaid ` 代码块 |
| 表格、任务列表、脚注 | GitHub 风格 Markdown |

### 链接注意事项

`[[链接]]` 只能指向 **`公共/` 目录内**的笔记。指向外部笔记会变成死链，`publish.ps1` 会在发布时提示你：

```
! 3 处链接指向「公共」以外的笔记（这些笔记不会公开，链接将失效）
```

### 图片放哪

两种方式都可以，脚本会自动找到：

1. **直接在 Obsidian 里粘贴图片** —— 存进 `Vault/附件/`，脚本会自动追踪并同步（推荐）
2. **放在 `公共/` 内的子目录** —— 保持原有相对路径

无论哪种，**只有被公开笔记引用到的附件才会上传**，Vault 里其他图片不会外泄。

### 视频走单独通道

视频（`.mp4` `.webm` `.mov` `.avi` `.mkv` 等）**不进 Git**，由 `publish.ps1` 通过
SSH 直接传到服务器的媒体目录，再由 Nginx 单独映射。这和你 Vault `.gitignore` 里
「视频不入库，体积大难管理」的约定一致，也避开了 GitHub 单文件 100MB 的上限。

写笔记时不用管这些，照常 `![[演示视频.mp4]]` 就行，网站上会正常显示播放器，
也支持拖动进度条。发布时会看到：

```
✓ 发现 1 个视频，共 47.6 MB（不进 Git，稍后直接传服务器）
▶ 上传视频
    上传 演示视频.mp4（47.6 MB），大文件请耐心等待…
```

按文件大小做增量判断，**视频没换过就不会重复上传**。

| 位置 | 存放内容 |
| ---- | ---- |
| `/www/wwwroot/notes.231652.xyz-media/` | 视频（不在 Git 里） |
| `/www/wwwroot/notes.231652.xyz/` | 网页、图片等其余内容 |

> 服务器上删视频：直接删媒体目录里的文件即可。笔记里不再引用的视频不会自动清理，
> 想省空间就手动删。

### 网址规则

Quartz 5 会把文件名转成小写，网址不带 `.html`、不带尾部斜杠：

| 笔记 | 网址 |
| ---- | ---- |
| `公共/Docker.md` | `/docker` |
| `公共/中文标题测试.md` | `/中文标题测试` |
| `公共/教程/Nginx.md` | `/教程/nginx` |

大写写法（`/Docker`）会自动跳转到小写地址，旧链接不会失效。

---

## 发布

### 常规发布

双击 **`发布到知识库.bat`**，或者：

```powershell
cd C:\Users\Administrator\Documents\xm\Quartz-obsidian
.\publish.ps1
```

脚本会依次完成：扫描敏感信息 → 追踪附件 → 同步 → 显示变更清单 → 提交 → 推送 → 触发服务器构建。

**内容没有变化时不会产生空 commit**，会直接提示「内容没有变化，无需发布」。

### 参数

| 命令 | 用途 |
| ---- | ---- |
| `.\publish.ps1` | 完整发布 |
| `.\publish.ps1 -Message "新增 Docker 笔记"` | 自定义提交信息 |
| `.\publish.ps1 -DryRun` | 只预演，不做任何修改（想确认会发布哪些内容时用） |
| `.\publish.ps1 -NoDeploy` | 只推送到 GitHub，不触发服务器构建 |
| `.\publish.ps1 -SkipScan` | 跳过敏感信息扫描（确认是误报时才用） |

### 发布后自查

`verify.sh` 会跑 46 项检查，涵盖页面可访问、私人内容未泄露、WikiLink、图片、
中文支持、移动端、HTTPS 证书、SEO、敏感路径防护、缓存压缩：

```bash
ssh -i "C:\Users\Administrator\.ssh\root-tw_id_ed25519" root@43.212.212.75 \
    "bash /www/app/quartz/verify.sh"
```

证书还没就绪时可以只测 HTTP：`bash /www/app/quartz/verify.sh --http`

---

## 服务器部署

平时不需要手动操作，`publish.ps1` 会自动触发。需要手动执行时：

```bash
ssh -i "C:\Users\Administrator\.ssh\root-tw_id_ed25519" root@43.212.212.75
bash /www/app/quartz/deploy.sh
```

`deploy.sh` 的关键设计：

- **依赖不重复安装**：只有 `package-lock.json` 变化时才执行 `npm ci`，平时跳过
- **限制并发**：服务器内存约 1 GB，构建时用 `--concurrency=1` 避免 OOM
- **产物校验**：检查 `index.html` 是否存在、文件数是否正常、首页是否为空
- **原子切换**：构建到临时目录，校验通过后用 `mv` 瞬间替换，访客不会看到半新半旧的页面
- **失败保护**：构建失败时直接退出并清理临时目录，**线上网站原封不动继续服务**
- **并发锁**：同时触发多次部署时只会执行一个

查看日志：

```bash
tail -50 /www/app/quartz/logs/deploy.log
```

---

## Nginx 与 HTTPS

配置文件见本目录的 [`nginx.conf`](nginx.conf)，已针对本站点写好注释。

### 当前状态：已配置完成

站点已在宝塔面板建好，Let's Encrypt 证书已签发（有效期至 2026-11-22，
自动续期由宝塔管理），[`nginx.conf`](nginx.conf) 已应用到：

```
/www/server/panel/vhost/nginx/notes.231652.xyz.conf
```

每次修改配置前都会自动备份为 `.conf.bak-<时间戳>`，同目录下可以找到。

### 要改配置的话

在宝塔面板「站点设置 → 配置文件」里改，保存时面板会自动 `nginx -t` 并 reload；
报错就点「回退」。或者用命令行改完后：

```bash
nginx -t && nginx -s reload
```

### 配置里有两个 nginx 语法坑，改动时注意

1. **正则里出现 `{` `}` 必须用双引号把整个正则括起来**，否则 nginx 会把花括号
   当成配置块的括号，报 `unknown directive`：
   ```nginx
   location ~* "^/(index|component)-[0-9a-f]{6,}\.(js|css)$" {   # 引号不能省
   ```

2. **子块里一旦写了 `add_header`，父块的 `add_header` 就全部不再继承**。
   所以设置缓存时优先用 `expires` 指令；确实需要 `add_header` 的地方
   （比如 `immutable`），要把安全响应头重新写一遍。

### 另外两点说明

- **`charset_types` 不要写 `text/html`**：nginx 默认已包含，重复会产生告警。
- **响应头里的 `set-cookie: server_session_...`** 来自宝塔的全局模块，不是本
  站点配置产生的。纯静态站点其实不需要它，它还会降低 CDN 缓存效率。
  介意的话可以在宝塔面板里关掉相关模块，但那是全局设置，会影响服务器上
  其他 18 个站点，改前先确认。

### 配置要点

- HTTP 自动 301 跳转 HTTPS，但放行 `/.well-known/acme-challenge/`（证书续期需要）
- 带内容 hash 的 CSS/JS 缓存一年；HTML 不缓存，发布后立即可见
- `charset utf-8`，保证中文标题和中文文件名不乱码
- 拦截 `.git`、`node_modules`、`.env`、`.md`、源码等路径（第二道防线）

---

## DNS 设置

当前配置已生效，无需改动：

| 类型 | 主机记录 | 记录值 |
| ---- | -------- | ------ |
| A | `notes` | `43.212.212.75` |

**不要动根域名 `231652.xyz` 的记录。**

### 用 Cloudflare 的话，代理开不开？

| 模式 | 说明 |
| ---- | ---- |
| **DNS only**（灰色云朵）| 域名直接解析到服务器 IP。**当前就是这个模式，推荐保持。** |
| **Proxied**（橙色云朵）| 流量经 Cloudflare 中转 |

对这个纯静态知识库来说：

- **DNS only 的好处**：Let's Encrypt 的 HTTP-01 验证能直接通过；访问路径最短；调试时看到的就是真实情况
- **Proxied 的好处**：隐藏服务器真实 IP、免费 CDN 加速、抗 DDoS；缺点是必须把 Cloudflare 的 SSL 模式设为 **Full (strict)**，否则会出现重定向循环，另外证书续期要额外配置

建议先用 DNS only 把站点跑稳，之后想加速再切换到 Proxied。

---

## 回滚

### 回滚网站文件（最快）

```bash
ssh -i "C:\Users\Administrator\.ssh\root-tw_id_ed25519" root@43.212.212.75

bash /www/app/quartz/rollback.sh           # 回到上一版
bash /www/app/quartz/rollback.sh --list    # 查看所有可用版本
bash /www/app/quartz/rollback.sh 20260824-153000   # 回到指定快照
```

回滚是可逆的：再执行一次就切回刚才的版本。

### 回滚内容（连 Git 一起退回）

在 Windows 本地：

```powershell
cd C:\Users\Administrator\Documents\xm\Quartz-obsidian
git log --oneline -10          # 找到要退回的那次提交
git revert <commit-id>
git push origin v5
```

然后在服务器执行 `bash /www/app/quartz/deploy.sh`。

> 注意：`git revert` 只改 `content/`，不会动你 Vault 里的原始笔记。

---

## 升级 Quartz

Quartz 是从 `jackyzha0/quartz` fork 的，升级步骤：

```powershell
cd C:\Users\Administrator\Documents\xm\Quartz-obsidian

# 首次升级前先关联上游（只需执行一次）
git remote add upstream https://github.com/jackyzha0/quartz.git

git fetch upstream
git merge upstream/v5          # 上游对应分支
```

如果 `quartz.config.yaml` 有冲突，对照 `quartz.config.default.yaml` 的新版本手动合并——升级往往会引入新插件或新配置项。

然后：

```powershell
git push origin v5
```

服务器上执行部署，`deploy.sh` 检测到 `package-lock.json` 变化会自动执行 `npm ci`：

```bash
bash /www/app/quartz/deploy.sh
```

**建议先在本地预览确认无误再推送：**

```powershell
npm install          # 首次需要
npx quartz build --serve
# 浏览器打开 http://localhost:8080
```

---

## 安全机制

私人内容不外泄，靠这几层保障：

| 层级 | 机制 |
| ---- | ---- |
| 1. 范围控制 | 只同步 `公共/` 目录，Vault 其余内容脚本根本不读取 |
| 2. 附件白名单 | 只上传被公开笔记引用到的附件 |
| 3. 敏感扫描 | 发布前扫描，命中即中止，任何内容都不会进入 Git |
| 4. Git 兜底 | `.gitignore` 拦截 `.env`、`*.key`、`id_rsa` 等 |
| 5. 精确暂存 | 脚本只执行 `git add -- content`，**绝不 `git add .`** |
| 6. 构建过滤 | `ignorePatterns` 排除 `private`、`templates` 等目录 |
| 7. Nginx 隔离 | 站点目录只有构建产物，源码不在可访问路径下 |

### 扫描能识别的内容

私钥文件（`-----BEGIN ... PRIVATE KEY`）、AWS Access Key、GitHub Token / PAT、OpenAI / Anthropic Key、Slack Token、Google API Key、Stripe Key、JWT、Telegram Bot Token、数据库连接串内嵌密码、`api_key = "..."` 形式的赋值、`密码：xxx` 形式的中文记录，以及 `.env`、`*.pem`、`id_rsa` 等危险文件名。

命中时会显示文件名和行号，并且**只显示片段不显示完整密钥**：

```
✗ 发现 2 处疑似敏感信息，已阻止发布：

    [AWS Access Key] 服务器笔记.md:10
        > AKIAIOSFODNN7EXAMPLE
    [中文密码记录] 服务器笔记.md:16
        > 密码：Hunter2Password
```

### 误报了怎么办

| 情况 | 处理 |
| ---- | ---- |
| 单行误报 | 该行末尾加 `publish-ignore-secret` |
| 整篇误报 | frontmatter 加 `allow-secrets: true` |
| 临时跳过 | `.\publish.ps1 -SkipScan` |
| **真的是密钥** | 从 `公共/` 移出，**并立即吊销该密钥** |

---

## 故障排查

### 网站打不开

```bash
# 1. 服务器是否在线
ping 43.212.212.75

# 2. Nginx 是否运行
ssh -i "C:\Users\Administrator\.ssh\root-tw_id_ed25519" root@43.212.212.75
systemctl status nginx
nginx -t

# 3. 站点目录是否有文件
ls /www/wwwroot/notes.231652.xyz/index.html

# 4. 看错误日志
tail -50 /www/wwwlogs/notes.231652.xyz.error.log
```

若站点目录为空，重新部署：`bash /www/app/quartz/deploy.sh`

### HTTPS 证书申请失败

| 原因 | 排查 |
| ---- | ---- |
| DNS 未生效 | `nslookup notes.231652.xyz` 应返回 `43.212.212.75` |
| 80 端口不通 | 检查云服务商安全组、宝塔面板防火墙是否放行 80 |
| Cloudflare 代理开着 | 临时切回 **DNS only** 再申请 |
| ACME 验证被拦截 | 确认 Nginx 放行 `/.well-known/acme-challenge/` |
| 申请太频繁 | Let's Encrypt 每域名每周 5 次上限，等一小时再试 |

证书到期时间：

```bash
echo | openssl s_client -connect notes.231652.xyz:443 -servername notes.231652.xyz 2>/dev/null | openssl x509 -noout -dates
```

### Quartz 构建失败

```bash
tail -80 /www/app/quartz/logs/deploy.log
```

**此时网站仍是旧版本，正常访问不受影响。**

手动复现错误：

```bash
cd /www/app/quartz
npx quartz build -d content -o /tmp/testbuild --concurrency=1
```

常见原因：

| 现象 | 原因与处理 |
| ---- | ---- |
| `JavaScript heap out of memory` | 内存不足。确认用了 `--concurrency=1`；笔记很多时可临时扩大 swap |
| YAML 解析错误 | 某篇笔记的 frontmatter 格式有问题，报错信息里有文件名。注意中文冒号 `：` 不能当分隔符 |
| 插件加载失败 | 执行 `npm ci` 重装依赖 |
| 磁盘写满 | `df -h`，服务器根分区当前使用率较高，注意清理 |

### Git 同步失败

**推送被拒绝**（远程有本地没有的提交）：

```powershell
cd C:\Users\Administrator\Documents\xm\Quartz-obsidian
git pull --rebase origin v5
.\publish.ps1
```

**服务器 pull 失败**（本地有改动）：

```bash
cd /www/app/quartz
git status
git checkout -- package.json package-lock.json   # deploy.sh 已自动处理这两个文件
```

**GitHub 认证失败**：用 Git Credential Manager 重新登录，或改用 SSH 方式的 remote。

### 图片不显示

1. 确认发布时脚本报告的附件数量不是 0
2. 检查是否有「引用找不到对应文件」的警告——通常是文件名拼写不一致（**注意大小写**，Linux 区分大小写）
3. 确认图片确实在 Vault 里：文件名改过但笔记里的引用没更新是最常见的原因
4. 服务器上确认：
   ```bash
   ls /www/wwwroot/notes.231652.xyz/附件/
   ```
5. 浏览器按 F12 看 Network 面板，确认图片请求返回 404 还是 403

### WikiLink 不生效 / 显示成纯文本

1. **链接指向了 `公共/` 之外的笔记** —— 最常见原因。发布时脚本会警告，把目标笔记也移进 `公共/` 即可
2. 文件名拼写不一致（大小写、空格、全角半角）
3. 同名笔记有多篇，`shortest` 模式无法确定目标 —— 改用带路径的写法 `[[目录/笔记名]]`

### 中文搜索搜不到预期结果

这是 Quartz 上游的限制，不是配置问题，说明一下原理以便理解它的边界。

搜索用的是 FlexSearch，分词规则为「按非字母数字字符切分 + 前缀匹配」。
中文汉字都属于「字母」类，中间又没有空格，所以**一整段连续的中文会被当成
一个词**，只能从头开始匹配：

| 笔记里的内容 | 搜「Docker」 | 搜「部署」 |
| ---- | ---- | ---- |
| `Docker部署教程`（连写） | ✓ 命中 | ✗ 搜不到 |
| `Docker 部署教程`（有空格） | ✓ 命中 | ✓ 命中 |

实际影响没有想象中大——中文写作里逗号、句号、空格本来就很多，
被切出的词不会太长。想让搜索更好用可以：

- 标题和小标题里适当用空格或标点分隔关键词
- 在 frontmatter 的 `tags` 和 `aliases` 里补上常用检索词，这些字段同样进索引
- 需要精确检索时，用浏览器的页内查找（`Ctrl + F`）

要彻底解决需要引入中文分词（如 jieba）并改造搜索插件，属于较大改动，
且会明显增加索引体积，个人知识库一般不值得。

### Nginx 报 404

- 检查网址形式：应该是 `/docker` 而不是 `/docker.html` 或 `/Docker/`
- 确认文件存在：`ls /www/wwwroot/notes.231652.xyz/` （文件名是小写的）
- 确认站点根目录配置正确指向 `/www/wwwroot/notes.231652.xyz`

### Nginx 报 502

静态站点正常不会出现 502。若出现，通常是宝塔把站点误配成了 PHP 或反向代理模式 —— 在面板里确认站点类型是**纯静态**，且配置里没有 `proxy_pass` 或 `fastcgi_pass`。

### DNS 不生效

```bash
nslookup notes.231652.xyz 8.8.8.8
nslookup notes.231652.xyz 223.5.5.5
```

- 修改 DNS 后需等待 TTL 过期（通常 10 分钟到 2 小时）
- Windows 刷新本地缓存：`ipconfig /flushdns`
- 确认添加的是 **A 记录**，主机记录填 `notes` 而不是完整域名

### 双击 .bat 后窗口一闪而过

已修复，原因记录在此以免以后改动时踩回去。

`发布到知识库.bat` **必须保持纯 ASCII，不要在里面加中文**。cmd.exe 读取 .bat
时用的是系统 ANSI 代码页（中文 Windows 上是 GBK），而文件存的是 UTF-8——
一个中文字占 3 字节，解析时会错位并吞掉后面的字符：

```
-NoProfile        被读成  -Profile
notes.231652.xyz  被读成  otes.231652.xyz
```

PowerShell 因为参数非法直接启动失败，窗口一闪就没了。`chcp 65001` 只改控制台
输出代码页，救不了 cmd 读取文件的方式。

所有中文提示都由 `publish.ps1` 输出（PowerShell 能正确处理 UTF-8），
`.bat` 只负责调用并在结尾 `pause`。

### 页面变成空白或一串乱码

多半是 frontmatter 里留了 `password:` 字段，整页被加密了。
删掉该字段重新发布即可。详见上面「关于 `password` 字段」。

### 发布了但网站没更新

1. 浏览器强制刷新：`Ctrl + F5`
2. 确认部署真的成功：`tail -20 /www/app/quartz/logs/deploy.log`
3. 确认笔记在 `公共/` 目录内
4. 确认 frontmatter 里没写 `draft: true`
5. 手机上看不到更新时，尝试无痕模式排除缓存

---

## 附录：清理验收测试文件

搭建时创建了几个测试文件，确认网站一切正常后可以删掉。它们都留在原地
没有自动删除，因为在 Vault 里删文件应该由你决定。

| 文件 | 作用 |
| ---- | ---- |
| `Obsidian Vault\公共\Test.md` | 验证 WikiLink、图片、Callout、代码块 |
| `Obsidian Vault\公共\中文标题测试.md` | 验证中文标题、中文 URL、中文标签 |
| `Obsidian Vault\私人测试\Test Private.md` | 验证私人内容不外泄 |
| `Obsidian Vault\附件\test.png` | 测试用图片（是已有图片的副本） |

在 Obsidian 里直接删除前三个，然后执行 `.\publish.ps1`，网站上对应页面就会消失
（`content/` 是镜像同步的，Vault 里删掉的笔记网站上也会删掉）。

> `verify.sh` 的部分检查依赖 `Test.md` 和 `test.png`，删除后重跑会有几项失败，
> 这是正常的——那时它的价值主要在证书、SEO、敏感路径防护这些与内容无关的检查上。

保留 `公共\index.md` 作为网站首页。

---

## 相关链接

- [Quartz 官方文档](https://quartz.jzhao.xyz)
- [Quartz 上游仓库](https://github.com/jackyzha0/quartz)
- [本项目仓库](https://github.com/kukuos/quartz)
