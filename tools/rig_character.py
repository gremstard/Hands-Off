"""Rig an exported Hands Off character GLB to the Quaternius UAL armature.

usage: Blender -b --python tools/rig_character.py -- in.glb out.glb [armature.glb]

- imports the UAL armature (from Mannequin_F.glb), drops its mesh
- imports the character, drops the reference 'Mannequin' mesh
- scales/positions the armature to the body's height, applies transforms
- body: automatic weights; face parts: 100% to the Head bone
- exports a GLB with the skin (no animations; Godot adds the UAL library)
"""
import bpy, sys, os, mathutils

argv = sys.argv[sys.argv.index("--") + 1:]
src, dst = argv[0], argv[1]
arm_glb = argv[2] if len(argv) > 2 else "assets/animations/Mannequin_F.glb"

bpy.ops.wm.read_factory_settings(use_empty=True)

# --- armature
bpy.ops.import_scene.gltf(filepath=arm_glb)
arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
ref_mesh = next(o for o in bpy.data.objects if o.type == "MESH")
bpy.data.objects.remove(ref_mesh, do_unlink=True)
# rig height = top of the Head bone in armature space (root sits at the feet)
rig_h = arm.data.bones["Head"].tail_local.z
arm.name = "Armature"
# The glb import leaves the armature posed (the file's node transforms) on
# top of its rest pose. Bind and export against the rest pose only.
posed = sum(1 for pb in arm.pose.bones if pb.rotation_quaternion.angle > 0.01 or pb.location.length > 0.001)
print("RIG posed bones on import: %d" % posed)
for pb in arm.pose.bones:
    pb.matrix_basis = mathutils.Matrix.Identity(4)
bpy.context.view_layer.update()

# The UAL rig rests in an A-pose; the character is modelled in a T-pose.
# Swing each arm chain up to horizontal before binding so the skin matches.
# (Godot drops the clips' per-bone position tracks, so this edit is safe.)
bpy.ops.object.select_all(action="DESELECT")
arm.select_set(True); bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode="EDIT")
eb = arm.data.edit_bones
ARM_PARTS = ("upperarm", "lowerarm", "hand", "index", "middle", "ring", "pinky", "thumb")
for side, sign in (("_l", 1.0), ("_r", -1.0)):
    up = eb["upperarm" + side]
    pivot = up.head.copy()
    cur = (up.tail - up.head).normalized()
    target = mathutils.Vector((sign, 0.0, 0.0))
    R = cur.rotation_difference(target).to_matrix().to_4x4()
    M = mathutils.Matrix.Translation(pivot) @ R @ mathutils.Matrix.Translation(-pivot)
    for b in eb:
        if b.name.endswith(side) and b.name.split("_")[0] in ARM_PARTS:
            b.transform(M, scale=False, roll=True)
bpy.ops.object.mode_set(mode="OBJECT")
print("RIG arms set to T-pose")

# Only the main body bones deform this blocky character. Fingers, leaf and
# helper bones would steal weight from the hands and torso.
DEFORM = {"pelvis", "spine_01", "spine_02", "spine_03", "neck_01", "Head",
          "clavicle_l", "upperarm_l", "lowerarm_l", "hand_l",
          "clavicle_r", "upperarm_r", "lowerarm_r", "hand_r",
          "thigh_l", "calf_l", "foot_l", "thigh_r", "calf_r", "foot_r"}
for b in arm.data.bones:
    b.use_deform = b.name in DEFORM

# --- character
before = set(bpy.data.objects)
bpy.ops.import_scene.gltf(filepath=src)
new = [o for o in bpy.data.objects if o not in before]
for o in new:
    if o.type == "MESH" and o.name.startswith("Mannequin"):
        bpy.data.objects.remove(o, do_unlink=True)
meshes = [o for o in bpy.data.objects if o.type == "MESH"]
body = max(meshes, key=lambda o: o.dimensions.z)
parts = [o for o in meshes if o is not body and not o.name.startswith("Mannequin")]

