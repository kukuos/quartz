#!/usr/bin/env bash
# ============================================================
# Quartz 部署脚本 —— notes.231652.xyz
#
# 由 Windows 端 publish.ps1 通过 SSH 触发，也可手动执行：
#     bash /www/app/quartz/deploy.sh
#
# 核心保证：构建失败时绝不动线上目录，旧版网站继续正常服务。
# ============================================================
set -Eeuo pipefail

# ---------------- 配置 ----------------
APP_DIR="/www/app/quartz"                          # Quartz 项目（含 node_modules）
SITE_DIR="/www/wwwroot/notes.231652.xyz"           # Nginx 站点根目录（线上）
BUILD_DIR="${SITE_DIR}.building"                   # 构建中转目录（与站点同一分区，保证 mv 原子）
PREV_DIR="${SITE_DIR}.prev"                        # 上一版，供快速回滚
BACKUP_DIR="${APP_DIR}/backups"                    # 历史快照（硬链接，几乎不占空间）
LOG_DIR="${APP_DIR}/logs"
LOG_FILE="${LOG_DIR}/deploy.log"
LOCK_FILE="${APP_DIR}/.deploy.lock"
KEEP_BACKUPS=3
MIN_FILES=10                                       # 产物文件数下限，低于此值视为构建异常
NGINX_USER="www"
NGINX_GROUP="www"

mkdir -p "$LOG_DIR" "$BACKUP_DIR"

# ---------------- 日志 ----------------
ts()   { date '+%Y-%m-%d %H:%M:%S'; }
log()  { echo "[$(ts)] $*" | tee -a "$LOG_FILE"; }
ok()   { echo "[$(ts)]   ✓ $*" | tee -a "$LOG_FILE"; }
warn() { echo "[$(ts)]   ! $*" | tee -a "$LOG_FILE"; }
err()  { echo "[$(ts)]   ✗ $*" | tee -a "$LOG_FILE" >&2; }

# 任何一步出错都走这里：清理中转目录，线上目录原封不动
on_error() {
    local code=$?
    local line=${1:-?}
    err "部署失败（第 ${line} 行，退出码 ${code}）"
    if [ -d "$BUILD_DIR" ]; then
        rm -rf "$BUILD_DIR"
        warn "已清理构建中转目录"
    fi
    if [ -d "$SITE_DIR" ]; then
        warn "线上网站未受影响，仍在正常服务：https://notes.231652.xyz"
    else
        warn "线上目录尚不存在，这是首次部署未完成"
    fi
    log "──────────────── 部署结束（失败） ────────────────"
    exit "$code"
}
trap 'on_error $LINENO' ERR

# ---------------- 并发锁 ----------------
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
    err "已有部署任务正在运行，本次跳过"
    exit 1
fi

log "════════════════ 开始部署 ════════════════"
cd "$APP_DIR"

# 跟踪当前所在分支（本仓库默认分支是 v5），换分支后无需修改脚本
GIT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [ -z "$GIT_BRANCH" ] || [ "$GIT_BRANCH" = "HEAD" ]; then
    err "当前处于游离 HEAD 状态，无法确定要拉取的分支"
    exit 1
fi
log "  分支：${GIT_BRANCH}"

# ---------------- 1. 拉取最新内容 ----------------
log "[1/6] 拉取 Git 最新内容"

# package.json / package-lock.json 可能被 install-plugins 改写过，
# 先还原这两个文件，避免 pull 因本地改动失败。只碰这两个文件，不动其他内容。
for f in package.json package-lock.json; do
    if ! git diff --quiet -- "$f" 2>/dev/null; then
        git checkout -- "$f"
        warn "已还原本地改动：$f"
    fi
done

BEFORE_SHA="$(git rev-parse HEAD)"
git fetch origin "$GIT_BRANCH" 2>&1 | tee -a "$LOG_FILE"
git merge --ff-only "origin/${GIT_BRANCH}" 2>&1 | tee -a "$LOG_FILE"
AFTER_SHA="$(git rev-parse HEAD)"

if [ "$BEFORE_SHA" = "$AFTER_SHA" ]; then
    log "  代码无更新（$(git rev-parse --short HEAD)），仍继续重建以确保产物最新"
else
    ok "已更新：$(git rev-parse --short "$BEFORE_SHA") -> $(git rev-parse --short "$AFTER_SHA")"
    git --no-pager log --oneline "${BEFORE_SHA}..${AFTER_SHA}" | head -10 | tee -a "$LOG_FILE"
fi

# ---------------- 2. 依赖 ----------------
log "[2/6] 检查依赖"

NEED_INSTALL=0
if [ ! -d node_modules ]; then
    NEED_INSTALL=1
    log "  node_modules 不存在"
elif [ "$BEFORE_SHA" != "$AFTER_SHA" ] && \
     ! git diff --quiet "${BEFORE_SHA}" "${AFTER_SHA}" -- package-lock.json package.json; then
    NEED_INSTALL=1
    log "  依赖清单有变化"
fi

