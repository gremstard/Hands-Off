import bpy, sys, mathutils, time
src = sys.argv[sys.argv.index("--") + 1]
bpy.ops.wm.read_factory_settings(use_empty=True)
t0 = time.time()
bpy.ops.import_scene.gltf(filepath=src)
print("RED import %.0fs" % (time.time() - t0))
body = max((o for o in bpy.data.objects if o.type == "MESH"), key=lambda o: len(o.data.vertices))
def bbox(o):
    cs = [o.matrix_world @ mathutils.Vector(c) for c in o.bound_box]
    return "x[%.2f,%.2f] z[%.2f,%.2f]" % (min(c.x for c in cs), max(c.x for c in cs), min(c.z for c in cs), max(c.z for c in cs))
print("RED body", len(body.data.vertices), "verts", bbox(body))
bpy.ops.object.select_all(action="DESELECT"); body.select_set(True); bpy.context.view_layer.objects.active = body
bpy.ops.object.mode_set(mode="EDIT"); bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.mesh.remove_doubles(threshold=0.0001)
bpy.ops.object.mode_set(mode="OBJECT")
print("RED after merge", len(body.data.vertices), bbox(body), "%.0fs" % (time.time() - t0))
# staged collapse
stage = 0
while len(body.data.vertices) > 30000 and stage < 8:
    stage += 1
    n = len(body.data.vertices)
    ratio = max(0.2, 24000.0 / n)
    mod = body.modifiers.new("D", "DECIMATE"); mod.decimate_type = "COLLAPSE"; mod.ratio = ratio
    bpy.ops.object.modifier_apply(modifier=mod.name)
    print("RED stage %d ratio %.2f -> %d verts %s  %.0fs" % (stage, ratio, len(body.data.vertices), bbox(body), time.time() - t0))
