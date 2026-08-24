#!/usr/bin/env bash
# ============================================================
# 站点验收测试 —— notes.231652.xyz
#
#   bash /www/app/quartz/verify.sh          # 测 HTTPS（默认）
#   bash /www/app/quartz/verify.sh --http   # 只测 HTTP（证书还没申请时用）
#
# 从 Windows 远程执行：
#   ssh -i "C:\Users\Administrator\.ssh\root-tw_id_ed25519" root@43.212.212.75 \
#       "bash /www/app/quartz/verify.sh"
# ============================================================

DOMAIN="notes.231652.xyz"
SCHEME="https"
[ "${1:-}" = "--http" ] && SCHEME="http"
SITE="${SCHEME}://${DOMAIN}"

PASS=0
FAIL=0
WARN=0

green() { printf '\033[32m%s\033[0m\n' "$1"; }
red()   { printf '\033[31m%s\033[0m\n' "$1"; }
yellow(){ printf '\033[33m%s\033[0m\n' "$1"; }
title() { printf '\n\033[36m── %s\033[0m\n' "$1"; }

# ok <描述> <条件命令...>
ok() {
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then
        green "  ✓ ${desc}"; PASS=$((PASS+1))
    else
        red   "  ✗ ${desc}"; FAIL=$((FAIL+1))
    fi
}

# 取状态码
code() { curl -s -o /dev/null -w '%{http_code}' -m 15 "$1"; }
# 取响应体
body() { curl -s -m 15 "$1"; }
# 取响应头
head_of() { curl -s -I -m 15 "$1"; }

echo "════════════════════════════════════════════"
echo "  验收测试：${SITE}"
echo "  时间：$(date '+%Y-%m-%d %H:%M:%S')"
echo "════════════════════════════════════════════"

# ---------------- 测试 1：基础访问 ----------------
title "测试 1：页面可访问"

C=$(code "${SITE}/")
if [ "$C" = "200" ]; then green "  ✓ 首页 200"; PASS=$((PASS+1)); else red "  ✗ 首页返回 ${C}"; FAIL=$((FAIL+1)); fi

C=$(code "${SITE}/test")
if [ "$C" = "200" ]; then green "  ✓ /test 200"; PASS=$((PASS+1)); else red "  ✗ /test 返回 ${C}"; FAIL=$((FAIL+1)); fi

# 大写形式应能通过重定向页访问
C=$(code "${SITE}/Test")
if [ "$C" = "200" ]; then green "  ✓ /Test（大写）200"; PASS=$((PASS+1)); else yellow "  ! /Test 返回 ${C}"; WARN=$((WARN+1)); fi

# 误加尾斜杠应 301 到无斜杠
C=$(curl -s -o /dev/null -w '%{http_code}' -m 15 "${SITE}/test/")
if [ "$C" = "301" ]; then green "  ✓ /test/ 正确 301 去掉尾斜杠"; PASS=$((PASS+1)); else yellow "  ! /test/ 返回 ${C}（预期 301）"; WARN=$((WARN+1)); fi

# 不存在的路径应真 404
C=$(code "${SITE}/这个页面不存在-abcxyz")
if [ "$C" = "404" ]; then green "  ✓ 不存在的路径返回 404"; PASS=$((PASS+1)); else red "  ✗ 不存在的路径返回 ${C}（预期 404）"; FAIL=$((FAIL+1)); fi

# ---------------- 测试 2：私人内容未泄露 ----------------
title "测试 2：私人内容未泄露"

if body "${SITE}/" | grep -qi "Test Private"; then
    red "  ✗ 首页出现了私人笔记内容！"; FAIL=$((FAIL+1))
else
    green "  ✓ 首页无私人笔记内容"; PASS=$((PASS+1))
fi

for p in "/test-private" "/Test Private" "/私人测试"; do
    C=$(code "${SITE}${p}")
    if [ "$C" = "404" ] || [ "$C" = "301" ]; then
        green "  ✓ ${p} 不可访问（${C}）"; PASS=$((PASS+1))
    else
        red "  ✗ ${p} 返回 ${C}，可能已泄露！"; FAIL=$((FAIL+1))
    fi
done

# 搜索索引里不应出现私人内容
if body "${SITE}/static/contentIndex.json" | grep -qi "Test Private"; then
    red "  ✗ 搜索索引里包含私人笔记！"; FAIL=$((FAIL+1))
else
    green "  ✓ 搜索索引无私人内容"; PASS=$((PASS+1))
fi

# ---------------- 测试 3：WikiLink ----------------
title "测试 3：WikiLink 与反向链接"

T=$(body "${SITE}/test")
echo "$T" | grep -q 'class="internal' \
    && { green "  ✓ WikiLink 已渲染为内部链接"; PASS=$((PASS+1)); } \
    || { red "  ✗ 未找到内部链接"; FAIL=$((FAIL+1)); }