if [ "$NEED_INSTALL" -eq 1 ]; then
    log "  执行 npm ci（这一步较慢，仅在依赖变化时触发）"
    npm ci --no-audit --no-fund 2>&1 | tail -20 | tee -a "$LOG_FILE"
    ok "依赖安装完成"
else
    ok "依赖无变化，跳过安装"
fi

# 同步 quartz.config.yaml 中声明的插件（幂等，未变化时不会改动 package.json）
log "  同步插件清单"
npm run install-plugins 2>&1 | tail -5 | tee -a "$LOG_FILE"

# ---------------- 3. 构建 ----------------
log "[3/6] 构建站点"

rm -rf "$BUILD_DIR"
BUILD_START=$(date +%s)

# --concurrency=1：本机内存较小（约 1G），限制并发避免构建期 OOM
if ! npx quartz build -d content -o "$BUILD_DIR" --concurrency=1 2>&1 | tee -a "$LOG_FILE"; then
    err "Quartz 构建失败"
    exit 1
fi

BUILD_END=$(date +%s)
ok "构建耗时 $((BUILD_END - BUILD_START)) 秒"

# Quartz 不生成 robots.txt，这里补上并指向 sitemap。
# 放在构建产物里而不是 Vault 里，避免在 Obsidian 中看到一个无关文件。
cat > "${BUILD_DIR}/robots.txt" <<'ROBOTS'
User-agent: *
Allow: /

Sitemap: https://notes.231652.xyz/sitemap.xml
ROBOTS
ok "已生成 robots.txt"

# ---------------- 4. 校验产物 ----------------
log "[4/6] 校验构建产物"

if [ ! -f "${BUILD_DIR}/index.html" ]; then
    err "产物缺少 index.html，判定构建异常"
    exit 1
fi

FILE_COUNT=$(find "$BUILD_DIR" -type f | wc -l)
if [ "$FILE_COUNT" -lt "$MIN_FILES" ]; then
    err "产物只有 ${FILE_COUNT} 个文件（下限 ${MIN_FILES}），判定构建异常"
    exit 1
fi

INDEX_SIZE=$(stat -c%s "${BUILD_DIR}/index.html")
if [ "$INDEX_SIZE" -lt 512 ]; then
    err "index.html 仅 ${INDEX_SIZE} 字节，判定构建异常"
    exit 1
fi

ok "产物校验通过：${FILE_COUNT} 个文件，$(du -sh "$BUILD_DIR" | cut -f1)"

# ---------------- 5. 原子切换 ----------------
log "[5/6] 切换线上目录"

# 权限：Nginx 以 www 用户读取；目录 755、文件 644，不使用 777
chown -R "${NGINX_USER}:${NGINX_GROUP}" "$BUILD_DIR"
find "$BUILD_DIR" -type d -exec chmod 755 {} +
find "$BUILD_DIR" -type f -exec chmod 644 {} +

mkdir -p "$(dirname "$SITE_DIR")"

# 宝塔可能在站点目录放置带 immutable 属性的 .user.ini，会让 mv 失败，先解锁
if [ -f "${SITE_DIR}/.user.ini" ]; then
    chattr -i "${SITE_DIR}/.user.ini" 2>/dev/null || true
fi

if [ -d "$SITE_DIR" ]; then
    # 保留一份硬链接快照用于历史回滚（几乎不额外占磁盘）
    SNAP="${BACKUP_DIR}/$(date '+%Y%m%d-%H%M%S')"
    cp -al "$SITE_DIR" "$SNAP" 2>/dev/null || cp -a "$SITE_DIR" "$SNAP"
    ok "已快照上一版本：$SNAP"

    rm -rf "$PREV_DIR"
    mv "$SITE_DIR" "$PREV_DIR"
fi

# mv 在同一分区上是原子操作，用户不会看到半新半旧的站点
mv "$BUILD_DIR" "$SITE_DIR"
ok "已切换到新版本"

# ---------------- 6. 收尾 ----------------
log "[6/6] 清理与校验"

# 只保留最近 N 份快照
if [ -d "$BACKUP_DIR" ]; then
    OLD=$(ls -1dt "${BACKUP_DIR}"/*/ 2>/dev/null | tail -n +$((KEEP_BACKUPS + 1)) || true)
    if [ -n "$OLD" ]; then
        echo "$OLD" | xargs -r rm -rf
        ok "已清理超出 ${KEEP_BACKUPS} 份的旧快照"
    fi
fi

# Nginx 配置无变化则无需 reload；这里只做一次配置自检
if nginx -t >/dev/null 2>&1; then
    ok "Nginx 配置正常"
else
    warn "Nginx 配置自检未通过，请在宝塔面板检查（不影响已生成的静态文件）"
fi

PAGE_COUNT=$(find "$SITE_DIR" -name '*.html' -type f | wc -l)
log "════════════════ 部署成功 ════════════════"
log "  页面数：${PAGE_COUNT}    版本：$(git rev-parse --short HEAD)"
log "  网站：https://notes.231652.xyz"
log "  回滚：bash ${APP_DIR}/rollback.sh"
log ""
exit 0
