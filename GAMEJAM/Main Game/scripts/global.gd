extends Node

# Database
var inventory_data: Array = [] 
var interaction_states: Dictionary = {} 

# Transisi
var next_spawn_pos: Vector2 = Vector2.ZERO
var next_spawn_flip: bool = false
var is_transitioning: bool = false

# ============ MOTHER NPC STATE ============
var mother_is_active: bool = false # Default harus FALSE saat game mulai
var mother_state: String = "sleeping" 

# Player
var player_current_pos: Vector2 = Vector2.ZERO
var player_is_hidden: bool = false 
var palu_collected: bool = false

func _ready():
	print("Global: Autoload aktif.")

func reset_all_data():
	print("=== RESETTING GAME DATA ===")
	inventory_data.clear()
	interaction_states.clear()
	
	mother_is_active = false
	mother_state = "sleeping"
	player_is_hidden = false
	palu_collected = false
	
	next_spawn_pos = Vector2(0, 0) 
	is_transitioning = false

# --- FUNGSI LAIN TETAP SAMA ---
func add_item(item_dict: Dictionary):
	if not item_dict.has("name") or not item_dict.has("texture"): return
	inventory_data.append(item_dict)

func remove_item(item_name: String):
	for i in range(inventory_data.size()):
		if inventory_data[i]["name"] == item_name:
			inventory_data.remove_at(i)
			return

func save_state(obj_name: String, data: Dictionary):
	interaction_states[obj_name] = data

func get_state(obj_name: String):
	return interaction_states.get(obj_name, null)

func update_player_hidden_status(hidden: bool):
	player_is_hidden = hidden

func trigger_mother_notice():
	mother_is_active = true
	mother_state = "noticed"
	var mother = get_tree().current_scene.find_child("Mother", true, false)
	if mother and mother.has_method("trigger_notice"):
		mother.trigger_notice()
