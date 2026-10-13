extends Area3D
## Ray-interactable mess/tool. Areas do not block walking or placement support.
var manager: Node
var kind := ""
var record_id := ""
var tool_id := ""
var _label: Label3D

func _ready() -> void:
	_label=Label3D.new()
	_label.name="InteractionLabel"
	_label.font_size=32
	_label.pixel_size=0.0026
	_label.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test=true
	_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	_label.width=600
	_label.visible=false
	add_child(_label)

func show_prompt(show_it: bool) -> void:
	if not _label: return
	_label.visible=show_it
	if not show_it: return
	var title: String={"broom":"Broom","mop":"Mop (%d/4)"%GameState.cleaning.mop_uses,"feather_duster":"Feather duster"}.get(tool_id,kind.capitalize())
	var key: String = GameSettings.key_name("interact")
	var action := key
	match kind:
		"tool":
			if tool_id=="broom" and not GameState.owned_items.get("broom",false): title="Broom · 20 G"
			if tool_id=="mop" and GameState.cleaning.mop_uses>=4: action="Too dirty! Wash the mop inside the toilet\n"+key
		"trash_bag":
			title="Trash bag (%d/4)"%GameState.cleaning.bag_load
			if GameState.cleaning.bag_load>=4: action="Take the trash out first\n"+key
		"wash": title="Wash mop"; action="Hold "+key
		"dumpster": title="Dumpster"
		_:
			action="Hold "+key
			if kind=="rubbish" and manager.held_tool=="broom" and GameState.cleaning.bag_load>=4: action="Take the trash out first"
			elif kind=="spill" and manager.held_tool=="mop" and GameState.cleaning.mop_uses>=4: action="Too dirty! Wash the mop inside the toilet"
	_label.text=title+"\n"+action
	var visual: Node3D=get_meta("visual") if has_meta("visual") else null
	var height:=ArtifactVisual.local_bounds(visual).size.y if visual else 0.5
	_label.position.y=height+0.12

func interact(actor: Node) -> void:
	if manager: manager.interact_target(self, actor)
