extends CharacterBody2D
class_name MotherNPC

@export_group("Stats")
@export var walk_speed: float = 100.0  
@export var chase_speed: float = 260.0 
@export var catch_distance: float = 100.0
@export var detect_radius: float = 450.0 
@export var notice_duration: float = 5.0 
@export var search_duration: float = 10.0

@export_group("Spawn Settings")
@export var scene_entry_delay: float = 5.0 

@export_group("References")
@export var ui_node: CanvasLayer

enum State { IDLE, NOTICE, CHASE, WALK_SEARCH, WALK_RETURN, CAUGHT }
var current_state = State.IDLE

var start_pos: Vector2 = Vector2.ZERO
var state_timer: float = 0.0
var wander_direction: int = 1
var is_spawning: bool = false

func _ready():
	add_to_group("Enemy")
	
	# [FIX: PASTIKAN IBU SELALU DI DEPAN LAYER BACKGROUND]
	z_index = 10 
	
	if not ui_node:
		ui_node = get_tree().current_scene.find_child("UI", true, false)
	
	# Delay 1 frame biar scene ready
	await get_tree().process_frame
	setup_spawn_logic()

func setup_spawn_logic():
	var scene_name = get_tree().current_scene.name.to_lower()
	
	print("------------------------------------------------")
	print("DEBUG MOTHER: Cek Kondisi Spawn...")
	print("1. Nama Scene saat ini: ", get_tree().current_scene.name)
	print("2. Status Global mother_is_active: ", Global.mother_is_active)
	print("3. Koordinat Player saat ini: ", Global.player_current_pos)
	
	# 1. LOGIKA SPAWN AWAL (LIVING ROOM)
	if "living" in scene_name:
		if not Global.mother_is_active:
			print(">>> KEPUTUSAN: Spawn IDLE di Living Room")
			
			# [FIX: KOORDINAT FIX 1000, 205]
			global_position = Vector2(0, 205) 
			
			start_pos = global_position
			current_state = State.IDLE
			
			# PAKSA MUNCUL
			visible = true 
			modulate.a = 1.0
			is_spawning = false
			
			# Cek apakah koordinat valid
			print(">>> IBU MUNCUL DI POSISI: ", global_position)
		else:
			print(">>> KEPUTUSAN: Living Room, tapi Ibu sedang aktif (Logic aneh? Resetting...)")
			# Fallback kalau error
			visible = true
			current_state = State.CHASE
	
	# 2. LOGIKA PINDAH SCENE (CHASE MODE)
	elif Global.mother_is_active:
		print(">>> KEPUTUSAN: Pindah Scene (Chase Mode)")
		print(">>> Ibu menunggu ", scene_entry_delay, " detik...")
		
		visible = false # Sembunyi dulu
		is_spawning = true
		
		await get_tree().create_timer(scene_entry_delay).timeout
		
		# Spawn di posisi pintu (bekas player masuk)
		global_position = Global.next_spawn_pos 
		global_position.y = 205 
		
		start_pos = global_position
		current_state = State.CHASE 
		
		visible = true
		is_spawning = false
		print(">>> BRAKK! Ibu Masuk di: ", global_position)
	
	else:
		print(">>> KEPUTUSAN: Scene aman (Ibu menghilang)")
		queue_free() # Hapus dari scene ini
	
	print("------------------------------------------------")

func _physics_process(delta):
	# Update posisi ke Global tiap frame biar UI/Logic lain tau
	if visible:
		# Debugging posisi jika jatuh ke jurang
		if global_position.y > 1000:
			print("WARNING: Ibu jatuh ke jurang! Reset Y ke 205")
			global_position.y = 205
			velocity.y = 0

	if is_spawning or not visible: return

	if not is_on_floor():
		velocity.y += 980.0 * delta

	match current_state:
		State.IDLE:
			_state_idle()
		State.NOTICE:
			_state_notice(delta)
		State.CHASE:
			_state_chase()
		State.WALK_SEARCH:
			_state_walk_search(delta)
		State.WALK_RETURN:
			_state_walk_return()
		State.CAUGHT:
			velocity.x = 0

	move_and_slide()
	_update_animation()