# Exports with the subdivision applied at render level arrive with millions
# of vertices. Merge split vertices, then collapse-decimate to game size.
BODY_TARGET = int(os.environ.get("RIG_BODY_VERTS", "60000"))
for o in meshes:
    target = BODY_TARGET if o is body else 800
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True); bpy.context.view_layer.objects.active = o
    n0 = len(o.data.vertices)
    # Merge the export's split vertices, but only where the UVs agree, so
    # texture seams (body strip vs hand strip) stay intact.
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(o.data)
    uv_layer = bm.loops.layers.uv.active
    buckets = {}
    for v in bm.verts:
        uv = None
        if uv_layer is not None and v.link_loops:
            l = v.link_loops[0][uv_layer].uv
            uv = (round(l.x, 4), round(l.y, 4))
        key = (round(v.co.x, 4), round(v.co.y, 4), round(v.co.z, 4), uv)
        buckets.setdefault(key, []).append(v)
    # the mirror seam (x ~ 0) must close even where the two halves' UVs differ
    seam = {}
    for v in bm.verts:
        if abs(v.co.x) < 0.002:
            key = (round(v.co.y, 3), round(v.co.z, 3))
            seam.setdefault(key, []).append(v)
    for g in seam.values():
        if len(g) > 1:
            buckets[("seam",) + tuple(id(x) for x in g[:1])] = g
    targetmap = {}
    for group in buckets.values():
        if len(group) > 1:
            for v in group[1:]:
                targetmap[v] = group[0]
    if targetmap:
        bmesh.ops.weld_verts(bm, targetmap=targetmap)
    # (face orientation from the export is kept; recalculating flips patches at the crotch)
    bm.to_mesh(o.data)
    bm.free()
    try:
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.customdata_custom_splitnormals_clear()
        bpy.ops.object.mode_set(mode="OBJECT")
    except Exception:
        bpy.ops.object.mode_set(mode="OBJECT")
    n = len(o.data.vertices)
    if n > target * 1.5:
        mod = o.modifiers.new("Decimate", "DECIMATE")
        mod.decimate_type = "COLLAPSE"
        mod.ratio = target / n
        mod.use_collapse_triangulate = True
        bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.ops.object.shade_smooth()
    print("RIG reduced %s: %d -> %d -> %d verts" % (o.name, n0, n, len(o.data.vertices)))

# Exports with an unapplied Mirror modifier arrive as half a body. Detect a
# one-sided body and mirror it across X (merging the seam).
bb = [body.matrix_world @ mathutils.Vector(c) for c in body.bound_box]
bx0 = min(c.x for c in bb); bx1 = max(c.x for c in bb)
if min(abs(bx0), abs(bx1)) < 0.08 * (bx1 - bx0):
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True); bpy.context.view_layer.objects.active = body
    # trim any overshoot past the centre line so the mirrored halves meet exactly
    keep_positive = abs(bx1) > abs(bx0)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    inv = body.matrix_world.inverted()
    co = inv @ mathutils.Vector((0.0, 0.0, 0.0))
    no = (inv.to_3x3() @ mathutils.Vector((1.0, 0.0, 0.0))).normalized()
    bpy.ops.mesh.bisect(plane_co=co, plane_no=no, clear_inner=keep_positive, clear_outer=not keep_positive)
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.remove_doubles(threshold=0.0005)
    bpy.ops.object.mode_set(mode="OBJECT")
    mod = body.modifiers.new("Mirror", "MIRROR")
    mod.use_axis[0] = True
    mod.use_mirror_merge = True
    mod.merge_threshold = 0.02
    bpy.ops.object.modifier_apply(modifier=mod.name)
    print("RIG body was one-sided (x %.2f..%.2f); mirrored across X -> %d verts" % (bx0, bx1, len(body.data.vertices)))
    for o in parts:
        pb = [o.matrix_world @ mathutils.Vector(c) for c in o.bound_box]
        px0 = min(c.x for c in pb); px1 = max(c.x for c in pb)
        if min(abs(px0), abs(px1)) < 0.08 * (px1 - px0) and (px1 - px0) > 0.05:
            bpy.ops.object.select_all(action="DESELECT")
            o.select_set(True); bpy.context.view_layer.objects.active = o
            m2 = o.modifiers.new("Mirror", "MIRROR")
            m2.use_axis[0] = True
            bpy.ops.object.modifier_apply(modifier=m2.name)
            print("RIG mirrored part %s" % o.name)

