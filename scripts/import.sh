#!/usr/bin/env bash
# GLB 模型导入全流程: 检查 → 修复 → 截图
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GLB_FILE=""
OUTPUT_DIR="/mnt/agents/output"
SKIP_FIX=false
SCREENSHOT_METHOD="threejs"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --output|-o) OUTPUT_DIR="$2"; shift 2 ;;
        --skip-fix) SKIP_FIX=true; shift ;;
        --screenshot-method|-m) SCREENSHOT_METHOD="$2"; shift 2 ;;
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

echo "╔════════════════════════════════════════╗"
echo "║   kais-3d-toolkit · 导入全流程          ║"
echo "╚════════════════════════════════════════╝"
echo ""
echo "文件: $GLB_FILE"
echo "输出: $OUTPUT_DIR"
echo "跳过修复: $SKIP_FIX"
echo "截图方式: $SCREENSHOT_METHOD"
echo ""

# 步骤 1: 检查
echo "━━━ 步骤 1/3: 检查模型 ━━━"
"$SCRIPT_DIR/inspect.sh" "$GLB_FILE" --output "$OUTPUT_DIR"
echo ""

MODEL_NAME=$(basename "$GLB_FILE" .glb)
ISSUES_FILE="${OUTPUT_DIR}/${MODEL_NAME}/issues.json"

# 步骤 2: 修复
if $SKIP_FIX; then
    echo "━━━ 步骤 2/3: 跳过修复 ━━━"
    WORK_FILE="$GLB_FILE"
else
    echo "━━━ 步骤 2/3: 修复模型 ━━━"

    # 检查是否有问题需要修复
    if [[ -f "$ISSUES_FILE" ]]; then
        ISSUE_COUNT=$(python3 -c "import json; print(len(json.load(open('$ISSUES_FILE'))))" 2>/dev/null || echo "0")
        if [[ "$ISSUE_COUNT" -gt 0 ]]; then
            echo "发现 $ISSUE_COUNT 个问题，开始修复..."
            "$SCRIPT_DIR/fix.sh" "$GLB_FILE" --auto --output "${OUTPUT_DIR}/${MODEL_NAME}/fixed.glb"
            WORK_FILE="${OUTPUT_DIR}/${MODEL_NAME}/fixed.glb"
        else
            echo "无需修复。"
            WORK_FILE="$GLB_FILE"
        fi
    else
        echo "未找到检查报告，跳过修复。"
        WORK_FILE="$GLB_FILE"
    fi
fi
echo ""

# 步骤 3: 截图
echo "━━━ 步骤 3/3: 模型截图 ━━━"
"$SCRIPT_DIR/screenshot.sh" "$WORK_FILE" --method "$SCREENSHOT_METHOD" --output "$OUTPUT_DIR"
echo ""

echo "╔════════════════════════════════════════╗"
echo "║   导入流程完成                          ║"
echo "╚════════════════════════════════════════╝"
echo ""
echo "输出目录: ${OUTPUT_DIR}/${MODEL_NAME}/"
echo "  ├── report.json        # 模型检查报告"
echo "  ├── issues.json        # 问题列表"
if [[ "$WORK_FILE" != "$GLB_FILE" ]]; then
    echo "  ├── fixed.glb          # 修复后模型"
fi
echo "  └── screenshots/       # 截图预览"
