<#
.SYNOPSIS
    把 Obsidian Vault 中「公共」目录的笔记发布到 https://notes.231652.xyz

.DESCRIPTION
    执行流程：
      1. 扫描敏感信息（发现疑似密钥/令牌/密码则中止发布）
      2. 追踪笔记引用的附件，只同步被引用到的附件
      3. 镜像同步 公共/ -> content/（Vault 里删掉的笔记，网站上也会消失）
      4. 有变更才 git commit + push（无变更不产生空 commit）
      5. SSH 触发服务器 deploy.sh 重新构建

.PARAMETER Message
    自定义 commit 信息。不填则自动生成。

.PARAMETER DryRun
    只做检查和同步预览，不写入 content/、不 commit、不部署。

.PARAMETER NoDeploy
    提交并推送，但不触发服务器部署。

.PARAMETER SkipScan
    跳过敏感信息扫描。仅在确认是误报时使用。

.EXAMPLE
    .\publish.ps1
    .\publish.ps1 -Message "新增 Docker 笔记"
    .\publish.ps1 -DryRun
#>

[CmdletBinding()]
param(
    [string]$Message,
    [switch]$DryRun,
    [switch]$NoDeploy,
    [switch]$SkipScan
)

# ===================== 配置区（按需修改） =====================
$VaultPath    = 'C:\Users\Administrator\Documents\Obsidian Vault'
$PublicDir    = '公共'                  # Vault 中作为公开范围的目录名
$AttachDirName= '附件'                  # 同步到 content/ 后附件存放的目录名
$QuartzRepo   = $PSScriptRoot           # 本脚本所在目录 = Quartz 工作副本
$SshKey       = 'C:\Users\Administrator\.ssh\root-tw_id_ed25519'
$SshTarget    = 'root@43.212.212.75'
$RemoteDeploy = '/www/app/quartz/deploy.sh'
$SiteUrl      = 'https://notes.231652.xyz'
# =============================================================

$ErrorActionPreference = 'Stop'
# 保证中文在控制台正常显示
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
$OutputEncoding = [Text.Encoding]::UTF8

# ---------- 输出辅助 ----------
function Write-Step  { param($m) Write-Host "`n▶ $m" -ForegroundColor Cyan }
function Write-Ok    { param($m) Write-Host "  ✓ $m" -ForegroundColor Green }
function Write-Warn2 { param($m) Write-Host "  ! $m" -ForegroundColor Yellow }
function Write-Err   { param($m) Write-Host "  ✗ $m" -ForegroundColor Red }
function Write-Info  { param($m) Write-Host "    $m" -ForegroundColor DarkGray }

# 双击 .bat 运行时暂停，让用户看清结果；非交互环境下静默跳过
function Wait-Exit {
    if ($env:CI) { return }
    try { Read-Host '按回车键退出' | Out-Null } catch { }
}

function Abort {
    param($m)
    Write-Host ''
    Write-Host "═══════════════════════════════════════════" -ForegroundColor Red
    Write-Host " 发布已中止：$m" -ForegroundColor Red
    Write-Host "═══════════════════════════════════════════" -ForegroundColor Red
    Write-Host ''
    Wait-Exit
    exit 1
}

Write-Host ''
Write-Host '╔═══════════════════════════════════════════╗' -ForegroundColor Magenta
Write-Host '║   发布到知识库  notes.231652.xyz          ║' -ForegroundColor Magenta
Write-Host '╚═══════════════════════════════════════════╝' -ForegroundColor Magenta

# ===================== 1. 前置检查 =====================
Write-Step '环境检查'

$PublicPath = Join-Path $VaultPath $PublicDir
if (-not (Test-Path -LiteralPath $VaultPath))  { Abort "找不到 Obsidian Vault：$VaultPath" }
if (-not (Test-Path -LiteralPath $PublicPath)) { Abort "找不到公开目录：$PublicPath`n     请先在 Obsidian 里创建「$PublicDir」文件夹。" }