# Optional extra smoothing: the normal exports are the cage at subdivision 2;
# RIG_SUBSURF=1 applies one more Catmull-Clark level to the body (x4 verts).
extra = int(os.environ.get("RIG_SUBSURF", "1"))
if extra > 0:
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True); bpy.context.view_layer.objects.active = body
    mod = body.modifiers.new("Subsurf", "SUBSURF")
    mod.levels = extra
    bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.ops.object.shade_smooth()
    print("RIG subdivided body +%d: %d verts" % (extra, len(body.data.vertices)))

# world-space bbox of the body
import mathutils
bpy.context.view_layer.update()
corners = [body.matrix_world @ mathutils.Vector(c) for c in body.bound_box]
zmin = min(c.z for c in corners); zmax = max(c.z for c in corners)
xmin = min(c.x for c in corners); xmax = max(c.x for c in corners)
body_h = zmax - zmin
s = rig_h / (body_h * 0.97)   # shrink the character onto the rig; Godot rescales to player height
# The UAL rig faces -Y in Blender (+Z in glTF). Work out which way the
# character faces from where the face parts (eyes, nose, mouth) sit relative
# to the body, and spin it half a turn only if needed. So the model can be
# exported facing either way.
import math
if parts:
    face_y = sum((o.matrix_world.translation.y) for o in parts) / len(parts)
    body_y = sum(((body.matrix_world @ mathutils.Vector(c)).y) for c in body.bound_box) / 8.0
    if face_y > body_y:
        flip = mathutils.Matrix.Rotation(math.pi, 4, "Z")
        for o in meshes:
            o.matrix_world = flip @ o.matrix_world
        bpy.context.view_layer.update()
        print("RIG character faced +Y; flipped to face the rig's -Y")
    else:
        print("RIG character already faces -Y; no flip")
for o in meshes:
    o.location = (o.location.x * s, o.location.y * s, (o.location.z - zmin) * s)
    o.scale = (o.scale.x * s, o.scale.y * s, o.scale.z * s)
bpy.context.view_layer.update()
bpy.ops.object.select_all(action="DESELECT")
for o in meshes:
    o.select_set(True)
bpy.context.view_layer.objects.active = body
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


corners = [body.matrix_world @ mathutils.Vector(c) for c in body.bound_box]
zmin = min(c.z for c in corners); zmax = max(c.z for c in corners)
xmin = min(c.x for c in corners); xmax = max(c.x for c in corners)
body_h = zmax - zmin

def bone_world(name, tail=False):
    b = arm.data.bones[name]
    return arm.matrix_world @ (b.tail_local if tail else b.head_local)

print("RIG body height %.2f  width %.2f  (rig %.2f) mesh scale %.3f" % (body_h, xmax - xmin, rig_h, s))
for n in ["Head", "hand_l", "hand_r", "foot_l", "pelvis", "upperarm_l"]:
    p = bone_world(n); print("RIG bone %-10s head z=%.2f x=%.2f" % (n, p.z, p.x))
print("RIG hand tip x=%.2f vs body x extent %.2f" % (bone_world("hand_l", tail=True).x, xmax))

# --- line the armature up with the body front-to-back: the rig's pelvis
# should sit at the hips' centre, not in front of them.
mw = body.matrix_world
hip_ys = [(mw @ v.co).y for v in body.data.vertices if abs((mw @ v.co).z - bone_world("pelvis").z) < 0.12 and abs((mw @ v.co).x) < 0.3]
if hip_ys:
    hip_cy = (min(hip_ys) + max(hip_ys)) / 2.0
    dy = hip_cy - bone_world("pelvis").y
    arm.location.y += dy
    bpy.context.view_layer.update()
    bpy.ops.object.select_all(action="DESELECT")
    arm.select_set(True); bpy.context.view_layer.objects.active = arm
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    print("RIG armature shifted %.2f on Y to the hips' centre" % dy)

