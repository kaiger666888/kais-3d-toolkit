# PBR 纹理修复规则详解

## TRELLIS2 GLB 纹理方案

TRELLIS2 生成的 GLB 使用双纹理 PBR 方案，与传统 PBR 工作流不同。

### 纹理映射

| 纹理文件 | 通道 | 用途 | Blender 节点 |
|----------|------|------|---------------|
| Image_0 | R, G, B | Base Color（漫反射颜色） | Principled BSDF → Base Color |
| Image_0 | A | PBR 属性数据（不是 alpha） | **不连接** |
| Image_1 | R | 未使用 | — |
| Image_1 | G | Roughness（粗糙度） | SeparateColor → Green → Principled BSDF → Roughness |
| Image_1 | B | Metallic（金属度） | SeparateColor → Blue → Principled BSDF → Metallic |

### 关键注意事项

1. **Image_0 的 Alpha 通道不是透明度**
   - Three.js 自动忽略此通道
   - Blender 会尝试将其用作 alpha，导致透明/半透明错误
   - **修复：材质 blend_method 设为 OPAQUE**

2. **材质模式必须是 OPAQUE**
   - 不能用 BLEND（Alpha Blending）
   - 不能用 CLIP（Alpha Clipping）
   - 用 HASHED 也不合适（会有噪点）

3. **Image_1 需要通道分离**
   - 导入时通常只连接了 Color 输出
   - 需要 SeparateColor 节点拆分通道
   - Green → Roughness, Blue → Metallic

### Blender 节点连接图

```
[Image_0 Texture]
    ├── Color → [Principled BSDF].Base Color

[Image_1 Texture]
    └── Color → [Separate Color]
                    ├── Green → [Principled BSDF].Roughness
                    └── Blue  → [Principled BSDF].Metallic
```

### Three.js 为什么不需要修复

Three.js 的 GLTFLoader 在加载 GLB 时：
- 自动将 Image_0.A 视为无关数据
- 默认使用 OPAQUE 模式
- PBR 通道自动映射（如果有扩展）

### 何时需要修复

- **Blender 导入时**：需要手动修复上述所有问题
- **发送给用户前**：建议用 Blender 修复后重新导出
- **快速预览时**：可用 Three.js 方案跳过修复

## 尺寸缩放规则

TRELLIS2 生成的模型通常尺寸约为 0.3×0.2×0.95m（约真实人体的 1/5~1/6）。

### 缩放策略

1. 计算模型最大维度
2. 如果最大维度 < 0.5m，执行缩放
3. 缩放因子 = 目标高度 / 当前高度
4. 默认目标高度：1.7m（成人平均身高）
5. 等比缩放（uniform scale）

### 判断逻辑

```python
max_dim = max(obj.dimensions.x, obj.dimensions.y, obj.dimensions.z)
if max_dim < 0.5:
    scale_factor = 1.7 / obj.dimensions.z  # 以高度为基准
    obj.scale *= scale_factor
```