$ContentPath = Join-Path $QuartzRepo 'content'
if (-not (Test-Path -LiteralPath (Join-Path $QuartzRepo 'quartz.config.yaml'))) {
    Abort "当前目录不是 Quartz 项目（缺少 quartz.config.yaml）：$QuartzRepo"
}
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Abort ' 未找到 git 命令' }

Write-Ok "Vault：$VaultPath"
Write-Ok "公开目录：$PublicDir"
Write-Ok "Quartz：$QuartzRepo"

# 收集公开目录下的 Markdown
$mdFiles = @(Get-ChildItem -LiteralPath $PublicPath -Recurse -File -Filter '*.md' -ErrorAction SilentlyContinue)
if ($mdFiles.Count -eq 0) {
    Abort "「$PublicDir」目录里没有任何 .md 笔记，没有内容可发布。"
}
Write-Ok "找到 $($mdFiles.Count) 篇笔记"

# ===================== 2. 敏感信息扫描 =====================
# 这是发布前最后一道防线。命中即中止，不会有任何内容进入 git。
$secretHits = @()

if ($SkipScan) {
    Write-Step '敏感信息扫描'
    Write-Warn2 '已通过 -SkipScan 跳过扫描（请确认内容安全）'
} else {
    Write-Step '敏感信息扫描'

    # --- 2a. 危险文件名 ---
    # 这些文件不该出现在公开目录，无论内容是什么。
    $badNamePatterns = @(
        '\.env($|\.)', '\.pem$', '\.key$', '\.pfx$', '\.p12$', '\.ppk$',
        '\.keystore$', '\.jks$', '^id_rsa', '^id_ed25519', '^id_ecdsa',
        '^\.htpasswd$', '^credentials$', '^\.npmrc$', '^\.netrc$',
        'secrets?\.(ya?ml|json|txt)$', '\.kdbx$'
    )
    $allPublicFiles = @(Get-ChildItem -LiteralPath $PublicPath -Recurse -File -Force -ErrorAction SilentlyContinue)
    foreach ($f in $allPublicFiles) {
        foreach ($pat in $badNamePatterns) {
            if ($f.Name -match $pat) {
                $rel = $f.FullName.Substring($PublicPath.Length).TrimStart('\')
                $secretHits += [pscustomobject]@{
                    File = $rel; Line = 0; Kind = '危险文件名'; Sample = $f.Name
                }
                break
            }
        }
    }

    # --- 2b. 文件内容正则 ---
    # 每条规则尽量收紧，降低误报；确实误报时可用 -SkipScan 或豁免标记。
    $rules = @(
        @{ Kind = '私钥文件内容'; Re = '-----BEGIN\s+(RSA|DSA|EC|OPENSSH|PGP|ENCRYPTED)?\s*PRIVATE KEY' }
        @{ Kind = 'AWS Access Key'; Re = '\b(AKIA|ASIA)[0-9A-Z]{16}\b' }
        @{ Kind = 'GitHub Token'; Re = '\bgh[pousr]_[A-Za-z0-9]{30,}\b' }
        @{ Kind = 'GitHub PAT(细粒度)'; Re = '\bgithub_pat_[A-Za-z0-9_]{50,}\b' }
        @{ Kind = 'OpenAI/Anthropic Key'; Re = '\bsk-(ant-)?[A-Za-z0-9_\-]{24,}\b' }
        @{ Kind = 'Slack Token'; Re = '\bxox[baprs]-[A-Za-z0-9\-]{10,}\b' }
        @{ Kind = 'Google API Key'; Re = '\bAIza[0-9A-Za-z_\-]{35}\b' }
        @{ Kind = 'Stripe Key'; Re = '\b[sr]k_(live|test)_[A-Za-z0-9]{20,}\b' }
        @{ Kind = 'JWT'; Re = '\beyJ[A-Za-z0-9_\-]{10,}\.eyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}' }
        @{ Kind = 'Telegram Bot Token'; Re = '\b\d{8,10}:AA[A-Za-z0-9_\-]{32,}\b' }
        @{ Kind = '连接串内嵌密码'; Re = '(mysql|postgres(ql)?|mongodb(\+srv)?|redis|amqp|ftp|ssh)://[^\s:/@]+:[^\s@]{4,}@' }
        # 赋值型：key = "值"。要求值里没有中文、没有空格，且不是明显的占位符。
        @{ Kind = '疑似密钥赋值'; Re = '(?i)\b(api[_\-]?key|apikey|access[_\-]?token|auth[_\-]?token|secret[_\-]?key|client[_\-]?secret|private[_\-]?key|password|passwd)\b\s*[:=]\s*["'']?([A-Za-z0-9_\-\.\/\+]{12,})["'']?' }
        # 中文语境的密码记录
        @{ Kind = '中文密码记录'; Re = '(密码|口令|密钥|私钥|访问令牌)\s*[:：=]\s*([A-Za-z0-9_\-\.\/\+!@#$%^&*]{6,})' }
    )

    # 明显是示例/占位符的值，不算命中
    $placeholderRe = '(?i)^(your|my|xxx+|example|sample|placeholder|test|demo|abc123|123456+|填写|你的|示例|占位|password|secret|token|changeme|\*+|<.*>|\{\{.*\}\}|\$\{.*\}|<your.*)$'

    foreach ($f in $mdFiles) {
        $rel = $f.FullName.Substring($PublicPath.Length).TrimStart('\')
        $lines = Get-Content -LiteralPath $f.FullName -Encoding UTF8 -ErrorAction SilentlyContinue
        if (-not $lines) { continue }

        # 整篇豁免：frontmatter 里写 allow-secrets: true
        $head = ($lines | Select-Object -First 15) -join "`n"
        if ($head -match '(?m)^allow-secrets:\s*true\s*$') {
            Write-Info "跳过（已标记 allow-secrets）：$rel"
            continue
        }

        for ($i = 0; $i -lt $lines.Count; $i++) {
            $line = $lines[$i]
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            # 单行豁免标记
            if ($line -match 'publish-ignore-secret') { continue }

            foreach ($rule in $rules) {
                $m = [regex]::Match($line, $rule.Re)
                if ($m.Success) {
                    # 赋值型规则做占位符白名单过滤
                    if ($rule.Kind -in @('疑似密钥赋值', '中文密码记录')) {
                        $val = $m.Groups[$m.Groups.Count - 1].Value
                        if ($val -match $placeholderRe) { continue }
                    }
                    # 截断展示，避免把完整密钥打印到屏幕上
                    $sample = $m.Value
                    if ($sample.Length -gt 40) { $sample = $sample.Substring(0, 40) + '…' }
                    $secretHits += [pscustomobject]@{
                        File = $rel; Line = ($i + 1); Kind = $rule.Kind; Sample = $sample
                    }
                }
            }
        }
    }

    if ($secretHits.Count -gt 0) {
        Write-Host ''
        Write-Err "发现 $($secretHits.Count) 处疑似敏感信息，已阻止发布："
        Write-Host ''
        foreach ($h in $secretHits) {
            if ($h.Line -gt 0) {
                Write-Host ("    [{0}] {1}:{2}" -f $h.Kind, $h.File, $h.Line) -ForegroundColor Yellow
            } else {
                Write-Host ("    [{0}] {1}" -f $h.Kind, $h.File) -ForegroundColor Yellow
            }
            Write-Host ("        > {0}" -f $h.Sample) -ForegroundColor DarkGray
        }
        Write-Host ''
        Write-Host '  处理方式：' -ForegroundColor Cyan
        Write-Host '    1. 真的是密钥 -> 从公开目录移出，并立即吊销该密钥' -ForegroundColor Gray
        Write-Host '    2. 是误报     -> 在该行末尾加注释 publish-ignore-secret' -ForegroundColor Gray
        Write-Host '    3. 整篇误报   -> frontmatter 加一行 allow-secrets: true' -ForegroundColor Gray
        Write-Host '    4. 临时跳过   -> .\publish.ps1 -SkipScan' -ForegroundColor Gray
        Abort '敏感信息扫描未通过'
    }
    Write-Ok '未发现敏感信息'
}

# ===================== 3. 追踪被引用的附件 =====================
# 只发布公开笔记真正引用到的附件，Vault 里其余附件不会外泄。
Write-Step '追踪笔记引用的附件'

$noteExt   = @('.md')
$attachExt = @('.png','.jpg','.jpeg','.gif','.webp','.svg','.bmp','.ico','.avif',
               '.pdf','.mp4','.webm','.mov','.mp3','.wav','.ogg','.m4a','.flac',
               '.zip','.canvas','.excalidraw')

# 建立 Vault 全量文件索引（按小写文件名分组），用于按名查找附件
$vaultFiles = @{}
Get-ChildItem -LiteralPath $VaultPath -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch '\\\.git\\' -and $_.FullName -notmatch '\\\.obsidian\\' -and $_.FullName -notmatch '\\\.trash\\' } |
    ForEach-Object {
        $k = $_.Name.ToLower()
        if (-not $vaultFiles.ContainsKey($k)) { $vaultFiles[$k] = @() }
        $vaultFiles[$k] += $_
    }

$wanted     = @{}   # 需要复制的附件： 目标相对路径 -> 源 FileInfo
$missingRef = @()   # 找不到的引用
$outsideRef = @()   # 引用了公开目录之外的笔记（会变成死链）

foreach ($f in $mdFiles) {
    $relNote = $f.FullName.Substring($PublicPath.Length).TrimStart('\')
    $text = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
    if (-not $text) { continue }

    # 去掉代码块，避免把示例代码里的路径当成真引用
    $scan = [regex]::Replace($text, '(?s)```.*?```', '')
    $scan = [regex]::Replace($scan, '`[^`\n]*`', '')

    $refs = New-Object System.Collections.Generic.List[string]

    # Obsidian 嵌入与 WikiLink：![[x]] [[x]] [[x|别名]] ![[x#标题]] ![[x|300]]
    foreach ($m in [regex]::Matches($scan, '!?\[\[([^\]\|#\^]+)')) {
        $refs.Add($m.Groups[1].Value.Trim())
    }
    # 标准 Markdown：![alt](path) [text](path)
    foreach ($m in [regex]::Matches($scan, '!?\[[^\]]*\]\(\s*<?([^)>\s]+)')) {
        $refs.Add($m.Groups[1].Value.Trim())
    }

    foreach ($ref in $refs) {
        if ([string]::IsNullOrWhiteSpace($ref)) { continue }
        # 跳过外链和锚点
        if ($ref -match '^(https?:|mailto:|tel:|data:|#|/)') { continue }

        $decoded = [uri]::UnescapeDataString($ref)
        $ext = [IO.Path]::GetExtension($decoded).ToLower()

        # 无扩展名或 .md：这是笔记链接
        if ($ext -eq '' -or $noteExt -contains $ext) {
            $target = if ($ext -eq '') { "$decoded.md" } else { $decoded }
            $leaf = [IO.Path]::GetFileName($target)
            # 公开目录里存在同名笔记就没问题（shortest 模式能解析）
            $inPublic = $mdFiles | Where-Object { $_.Name -ieq $leaf }
            if (-not $inPublic) {
                $outsideRef += [pscustomobject]@{ Note = $relNote; Ref = $ref }
            }
            continue
        }

        # 附件类型：在 Vault 内定位实际文件
        if ($attachExt -contains $ext) {
            $src = $null
            # 1) 相对笔记所在目录
            $p1 = Join-Path $f.DirectoryName $decoded
            if (Test-Path -LiteralPath $p1 -PathType Leaf) { $src = Get-Item -LiteralPath $p1 }
            # 2) 相对 Vault 根（Obsidian 绝对路径写法）
            if (-not $src) {
                $p2 = Join-Path $VaultPath $decoded
                if (Test-Path -LiteralPath $p2 -PathType Leaf) { $src = Get-Item -LiteralPath $p2 }
            }
            # 3) 全 Vault 按文件名查找（Obsidian 默认的短名嵌入）
            if (-not $src) {
                $leaf = [IO.Path]::GetFileName($decoded).ToLower()
                if ($vaultFiles.ContainsKey($leaf)) {
                    # 优先取公开目录里的同名文件
                    $cands = $vaultFiles[$leaf]
                    $src = ($cands | Where-Object { $_.FullName.StartsWith($PublicPath) } | Select-Object -First 1)
                    if (-not $src) { $src = $cands[0] }
                }
            }

            if ($src) {
                # 公开目录内的附件保持原相对路径；目录外的统一收进 附件/
                if ($src.FullName.StartsWith($PublicPath)) {
                    $dest = $src.FullName.Substring($PublicPath.Length).TrimStart('\')
                } else {
                    $dest = Join-Path $AttachDirName $src.Name
                }
                $wanted[$dest] = $src
            } else {
                $missingRef += [pscustomobject]@{ Note = $relNote; Ref = $ref }
            }
        }
    }
}

Write-Ok "需要同步 $($wanted.Count) 个附件"
if ($missingRef.Count -gt 0) {
    Write-Warn2 "$($missingRef.Count) 处引用找不到对应文件（发布后会显示为破损链接）："
    $missingRef | Select-Object -First 10 | ForEach-Object { Write-Info "$($_.Note) -> $($_.Ref)" }
    if ($missingRef.Count -gt 10) { Write-Info "…还有 $($missingRef.Count - 10) 处" }
}
if ($outsideRef.Count -gt 0) {
    Write-Warn2 "$($outsideRef.Count) 处链接指向「$PublicDir」以外的笔记（这些笔记不会公开，链接将失效）："
    $outsideRef | Select-Object -First 10 | ForEach-Object { Write-Info "$($_.Note) -> [[$($_.Ref)]]" }
    if ($outsideRef.Count -gt 10) { Write-Info "…还有 $($outsideRef.Count - 10) 处" }
}

# ===================== 4. 镜像同步到 content/ =====================
Write-Step "同步到 content/"

if ($DryRun) {
    Write-Warn2 'DryRun 模式：以下操作不会真正执行'
    Write-Info "将同步 $($mdFiles.Count) 篇笔记 + $($wanted.Count) 个附件到 $ContentPath"
    Write-Host ''
    Write-Host '  预演结束，未做任何修改。' -ForegroundColor Cyan
    exit 0
}

# 安全检查：确认目标确实是本仓库的 content 目录，避免误删
if ($ContentPath -notmatch [regex]::Escape($QuartzRepo)) { Abort "content 路径异常：$ContentPath" }
if (-not (Test-Path -LiteralPath $ContentPath)) { New-Item -ItemType Directory -Path $ContentPath -Force | Out-Null }

# 清空 content/（它完全由本脚本管理，源头是 Vault）
Get-ChildItem -LiteralPath $ContentPath -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -ne '.gitkeep' } |
    Remove-Item -Recurse -Force -ErrorAction Stop

# 复制笔记，保持 公共/ 内的目录结构
foreach ($f in $mdFiles) {
    $rel  = $f.FullName.Substring($PublicPath.Length).TrimStart('\')
    $dest = Join-Path $ContentPath $rel
    $dir  = Split-Path $dest -Parent
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Copy-Item -LiteralPath $f.FullName -Destination $dest -Force
}
Write-Ok "已复制 $($mdFiles.Count) 篇笔记"

# 复制被引用到的附件
foreach ($kv in $wanted.GetEnumerator()) {
    $dest = Join-Path $ContentPath $kv.Key
    $dir  = Split-Path $dest -Parent
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Copy-Item -LiteralPath $kv.Value.FullName -Destination $dest -Force
}
Write-Ok "已复制 $($wanted.Count) 个附件"

# ===================== 5. 检查变更 =====================
Write-Step 'Git 变更检查'

Push-Location $QuartzRepo
try {
    # 只暂存 content/，绝不 git add .
    & git add --all -- content 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { Abort 'git add 失败' }

    $staged = & git diff --cached --name-status -- content
    if (-not $staged) {
        Write-Ok '内容没有变化，无需发布'
        Write-Host ''
        Write-Host "  网站保持不变：$SiteUrl" -ForegroundColor Cyan
        Write-Host ''
        Wait-Exit
        exit 0
    }

    Write-Host ''
    Write-Host '  本次变更：' -ForegroundColor Cyan
    $added = 0; $modified = 0; $deleted = 0
    foreach ($line in $staged) {
        $parts = $line -split "`t", 2
        $st = $parts[0]; $path = $parts[1] -replace '^content/', ''
        switch -Regex ($st) {
            '^A' { Write-Host "    + 新增  $path" -ForegroundColor Green;  $added++ }
            '^M' { Write-Host "    ~ 修改  $path" -ForegroundColor Yellow; $modified++ }
            '^D' { Write-Host "    - 删除  $path" -ForegroundColor Red;    $deleted++ }
            '^R' { Write-Host "    > 重命名 $path" -ForegroundColor Cyan;  $modified++ }
            default { Write-Host "    ? $st $path" -ForegroundColor Gray }
        }
    }
    Write-Host ''
    Write-Info "共计：新增 $added，修改 $modified，删除 $deleted"

    # ===================== 6. 提交并推送 =====================
    Write-Step '提交并推送'

    if (-not $Message) {
        $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm'
        $Message = "发布内容更新（+$added ~$modified -$deleted） $stamp"
    }

    & git commit -m $Message 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { Abort 'git commit 失败' }
    Write-Ok "已提交：$Message"

    & git push origin HEAD 2>&1 | ForEach-Object { Write-Info $_ }
    if ($LASTEXITCODE -ne 0) {
        Write-Err 'git push 失败。提交已保存在本地，修复网络或凭据后可重新运行本脚本。'
        Abort 'push 失败'
    }
    Write-Ok '已推送到 GitHub'
}
finally {
    Pop-Location
}

# ===================== 7. 触发服务器部署 =====================
if ($NoDeploy) {
    Write-Step '跳过部署'
    Write-Warn2 '已指定 -NoDeploy，服务器不会自动更新'
    Write-Host ''
    exit 0
}

Write-Step '服务器部署'

if (-not (Test-Path -LiteralPath $SshKey)) { Abort "找不到 SSH 私钥：$SshKey" }
if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) { Abort '未找到 ssh 命令' }

Write-Info "连接 $SshTarget …"
& ssh -i $SshKey -o StrictHostKeyChecking=accept-new -o ConnectTimeout=20 $SshTarget "bash $RemoteDeploy" 2>&1 |
    ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }

$deployCode = $LASTEXITCODE
Write-Host ''
if ($deployCode -eq 0) {
    Write-Host '╔═══════════════════════════════════════════╗' -ForegroundColor Green
    Write-Host '║              发布成功                     ║' -ForegroundColor Green
    Write-Host '╚═══════════════════════════════════════════╝' -ForegroundColor Green
    Write-Host ''
    Write-Host "  $SiteUrl" -ForegroundColor Cyan
    Write-Host ''
    Write-Info '浏览器可能有缓存，看不到更新时按 Ctrl+F5 强制刷新。'
} else {
    Write-Err "服务器部署失败（退出码 $deployCode）"
    Write-Host ''
    Write-Host '  内容已推送到 GitHub，但服务器构建失败。' -ForegroundColor Yellow
    Write-Host '  好消息：旧版网站仍在正常运行，没有被破坏。' -ForegroundColor Yellow
    Write-Host ''
    Write-Host '  排查方式：' -ForegroundColor Cyan
    Write-Host "    ssh -i `"$SshKey`" $SshTarget" -ForegroundColor Gray
    Write-Host "    tail -50 /www/app/quartz/logs/deploy.log" -ForegroundColor Gray
    Write-Host ''
}

Write-Host ''
Wait-Exit
exit $deployCode
