extends Node2D
# Memunculkan musuh berdasarkan JARAK TEMPUH player ke depan (bukan waktu).
# Player diam = tidak ada musuh baru. Mundur tidak dihitung: hanya kemajuan melewati titik terjauh yang pernah dicapai.

@export var enemy_scene: PackedScene

@export_group("Spawn berdasarkan jarak")
@export var spawn_distance_min: float = 500.0   # jarak tempuh minimum antar spawn (piksel)
@export var spawn_distance_max: float = 900.0   # jarak tempuh maksimum antar spawn
@export var max_alive: int = 5                  # batas musuh yang hidup bersamaan
@export var spawn_margin: float = 150.0         # jarak ekstra di luar tepi kanan layar
@export var fallback_spawn_ahead: float = 800.0 # dipakai kalau kamera tidak ditemukan

@export_group("Deteksi tanah")
@export_flags_2d_physics var ground_mask: int = 1   # layer tanah / platform
@export var ray_up: float = 400.0
@export var ray_down: float = 900.0
@export var spawn_extra_height: float = 2.0

var player: Node2D
var _furthest_x: float = 0.0
var _distance_since_spawn: float = 0.0
var _next_spawn_distance: float = 0.0


func _ready() -> void:
	_next_spawn_distance = randf_range(spawn_distance_min, spawn_distance_max)


func _physics_process(_delta: float) -> void:
	if enemy_scene == null:
		return

	if player == null:
		player = get_tree().get_first_node_in_group("player") as Node2D
		if player == null:
			return
		_furthest_x = player.global_position.x
		return

	var x := player.global_position.x
	if x > _furthest_x:
		_distance_since_spawn += x - _furthest_x
		_furthest_x = x

	if _distance_since_spawn >= _next_spawn_distance:
		_on_spawn_due()


func _on_spawn_due() -> void:
	var alive := get_tree().get_nodes_in_group("enemy").size()
	if alive >= max_alive:
		_reset_spawn_counter()   # terlalu ramai: lewati spawn ini
	elif _spawn_enemy():
		_reset_spawn_counter()
	# Kalau tanah tidak ketemu (misal ada jurang), dicoba lagi di frame berikutnya.


func _reset_spawn_counter() -> void:
	_distance_since_spawn = 0.0
	_next_spawn_distance = randf_range(spawn_distance_min, spawn_distance_max)


func _spawn_enemy() -> bool:
	var spawn_x := player.global_position.x + _get_spawn_ahead()
	var hit := _find_ground(spawn_x)
	if hit.is_empty():
		return false

	var enemy := enemy_scene.instantiate() as Node2D
	get_tree().current_scene.add_child(enemy)

	var feet := 0.0
	if enemy.has_method("get_feet_offset"):
		feet = enemy.call("get_feet_offset")
	enemy.global_position = Vector2(spawn_x, hit.position.y - feet - spawn_extra_height)
	return true


# Jarak spawn di depan player = setengah lebar layar (disesuaikan zoom kamera) + margin,
# jadi musuh selalu muncul di luar layar.
func _get_spawn_ahead() -> float:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return fallback_spawn_ahead
	return get_viewport_rect().size.x * 0.5 / cam.zoom.x + spawn_margin


func _find_ground(x: float) -> Dictionary:
	var space := get_world_2d().direct_space_state
	var from := Vector2(x, player.global_position.y - ray_up)
	var to := Vector2(x, player.global_position.y + ray_down)
	var query := PhysicsRayQueryParameters2D.create(from, to, ground_mask)
	return space.intersect_ray(query)
