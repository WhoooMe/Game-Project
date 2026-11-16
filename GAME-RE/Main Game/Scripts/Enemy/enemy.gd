extends CharacterBody2D
# Musuh: berjalan ke arah player (state SKIP) dan melompat secara acak (state JUMP).
# Struktur scene yang dibutuhkan:
#   Enemy (CharacterBody2D)            <- script ini
#   |- AnimatedSprite2D                <- animasi "SKIP" dan "JUMP" (dan "DEAD" kalau ada, opsional)
#   |- CollisionEnemy (CollisionShape2D)  <- collision badan (berdiri di tanah)
#   |- Hitbox (Area2D)                 <- MENYAKITI player (nama harus mengandung "hitbox")
#   |  |- CollisionShape2D
#   |- Hurtbox (Area2D)                <- MENERIMA peluru player (nama harus mengandung "hurtbox")
#   |  |- CollisionShape2D
#   |- DetectionArea (Area2D)          <- zona bahaya: player masuk -> musuh lebih sering lompat (nama harus mengandung "detection")
#      |- CollisionShape2D             <- ukurannya tidak diubah; letakkan di DEPAN musuh (sisi mana pun, otomatis dibalik sesuai arah jalan)

signal died(points: int, at_position: Vector2)

enum State { SKIP, JUMP }

@export_group("Movement")
@export var walk_speed: float = 90.0
@export var air_speed_multiplier: float = 1.2   # sedikit lebih cepat di udara
@export var gravity: float = 1400.0
@export var max_fall_speed: float = 900.0
@export var art_faces_right: bool = false       # centang kalau gambar asli musuh menghadap KANAN

@export_group("Random Jump")
@export var jump_velocity: float = -380.0
@export var jump_interval_min: float = 1.0      # jeda minimum sebelum "cek lompat" berikutnya (detik)
@export var jump_interval_max: float = 3.0      # jeda maksimum
@export_range(0.0, 1.0, 0.05) var jump_chance: float = 0.6   # peluang benar-benar lompat tiap pengecekan

@export_group("Detection Zone")
# Saat player berada di dalam DetectionArea, musuh jadi lebih "agresif": jeda lompat lebih pendek dan peluang lompat lebih besar.
@export var alert_jump_interval_min: float = 0.3
@export var alert_jump_interval_max: float = 0.9
@export_range(0.0, 1.0, 0.05) var alert_jump_chance: float = 0.9

@export_group("Animation")
@export var skip_animation: StringName = &"SKIP"
@export var jump_animation: StringName = &"JUMP"
@export var death_animation: StringName = &"DEAD"   # opsional, dilewati kalau tidak ada

@export_group("Collision dan HitBox")
# Ukuran collision + hitbox saat JUMP relatif terhadap ukuran normal (SKIP). x = lebar, y = tinggi.
# Mengecil dari atas, kaki tetap di bawah. Atur sampai pas dengan sprite JUMP.
@export var jump_size_ratio: Vector2 = Vector2(0.8, 0.7)

@export_group("Health dan Poin")
@export var max_health: int = 1
@export var points_min: int = 100
@export var points_max: int = 1000
@export var death_fade_time: float = 0.4

@export_group("Despawn")
@export var despawn_distance: float = 2500.0    # hilang kalau terlalu jauh dari player

var state: State = State.SKIP
var direction: int = 0              # 1 = kanan, -1 = kiri (0 = belum ditentukan)
var health: int
var is_dead: bool = false
var jump_timer: float = 0.0
var current_anim: StringName = &""

var player: Node2D
var animated_sprite: AnimatedSprite2D
var body_shape: CollisionShape2D
var hitbox: Area2D
var hitbox_shape: CollisionShape2D
var hurtbox: Area2D
var hurtbox_shape: CollisionShape2D
var detection_area: Area2D
var detection_shape: CollisionShape2D
var _detect_count: int = 0          # jumlah node player yang sedang berada di DetectionArea

var _base_body_size: Vector2 = Vector2.ZERO
var _base_body_pos: Vector2 = Vector2.ZERO
var _base_hit_size: Vector2 = Vector2.ZERO
var _base_hit_pos: Vector2 = Vector2.ZERO
var _base_hurt_size: Vector2 = Vector2.ZERO
var _base_hurt_pos: Vector2 = Vector2.ZERO
var _current_ratio: Vector2 = Vector2.ONE


func _ready() -> void:
	add_to_group("enemy")
	health = max_health

	_find_nodes()
	_make_shapes_unique()
	_cache_base_shapes()

	if hitbox != null:
		hitbox.add_to_group("enemy_hitbox")   # dikenali oleh HurtBox player

	if detection_area != null:
		detection_area.body_entered.connect(_on_detection_entered)
		detection_area.area_entered.connect(_on_detection_entered)
		detection_area.body_exited.connect(_on_detection_exited)
		detection_area.area_exited.connect(_on_detection_exited)

	player = get_tree().get_first_node_in_group("player") as Node2D
	_schedule_next_jump()


