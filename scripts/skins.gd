class_name Skins
extends RefCounted
## Character skins = one GLB per colour in assets/characters/. Drop a new
## file in and it shows up in the lobby picker. "mannequin" is the rigged
## Quaternius placeholder with working animations.

const DIR := "res://assets/characters/"
const MANNEQUIN := "mannequin"
const MANNEQUIN_PATH := "res://assets/animations/Mannequin_F.glb"
const ANIM_LIBRARY_PATH := "res://assets/animations/UAL1_Standard.glb"
const DEFAULT := "red"


static func list() -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(DIR)
	if d:
		for f in d.get_files():
			var base := f
			for ext in [".glb.import", ".glb.remap", ".glb"]:
				if base.ends_with(ext):
					base = base.trim_suffix(ext)
					if not out.has(base):
						out.append(base)
					break
	out.sort()
	return out


static func path(skin: String) -> String:
	if skin == MANNEQUIN:
		return MANNEQUIN_PATH
	return DIR + skin + ".glb"


static func display_name(skin: String) -> String:
	return skin.capitalize()


static func valid(skin: String) -> String:
	return skin if list().has(skin) else DEFAULT
