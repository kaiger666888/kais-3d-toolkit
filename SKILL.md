---
name: kais-3d-toolkit
version: 1.0.0
description: "GLB 3D 模型统一管理工具链。'3d工具' '3d toolkit' 'glb检查' 'glb修复' 'glb导入' 'glb截图' '模型检查' '模型修复' '模型截图' '3d模型处理' 'glb inspect' 'glb fix' 'glb screenshot' 'trellis后处理' 'trellis fix' '3d预览' '模型预览' 'model preview' '3d pipeline' 'glb pipeline' 'pbr修复' 'pbr fix' '检查glb' '修复3d模型' '模型质量检查' 'blender glb' 'glb blender'。当需要检查GLB模型信息、修复TRELLIS2生成模型兼容性、多角度截图预览、处理PBR纹理映射时触发"
---

# kais-3d-toolkit — GLB 3D 模型统一管理工具链

> GLB 模型导入→检查→修复→截图一站式处理，专为 TRELLIS2 生成模型优化。

## 自动化分级

| 步骤 | 区域 | 人工参与 |
|------|------|---------|
| 模型检查 (inspect) | AUTO | 无人值守，输出报告 |
| 自动修复 (fix) | AUTO | 按规则自动修复已知问题 |
| 快速截图 (screenshot threejs) | AUTO | Three.js 渲染，<5s |
| 高质量截图 (screenshot blender) | SEMIAUTO | Blender 渲染，需确认修复 |
| 导入+全流程 (import) | AUTO | 一键完成检查+修复+截图 |

## 环境依赖

| 工具 | 路径 | 用途 |
|------|------|------|
| Blender 4.5+ | `/usr/local/bin/blender` | 高质量渲染、模型修复 |
| Playwright | `/home/kai/.openclaw/workspace/node_modules/playwright` | Three.js 截图渲染 |
| 输出目录 | `/mnt/agents/output/` | 截图和报告输出 |

## 触发场景

- 用户说"检查这个 GLB"/"修复 GLB"/"3D 模型截图"
- TRELLIS2 生成模型后的后处理
- 从外部获取 GLB 需要质量检查
- 发送给用户前的模型预处理

## 使用方法

### 检查模型 (inspect)

检查 GLB 模型基本信息，输出结构化报告。

```bash
# 基本检查
./scripts/inspect.sh model.glb

# 指定输出目录
./scripts/inspect.sh model.glb --output /mnt/agents/output/
```

输出报告包含：
- 对象列表（名称/顶点数/面数/类型）
- 材质信息（名称/纹理通道/blend_mode）
- 模型尺寸（原始 + 建议）
- 已知问题检测（Cube残留/尺寸过小/PBR配置/法线方向）

### 修复模型 (fix)

自动修复 GLB→Blender 已知兼容性问题。

```bash
# 交互式修复（会显示检测到的问题并确认）
./scripts/fix.sh model.glb

# 全自动修复（不询问）
./scripts/fix.sh model.glb --auto

# 修复并另存
./scripts/fix.sh model.glb --output model_fixed.glb
```

修复规则（按顺序执行）：

| # | 问题 | 检测条件 | 修复动作 |
|---|------|---------|---------|
| 1 | Cube 残留 | 对象名"Cube"且有8顶点6面 | 删除 |
| 2 | 模型太小 | 主模型 < 0.5m 任意维度 | 等比放大至合理尺寸 |
| 3 | 材质模式 | blend_mode ≠ OPAQUE | 设为 OPAQUE |
| 4 | PBR 纹理 | Image_1 存在但未连接 | SeparateColor→Green=Roughness, Blue=Metallic |
| 5 | 法线方向 | 存在翻转法线 | recalculate outside |
| 6 | 底面未对齐 | 模型底部 > z=0.01 | 移动使底面 z=0 |

### 截图 (screenshot)

#### Three.js 快速截图（推荐日常使用）

