#!/usr/bin/env bash
# GLB 模型检查工具 - 输出模型信息报告
set -euo pipefail

GLB_FILE=""
OUTPUT_DIR="/mnt/agents/output"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --output|-o) OUTPUT_DIR="$2"; shift 2 ;;
        -*) echo "未知参数: $1"; exit 1 ;;
        *) GLB_FILE="$1"; shift ;;
    esac
done

if [[ -z "$GLB_FILE" ]]; then
    echo "用法: inspect.sh <model.glb> [--output <dir>]"
    exit 1
fi

if [[ ! -f "$GLB_FILE" ]]; then
    echo "错误: 文件不存在: $GLB_FILE"
    exit 1
fi

MODEL_NAME=$(basename "$GLB_FILE" .glb)
OUT_DIR="${OUTPUT_DIR}/${MODEL_NAME}"
mkdir -p "$OUT_DIR"

echo "=== 检查模型: $GLB_FILE ==="
echo "输出目录: $OUT_DIR"

# 使用 Blender Python API 检查模型
BLENDER="/usr/local/bin/blender"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PYTHON_SCRIPT="${SCRIPT_DIR}/_inspect_blender.py"

if [[ ! -x "$BLENDER" ]]; then
    echo "错误: Blender 未找到: $BLENDER"
    exit 1
fi

"$BLENDER" --background --python "$PYTHON_SCRIPT" -- "$GLB_FILE" "$OUT_DIR" 2>&1 | grep -v "^Blender\|^Read\|^Fra:"

echo ""
echo "检查完成。"
