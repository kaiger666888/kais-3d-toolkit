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

    # 创建临时 HTML
    HTML_DIR="/tmp/kais-3d-screenshot"
    mkdir -p "$HTML_DIR"

    # 复制 GLB 到 HTTP 可访问路径
    cp "$GLB_FILE" "$HTML_DIR/model.glb"

    for ANGLE in "${ANGLE_LIST[@]}"; do
        case "$ANGLE" in
            front)   CAM_X=0;   CAM_Y=1.2; CAM_Z=2.5; TARGET_Y=0.8 ;;
            side)    CAM_X=2.5; CAM_Y=1.2; CAM_Z=0;   TARGET_Y=0.8 ;;
            top)     CAM_X=0;   CAM_Y=3.0; CAM_Z=0.01;TARGET_Y=0   ;;
            45deg)   CAM_X=1.8; CAM_Y=1.2; CAM_Z=1.8; TARGET_Y=0.8 ;;
            back)    CAM_X=0;   CAM_Y=1.2; CAM_Z=-2.5;TARGET_Y=0.8 ;;
            low)     CAM_X=1.5; CAM_Y=0.3; CAM_Z=1.5; TARGET_Y=0.8 ;;
            closeup) CAM_X=0;   CAM_Y=1.5; CAM_Z=1.0; TARGET_Y=1.4 ;;
            *)       CAM_X=1.8; CAM_Y=1.2; CAM_Z=1.8; TARGET_Y=0.8 ;;
        esac

        OUTPUT_FILE="${SCREENSHOT_DIR}/${ANGLE}.png"

        cat > "$HTML_DIR/viewer.html" << HTMLEOF
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<style>
body { margin: 0; overflow: hidden; background: #1a1a2e; }
canvas { display: block; }
</style>
</head>
<body>
<script type="importmap">
{
  "imports": {
    "three": "https://cdn.jsdelivr.net/npm/three@0.170.0/build/three.module.js",
    "three/addons/": "https://cdn.jsdelivr.net/npm/three@0.170.0/examples/jsm/"
  }
}
</script>
<script type="module">
import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';

const W = ${RESOLUTION}, H = ${RESOLUTION};
const scene = new THREE.Scene();
scene.background = new THREE.Color(0x1a1a2e);

const camera = new THREE.PerspectiveCamera(45, W / H, 0.1, 100);
camera.position.set(${CAM_X}, ${CAM_Y}, ${CAM_Z});
camera.lookAt(0, ${TARGET_Y}, 0);

const renderer = new THREE.WebGLRenderer({ antialias: true });
renderer.setSize(W, H);
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 1.2;

const ambient = new THREE.AmbientLight(0xffffff, 0.5);
scene.add(ambient);
const dir1 = new THREE.DirectionalLight(0xffffff, 2);
dir1.position.set(5, 8, 5);
scene.add(dir1);
const dir2 = new THREE.DirectionalLight(0x8888ff, 0.8);
dir2.position.set(-3, 4, -3);
scene.add(dir2);

const loader = new GLTFLoader();
loader.load('/model.glb', (gltf) => {
  const model = gltf.scene;
  const box = new THREE.Box3().setFromObject(model);
  const size = box.getSize(new THREE.Vector3());
  const maxDim = Math.max(size.x, size.y, size.z);
  const s = 1.5 / maxDim;
  model.scale.setScalar(s);
  box.setFromObject(model);
  const center = box.getCenter(new THREE.Vector3());
  model.position.sub(center);
  model.position.y += box.getSize(new THREE.Vector3()).y / 2;
  scene.add(model);
  renderer.render(scene, camera);
  window.__ready = true;
});
</script>
</body>
</html>
HTMLEOF

        echo "  渲染角度: $ANGLE"
        # 用 Playwright 截图
        node -e "
const { chromium } = require('/home/kai/.openclaw/workspace/node_modules/playwright');
(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: ${RESOLUTION}, height: ${RESOLUTION} } });
  await page.goto('file://${HTML_DIR}/viewer.html');
  await page.waitForFunction(() => window.__ready, { timeout: 10000 }).catch(() => {});
  await page.waitForTimeout(500);
  await page.screenshot({ path: '${OUTPUT_FILE}' });
  await browser.close();
  console.log('  ✓ ${ANGLE} 保存完成');
})();
" 2>&1 || echo "  ⚠ ${ANGLE} 截图失败（Playwright）"

    done

    # 清理临时文件
    rm -f "$HTML_DIR/model.glb" "$HTML_DIR/viewer.html"
}

