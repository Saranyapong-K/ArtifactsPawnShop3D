class_name CleaningState
extends RefCounted
## Saved cleanliness. Hands and tool visuals belong to CleaningManager.

const MAX_MESS := 12
const MOP_CAPACITY := 4
const DUST_DAYS := 3
const CLEAN_SECONDS := 8.0
const ROBOT_CLEAN_SECONDS := 20.0
const BAG_CAPACITY := 4
const REQUIRED_TOOL := {"rubbish": "broom", "spill": "mop", "dust": "feather_duster"}
var initialized := false
var mess: Array[Dictionary] = []
var mop_uses := 0
var mop_wash_progress := 0.0
var bag_load := 0
var broom_available := false
var next_mess_minute := 0
var schedule_day := 0
var dusted_days: Dictionary = {}

func stars() -> int:
	return clampi(6 - ceili(mess.size() / 2.0), 0, 6)

func offer_bonus() -> float:
	return stars() * 0.01

func occupied(spot: String) -> bool:
	for record in mess:
		if record.spot == spot: return true
	return false

func add_mess(kind: String, spot: String, position: Vector3, variant: int = 0) -> bool:
	if not REQUIRED_TOOL.has(kind) or spot.is_empty() or occupied(spot) or mess.size() >= MAX_MESS:
		return false
	mess.append({"id": "mess-%x-%x" % [Time.get_ticks_usec(), randi()], "kind": kind,
		"spot": spot, "position": [position.x, position.y, position.z], "variant": clampi(variant, 0, 2), "progress": 0.0, "rotation":randf_range(0,TAU)})
	return true

func get_mess(id: String) -> Dictionary:
	for record in mess:
		if record.id == id: return record
	return {}

func can_clean(id: String, tool: String) -> Dictionary:
	var record := get_mess(id)
	if record.is_empty(): return {"ok": false, "message": "This spot is already clean."}
	if REQUIRED_TOOL[record.kind] != tool:
		return {"ok": false, "message": "Use the %s for this mess." % REQUIRED_TOOL[record.kind].replace("_", " ")}
	if tool == "mop" and mop_uses >= MOP_CAPACITY:
		return {"ok": false, "message": "Too dirty"}
	if record.kind == "rubbish" and bag_load >= BAG_CAPACITY:
		return {"ok": false, "message": "Trash bag full (4/4). Put the broom away, carry the bag, and empty it at the dumpster."}
	return {"ok": true, "message": ""}

func advance(id: String, tool: String, seconds: float, day: int) -> Dictionary:
	var allowed := can_clean(id, tool)
	if not allowed.ok: return allowed
	if is_nan(seconds) or is_inf(seconds) or seconds < 0:
		return {"ok": false, "message": "Invalid cleaning time."}
	var record := get_mess(id)
	record.progress = minf(CLEAN_SECONDS, float(record.get("progress", 0.0)) + seconds)
	if record.progress < CLEAN_SECONDS:
		return {"ok": true, "completed": false, "progress": record.progress / CLEAN_SECONDS, "message": ""}
	var result := clean(id, tool, day)
	result.completed = result.ok
	result.progress = 1.0
	return result

func clean(id: String, tool: String, day: int) -> Dictionary:
	var allowed := can_clean(id, tool)
	if not allowed.ok: return allowed
	for index in mess.size():
		var record := mess[index]
		if record.id != id: continue
		if float(record.get("progress", 0.0)) < CLEAN_SECONDS:
			return {"ok": false, "message": "Keep cleaning this spot."}
		if tool == "mop": mop_uses += 1
		if record.kind == "rubbish": bag_load += 1
		if record.kind == "dust": dusted_days[record.spot] = day
		mess.remove_at(index)
		return {"ok": true, "message": "Cleaned!" + (" The mop now needs washing." if tool == "mop" and mop_uses == MOP_CAPACITY else "")}
	return {"ok": false, "message": "This spot is already clean."}

