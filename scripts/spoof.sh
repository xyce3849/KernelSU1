#!/usr/bin/env bash
#
# KernelSU 管理器包名伪装脚本
#
# 用法（在仓库根目录执行）:
#   bash scripts/spoof.sh <新包名> [新应用名]
#
# 示例:
#   bash scripts/spoof.sh io.github.xyce3849.kmanager
#   bash scripts/spoof.sh com.abc.xyz "My Manager"
#
# 作用：把官方包名 me.weishu.kernelsu 在源码层面彻底替换成新包名，包括：
#   1. 源码目录  manager/app/src/main/java/me/weishu/kernelsu  ->  <新包名路径>
#   2. 点分写法  me.weishu.kernelsu   ->  新包名        (Kotlin package / import / namespace / Manifest)
#   3. 斜杠写法  me/weishu/kernelsu   ->  新包名路径    (源码引用路径)
#   4. 下划线写法 me_weishu_kernelsu  ->  新包名_        (JNI 函数名 Java_me_weishu_kernelsu_*)
#   5. ksud 侧   userspace/ksud/src/late_load.rs 的 Manager Activity 路径
#   6. 可选：把应用显示名 "KernelSU" 换成自定义名称
#
# 说明：若第一个参数为空或等于官方包名，脚本直接跳过（保持原样构建）。
#
set -euo pipefail

OLD_DOT="me.weishu.kernelsu"
OLD_SLASH="me/weishu/kernelsu"
OLD_UNDER="me_weishu_kernelsu"
OLD_NAME="KernelSU"

NEW_DOT="${1:-}"
NEW_NAME="${2:-}"

# ---------- 参数校验 ----------
if [ -z "$NEW_DOT" ] || [ "$NEW_DOT" = "$OLD_DOT" ]; then
    echo "[spoof] 未指定新包名或包名与官方相同，跳过伪装，按原包名构建。"
    exit 0
fi

# Android 包名规范：全小写，点分隔，每段以字母开头
if ! printf '%s' "$NEW_DOT" | grep -qE '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$'; then
    echo "[spoof] 错误：包名不合法 -> $NEW_DOT" >&2
    echo "[spoof] 包名规则：只能含小写字母、数字、下划线，用点分隔，每段以字母开头。" >&2
    echo "[spoof] 正确示例：io.github.xyce3849.kmanager / com.abc.xyz" >&2
    exit 1
fi

# 段数对齐：官方是 3 段，新包名也建议 3 段（否则源码目录层级会变，但编译仍可过）
NEW_SLASH="${NEW_DOT//./\/}"
NEW_UNDER="${NEW_DOT//./_}"

echo "[spoof] 目标包名: $NEW_DOT"
echo "[spoof] 目录路径: $NEW_SLASH"
[ -n "$NEW_NAME" ] && echo "[spoof] 应用名称: $NEW_NAME"

# ---------- 1. 重命名源码目录（java / aidl / 任何 me/weishu/kernelsu 目录） ----------
MOVED=0
while IFS= read -r dir; do
    [ -z "$dir" ] && continue
    base="${dir%/me/weishu/kernelsu}"          # 去掉尾部的 me/weishu/kernelsu
    dest="${base}/${NEW_SLASH}"
    mkdir -p "$(dirname "$dest")"
    mv "$dir" "$dest"
    echo "[spoof] ✓ 目录迁移: $dir -> $dest"
    MOVED=$((MOVED + 1))
done < <(find manager -depth -type d -path "*/me/weishu/kernelsu" 2>/dev/null || true)

# 清理残留的空目录 me/weishu
find manager -depth -type d -path "*/me/weishu" -empty -delete 2>/dev/null || true

if [ "$MOVED" -eq 0 ]; then
    echo "[spoof] ! 未找到 me/weishu/kernelsu 源码目录（可能已被替换过），跳过目录迁移"
fi

# ---------- 2. 替换文件内容 ----------
# 覆盖管理器与 ksud 全部源码（含 aidl / build.rs），避免误伤 website/docs
mapfile -t TARGET_FILES < <(find manager userspace/ksud -type f \
    \( -name '*.kt' -o -name '*.java' -o -name '*.kts' -o -name '*.gradle' \
       -o -name '*.xml' -o -name '*.properties' -o -name '*.pro' \
       -o -name '*.aidl' -o -name '*.rs' -o -name '*.cc' -o -name '*.cpp' -o -name '*.h' \) 2>/dev/null || true)

if [ "${#TARGET_FILES[@]}" -gt 0 ]; then
    printf '%s\0' "${TARGET_FILES[@]}" | xargs -0 -r sed -i \
        -e "s|${OLD_DOT//./\\.}|${NEW_DOT}|g" \
        -e "s|${OLD_SLASH}|${NEW_SLASH}|g" \
        -e "s|${OLD_UNDER}|${NEW_UNDER}|g"
    echo "[spoof] ✓ 已替换 ${#TARGET_FILES[@]} 个文件中的包名引用（点/斜杠/下划线三种写法）"
fi

# ---------- 3. 可选：替换应用显示名 ----------
if [ -n "$NEW_NAME" ] && [ "$NEW_NAME" != "$OLD_NAME" ]; then
    if [ -f "manager/app/build.gradle.kts" ]; then
        sed -i "s|val defaultManagerName = if (isPrBuild) \"KernelSU PR\" else \"KernelSU\"|val defaultManagerName = if (isPrBuild) \"${NEW_NAME} PR\" else \"${NEW_NAME}\"|" \
            "manager/app/build.gradle.kts"
        echo "[spoof] ✓ 应用显示名已改为: $NEW_NAME"
    fi
fi

echo "[spoof] 完成。"