```bash
# 默认4角度截图
./scripts/screenshot.sh model.glb --method threejs

# 指定角度
./scripts/screenshot.sh model.glb --method threejs --angles front,side,top

# 自定义分辨率
./scripts/screenshot.sh model.glb --method threejs --resolution 1024
```

- 渲染速度：<5s
- 优势：自动忽略 alpha 通道，无需 Blender
- 限制：PBR 材质可能不如 Blender 准确

#### Blender 高质量截图

```bash
# EEVEE_NEXT 渲染（需要先 fix）
./scripts/screenshot.sh model.glb --method blender

# 指定渲染引擎
./scripts/screenshot.sh model.glb --method blender --engine cycles

# 指定采样数
./scripts/screenshot.sh model.glb --method blender --samples 128
```

- 渲染速度：~10-30s/张
- 优势：PBR 材质准确，EEVEE_NEXT/Cycles 高质量
- 前提：模型需先修复（Cube/材质模式）

### 导入全流程 (import)

一键完成检查→修复→截图。

```bash
# 完整流程
./scripts/import.sh model.glb

# 只截图不修复
./scripts/import.sh model.glb --skip-fix

# 指定截图方式
./scripts/import.sh model.glb --screenshot-method blender
```

## 参数说明

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `--output` / `-o` | path | `/mnt/agents/output/` | 输出目录 |
| `--method` | string | `threejs` | 截图方式：threejs / blender |
| `--angles` | string | `front,side,top,45deg` | 截图角度（逗号分隔） |
| `--resolution` | int | 512 | 截图分辨率 |
| `--engine` | string | `eevee` | Blender 渲染引擎：eevee / cycles |
| `--samples` | int | 32 | 渲染采样数 |
| `--auto` | flag | false | 自动修复（不询问） |
| `--skip-fix` | flag | false | 跳过修复步骤 |

## 截图角度说明

| 角度名 | 相机位置 | 适用于 |
|--------|---------|--------|
| `front` | 正前方 | 默认包含 |
| `side` | 右侧90° | 默认包含 |
| `top` | 正上方俯视 | 默认包含 |
| `45deg` | 前侧45° | 默认包含 |
| `back` | 正后方 | 可选 |
| `low` | 低角度仰拍 | 可选 |
| `closeup` | 面部特写 | 可选 |

## 输出规范

```
/mnt/agents/output/<model_name>/
├── report.json           # 检查报告
├── issues.json           # 发现的问题列表
├── fixed.glb             # 修复后的模型（如有修复）
└── screenshots/
    ├── front.png
    ├── side.png
    ├── top.png
    └── 45deg.png
```

## PBR 纹理规则

TRELLIS2 生成的 GLB 使用特殊 PBR 纹理方案：

| 纹理 | 通道 | 用途 | 注意 |
|------|------|------|------|
| Image_0 | RGB | Base Color（漫反射颜色） | 第4通道非 alpha，是 PBR 数据 |
| Image_0 | A | PBR 属性数据 | Three.js 自动忽略，Blender 需设 OPAQUE |
| Image_1 | R | 未使用 | — |
| Image_1 | G | Roughness（粗糙度） | SeparateColor 提取 |
| Image_1 | B | Metallic（金属度） | SeparateColor 提取 |

**关键规则：**
- 材质 blend_mode 必须为 OPAQUE（不能是 BLEND 或 CLIP）
- Image_0 的第4通道不是透明度，不能用于 alpha 混合
- Three.js 自动处理此问题，Blender 需要手动设置

## 与其他 Skill 协作

```
TRELLIS2 (Image-to-3D) → GLB 输出
       ↓
kais-3d-toolkit (本skill) → 检查/修复/截图
       ↓
kais-blender-engine (高质量渲染/动画) → 集成到场景
       ↓
kais-jimeng / kais-camera → 最终视频/图片
```

## 注意事项

- Blender 脚本通过 `blender --background --python` 无头运行
- Three.js 截图需要 Playwright Chromium，首次可能需要 `npx playwright install chromium`
- 修复操作会修改模型文件，建议先 inspect 确认
- `--auto` 模式下所有修复自动执行，请确认模型可被修改
