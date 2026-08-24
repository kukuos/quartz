#!/usr/bin/env bash
# ============================================================
# 回滚脚本 —— 把网站恢复到上一个版本
#
#   bash /www/app/quartz/rollback.sh            # 回滚到上一版
#   bash /www/app/quartz/rollback.sh --list     # 查看所有可用版本
#   bash /www/app/quartz/rollback.sh 20260824-153000   # 回滚到指定快照
#
# 回滚只替换静态文件，不碰 Git 内容。若要连内容一起回退，
# 请在 Windows 端用 git revert 后重新执行 publish.ps1。
# ============================================================
set -Eeuo pipefail

APP_DIR="/www/app/quartz"
SITE_DIR="/www/wwwroot/notes.231652.xyz"
PREV_DIR="${SITE_DIR}.prev"
BACKUP_DIR="${APP_DIR}/backups"
LOG_FILE="${APP_DIR}/logs/deploy.log"
NGINX_USER="www"
NGINX_GROUP="www"

ts()  { date '+%Y-%m-%d %H:%M:%S'; }
log() { echo "[$(ts)] $*" | tee -a "$LOG_FILE"; }
err() { echo "[$(ts)]   ✗ $*" | tee -a "$LOG_FILE" >&2; }
ok()  { echo "[$(ts)]   ✓ $*" | tee -a "$LOG_FILE"; }

list_versions() {
    echo ""
    echo "当前线上版本："
    if [ -d "$SITE_DIR" ]; then
        echo "  $SITE_DIR  （$(find "$SITE_DIR" -name '*.html' | wc -l) 个页面，修改于 $(date -r "$SITE_DIR" '+%Y-%m-%d %H:%M:%S')）"
    else
        echo "  (站点目录不存在)"
    fi
    echo ""
    echo "上一版本（默认回滚目标）："
    if [ -d "$PREV_DIR" ]; then
        echo "  $PREV_DIR  （$(find "$PREV_DIR" -name '*.html' | wc -l) 个页面，修改于 $(date -r "$PREV_DIR" '+%Y-%m-%d %H:%M:%S')）"
    else
        echo "  (无)"
    fi
    echo ""
    echo "历史快照："
    if compgen -G "${BACKUP_DIR}/*/" > /dev/null; then
        for d in $(ls -1dt "${BACKUP_DIR}"/*/); do
            name=$(basename "$d")
            echo "  $name  （$(find "$d" -name '*.html' | wc -l) 个页面）"
        done
    else
        echo "  (无)"
    fi
    echo ""
}

if [ "${1:-}" = "--list" ] || [ "${1:-}" = "-l" ]; then
    list_versions
    exit 0
fi

# 确定回滚源
if [ -n "${1:-}" ]; then
    SRC="${BACKUP_DIR}/$1"
    if [ ! -d "$SRC" ]; then
        err "找不到快照：$1"
        list_versions
        exit 1
    fi
else
    SRC="$PREV_DIR"
    if [ ! -d "$SRC" ]; then
        err "没有可回滚的上一版本（${PREV_DIR} 不存在）"
        echo "用 --list 查看历史快照，或指定快照名回滚。"
        exit 1
    fi
fi

# 校验回滚源可用，避免回滚到一个同样损坏的版本
if [ ! -f "${SRC}/index.html" ]; then
    err "回滚源缺少 index.html，拒绝回滚：$SRC"
    exit 1
fi

log "════════════════ 开始回滚 ════════════════"
log "  回滚源：$SRC"

STAGE="${SITE_DIR}.rollback"
rm -rf "$STAGE"
cp -a "$SRC" "$STAGE"

chown -R "${NGINX_USER}:${NGINX_GROUP}" "$STAGE"
find "$STAGE" -type d -exec chmod 755 {} +
find "$STAGE" -type f -exec chmod 644 {} +

if [ -f "${SITE_DIR}/.user.ini" ]; then
    chattr -i "${SITE_DIR}/.user.ini" 2>/dev/null || true
fi

# 把当前版本挪到 .prev，这样回滚本身也可以再被回滚
if [ -d "$SITE_DIR" ]; then
    rm -rf "${SITE_DIR}.tmp-old"
    mv "$SITE_DIR" "${SITE_DIR}.tmp-old"
fi
mv "$STAGE" "$SITE_DIR"
rm -rf "$PREV_DIR"
[ -d "${SITE_DIR}.tmp-old" ] && mv "${SITE_DIR}.tmp-old" "$PREV_DIR"

ok "已回滚，当前页面数：$(find "$SITE_DIR" -name '*.html' | wc -l)"
log "════════════════ 回滚完成 ════════════════"
log "  网站：https://notes.231652.xyz"
log "  再次执行本脚本可切回刚才的版本"
echo ""