# --- fit the arm chain to the mesh. Godot drops the clips' position tracks
# (except root/pelvis), so bone positions and lengths can be edited freely.
mw = body.matrix_world
vs = [mw @ v.co for v in body.data.vertices]
pelvis_z = bone_world("pelvis").z
arm_z = bone_world("upperarm_l").z
neck_probe = bone_world("neck_01").z
# Shoulder = where the cross-section stops spanning the whole torso height
# and becomes just the arm's thickness, scanning outward along X.
torso_span = neck_probe - pelvis_z
torso_hw = xmax * 0.3
nb = 60
profile = []
for i in range(nb):
    x0 = xmax * i / nb; x1 = xmax * (i + 1) / nb
    zs = [v.z for v in vs if x0 <= abs(v.x) < x1 and v.z > pelvis_z]
    profile.append((x0, (max(zs) - min(zs)) if zs else 0.0, max(zs) if zs else 0.0, min(zs) if zs else 0.0))
print("RIG x-profile (x, z-extent, top, bottom): " + " ".join("%.2f:%.2f/%.2f/%.2f" % p for p in profile[::3]))
for x0, ext, top, bot in profile:
    if ext > 0 and ext < 0.3 * torso_span:   # the slice is just the arm's thickness
        torso_hw = x0
        break
hand_len = (xmax - torso_hw) * 0.2
print("RIG torso half-width %.2f, arm span to %.2f, hand length %.2f" % (torso_hw, xmax, hand_len))
bpy.ops.object.select_all(action="DESELECT")
arm.select_set(True); bpy.context.view_layer.objects.active = arm
# arm centre line (height and front/back) measured from the arm geometry
arm_pts = [v for v in vs if abs(v.x) > torso_hw * 1.1 and v.z > pelvis_z]
arm_cz = (min(v.z for v in arm_pts) + max(v.z for v in arm_pts)) / 2.0 if arm_pts else arm_z
arm_cy = (min(v.y for v in arm_pts) + max(v.y for v in arm_pts)) / 2.0 if arm_pts else bone_world("upperarm_l").y
print("RIG arm centre line z=%.2f y=%.2f (rig had z=%.2f)" % (arm_cz, arm_cy, arm_z))
bpy.ops.object.mode_set(mode="EDIT")
eb = arm.data.edit_bones
for side, sign in (("_l", 1.0), ("_r", -1.0)):
    clav = eb["clavicle" + side]; up = eb["upperarm" + side]; low = eb["lowerarm" + side]; hand = eb["hand" + side]
    z = arm_cz; y = arm_cy
    sh_x = sign * torso_hw * 1.0
    hand_x = sign * (xmax - hand_len)
    elbow_x = sh_x + (hand_x - sh_x) * 0.52
    old_hand_head = hand.head.copy()
    clav.tail = mathutils.Vector((sh_x, y, z))
    up.head = mathutils.Vector((sh_x, y, z)); up.tail = mathutils.Vector((elbow_x, y, z))
    low.head = mathutils.Vector((elbow_x, y, z)); low.tail = mathutils.Vector((hand_x, y, z))
    hand.head = mathutils.Vector((hand_x, y, z)); hand.tail = mathutils.Vector((sign * xmax, y, z))
    delta = hand.head - old_hand_head
    for b in eb:
        if b.name.endswith(side) and b.name.split("_")[0] in ("index", "middle", "ring", "pinky", "thumb"):
            b.head += delta; b.tail += delta
bpy.ops.object.mode_set(mode="OBJECT")
print("RIG arm chain fitted: shoulder x=%.2f hand x=%.2f..%.2f" % (torso_hw * 0.9, xmax - hand_len, xmax))

# --- skin the body
bpy.ops.object.select_all(action="DESELECT")
body.select_set(True); arm.select_set(True)
bpy.context.view_layer.objects.active = arm
try:
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")
except Exception as e:
    print("RIG auto weights raised", e)
unweighted = sum(1 for v in body.data.vertices if sum(g.weight for g in v.groups) < 0.01)
print("RIG body verts %d unweighted after auto %d" % (len(body.data.vertices), unweighted))

