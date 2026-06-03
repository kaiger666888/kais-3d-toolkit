#!/usr/bin/env bash
# GLB 模型自动修复工具
set -euo pipefail

GLB_FILE=""
OUTPUT_FILE=""
AUTO_MODE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --output|-o) OUTPUT_FILE="$2"; shift 2 ;;
        --auto) AUTO_MODE=true; shift ;;
        -*) echo "未知参数: $1"; exit 1 ;;
        *) GLB_FILE="$1"; shift ;;
    esac
done

if [[ -z "$GLB_FILE" ]]; then
    echo "用法: fix.sh <model.glb> [--output <fixed.glb>] [--auto]"
    exit 1
fi

if [[ ! -f "$GLB_FILE" ]]; then
    echo "错误: 文件不存在: $GLB_FILE"
    exit 1
fi

MODEL_NAME=$(basename "$GLB_FILE" .glb)
MODEL_DIR=$(dirname "$(realpath "$GLB_FILE")")

if [[ -z "$OUTPUT_FILE" ]]; then
    OUTPUT_FILE="${MODEL_DIR}/${MODEL_NAME}_fixed.glb"
fi

BLENDER="/usr/local/bin/blender"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ ! -x "$BLENDER" ]]; then
    echo "错误: Blender 未找到: $BLENDER"
    exit 1
fi

echo "=== 修复模型: $GLB_FILE ==="
echo "输出文件: $OUTPUT_FILE"
echo "自动模式: $AUTO_MODE"

AUTO_ARG=""
if $AUTO_MODE; then
    AUTO_ARG="--auto"
fi

"$BLENDER" --background --python "${SCRIPT_DIR}/_fix_blender.py" -- "$GLB_FILE" "$OUTPUT_FILE" $AUTO_ARG 2>&1 | grep -v "^Blender\|^Read\|^Fra:" | grep -v "^07:" | grep -v "glTF import"

echo "修复完成: $OUTPUT_FILE"