func _physics_process(delta: float) -> void:
	if direction == 0:
		_face_player()   # arah ditentukan sekali, saat frame fisika pertama (posisi spawn sudah final)

	_check_despawn()
	_apply_gravity(delta)
	_handle_random_jump(delta)

	var speed := walk_speed * (air_speed_multiplier if state == State.JUMP else 1.0)
	velocity.x = direction * speed

	_update_state()
	move_and_slide()


# ---------------------------------------------------------------- Pergerakan
func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y = minf(velocity.y + gravity * delta, max_fall_speed)
	else:
		velocity.y = 0.0


func _handle_random_jump(delta: float) -> void:
	if not is_on_floor():
		return
	jump_timer -= delta
	if jump_timer <= 0.0:
		# Kadang lompat, kadang tidak, dan jedanya juga acak -> sulit ditebak player.
		var chance := alert_jump_chance if player_in_range() else jump_chance
		if randf() < chance:
			velocity.y = jump_velocity
		_schedule_next_jump()


func _schedule_next_jump() -> void:
	if player_in_range():
		jump_timer = randf_range(alert_jump_interval_min, alert_jump_interval_max)
	else:
		jump_timer = randf_range(jump_interval_min, jump_interval_max)


# ---------------------------------------------------------------- Detection Zone
func player_in_range() -> bool:
	return _detect_count > 0


func _is_player(node: Node) -> bool:
	if node.is_in_group("player"):
		return true
	var parent := node.get_parent()
	return parent != null and parent.is_in_group("player")   # mis. HurtBox di dalam Player


func _on_detection_entered(node: Node) -> void:
	if is_dead or not _is_player(node):
		return
	_detect_count += 1
	if _detect_count == 1:
		# Player baru masuk zona: percepat lompat berikutnya supaya terasa "tiba-tiba".
		jump_timer = minf(jump_timer, randf_range(alert_jump_interval_min, alert_jump_interval_max))


func _on_detection_exited(node: Node) -> void:
	if not _is_player(node):
		return
	_detect_count = maxi(_detect_count - 1, 0)


# Zona selalu berada di DEPAN musuh, mengikuti arah jalannya.
func _update_detection_side() -> void:
	if detection_area != null:
		detection_area.position.x = absf(detection_area.position.x) * direction
	if detection_shape != null:
		detection_shape.position.x = absf(detection_shape.position.x) * direction


func _face_player() -> void:
	if player == null:
		player = get_tree().get_first_node_in_group("player") as Node2D
	if player != null:
		direction = 1 if player.global_position.x > global_position.x else -1
	else:
		direction = -1
	if animated_sprite != null:
		animated_sprite.flip_h = (direction > 0) != art_faces_right
	_update_detection_side()


func _check_despawn() -> void:
	if player == null:
		return
	var far_x := absf(player.global_position.x - global_position.x) > despawn_distance
	var fell := global_position.y > player.global_position.y + 1500.0
	if far_x or fell:
		queue_free()


# ---------------------------------------------------------------- State dan animasi
func _update_state() -> void:
	state = State.JUMP if (not is_on_floor() or velocity.y < 0.0) else State.SKIP

	match state:
		State.SKIP:
			_play_anim(skip_animation)
		State.JUMP:
			_play_anim(jump_animation)

	_update_collision_shape()


func _play_anim(anim_name: StringName) -> void:
	if animated_sprite == null or current_anim == anim_name:
		return
	animated_sprite.play(anim_name)
	current_anim = anim_name


# ---------------------------------------------------------------- Collision dan HitBox
func _update_collision_shape() -> void:
	var ratio := jump_size_ratio if state == State.JUMP else Vector2.ONE
	if ratio.is_equal_approx(_current_ratio):
		return
	_current_ratio = ratio
	_apply_ratio(body_shape, _base_body_size, _base_body_pos, ratio)
	_apply_ratio(hitbox_shape, _base_hit_size, _base_hit_pos, ratio)
	_apply_ratio(hurtbox_shape, _base_hurt_size, _base_hurt_pos, ratio)


func _apply_ratio(node: CollisionShape2D, base_size: Vector2, base_pos: Vector2, ratio: Vector2) -> void:
	if node == null or node.shape == null or base_size == Vector2.ZERO:
		return
	_set_shape_size(node.shape, Vector2(base_size.x * ratio.x, base_size.y * ratio.y))
	var applied := _get_shape_size(node.shape)
	# Geser ke bawah setengah selisih tinggi supaya bagian kaki tetap di tempat yang sama.
	node.position.y = base_pos.y + (base_size.y - applied.y) * 0.5


func _get_shape_size(shape: Shape2D) -> Vector2:
	var rect := shape as RectangleShape2D
	if rect != null:
		return rect.size
	var capsule := shape as CapsuleShape2D
	if capsule != null:
		return Vector2(capsule.radius * 2.0, capsule.height)
	var circle := shape as CircleShape2D
	if circle != null:
		return Vector2(circle.radius * 2.0, circle.radius * 2.0)
	return Vector2.ZERO