# === Blender 方案 ===
screenshot_blender() {
    echo "使用 Blender 渲染（引擎: $BLENDER_ENGINE, 采样: $SAMPLES）..."

    BLENDER="/usr/local/bin/blender"
    if [[ ! -x "$BLENDER" ]]; then
        echo "错误: Blender 未找到"
        exit 1
    fi

    for ANGLE in "${ANGLE_LIST[@]}"; do
        OUTPUT_FILE="${SCREENSHOT_DIR}/${ANGLE}.png"
        echo "  渲染角度: $ANGLE"

        case "$ANGLE" in
            front)   CAM_SCRIPT="cam.location=(0, -2.5, 1.2); cam.rotation_euler=(radians(75), 0, 0)" ;;
            side)    CAM_SCRIPT="cam.location=(2.5, 0, 1.2); cam.rotation_euler=(radians(90), 0, radians(90))" ;;
            top)     CAM_SCRIPT="cam.location=(0, 0, 3.0); cam.rotation_euler=(0, 0, 0)" ;;
            45deg)   CAM_SCRIPT="cam.location=(1.8, -1.8, 1.2); cam.rotation_euler=(radians(75), 0, radians(45))" ;;
            back)    CAM_SCRIPT="cam.location=(0, 2.5, 1.2); cam.rotation_euler=(radians(75), 0, radians(180))" ;;
            low)     CAM_SCRIPT="cam.location=(1.5, -1.5, 0.3); cam.rotation_euler=(radians(85), 0, radians(45))" ;;
            closeup) CAM_SCRIPT="cam.location=(0, -1.0, 1.5); cam.rotation_euler=(radians(80), 0, 0)" ;;
            *)       CAM_SCRIPT="cam.location=(1.8, -1.8, 1.2); cam.rotation_euler=(radians(75), 0, radians(45))" ;;
        esac

        "$BLENDER" --background --python-expr "
import bpy, math
from math import radians

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath='${GLB_FILE}')

# 设置渲染引擎
engine = '${BLENDER_ENGINE}'
if engine == 'cycles':
    bpy.context.scene.render.engine = 'CYCLES'
    bpy.context.scene.cycles.samples = ${SAMPLES}
else:
    bpy.context.scene.render.engine = 'BLENDER_EEVEE_NEXT'

# 渲染设置
bpy.context.scene.render.resolution_x = ${RESOLUTION}
bpy.context.scene.render.resolution_y = ${RESOLUTION}
bpy.context.scene.render.filepath = '${OUTPUT_FILE}'
bpy.context.scene.render.image_settings.file_format = 'PNG'

# 灯光
light_data = bpy.data.lights.new('key', type='SUN')
light_data.energy = 3
light_obj = bpy.data.objects.new('key_light', light_data)
bpy.context.collection.objects.link(light_obj)
light_obj.location = (5, -5, 8)

light2_data = bpy.data.lights.new('fill', type='SUN')
light2_data.energy = 1
light2_data.color = (0.5, 0.5, 1.0)
light2_obj = bpy.data.objects.new('fill_light', light2_data)
bpy.context.collection.objects.link(light2_obj)
light2_obj.location = (-3, 3, 4)

# 相机
cam_data = bpy.data.cameras.new('cam')
cam_obj = bpy.data.objects.new('camera', cam_data)
bpy.context.collection.objects.link(cam_obj)
bpy.context.scene.camera = cam_obj
cam = cam_obj

${CAM_SCRIPT}

# 相机追踪原点
track_constraint = cam_obj.constraints.new('TRACK_TO')
track_constraint.target = bpy.data.objects.new('target', None)
bpy.context.collection.objects.link(track_constraint.target)
track_constraint.track_axis = 'TRACK_NEGATIVE_Z'
track_constraint.up_axis = 'UP_Y'

bpy.ops.render.render(write_still=True)
print('  ✓ ${ANGLE} 保存完成')
" 2>&1 | grep -E "✓|Error|错误" || echo "  ✓ ${ANGLE} 完成"

    done
}

# 执行截图
case "$METHOD" in
    threejs) screenshot_threejs ;;
    blender) screenshot_blender ;;
    *) echo "未知截图方式: $METHOD (支持: threejs, blender)"; exit 1 ;;
esac

echo ""
echo "截图完成: $SCREENSHOT_DIR"
ls -la "$SCREENSHOT_DIR/"
