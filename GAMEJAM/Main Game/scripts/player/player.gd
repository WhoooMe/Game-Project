extends CharacterBody2D
class_name PlayerBase

@export var ui_node: CanvasLayer
@export var speed := 200.0
@onready var anim := $AnimatedSprite2D

# --- VARIABEL SISTEM LEMARI ---
var is_hidden := false
var can_move := true
var is_input_locked := false # Kunci dari UI (Overlay aktif)
var current_wardrobe: Node2D = null
var pos_before_hide := Vector2.ZERO 

func _ready():
	add_to_group("Player") # Pastikan masuk grup Player
	
	if Global.is_transitioning:
		# Matikan visual sementara loading
		self.visible = false 
		can_move = false
		call_deferred("_do_force_teleport")
	else:
		print("Player Ready.")

func set_input_locked(locked: bool) -> void:
	is_input_locked = locked
	if locked:
		velocity = Vector2.ZERO
		if anim: anim.play("idle")

func _do_force_teleport():
	self.global_position = Global.next_spawn_pos
	if anim: anim.flip_h = Global.next_spawn_flip
	await get_tree().process_frame
	self.visible = true
	can_move = true 
	Global.is_transitioning = false

# --- PHYSICS PROCESS ---
func _physics_process(delta: float) -> void:
	# [UPDATE PENTING] Kirim posisi ke Global tiap frame untuk Mother
	Global.player_current_pos = global_position
	
	# Jika ngumpet atau UI Overlay aktif -> STOP Physics
	if is_hidden or is_input_locked:
		return 

	if not is_on_floor():
		velocity += get_gravity() * delta

	if can_move:
		var direction := Input.get_axis("ui_left", "ui_right")
		handle_movement(direction)
		move_and_slide()

func handle_movement(direction: float):
	if direction != 0:
		velocity.x = direction * speed
		if anim:
			anim.play("walk")
			anim.flip_h = direction < 0
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		if anim: anim.play("idle")

# ========================================================
#           SISTEM LEMARI (HIDE & SEEK)
# ========================================================

func _input(event):
	# Gunakan ui_accept (Spasi/Enter) agar lebih umum
	if is_hidden and event.is_action_pressed("ui_accept"):
		exit_wardrobe()

func enter_wardrobe_mode(wardrobe_node: Node2D):
	print("Player masuk lemari...")
	pos_before_hide = global_position
	
	is_hidden = true
	can_move = false
	current_wardrobe = wardrobe_node
	velocity = Vector2.ZERO
	
	# Pindah ke posisi lemari
	global_position = wardrobe_node.global_position
	
	# Hilangkan visual player
	self.modulate.a = 0.0 
	$CollisionShape2D.set_deferred("disabled", true)
	
	if ui_node and ui_node.has_method("show_exit_hint"):
		ui_node.show_exit_hint()
	
	# [UPDATE PENTING] Beritahu Global & Mother
	Global.update_player_hidden_status(true)

func exit_wardrobe():
	print("Player keluar lemari...")
	if not current_wardrobe: return
	
	# Visual lemari buka
	if current_wardrobe.has_method("force_visual_open"):
		current_wardrobe.force_visual_open()
	
	# Reset Status
	is_hidden = false
	can_move = true
	
	# Kembalikan Posisi
	global_position = pos_before_hide 
	
	# Munculkan visual lagi
	self.modulate.a = 1.0 
	$CollisionShape2D.set_deferred("disabled", false)
	
	if ui_node and ui_node.has_method("hide_exit_hint"):
		ui_node.hide_exit_hint()
	
	current_wardrobe = null
	
	# [UPDATE PENTING] Beritahu Global & Mother
	Global.update_player_hidden_status(false)
