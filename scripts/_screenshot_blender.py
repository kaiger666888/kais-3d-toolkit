import bpy, math, sys

def get_args():
    if '--' in sys.argv:
        idx = sys.argv.index('--')
        return sys.argv[idx+1:]
    else:
        return sys.argv[6:]

args = get_args()
filepath = args[0]
output_path = args[1]
angle = args[2]
resolution = int(args[3])
engine = args[4]
samples = int(args[5])

# 清空默认场景对象
bpy.ops.object.select_all(action='SELECT')
try:
    bpy.ops.object.delete()
except Exception:
    pass
bpy.ops.import_scene.gltf(filepath=filepath)

# 设置渲染引擎
if engine == 'cycles':
    bpy.context.scene.render.engine = 'CYCLES'
    bpy.context.scene.cycles.samples = samples
else:
    bpy.context.scene.render.engine = 'BLENDER_EEVEE_NEXT'

bpy.context.scene.render.resolution_x = resolution
bpy.context.scene.render.resolution_y = resolution
bpy.context.scene.render.filepath = output_path
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

# 角度配置
cam_positions = {
    'front':   (0, -2.5, 1.2, (75, 0, 0)),
    'side':    (2.5, 0, 1.2, (90, 0, 90)),
    'top':     (0, 0, 3.0, (0, 0, 0)),
    '45deg':   (1.8, -1.8, 1.2, (75, 0, 45)),
    'back':    (0, 2.5, 1.2, (75, 0, 180)),
    'low':     (1.5, -1.5, 0.3, (85, 0, 45)),
    'closeup': (0, -1.0, 1.5, (80, 0, 0)),
}

pos = cam_positions.get(angle, cam_positions['45deg'])
cam_obj.location = pos[0], pos[1], pos[2]

from math import radians
cam_data.lens = 50

# 简单方式：创建一个空对象作为 target，用 Track To
target_obj = bpy.data.objects.new('track_target', None)
bpy.context.collection.objects.link(target_obj)
target_obj.location = (0, 0, 0.9)

constraint = cam_obj.constraints.new('TRACK_TO')
constraint.target = target_obj
constraint.track_axis = 'TRACK_NEGATIVE_Z'
constraint.up_axis = 'UP_Y'

bpy.ops.render.render(write_still=True)
print(f"  ✓ {angle} 保存完成")
