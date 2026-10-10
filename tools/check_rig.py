"""Reimport a rigged GLB and report how well the bones sit inside the mesh."""
import bpy, sys, mathutils
path = sys.argv[sys.argv.index("--") + 1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=path)
arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
body = max((o for o in bpy.data.objects if o.type == "MESH"), key=lambda o: len(o.data.vertices))
mw = body.matrix_world
vs = [mw @ v.co for v in body.data.vertices]
def bw(n): return arm.matrix_world @ arm.data.bones[n].head_local
bx = (min(v.x for v in vs), max(v.x for v in vs)); by = (min(v.y for v in vs), max(v.y for v in vs)); bz = (min(v.z for v in vs), max(v.z for v in vs))
print("CHECK body x %.2f..%.2f  y %.2f..%.2f  z %.2f..%.2f" % (bx + by + bz))
for n in ["pelvis", "spine_03", "Head", "upperarm_l", "hand_l", "thigh_l", "foot_l"]:
    p = bw(n)
    near = [v for v in vs if (v - p).length < 0.12]
    print("CHECK %-10s at x=%.2f y=%.2f z=%.2f  mesh verts within 12cm: %d" % (n, p.x, p.y, p.z, len(near)))
hip = [v for v in vs if abs(v.z - bw("pelvis").z) < 0.1]
print("CHECK hips centre y=%.2f vs pelvis bone y=%.2f" % ((min(v.y for v in hip) + max(v.y for v in hip)) / 2, bw("pelvis").y))
arm_pts = [v for v in vs if abs(v.x) > 0.3 and v.z > 1.0]
print("CHECK arm centre z=%.2f vs upperarm bone z=%.2f" % ((min(v.z for v in arm_pts) + max(v.z for v in arm_pts)) / 2, bw("upperarm_l").z))