if unweighted > len(body.data.vertices) * 0.05:
    # Bone-heat failed (usual on dense subdivided blocky meshes). Fall back to
    # distance-to-bone-segment weights over the main limb bones.
    print("RIG falling back to nearest-bone weights")
    LIMB = ["pelvis", "spine_01", "spine_02", "spine_03", "neck_01", "Head",
            "clavicle_l", "upperarm_l", "lowerarm_l", "hand_l",
            "clavicle_r", "upperarm_r", "lowerarm_r", "hand_r",
            "thigh_l", "calf_l", "foot_l", "thigh_r", "calf_r", "foot_r"]
    segs = []
    for n in LIMB:
        b = arm.data.bones[n]
        h = arm.matrix_world @ b.head_local; t = arm.matrix_world @ b.tail_local
        if n.startswith("hand"):  # extend hand bones to cover the hand blocks
            t = h + (t - h) * 3.0
        segs.append((n, h, t))
    for vg in list(body.vertex_groups):
        body.vertex_groups.remove(vg)
    groups = {n: body.vertex_groups.new(name=n) for n in LIMB}
    if not any(m.type == "ARMATURE" for m in body.modifiers):
        body.modifiers.new("Armature", "ARMATURE").object = arm
    body.parent = arm
    mw = body.matrix_world
    def seg_dist(p, a, b):
        ab = b - a; t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-6)))
        return (p - (a + ab * t)).length
    for v in body.data.vertices:
        p = mw @ v.co
        d = sorted(((seg_dist(p, a, b), n) for n, a, b in segs))[:2]
        d0, n0 = d[0]; d1, n1 = d[1]
        # smooth blend when two bones are nearly equidistant
        w1 = 0.0
        if d1 < d0 * 1.6:
            w1 = 0.5 * (1.0 - (d1 - d0) / (d0 * 0.6))
            w1 = max(0.0, min(0.5, w1))
        groups[n0].add([v.index], 1.0 - w1, "REPLACE")
        if w1 > 0.0:
            groups[n1].add([v.index], w1, "REPLACE")
    unweighted = sum(1 for v in body.data.vertices if sum(g.weight for g in v.groups) < 0.01)
    print("RIG body verts unweighted after fallback %d" % unweighted)

# --- clean up the automatic weights for a blocky body:
#  * everything above the neck (narrowest slice between shoulders and top)
#    follows Head exactly, like the face parts
#  * torso vertices never follow the arm chain; arm vertices never follow
#    the torso, so the shoulders keep their corners
mw = body.matrix_world
vs = [(v.index, mw @ v.co) for v in body.data.vertices]
top_z = max(p.z for _, p in vs)
arm_z = bone_world("upperarm_l").z
# head block: scan down from the top; the head ends where a slice becomes
# much wider than the head (the shoulders). Works even with no neck at all.
nslices = 60
hip_probe = bone_world("pelvis").z
widths = []
for i in range(nslices):
    z0 = hip_probe + (top_z - hip_probe) * i / nslices
    z1 = hip_probe + (top_z - hip_probe) * (i + 1) / nslices
    w = [abs(p.x) for _, p in vs if z0 <= p.z < z1]
    widths.append((z0, max(w) if w else 0.0))
head_w = max(w for z, w in widths[-6:])
neck_cut = bone_world("Head").z
for z0, w in reversed(widths):
    if w > head_w * 1.35:
        neck_cut = z0 + (top_z - hip_probe) / nslices
        break
groups = {vg.name: vg for vg in body.vertex_groups}
def ensure(name):
    if name not in groups:
        groups[name] = body.vertex_groups.new(name=name)
    return groups[name]
ARM = {"clavicle_l", "upperarm_l", "lowerarm_l", "hand_l", "clavicle_r", "upperarm_r", "lowerarm_r", "hand_r"}
TORSO = {"pelvis", "spine_01", "spine_02", "spine_03", "neck_01"}
head_idx = [i for i, p in vs if p.z >= neck_cut]
for vg in body.vertex_groups:
    if vg.name != "Head":
        vg.remove(head_idx)
ensure("Head").add(head_idx, 1.0, "REPLACE")
# neck blend: a thin band under the cut mixes Head with the torso weights so
# the neck bends instead of creasing
neck_band = (top_z - hip_probe) / nslices * 1.5
for i, p in vs:
    if neck_cut - neck_band <= p.z < neck_cut:
        t = (p.z - (neck_cut - neck_band)) / neck_band
        t = t * t * (3.0 - 2.0 * t) * 0.85
        v = body.data.vertices[i]
        tot = sum(g.weight for g in v.groups)
        if tot > 0:
            for g in v.groups:
                body.vertex_groups[g.group].add([i], g.weight / tot * (1.0 - t), "REPLACE")
        ensure("Head").add([i], t, "ADD")