# ========================================================
# 🧠 LOGIC
# ========================================================

func _state_idle():
	velocity.x = 0
	var dist = global_position.distance_to(Global.player_current_pos)
	
	# Jarak Notice (450px)
	if dist < detect_radius and not Global.player_is_hidden:
		trigger_notice()

func _state_notice(delta):
	velocity.x = 0
	state_timer -= delta
	
	# Hadap Player
	var dir_to_player = sign(Global.player_current_pos.x - global_position.x)
	if dir_to_player != 0 and has_node("AnimatedSprite2D"):
		$AnimatedSprite2D.flip_h = dir_to_player < 0
	
	if state_timer <= 0:
		print("Ibu: SINI KAMU!")
		Global.mother_is_active = true
		current_state = State.CHASE

func _state_chase():
	if Global.player_is_hidden:
		var scene_name = get_tree().current_scene.name.to_lower()
		if "parent" in scene_name:
			state_timer = search_duration
			current_state = State.WALK_SEARCH 
		else:
			current_state = State.WALK_RETURN 
		return

	var direction = sign(Global.player_current_pos.x - global_position.x)
	velocity.x = direction * chase_speed
	
	if global_position.distance_to(Global.player_current_pos) <= catch_distance:
		_trigger_catch()
	
	_handle_door()

func _state_walk_search(delta):
	state_timer -= delta
	velocity.x = wander_direction * walk_speed
	if randf() < 0.02: wander_direction *= -1
	
	if state_timer <= 0:
		current_state = State.WALK_RETURN
	
	if not Global.player_is_hidden:
		current_state = State.CHASE

func _state_walk_return():
	var direction = sign(start_pos.x - global_position.x)
	velocity.x = direction * walk_speed
	
	if abs(global_position.x - start_pos.x) < 50:
		Global.mother_is_active = false
		queue_free()

# ========================================================
# 🔧 HELPERS
# ========================================================

func trigger_notice():
	if current_state == State.IDLE:
		print("Ibu: Hah??")
		current_state = State.NOTICE
		state_timer = notice_duration

func _trigger_catch():
	if current_state == State.CAUGHT: return
	current_state = State.CAUGHT
	
	if ui_node:
		if ui_node.has_method("lock_player_movement"):
			ui_node.lock_player_movement(true)
		
		if ui_node.has_method("show_message"):
			ui_node.show_message("TERTANGKAP!", Color.RED)
		if ui_node.has_node("Dimmer"): 
			ui_node.get_node("Dimmer").show()
		
		await get_tree().create_timer(2.0).timeout
		
		if ui_node.has_method("fade_out"):
			var tween = ui_node.fade_out()
			if tween: await tween.finished
			
		Global.reset_all_data()
		get_tree().change_scene_to_file("res://scenes/area/bedroom.tscn")

func _handle_door():
	var detector = get_node_or_null("DoorDetector")
	if detector and detector.has_overlapping_areas():
		for area in detector.get_overlapping_areas():
			if "Door" in area.name and area.has_method("npc_buka_pintu"):
				area.npc_buka_pintu()
			elif "Door" in area.name and area.has_method("buka_pintu"):
				if area.get("is_open") == false:
					area.buka_pintu()

func _update_animation():
	var anim = get_node_or_null("AnimatedSprite2D")
	if not anim: return
	
	match current_state:
		State.IDLE:
			anim.play("idle")
		State.NOTICE:
			if anim.sprite_frames.has_animation("notice"): anim.play("notice")
			else: anim.play("idle")
		State.CHASE:
			if anim.sprite_frames.has_animation("run"): anim.play("run")
			elif anim.sprite_frames.has_animation("chase"): anim.play("chase")
			else: anim.play("walk")
			if velocity.x != 0: anim.flip_h = velocity.x < 0
		State.WALK_SEARCH, State.WALK_RETURN:
			anim.play("walk")
			if velocity.x != 0: anim.flip_h = velocity.x < 0
		State.CAUGHT:
			anim.play("idle")