echo "$T" | grep -q '点这里看中文页面' \
    && { green "  ✓ 别名链接文字正确"; PASS=$((PASS+1)); } \
    || { red "  ✗ 别名链接未生效"; FAIL=$((FAIL+1)); }

body "${SITE}/中文标题测试" | grep -q 'backlinks' \
    && { green "  ✓ 反向链接区域存在"; PASS=$((PASS+1)); } \
    || { yellow "  ! 未找到反向链接区域"; WARN=$((WARN+1)); }

# ---------------- 测试 4：图片 ----------------
title "测试 4：图片嵌入"

echo "$T" | grep -q 'src="./附件/test.png"' \
    && { green "  ✓ 图片路径解析正确"; PASS=$((PASS+1)); } \
    || { red "  ✗ 图片路径不正确"; FAIL=$((FAIL+1)); }

C=$(code "${SITE}/附件/test.png")
if [ "$C" = "200" ]; then green "  ✓ 图片可访问（200）"; PASS=$((PASS+1)); else red "  ✗ 图片返回 ${C}"; FAIL=$((FAIL+1)); fi

CT=$(head_of "${SITE}/附件/test.png" | grep -i "^content-type" | tr -d '\r')
echo "$CT" | grep -qi "image/png" \
    && { green "  ✓ 图片 MIME 正确"; PASS=$((PASS+1)); } \
    || { red "  ✗ 图片 MIME 异常：${CT}"; FAIL=$((FAIL+1)); }

# ---------------- 测试 5：中文 ----------------
title "测试 5：中文支持"

Z=$(body "${SITE}/中文标题测试")
echo "$Z" | grep -q '<title>中文标题测试</title>' \
    && { green "  ✓ 中文标题正常"; PASS=$((PASS+1)); } \
    || { red "  ✗ 中文标题异常"; FAIL=$((FAIL+1)); }

head_of "${SITE}/中文标题测试" | grep -qi "charset=utf-8" \
    && { green "  ✓ 响应头声明 UTF-8"; PASS=$((PASS+1)); } \
    || { red "  ✗ 响应头未声明 UTF-8"; FAIL=$((FAIL+1)); }

C=$(code "${SITE}/tags/测试")
if [ "$C" = "200" ]; then green "  ✓ 中文标签页可访问"; PASS=$((PASS+1)); else red "  ✗ 中文标签页返回 ${C}"; FAIL=$((FAIL+1)); fi

# 中文搜索索引
if body "${SITE}/static/contentIndex.json" | grep -q "中文标题测试"; then
    green "  ✓ 搜索索引包含中文内容"; PASS=$((PASS+1))
else
    red "  ✗ 搜索索引缺少中文内容"; FAIL=$((FAIL+1))
fi

# ---------------- 测试 6：移动端 ----------------
title "测试 6：移动端适配"

echo "$Z" | grep -q 'name="viewport"' \
    && { green "  ✓ 存在 viewport 声明"; PASS=$((PASS+1)); } \
    || { red "  ✗ 缺少 viewport 声明"; FAIL=$((FAIL+1)); }

MC=$(curl -s -o /dev/null -w '%{http_code}' -m 15 \
     -A "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15" "${SITE}/")
if [ "$MC" = "200" ]; then green "  ✓ 手机 UA 访问正常"; PASS=$((PASS+1)); else red "  ✗ 手机 UA 返回 ${MC}"; FAIL=$((FAIL+1)); fi