# torso / arm separation (below the neck, above the hips) with a short
# blend band across the shoulder so the joint bends instead of tearing
hip_z = bone_world("pelvis").z
band0 = torso_hw * 0.80
band1 = torso_hw * 1.30
head_set = set(head_idx)

torso_idx = [i for i, p in vs if hip_z < p.z < neck_cut and abs(p.x) < band0]
arm_idx = [i for i, p in vs if p.z > hip_z and abs(p.x) > band1 and i not in head_set]
band_idx = [i for i, p in vs if p.z > hip_z and band0 <= abs(p.x) <= band1 and i not in head_set]
for name in ARM | {"Head"}:
    if name in groups:
        groups[name].remove(torso_idx)
for name in TORSO | {"Head"} | {"thigh_l", "thigh_r"}:
    if name in groups:
        groups[name].remove(arm_idx)
# band: explicit spine_03 <-> upperarm mix by distance across the shoulder
sp3 = ensure("spine_03")
pos = dict(vs)
for i in band_idx:
    p = pos[i]
    t = (abs(p.x) - band0) / (band1 - band0)
    t = t * t * (3.0 - 2.0 * t)
    side = "_l" if p.x > 0 else "_r"
    for vg in body.vertex_groups:
        vg.remove([i])
    sp3.add([i], 1.0 - t, "REPLACE")
    ensure("upperarm" + side).add([i], t, "REPLACE")
# anything left with no weight gets a sensible default
def total(v):
    return sum(g.weight for g in v.groups)
sp = ensure("spine_03"); fixed = 0
for i in torso_idx:
    v = body.data.vertices[i]
    if total(v) < 0.01:
        sp.add([i], 1.0, "REPLACE"); fixed += 1
for side in ("_l", "_r"):
    up = ensure("upperarm" + side)
    for i in arm_idx:
        v = body.data.vertices[i]
        p = mw @ v.co
        if total(v) < 0.01 and (p.x > 0) == (side == "_l"):
            up.add([i], 1.0, "REPLACE"); fixed += 1
print("RIG head block: %d verts pinned to Head (neck z=%.2f); torso %d / band %d / arm %d, %d defaulted" % (len(head_idx), neck_cut, len(torso_idx), len(band_idx), len(arm_idx), fixed))

# --- verify the chin under the mouth is on Head too (mouth sync)
def center_z(o):
    zs = [(o.matrix_world @ v.co).z for v in o.data.vertices]
    return (min(zs) + max(zs)) / 2.0
mouth = min(parts, key=center_z) if parts else None
if mouth:
    mz = center_z(mouth)
    mw = body.matrix_world
    near = [v for v in body.data.vertices if abs((mw @ v.co).z - mz) < 0.05 and abs((mw @ v.co).x) < 0.12]
    hi = body.vertex_groups["Head"].index
    on_head = sum(1 for v in near if any(g.group == hi and g.weight > 0.99 for g in v.groups))
    print("RIG mouth sync: %d/%d body verts at mouth height are 100%% Head (mouth z=%.2f, neck cut z=%.2f)" % (on_head, len(near), mz, neck_cut))

# --- face parts ride the Head bone
for o in parts:
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True); arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.parent_set(type="ARMATURE_NAME")
    for vg in list(o.vertex_groups):
        o.vertex_groups.remove(vg)
    vg = o.vertex_groups.new(name="Head")
    vg.add([v.index for v in o.data.vertices], 1.0, "REPLACE")

# drop any leftover reference mannequin mesh before export
for o in list(bpy.data.objects):
    if o.type == "MESH" and o.name.startswith("Mannequin"):
        bpy.data.objects.remove(o, do_unlink=True)
bpy.ops.object.select_all(action="SELECT")
bpy.ops.export_scene.gltf(filepath=dst, export_format="GLB", export_apply=True, export_yup=True,
                          export_animations=False, export_skins=True, export_morph=False)
print("RIG exported", dst)
