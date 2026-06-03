import bpy, json, sys, os

def inspect_model(filepath, output_dir):
    # 清空场景但保留 gltf importer addon
    bpy.ops.object.select_all(action='SELECT')
    try:
        bpy.ops.object.delete()
    except Exception:
        pass
    bpy.ops.import_scene.gltf(filepath=filepath)

    objects_info = []
    materials_info = []
    issues = []

    for obj in bpy.data.objects:
        if obj.type == 'MESH':
            mesh = obj.data
            verts = len(mesh.vertices)
            faces = len(mesh.polygons)

            obj_info = {
                "name": obj.name,
                "vertices": verts,
                "faces": faces,
                "type": obj.type,
                "dimensions": {
                    "x": round(obj.dimensions.x, 4),
                    "y": round(obj.dimensions.y, 4),
                    "z": round(obj.dimensions.z, 4),
                },
                "location": {
                    "x": round(obj.location.x, 4),
                    "y": round(obj.location.y, 4),
                    "z": round(obj.location.z, 4),
                },
            }
            objects_info.append(obj_info)

            # 检测 Cube 残留
            if obj.name == "Cube" and verts == 8 and faces == 6:
                issues.append({
                    "type": "cube_residual",
                    "severity": "high",
                    "object": obj.name,
                    "message": "检测到 GLB 导入残留 Cube（8顶点6面），应删除"
                })

            # 检测尺寸过小
            max_dim = max(obj.dimensions.x, obj.dimensions.y, obj.dimensions.z)
            if max_dim < 0.5 and obj.name != "Cube":
                issues.append({
                    "type": "too_small",
                    "severity": "high",
                    "object": obj.name,
                    "message": f"模型太小（最大维度 {max_dim:.3f}m），建议放大",
                    "max_dimension": round(max_dim, 4)
                })

            # 检测法线方向
            if mesh.polygons:
                flipped = sum(1 for p in mesh.polygons if not p.use_smooth)
                if flipped > len(mesh.polygons) * 0.5:
                    issues.append({
                        "type": "normals_inconsistent",
                        "severity": "medium",
                        "object": obj.name,
                        "message": f"法线方向可能不一致（{flipped}/{len(mesh.polygons)} 面为硬边）"
                    })

            # 检测底面未对齐
            bbox_min_z = min(corner[2] for corner in obj.bound_box)
            if bbox_min_z > 0.01:
                issues.append({
                    "type": "not_grounded",
                    "severity": "low",
                    "object": obj.name,
                    "message": f"模型底部未对齐地面（z={bbox_min_z:.4f}），建议下移"
                })

    # 检查材质
    for mat in bpy.data.materials:
        if not mat.use_nodes:
            continue

        mat_info = {
            "name": mat.name,
            "blend_mode": getattr(mat, 'blend_method', 'UNKNOWN'),
            "use_backface_culling": getattr(mat, 'use_backface_culling', False),
            "textures": [],
        }

        # 检查纹理节点
        for node in mat.node_tree.nodes:
            if node.type == 'TEX_IMAGE' and node.image:
                tex_info = {
                    "node_name": node.name,
                    "image_name": node.image.name,
                    "size": list(node.image.size),
                    "colorspace": node.image.colorspace_settings.name,
                }
                mat_info["textures"].append(tex_info)

                # 检测 PBR Image_1 是否已正确连接
                if "Image_1" in node.image.name or "image_1" in node.image.name.lower():
                    if not node.outputs[0].is_linked:
                        issues.append({
                            "type": "pbr_unconnected",
                            "severity": "high",
                            "material": mat.name,
                            "message": "Image_1 (PBR) 纹理未连接，需 SeparateColor→Roughness/Metallic"
                        })

        materials_info.append(mat_info)

        # 检测材质模式
        blend = getattr(mat, 'blend_method', None)
        if blend and blend != 'OPAQUE':
            issues.append({
                "type": "wrong_blend_mode",
                "severity": "high",
                "material": mat.name,
                "message": f"材质模式为 {blend}，应为 OPAQUE"
            })

    report = {
        "file": filepath,
        "objects_count": len(bpy.data.objects),
        "mesh_objects": len([o for o in bpy.data.objects if o.type == 'MESH']),
        "materials_count": len(bpy.data.materials),
        "objects": objects_info,
        "materials": materials_info,
        "total_vertices": sum(o["vertices"] for o in objects_info),
        "total_faces": sum(o["faces"] for o in objects_info),
    }

    report_path = os.path.join(output_dir, "report.json")
    issues_path = os.path.join(output_dir, "issues.json")

    with open(report_path, 'w') as f:
        json.dump(report, f, indent=2, ensure_ascii=False)

    with open(issues_path, 'w') as f:
        json.dump(issues, f, indent=2, ensure_ascii=False)

    # 输出摘要
    print(f"\n{'='*50}")
    print(f"模型检查报告: {filepath}")
    print(f"{'='*50}")
    print(f"对象数: {report['mesh_objects']}")
    print(f"总顶点: {report['total_vertices']}")
    print(f"总面数: {report['total_faces']}")
    print(f"材质数: {report['materials_count']}")
    print()

    for obj in objects_info:
        dim = obj['dimensions']
        print(f"  [{obj['name']}] {obj['vertices']}v {obj['faces']}f  尺寸: {dim['x']:.3f}×{dim['y']:.3f}×{dim['z']:.3f}m")

    if issues:
        print(f"\n发现 {len(issues)} 个问题:")
        for issue in issues:
            icon = {"high": "❌", "medium": "⚠️", "low": "ℹ️"}.get(issue['severity'], "?")
            print(f"  {icon} [{issue['severity']}] {issue['message']}")
    else:
        print("\n✅ 未发现已知问题")

    print(f"\n报告已保存: {report_path}")
    print(f"问题列表: {issues_path}")

if '--' in sys.argv:
    idx = sys.argv.index('--')
    args = sys.argv[idx+1:]
else:
    args = sys.argv[5:]  # blender --background --python script.py arg1 arg2
inspect_model(args[0], args[1])
