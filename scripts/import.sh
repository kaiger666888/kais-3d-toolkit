#!/usr/bin/env bash
# GLB 模型导入全流程：检查→修复→截图
set -euo pipefail

GLB_FILE=""
OUTPUT_DIR="/mnt/agents/output"
SKIP_FIX=false
SCREENSHOT_METHOD="threejs"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --output|-o) OUTPUT_DIR="$2"; shift 2 ;;
        --skip-fix) SKIP_FIX=true; shift ;;
        --screenshot-method) SCREENSHOT_METHOD="$2"; shift 2 ;;
        -*) echo "未知参数: $1"; exit 1 ;;
        *) GLB_FILE="$1"; shift ;;
    esac
done

if [[ -z "$GLB_FILE" ]]; then
    echo "用法: import.sh <model.glb> [--output <dir>] [--skip-fix] [--screenshot-method threejs|blender]"
    exit 1
fi

if [[ ! -f "$GLB_FILE" ]]; then
    echo "错误: 文件不存在: $GLB_FILE"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "╔══════════════════════════════════════╗"
echo "║  kais-3d-toolkit: 导入全流程         ║"
echo "╚══════════════════════════════════════╝"
echo "  文件: $GLB_FILE"
echo "  输出: $OUTPUT_DIR"
echo ""

# Step 1: 检查
echo "━━━ Step 1/3: 检查模型 ━━━"
bash "${SCRIPT_DIR}/inspect.sh" "$GLB_FILE" --output "$OUTPUT_DIR"
echo ""

# Step 2: 修复（除非 --skip-fix）
if $SKIP_FIX; then
    echo "━━━ Step 2/3: 跳过修复 ━━━"
else
    echo "━━━ Step 2/3: 修复模型 ━━━"
    MODEL_NAME=$(basename "$GLB_FILE" .glb)
    FIXED_FILE="${OUTPUT_DIR}/${MODEL_NAME}/fixed.glb"
    bash "${SCRIPT_DIR}/fix.sh" "$GLB_FILE" --output "$FIXED_FILE" --auto

    # 用修复后的文件继续截图
    GLB_FILE="$FIXED_FILE"
    echo ""
fi

# Step 3: 截图
echo "━━━ Step 3/3: 截图 ━━━"
bash "${SCRIPT_DIR}/screenshot.sh" "$GLB_FILE" --method "$SCREENSHOT_METHOD" --output "$OUTPUT_DIR"

echo ""
echo "╔══════════════════════════════════════╗"
echo "║  全流程完成 ✅                        ║"
echo "╚══════════════════════════════════════╝"
