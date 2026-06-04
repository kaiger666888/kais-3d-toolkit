import bpy, json, sys, os, math

def get_args():
    if '--' in sys.argv:
        idx = sys.argv.index('--')
        return sys.argv[idx+1:]
    else:
        return sys.argv[5:]

args = get_args()
filepath = args[0]
output_path = args[1]
auto_mode = '--auto' in args

def fix_model(filepath, output_path, auto_mode):
    # 导入 GLB（不使用 read_factory_settings，因为它会清除 addon）
    # 先删除默认场景中的所有对象
    bpy.ops.object.select_all(action='SELECT')
    try:
        bpy.ops.object.delete()
    except Exception:
        pass
    bpy.ops.import_scene.gltf(filepath=filepath)

    fixes_applied = []

    # === 修复 1: 删除 Cube 残留 ===
    for obj in list(bpy.data.objects):
        if obj.name == "Cube" and obj.type == 'MESH':
            mesh = obj.data
            if len(mesh.vertices) == 8 and len(mesh.polygons) == 6:
                print(f"  删除残留 Cube: {obj.name}")
                bpy.data.objects.remove(obj, do_unlink=True)
                fixes_applied.append({"fix": "delete_cube", "object": "Cube"})

    # === 修复 2: 模型太小 → 放大 ===
    main_objects = [o for o in bpy.data.objects if o.type == 'MESH']
    for obj in main_objects:
        max_dim = max(obj.dimensions.x, obj.dimensions.y, obj.dimensions.z)
        if max_dim < 0.5:
            scale_factor = 1.0 / max_dim
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

            mat.node_tree.links.new(image_1_node.outputs['Color'], sep.inputs['Color'])
            mat.node_tree.links.new(sep.outputs['Green'], principled.inputs['Roughness'])
            mat.node_tree.links.new(sep.outputs['Blue'], principled.inputs['Metallic'])

            print(f"  PBR 连接 {mat.name}: Image_1 → SeparateColor → Roughness/Metallic")
            fixes_applied.append({"fix": "pbr_connection", "material": mat.name})

    # === 修复 5: 网格清理（合并重叠顶点 + 清理退化面）===
    for obj in bpy.data.objects:
        if obj.type == 'MESH':
            bpy.context.view_layer.objects.active = obj
            obj.select_set(True)

            pre_verts = len(obj.data.vertices)
            pre_faces = len(obj.data.polygons)

            bpy.ops.object.mode_set(mode='EDIT')
            bpy.ops.mesh.select_all(action='SELECT')

            # 合并距离内的重叠顶点（消除表面凸起主因）
            bpy.ops.mesh.remove_doubles(threshold=0.0001)

            # 删除面积为0的退化面
            bpy.ops.mesh.delete_loose()
            # clean_vertices 在 Blender 4.5 中移除，用手动方式
            bpy.ops.mesh.dissolve_degenerate(threshold=0.0001)

            # 法线统一朝外
            bpy.ops.mesh.normals_make_consistent(inside=False)

            bpy.ops.object.mode_set(mode='OBJECT')
            obj.select_set(False)

            post_verts = len(obj.data.vertices)
            post_faces = len(obj.data.polygons)
            merged = pre_verts - post_verts
            removed_faces = pre_faces - post_faces

            if merged > 0 or removed_faces > 0:
                print(f"  网格清理 {obj.name}: 合并 {merged} 重叠顶点, 删除 {removed_faces} 退化面")
                fixes_applied.append({
                    "fix": "mesh_cleanup",
                    "object": obj.name,
                    "merged_vertices": merged,
                    "removed_faces": removed_faces,
                    "pre_verts": pre_verts,
                    "post_verts": post_verts,
                })

    # === 修复 6: 底面对齐 z=0 ===
    for obj in bpy.data.objects:
        if obj.type == 'MESH':
            bbox_min_z = min(corner[2] for corner in obj.bound_box)
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
    )

    print(f"\n{'='*50}")
    print(f"修复完成: {len(fixes_applied)} 项修复")
    for fix in fixes_applied:
        print(f"  ✅ {fix['fix']}: {fix.get('object', fix.get('material', ''))}")
    print(f"\n修复后模型: {output_path}")

fix_model(filepath, output_path, auto_mode)