func _set_shape_size(shape: Shape2D, new_size: Vector2) -> void:
	var rect := shape as RectangleShape2D
	if rect != null:
		rect.size = new_size
		return
	var capsule := shape as CapsuleShape2D
	if capsule != null:
		capsule.radius = new_size.x * 0.5
		capsule.height = maxf(new_size.y, capsule.radius * 2.0)
		return
	var circle := shape as CircleShape2D
	if circle != null:
		circle.radius = minf(new_size.x, new_size.y) * 0.5


# Jarak dari titik tengah musuh ke kakinya; dipakai spawner supaya musuh muncul pas di atas tanah.
func get_feet_offset() -> float:
	if body_shape == null:
		return 0.0
	return body_shape.position.y + _base_body_size.y * 0.5


func _find_nodes() -> void:
	var sprites := find_children("*", "AnimatedSprite2D", true, false)
	if not sprites.is_empty():
		animated_sprite = sprites[0] as AnimatedSprite2D

	for child in get_children():
		if body_shape == null and child is CollisionShape2D:
			body_shape = child
		elif child is Area2D:
			var node_name := String(child.name).to_lower()
			if hitbox == null and node_name.contains("hitbox"):
				hitbox = child
			elif hurtbox == null and node_name.contains("hurtbox"):
				hurtbox = child
			elif detection_area == null and node_name.contains("detection"):
				detection_area = child

	hitbox_shape = _first_shape_of(hitbox)
	hurtbox_shape = _first_shape_of(hurtbox)
	detection_shape = _first_shape_of(detection_area)

	if animated_sprite == null or body_shape == null or hitbox == null or hitbox_shape == null:
		push_warning("Enemy: butuh AnimatedSprite2D, CollisionShape2D, serta Area2D 'Hitbox' (+ CollisionShape2D).")
	if hurtbox == null or hurtbox_shape == null:
		push_warning("Enemy: Area2D 'Hurtbox' (+ CollisionShape2D) tidak ditemukan, peluru tidak bisa mengenai musuh lewat hurtbox.")


func _first_shape_of(area: Area2D) -> CollisionShape2D:
	if area == null:
		return null
	for child in area.get_children():
		if child is CollisionShape2D:
			return child
	return null


# Penting: semua musuh dibuat dari scene yang sama. Tanpa duplicate(), mengubah ukuran shape
# satu musuh akan ikut mengubah ukuran SEMUA musuh lain.
func _make_shapes_unique() -> void:
	if body_shape != null and body_shape.shape != null:
		body_shape.shape = body_shape.shape.duplicate()
	if hitbox_shape != null and hitbox_shape.shape != null:
		hitbox_shape.shape = hitbox_shape.shape.duplicate()
	if hurtbox_shape != null and hurtbox_shape.shape != null:
		hurtbox_shape.shape = hurtbox_shape.shape.duplicate()


func _cache_base_shapes() -> void:
	if body_shape != null and body_shape.shape != null:
		_base_body_size = _get_shape_size(body_shape.shape)
		_base_body_pos = body_shape.position
	if hitbox_shape != null and hitbox_shape.shape != null:
		_base_hit_size = _get_shape_size(hitbox_shape.shape)
		_base_hit_pos = hitbox_shape.position
	if hurtbox_shape != null and hurtbox_shape.shape != null:
		_base_hurt_size = _get_shape_size(hurtbox_shape.shape)
		_base_hurt_pos = hurtbox_shape.position


# ---------------------------------------------------------------- Damage, mati, poin
# Dipanggil oleh peluru player (bullet.gd).
func take_damage(amount: int) -> void:
	if is_dead:
		return
	health -= amount
	if health <= 0:
		_die()
	else:
		_hit_flash()


func _hit_flash() -> void:
	if animated_sprite == null:
		return
	animated_sprite.modulate = Color(1.0, 0.5, 0.5)
	var tween := create_tween()
	tween.tween_property(animated_sprite, "modulate", Color.WHITE, 0.15)


func _die() -> void:
	is_dead = true

	var points := randi_range(points_min, points_max)   # poin acak 100 - 1000
	_award_points(points)
	died.emit(points, global_position)

	# Dipanggil dari callback fisika (peluru), jadi collision dimatikan lewat set_deferred.
	if body_shape != null:
		body_shape.set_deferred("disabled", true)
	if hitbox_shape != null:
		hitbox_shape.set_deferred("disabled", true)
	if hurtbox_shape != null:
		hurtbox_shape.set_deferred("disabled", true)
	if detection_shape != null:
		detection_shape.set_deferred("disabled", true)
	set_physics_process(false)

	if animated_sprite != null and animated_sprite.sprite_frames != null \
			and animated_sprite.sprite_frames.has_animation(death_animation):
		animated_sprite.play(death_animation)

	var fade_target: CanvasItem = animated_sprite if animated_sprite != null else self
	var tween := create_tween()
	tween.tween_property(fade_target, "modulate:a", 0.0, death_fade_time)
	tween.tween_callback(queue_free)


func _award_points(points: int) -> void:
	var score_manager := get_node_or_null("/root/ScoreManager")
	if score_manager != null:
		score_manager.call("add_points", points)
	else:
		push_warning("Enemy: ScoreManager belum didaftarkan sebagai Autoload, poin tidak tercatat.")