# ---------------- 测试 7：HTTPS ----------------
if [ "$SCHEME" = "https" ]; then
    title "测试 7：HTTPS 与证书"

    RD=$(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' -m 15 "http://${DOMAIN}/")
    echo "$RD" | grep -q "^30[18] https://" \
        && { green "  ✓ HTTP 自动跳转 HTTPS（${RD}）"; PASS=$((PASS+1)); } \
        || { red "  ✗ HTTP 未跳转：${RD}"; FAIL=$((FAIL+1)); }

    if curl -s -o /dev/null -m 15 "${SITE}/" 2>/dev/null; then
        green "  ✓ 证书验证通过"; PASS=$((PASS+1))
    else
        red "  ✗ 证书验证失败"; FAIL=$((FAIL+1))
    fi

    CERT=$(echo | openssl s_client -connect "${DOMAIN}:443" -servername "${DOMAIN}" 2>/dev/null \
           | openssl x509 -noout -dates -issuer 2>/dev/null)
    if [ -n "$CERT" ]; then
        echo "$CERT" | sed 's/^/      /'
        EXP=$(echo "$CERT" | grep notAfter | cut -d= -f2)
        EXP_TS=$(date -d "$EXP" +%s 2>/dev/null || echo 0)
        NOW_TS=$(date +%s)
        DAYS=$(( (EXP_TS - NOW_TS) / 86400 ))
        if [ "$DAYS" -gt 20 ]; then
            green "  ✓ 证书剩余 ${DAYS} 天"; PASS=$((PASS+1))
        else
            yellow "  ! 证书仅剩 ${DAYS} 天，确认自动续期是否正常"; WARN=$((WARN+1))
        fi
    fi
else
    title "测试 7：HTTPS（已跳过，当前为 --http 模式）"
fi

# ---------------- 测试 8：SEO ----------------
title "测试 8：SEO 与订阅"

for f in /sitemap.xml /index.xml /robots.txt; do
    C=$(code "${SITE}${f}")
    if [ "$C" = "200" ]; then green "  ✓ ${f} 可访问"; PASS=$((PASS+1)); else red "  ✗ ${f} 返回 ${C}"; FAIL=$((FAIL+1)); fi
done

echo "$Z" | grep -q 'rel="canonical"' \
    && { green "  ✓ canonical 存在"; PASS=$((PASS+1)); } \
    || { red "  ✗ canonical 缺失"; FAIL=$((FAIL+1)); }

body "${SITE}/" | grep -q 'rel="canonical" href="https://notes.231652.xyz/"' \
    && { green "  ✓ 首页 canonical 指向根地址"; PASS=$((PASS+1)); } \
    || { yellow "  ! 首页 canonical 不是根地址"; WARN=$((WARN+1)); }

echo "$Z" | grep -q 'property="og:title"' \
    && { green "  ✓ OpenGraph 标签存在"; PASS=$((PASS+1)); } \
    || { red "  ✗ OpenGraph 缺失"; FAIL=$((FAIL+1)); }

body "${SITE}/robots.txt" | grep -q "Sitemap:" \
    && { green "  ✓ robots.txt 指向 sitemap"; PASS=$((PASS+1)); } \
    || { red "  ✗ robots.txt 未指向 sitemap"; FAIL=$((FAIL+1)); }

# ---------------- 测试 9：安全 ----------------
title "测试 9：敏感路径防护"

for p in "/.git/config" "/.env" "/package.json" "/quartz.config.yaml" "/node_modules/" "/deploy.sh" "/index.md"; do
    C=$(code "${SITE}${p}")
    if [ "$C" = "404" ] || [ "$C" = "403" ]; then
        green "  ✓ ${p} 被拦截（${C}）"; PASS=$((PASS+1))
    else
        red "  ✗ ${p} 返回 ${C}，存在暴露风险！"; FAIL=$((FAIL+1))
    fi
done

H=$(head_of "${SITE}/")
echo "$H" | grep -qi "x-content-type-options" \
    && { green "  ✓ 安全响应头已设置"; PASS=$((PASS+1)); } \
    || { yellow "  ! 缺少 X-Content-Type-Options"; WARN=$((WARN+1)); }

# ---------------- 测试 10：缓存与压缩 ----------------
title "测试 10：缓存与压缩"

CSS=$(body "${SITE}/" | grep -oE 'href="[^"]*index-[0-9a-f]+\.css"' | head -1 | sed 's/href="//;s/"//;s|^\./||')
if [ -n "$CSS" ]; then
    CH=$(head_of "${SITE}/${CSS}")
    echo "$CH" | grep -qi "immutable" \
        && { green "  ✓ 带 hash 的 CSS 长期强缓存"; PASS=$((PASS+1)); } \
        || { yellow "  ! CSS 未设置 immutable 缓存"; WARN=$((WARN+1)); }
fi

echo "$H" | grep -qi "cache-control: no-cache" \
    && { green "  ✓ HTML 不缓存，发布后立即可见"; PASS=$((PASS+1)); } \
    || { yellow "  ! HTML 缓存策略非预期"; WARN=$((WARN+1)); }

curl -s -I -m 15 -H "Accept-Encoding: gzip" "${SITE}/" | grep -qi "content-encoding: gzip" \
    && { green "  ✓ gzip 压缩已启用"; PASS=$((PASS+1)); } \
    || { yellow "  ! 未检测到 gzip"; WARN=$((WARN+1)); }

# ---------------- 汇总 ----------------
echo ""
echo "════════════════════════════════════════════"
printf "  通过 %d 项" "$PASS"
[ "$WARN" -gt 0 ] && printf "，警告 %d 项" "$WARN"
[ "$FAIL" -gt 0 ] && printf "，\033[31m失败 %d 项\033[0m" "$FAIL"
echo ""
echo "════════════════════════════════════════════"

if [ "$FAIL" -gt 0 ]; then
    echo ""
    red "  有测试未通过，请查看上面标 ✗ 的项目。"
    echo "  排查参考 README 的「故障排查」章节。"
    exit 1
fi
echo ""
green "  全部通过。"
exit 0
