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
if [[ ! -x "$BLENDER" ]]; then
    echo "错误: Blender 未找到: $BLENDER"
    exit 1
fi

AUTO_FLAG=""
if $AUTO_MODE; then
    AUTO_FLAG="true"
else
    AUTO_FLAG="false"
fi

echo "=== 修复模型: $GLB_FILE ==="
echo "输出文件: $OUTPUT_FILE"
echo "自动模式: $AUTO_MODE"

PYTHON_SCRIPT=$(cat <<PYEOF
import bpy, json, sys, os, math

auto_mode = ${AUTO_FLAG}

def fix_model(filepath, output_path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=filepath)

    fixes_applied = []

    # === 修复 1: 删除 Cube 残留 ===
    for obj in list(bpy.data.objects):
        if obj.name == "Cube" and obj.type == 'MESH':
            mesh = obj.data
            if len(mesh.vertices) == 8 and len(mesh.polygons) == 6:
                if auto_mode or True:  # Cube 删除不需要确认
                    print(f"  删除残留 Cube: {obj.name}")
                    bpy.data.objects.remove(obj, do_unlink=True)
                    fixes_applied.append({"fix": "delete_cube", "object": "Cube"})

    # === 修复 2: 模型太小 → 放大 ===
    main_objects = [o for o in bpy.data.objects if o.type == 'MESH']
    for obj in main_objects:
        max_dim = max(obj.dimensions.x, obj.dimensions.y, obj.dimensions.z)
        if max_dim < 0.5:
            scale_factor = 1.0 / max_dim
            # 对人体模型，目标高度约 1.7m
            target_height = 1.7
            if obj.dimensions.z * scale_factor < 0.5:
                scale_factor = target_height / obj.dimensions.z

            print(f"  放大 {obj.name}: {max_dim:.3f}m → ×{scale_factor:.2f}")
            obj.scale *= scale_factor
            bpy.context.view_layer.update()
            fixes_applied.append({
                "fix": "scale_up",
                "object": obj.name,
                "factor": round(scale_factor, 3),
                "original_max_dim": round(max_dim, 4),
                "new_max_dim": round(max(obj.dimensions.x, obj.dimensions.y, obj.dimensions.z), 4),
            })

    # === 修复 3: 材质模式 → OPAQUE ===
    for mat in bpy.data.materials:
        blend = getattr(mat, 'blend_method', None)
        if blend and blend != 'OPAQUE':
            old_mode = blend
            mat.blend_method = 'OPAQUE'
            print(f"  材质 {mat.name}: {old_mode} → OPAQUE")
            fixes_applied.append({"fix": "blend_mode", "material": mat.name, "from": old_mode, "to": "OPAQUE"})

    # === 修复 4: PBR 纹理连接 ===
    for mat in bpy.data.materials:
        if not mat.use_nodes:
            continue

        # 查找 Image_1 纹理节点
        image_1_node = None
        principled = None
        for node in mat.node_tree.nodes:
            if node.type == 'TEX_IMAGE' and node.image:
                if "image_1" in node.image.name.lower():
                    image_1_node = node
            if node.type == 'PRINCIPLED_BSDF':
                principled = node

        if image_1_node and principled:
            # 创建 Separate Color 节点
            sep = mat.node_tree.nodes.new('ShaderNodeSeparateColor')
            sep.location = (image_1_node.location.x + 200, image_1_node.location.y)

            # 连接: Image_1 → Separate Color
            mat.node_tree.links.new(image_1_node.outputs['Color'], sep.inputs['Color'])

            # 连接: Green → Roughness, Blue → Metallic
            mat.node_tree.links.new(sep.outputs['Green'], principled.inputs['Roughness'])
            mat.node_tree.links.new(sep.outputs['Blue'], principled.inputs['Metallic'])

            print(f"  PBR 连接 {mat.name}: Image_1 → SeparateColor → Roughness/Metallic")
            fixes_applied.append({"fix": "pbr_connection", "material": mat.name})

    # === 修复 5: 法线修复 ===
    for obj in bpy.data.objects:
        if obj.type == 'MESH':
            bpy.context.view_layer.objects.active = obj
            obj.select_set(True)
            bpy.ops.object.mode_set(mode='EDIT')
            bpy.ops.mesh.select_all(action='SELECT')
            bpy.ops.mesh.normals_make_consistent(inside=False)
            bpy.ops.object.mode_set(mode='OBJECT')
            obj.select_set(False)
            fixes_applied.append({"fix": "recalculate_normals", "object": obj.name})

    # === 修复 6: 底面对齐 z=0 ===
    for obj in bpy.data.objects:
        if obj.type == 'MESH':
            bbox_min_z = min(v.co.z for v in obj.bound_box)
            if bbox_min_z > 0.01 or bbox_min_z < -0.01:
                obj.location.z -= bbox_min_z
                bpy.context.view_layer.update()
                print(f"  底面对齐 {obj.name}: z={bbox_min_z:.4f} → z=0")
                fixes_applied.append({
                    "fix": "ground_align",
                    "object": obj.name,
                    "offset": round(-bbox_min_z, 4)
                })

    # 导出修复后的模型
    os.makedirs(os.path.dirname(os.path.abspath(output_path)), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=output_path,
        export_format='GLB',
        export_apply_modifiers=True,
    )

    # 输出摘要
    print(f"\n{'='*50}")
    print(f"修复完成: {len(fixes_applied)} 项修复")
    for fix in fixes_applied:
        print(f"  ✅ {fix['fix']}: {fix.get('object', fix.get('material', ''))}")
    print(f"\n修复后模型: {output_path}")

fix_model("${GLB_FILE}", "${OUTPUT_FILE}")
PYEOF
)

"$BLENDER" --background --python-expr "$PYTHON_SCRIPT" 2>&1 | grep -v "^Blender\|^Read\|^Fra:"

echo "修复完成: $OUTPUT_FILE"
