#!/usr/bin/env bash
# GLB 模型截图工具 - Three.js 或 Blender 渲染
set -euo pipefail

GLB_FILE=""
METHOD="threejs"
ANGLES="front,side,top,45deg"
RESOLUTION=512
BLENDER_ENGINE="eevee"
SAMPLES=32
OUTPUT_DIR="/mnt/agents/output"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --method|-m) METHOD="$2"; shift 2 ;;
        --angles|-a) ANGLES="$2"; shift 2 ;;
        --resolution|-r) RESOLUTION="$2"; shift 2 ;;
        --engine|-e) BLENDER_ENGINE="$2"; shift 2 ;;
        --samples|-s) SAMPLES="$2"; shift 2 ;;
        --output|-o) OUTPUT_DIR="$2"; shift 2 ;;
        -*) echo "未知参数: $1"; exit 1 ;;
        *) GLB_FILE="$1"; shift ;;
    esac
done

if [[ -z "$GLB_FILE" ]]; then
    echo "用法: screenshot.sh <model.glb> [--method threejs|blender] [--angles front,side,top] [--resolution 512]"
    exit 1
fi

if [[ ! -f "$GLB_FILE" ]]; then
    echo "错误: 文件不存在: $GLB_FILE"
    exit 1
fi

MODEL_NAME=$(basename "$GLB_FILE" .glb)
SCREENSHOT_DIR="${OUTPUT_DIR}/${MODEL_NAME}/screenshots"
mkdir -p "$SCREENSHOT_DIR"

echo "=== 截图: $GLB_FILE ==="
echo "方式: $METHOD | 角度: $ANGLES | 分辨率: ${RESOLUTION}x${RESOLUTION}"

IFS=',' read -ra ANGLE_LIST <<< "$ANGLES"

# === Three.js 方案 ===
screenshot_threejs() {
    echo "使用 Three.js 渲染..."
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    node "${SCRIPT_DIR}/_screenshot_threejs.js" "$GLB_FILE" "$SCREENSHOT_DIR" "$RESOLUTION" "$ANGLES"
}

# === Blender 方案 ===
screenshot_blender() {
    echo "使用 Blender 渲染（引擎: $BLENDER_ENGINE, 采样: $SAMPLES）..."

    BLENDER="/usr/local/bin/blender"
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    BLENDER_PY="${SCRIPT_DIR}/_screenshot_blender.py"

    if [[ ! -x "$BLENDER" ]]; then
        echo "错误: Blender 未找到"
        exit 1
    fi

    for ANGLE in "${ANGLE_LIST[@]}"; do
        OUTPUT_FILE="${SCREENSHOT_DIR}/${ANGLE}.png"
        echo "  渲染角度: $ANGLE"

        "$BLENDER" --background --python "$BLENDER_PY" -- "$GLB_FILE" "$OUTPUT_FILE" "$ANGLE" "$RESOLUTION" "$BLENDER_ENGINE" "$SAMPLES" 2>&1 | grep -E "OK|Error|错误" || echo "  OK $ANGLE"
    done
}

case "$METHOD" in
    threejs) screenshot_threejs ;;
    blender) screenshot_blender ;;
    *) echo "未知截图方式: $METHOD (支持: threejs, blender)"; exit 1 ;;
esac

echo ""
echo "截图完成: $SCREENSHOT_DIR"
ls -la "$SCREENSHOT_DIR/" 2>/dev/null