func advance_robot(id: String, seconds: float, day: int) -> Dictionary:
	var record := get_mess(id)
	if record.is_empty() or not is_finite(seconds) or seconds < 0:
		return {"ok": false, "completed": false}
	# Shared progress is work, in manual-cleaning units. The robot takes twenty
	# seconds for a fresh spot; switching tools or saving retains completed work.
	record.progress = minf(CLEAN_SECONDS, float(record.get("progress", 0.0)) + seconds * CLEAN_SECONDS / ROBOT_CLEAN_SECONDS)
	if record.progress < CLEAN_SECONDS:
		return {"ok": true, "completed": false, "progress": record.progress / CLEAN_SECONDS}
	if record.kind == "dust": dusted_days[record.spot] = day
	mess.erase(record)
	return {"ok": true, "completed": true, "progress": 1.0}

func advance_wash(seconds: float) -> Dictionary:
	if is_nan(seconds) or is_inf(seconds) or seconds < 0:
		return {"ok": false, "message": "Invalid washing time."}
	mop_wash_progress = minf(CLEAN_SECONDS, mop_wash_progress + seconds)
	if mop_wash_progress < CLEAN_SECONDS:
		return {"ok": true, "completed": false, "progress": mop_wash_progress / CLEAN_SECONDS, "message": ""}
	mop_uses = 0
	mop_wash_progress = 0.0
	return {"ok": true, "completed": true, "progress": 1.0, "message": "Mop washed. Ready for four more spills."}

func empty_bag() -> bool:
	if bag_load <= 0: return false
	bag_load = 0
	return true

func to_dict() -> Dictionary:
	return {"initialized": initialized, "mess": mess.duplicate(true), "mop_uses": mop_uses,
		"bag_load": bag_load, "mop_wash_progress": mop_wash_progress,
		"broom_available": broom_available, "next_mess_minute": next_mess_minute,
		"schedule_day": schedule_day, "dusted_days": dusted_days.duplicate()}

static func from_dict(value: Variant) -> CleaningState:
	if not value is Dictionary: return null
	var state := CleaningState.new()
	var records: Variant = value.get("mess", [])
	var ages: Variant = value.get("dusted_days", {})
	if not records is Array or records.size() > MAX_MESS or not ages is Dictionary: return null
	var ids := {}
	var spots := {}
	for record in records:
		if not record is Dictionary: return null
		for key in ["id", "kind", "spot"]:
			if not record.get(key) is String or String(record[key]).is_empty(): return null
		if not REQUIRED_TOOL.has(record.kind) or ids.has(record.id) or spots.has(record.spot): return null
		if not ArtifactData._valid_vector(record.get("position"), 3): return null
		ids[record.id] = true
		spots[record.spot] = true
		var normalized: Dictionary = record.duplicate(true)
		var progress: Variant = record.get("progress", 0.0)
		if not typeof(progress) in [TYPE_FLOAT, TYPE_INT] or is_nan(float(progress)) or is_inf(float(progress)): return null
		normalized.progress = clampf(float(progress), 0.0, CLEAN_SECONDS)
		var angle: Variant = record.get("rotation",float(String(record.id).hash()&0xFFFF)/65535.0*TAU)
		if not typeof(angle) in [TYPE_FLOAT,TYPE_INT] or not is_finite(float(angle)): return null
		normalized.rotation = fposmod(float(angle),TAU)
		normalized.variant = clampi(int(record.get("variant", 0)), 0, 2)
		state.mess.append(normalized)
	for key in ages:
		if not key is String or not (typeof(ages[key]) in [TYPE_INT, TYPE_FLOAT]): return null
		state.dusted_days[key] = maxi(1, int(ages[key]))
	state.initialized = bool(value.get("initialized", false))
	state.mop_uses = clampi(int(value.get("mop_uses", 0)), 0, MOP_CAPACITY)
	var wash_progress: Variant = value.get("mop_wash_progress", 0.0)
	if not typeof(wash_progress) in [TYPE_FLOAT, TYPE_INT] or is_nan(float(wash_progress)) or is_inf(float(wash_progress)): return null
	state.mop_wash_progress = clampf(float(wash_progress), 0.0, CLEAN_SECONDS)
	state.bag_load = clampi(int(value.get("bag_load", 0)), 0, BAG_CAPACITY)
	state.broom_available = bool(value.get("broom_available", false))
	state.next_mess_minute = maxi(0, int(value.get("next_mess_minute", 0)))
	state.schedule_day = maxi(0, int(value.get("schedule_day", 0)))
	return state
