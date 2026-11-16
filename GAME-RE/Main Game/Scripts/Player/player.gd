extends CharacterBody2D

signal health_changed(current: int, max: int)
signal player_died
signal player_hurt

# -- Movement --
@export var speed: float = 220.0
@export var acceleration: float = 1800.0
@export var friction: float = 2200.0

# -- Lompat (variable height) --
@export var jump_velocity: float = -420.0       # kecepatan awal lompat (tinggi maksimal kalau ditahan)
@export var jump_cut_multiplier: float = 0.45   # seberapa besar lompatan dipotong kalau tombol dilepas cepat
@export var gravity: float = 1400.0
@export var max_fall_speed: float = 900.0
@export var coyote_time: float = 0.1            # toleransi lompat sesaat setelah lepas platform (feel-good, opsional)
@export var jump_buffer_time: float = 0.12      # toleransi input jump sesaat sebelum menyentuh tanah (opsional)

# -- Dash --
@export var dash_speed: float = 620.0
@export var dash_duration: float = 0.18
@export var dash_cooldown: float = 0.5
@export var can_air_dash: bool = true

# [BARU - PRE DASH AIR] Durasi cadangan kalau animasi "PRE_DASH_AIR" belum dibuat di SpriteFrames
@export var pre_dash_air_fallback_time: float = 0.1

# -- Crouch --
@export var fast_fall_speed: float = 1100.0     # kecepatan turun saat kombo jump + crouch

# --- Weapon ---
@export var bullet_scene: PackedScene
@export var fire_rate: float = 0.35             # jeda antar tembakan (detik)
@export var bullet_damage: int = 1
# [BARU - SHOOT ANIM] Berapa lama animasi nembak bertahan setelah peluru keluar.
# Dibuat sedikit lebih besar dari fire_rate supaya animasi tidak "kedip" saat tombol tembak ditahan.
@export var shoot_anim_hold: float = 0.4

# --- Health ---
@export var max_health: int = 3
@export var invincibility_duration: float = 2.5
# [BARU - HIT] Durasi animasi kena hit
@export var hit_anim_duration: float = 0.3
# [BARU - DEATH EFFECT] Sprite naik perlahan sambil memudar setelah mati
@export var death_rise_distance: float = 40.0   # seberapa tinggi sprite naik (piksel)
@export var death_fade_duration: float = 1.2    # lama naik + memudar (detik)
@export var death_fade_delay: float = 0.3       # jeda sebelum mulai naik/memudar, supaya animasi DEAD sempat terlihat

var current_health: int
var is_invincible: bool = false

# [DIUBAH] Ditambah PRE_DASH_AIR, HIT, DEAD di paling belakang (urutan lama tidak berubah)
enum State { IDLE, RUN, JUMP, FALL, CROUCH, DASH, PRE_DASH_AIR, HIT, DEAD }
var state: State = State.IDLE

var facing_direction: int = 1   # 1 = kanan, -1 = kiri
var is_dashing: bool = false
var can_dash: bool = true
var dash_direction: int = 1
var wants_crouch_on_land: bool = false
var is_crouching: bool = false

var coyote_timer: float = 0.0
var jump_buffer_timer: float = 0.0

# [BARU - PRE DASH AIR]
var is_pre_dashing: bool = false
var pre_dash_timer: float = 0.0

# [BARU - CROUCH IDLE] true kalau animasi intro "CROUNCH" sudah selesai diputar sekali
var crouch_intro_done: bool = false

# [BARU - CROUCH SHOOT] true kalau animasi "DUCK" (transisi ke pose nembak jongkok) sudah selesai diputar sekali.
# Setelah itu animasi "CROUNCH_BOIL" yang di-loop selama crouch + tembak ditahan.
var crouch_shoot_intro_done: bool = false

# [BARU - SHOOT ANIM] > 0 berarti player sedang dalam pose menembak
var shoot_anim_timer: float = 0.0

# [BARU - HIT] > 0 berarti animasi HIT sedang diputar
var hit_anim_timer: float = 0.0

# [BARU] Nama animasi yang sedang diputar (dilacak sendiri supaya tidak ter-restart tiap frame)
var current_anim: StringName = &""

# [BARU - COLLISION] Tinggi collision relatif terhadap tinggi saat berdiri (1.0 = tinggi normal).
# Mengecil dari ATAS, kaki tetap menempel di tanah. Atur angkanya di Inspector sampai pas dengan sprite.
@export_range(0.2, 1.0, 0.01) var crouch_height_ratio: float = 0.6   # saat crouch
@export_range(0.2, 1.0, 0.01) var air_height_ratio: float = 0.75     # saat lompat / jatuh
@export var resize_body_collision: bool = true   # matikan kalau hanya HurtBox yang mau ikut mengecil

var body_shape: CollisionShape2D
var hurtbox_shape: CollisionShape2D
var _base_body_height: float = 0.0
var _base_body_pos_y: float = 0.0
var _base_hurt_height: float = 0.0
var _base_hurt_pos_y: float = 0.0
var _current_collision_ratio: float = 1.0

@onready var animated_sprite: AnimatedSprite2D = $AnimatePlayer
@onready var muzzle: Marker2D = $Muzzle
# [DIUBAH - FIX ERROR MUZZLE] Dicari lewat beberapa kemungkinan nama supaya tidak error kalau ejaan node berbeda
# (di scene-mu node ini bernama "MuzzleCrounch", bukan "MuzzleCrouch").
@onready var muzzle_crouch: Marker2D = _find_marker(["MuzzleCrouch", "MuzzleCrounch"])
# [BARU - MUZZLE RUN] Titik keluar peluru saat berlari. Buat node Marker2D bernama "MuzzleRun" di bawah Player.
@onready var muzzle_run: Marker2D = _find_marker(["MuzzleRun"])
@onready var fire_rate_timer: Timer = $FireRateTimer
@onready var dash_timer: Timer = $DashTimer
@onready var dash_cooldown_timer: Timer = $DashCooldownTime
@onready var invincibility_timer: Timer = $InvincibilityTimer
@onready var hurtbox: Area2D = $HurtBox


func _ready() -> void:
	add_to_group("player")

	current_health = max_health

	fire_rate_timer.wait_time = fire_rate
	fire_rate_timer.one_shot = true

	dash_timer.wait_time = dash_duration
	dash_timer.one_shot = true

	dash_cooldown_timer.wait_time = dash_cooldown
	dash_cooldown_timer.one_shot = true

	invincibility_timer.wait_time = invincibility_duration
	invincibility_timer.one_shot = true

	dash_timer.timeout.connect(_on_dash_timer_timeout)
	dash_cooldown_timer.timeout.connect(_on_dash_cooldown_timeout)
	invincibility_timer.timeout.connect(_on_invincibility_timeout)
	hurtbox.area_entered.connect(_on_hurtbox_area_entered)

	# [BARU - CROUCH IDLE] Dipakai untuk tahu kapan intro "CROUNCH" selesai
	animated_sprite.animation_finished.connect(_on_animation_finished)
	# [FIX - DUCK] Animasi "DUCK" di SpriteFrames diset Loop ON, jadi animation_finished tidak pernah terpanggil.
	# animation_looped dipakai sebagai penanda "satu putaran selesai" supaya lanjut ke CROUCH_BOIL.
	animated_sprite.animation_looped.connect(_on_animation_finished)

	_setup_collision_shapes()   # [BARU - COLLISION]

	health_changed.emit(current_health, max_health)


func _physics_process(delta: float) -> void:
	_update_timers(delta)

	# [DIUBAH - PRE DASH AIR] Tambahan cabang: saat pre dash, player melayang diam dulu
	if is_pre_dashing:
		_process_pre_dash_air(delta)
	elif is_dashing:
		_process_dash_movement()
	else:
		_apply_gravity(delta)
		_handle_crouch_input()
		_handle_jump_input()
		_handle_dash_input()
		_handle_horizontal_movement(delta)

	_handle_shoot_input()
	_update_state()
	_update_facing()

	move_and_slide()

	if is_on_floor() and wants_crouch_on_land:
		wants_crouch_on_land = false
		is_crouching = true


func _update_timers(delta: float) -> void:
	if is_on_floor():
		coyote_timer = coyote_time
	else:
		coyote_timer = max(coyote_timer - delta, 0.0)

	if jump_buffer_timer > 0.0:
		jump_buffer_timer = max(jump_buffer_timer - delta, 0.0)

	# [BARU - SHOOT ANIM]
	if shoot_anim_timer > 0.0:
		shoot_anim_timer = max(shoot_anim_timer - delta, 0.0)

	# [BARU - HIT]
	if hit_anim_timer > 0.0:
		hit_anim_timer = max(hit_anim_timer - delta, 0.0)


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y = min(velocity.y + gravity * delta, max_fall_speed)
	else:
		velocity.y = 0.0


func _handle_horizontal_movement(delta: float) -> void:
	var input_direction := Input.get_axis("move_left", "move_right")

	# Jongkok di darat = diam total (desain ala Contra, aim rendah).
	# Kalau nanti mau bisa "crouch-walk", tinggal ganti return ini jadi speed lebih kecil.
	if is_crouching and is_on_floor():
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)
		return

	if input_direction != 0.0:
		velocity.x = move_toward(velocity.x, input_direction * speed, acceleration * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)


func _handle_jump_input() -> void:
	if Input.is_action_just_pressed("jump"):
		jump_buffer_timer = jump_buffer_time

	if jump_buffer_timer > 0.0 and coyote_timer > 0.0 and not is_crouching:
		velocity.y = jump_velocity
		jump_buffer_timer = 0.0
		coyote_timer = 0.0

	# Variable jump height: lepas tombol lebih awal saat masih naik -> lompatan dipotong pendek.
	if Input.is_action_just_released("jump") and velocity.y < 0.0:
		velocity.y *= jump_cut_multiplier


func _handle_crouch_input() -> void:
	var crouch_held := Input.is_action_pressed("crouch")

	if crouch_held and not is_on_floor():
		# Kombo Jump + Crouch = fast fall langsung ke tanah, lalu otomatis jongkok saat mendarat.
		velocity.y = fast_fall_speed
		wants_crouch_on_land = true
		is_crouching = false
	elif crouch_held and is_on_floor():
		is_crouching = true
	elif not crouch_held:
		is_crouching = false


func _handle_dash_input() -> void:
	if Input.is_action_just_pressed("dash") and can_dash:
		var grounded_dash_ok := is_on_floor()
		var air_dash_ok := (not is_on_floor()) and can_air_dash
		if grounded_dash_ok:
			_start_dash()
		elif air_dash_ok:
			# [DIUBAH - PRE DASH AIR] Dash di udara lewat animasi pre dash dulu, bukan langsung dash
			_start_pre_dash_air()


# [BARU - PRE DASH AIR] ------------------------------------------------------
func _start_pre_dash_air() -> void:
	is_pre_dashing = true
	can_dash = false
	dash_direction = facing_direction
	velocity = Vector2.ZERO
	# Lama pre dash = panjang animasi "PRE_DASH_AIR" (otomatis dihitung dari SpriteFrames)
	pre_dash_timer = _get_anim_duration(&"PRE_DASH_AIR", pre_dash_air_fallback_time)


func _process_pre_dash_air(delta: float) -> void:
	velocity = Vector2.ZERO   # melayang diam selama animasi pre dash
	pre_dash_timer -= delta
	if pre_dash_timer <= 0.0:
		is_pre_dashing = false
		_start_dash()         # langsung masuk state DASH
# ---------------------------------------------------------------------------


func _start_dash() -> void:
	is_dashing = true
	can_dash = false
	dash_direction = facing_direction
	velocity.y = 0.0
	dash_timer.start()


func _process_dash_movement() -> void:
	velocity.x = dash_direction * dash_speed
	velocity.y = 0.0
	# [DIUBAH - FIX DOUBLE DASH] move_and_slide() dihapus dari sini karena sudah dipanggil
	# sekali per frame di _physics_process(). Sebelumnya dipanggil dua kali -> jarak dash 2x lipat.


func _on_dash_timer_timeout() -> void:
	is_dashing = false
	dash_cooldown_timer.start()


func _on_dash_cooldown_timeout() -> void:
	can_dash = true


func _handle_shoot_input() -> void:
	# [BARU - NO SHOOT WHILE DASH] Tidak bisa menembak saat pre dash maupun dash
	if is_dashing or is_pre_dashing:
		return
	if Input.is_action_pressed("shoot") and fire_rate_timer.is_stopped():
		_shoot()


func _shoot() -> void:
	# [BARU - SHOOT ANIM] Aktifkan pose menembak (idle / crouch / run / jump ditentukan di _update_state)
	shoot_anim_timer = shoot_anim_hold

	if bullet_scene == null:
		push_warning("Player: bullet_scene belum di-assign di Inspector.")
		return

	var spawn_point: Marker2D = _get_spawn_point()   # [DIUBAH - MUZZLE RUN] pilih Muzzle / MuzzleCrouch / MuzzleRun
	var bullet: Node = bullet_scene.instantiate()
	get_tree().current_scene.add_child(bullet)
	bullet.global_position = spawn_point.global_position
	bullet.setup(facing_direction, bullet_damage)

	fire_rate_timer.start()


# [BARU - MUZZLE RUN] Pilih titik keluar peluru sesuai kondisi player.
# Kalau node muzzle khusus belum dibuat, otomatis dipakai "Muzzle" biasa (tidak error).
func _get_spawn_point() -> Marker2D:
	if is_crouching and muzzle_crouch != null:
		return muzzle_crouch
	if state == State.RUN and muzzle_run != null:
		return muzzle_run
	return muzzle


# [BARU] Cari Marker2D berdasarkan daftar nama yang mungkin; null kalau tidak ada satu pun.
func _find_marker(node_names: Array) -> Marker2D:
	for node_name in node_names:
		var found := get_node_or_null(NodePath(node_name)) as Marker2D
		if found != null:
			return found
	push_warning("Player: node %s tidak ditemukan, memakai Muzzle biasa." % [node_names])
	return null


func _update_facing() -> void:
	# [DIUBAH - PRE DASH AIR] Arah dikunci juga saat pre dash
	if is_dashing or is_pre_dashing:
		return
	var input_direction := Input.get_axis("move_left", "move_right")
	if input_direction > 0.0:
		facing_direction = 1
		animated_sprite.flip_h = false
	elif input_direction < 0.0:
		facing_direction = -1
		animated_sprite.flip_h = true

	# [BARU - MUZZLE FLIP] Titik keluar peluru ikut berbalik sesuai arah hadap.
	# Syarat: semua marker ditaruh di sisi KANAN (X positif) di editor.
	for marker in [muzzle, muzzle_crouch, muzzle_run]:
		if marker != null:
			marker.position.x = absf(marker.position.x) * facing_direction


func _update_state() -> void:
	var new_state: State

	if hit_anim_timer > 0.0:
		# [BARU - HIT]
		new_state = State.HIT
	elif is_pre_dashing:
		# [BARU - PRE DASH AIR]
		new_state = State.PRE_DASH_AIR
	elif is_dashing:
		new_state = State.DASH
	elif is_crouching and is_on_floor():
		new_state = State.CROUCH
	elif not is_on_floor() and velocity.y < 0.0:
		new_state = State.JUMP
	elif not is_on_floor() and velocity.y >= 0.0:
		new_state = State.FALL
	elif abs(velocity.x) > 10.0:
		new_state = State.RUN
	else:
		new_state = State.IDLE

	# [BARU - CROUCH IDLE] Setiap baru masuk CROUCH, intro "CROUNCH" diputar lagi dari awal
	if new_state == State.CROUCH and state != State.CROUCH:
		crouch_intro_done = false
		crouch_shoot_intro_done = false   # [BARU - CROUCH SHOOT]

	state = new_state
	_update_collision_shape()   # [BARU - COLLISION]

	var is_shooting := shoot_anim_timer > 0.0

	# Sesuaikan nama-nama animasi ini dengan yang ada di AnimatedSprite2D kamu.
	match state:
		State.IDLE:
			if is_shooting:
				_play_anim(&"SHOOT_IDLE")      # [BARU - SHOOT ANIM] nembak posisi idle
			else:
				_play_anim(&"IDLE")
		State.RUN:
			if is_shooting:
				_play_anim(&"SHOOT_RUN")       # [BARU - SHOOT ANIM] nembak posisi lari
			else:
				_play_anim(&"RUN")
		State.JUMP:
			# [BARU - SHOOT ANIM] nembak posisi lompat = tetap pakai animasi JUMP (tidak ada animasi khusus)
			_play_anim(&"JUMP")
		State.FALL:
			# [DIUBAH - FIX FALL] Sebelumnya play("fall") padahal animasi itu tidak ada,
			# akibatnya animasi terakhir (DASH) tetap nyangkut. Sekarang fall pakai animasi JUMP.
			_play_anim(&"JUMP")
		State.CROUCH:
			if is_shooting:
				# [DIUBAH - CROUCH SHOOT] nembak posisi crouch: "DUCK" sekali dulu, lalu "CROUNCH_BOIL" (loop).
				# Intro crouch dianggap selesai supaya setelah menembak tidak mengulang animasi turun jongkok.
				crouch_intro_done = true
				# Kalau animasi DUCK belum dibuat di SpriteFrames, langsung lompat ke CROUNCH_BOIL.
				if not crouch_shoot_intro_done and not animated_sprite.sprite_frames.has_animation(&"DUCK"):
					crouch_shoot_intro_done = true

				if crouch_shoot_intro_done:
					_play_anim(&"CROUCH_BOIL")    # loop selama crouch + tembak ditahan
				else:
					_play_anim(&"DUCK")            # diputar sekali
			else:
				# [BARU - CROUCH SHOOT] Berhenti menembak -> siap-siap memutar DUCK lagi pada tembakan berikutnya
				crouch_shoot_intro_done = false
				if crouch_intro_done:
					_play_anim(&"CROUCH_IDLE")    # [BARU - CROUCH IDLE] loop selama tombol crouch ditahan
				else:
					_play_anim(&"CROUCH")         # intro, diputar sekali
		State.DASH:
			_play_anim(&"DASH")
		State.PRE_DASH_AIR:
			_play_anim(&"PRE_DASH_AIR")        # [BARU - PRE DASH AIR] diputar sekali sebelum DASH
		State.HIT:
			_play_anim(&"HIT")                 # [BARU - HIT]
		State.DEAD:
			_play_anim(&"DEAD")                # [BARU - DEAD]


# [BARU] Putar animasi hanya kalau berbeda dari yang sedang aktif.
# Ini mencegah animasi non-loop (CROUNCH, HIT, dll) ter-restart tiap frame.
# RUN <-> SHOOT_RUN mempertahankan frame supaya langkah kaki tidak "loncat" saat mulai/berhenti nembak.
func _play_anim(anim_name: StringName) -> void:
	if current_anim == anim_name:
		return

	var keep_frame := (current_anim == &"RUN" and anim_name == &"SHOOT_RUN") \
		or (current_anim == &"SHOOT_RUN" and anim_name == &"RUN")

	if keep_frame:
		var f := animated_sprite.frame
		var p := animated_sprite.frame_progress
		animated_sprite.play(anim_name)
		animated_sprite.set_frame_and_progress(f, p)
	else:
		animated_sprite.play(anim_name)

	current_anim = anim_name


# [BARU] Hitung durasi animasi (detik) dari SpriteFrames; pakai fallback kalau animasinya belum ada.
func _get_anim_duration(anim_name: StringName, fallback: float) -> float:
	var frames := animated_sprite.sprite_frames
	if frames == null or not frames.has_animation(anim_name):
		return fallback
	var anim_speed := frames.get_animation_speed(anim_name)
	if anim_speed <= 0.0:
		return fallback
	var total := 0.0
	for i in frames.get_frame_count(anim_name):
		total += frames.get_frame_duration(anim_name, i)
	return total / anim_speed / maxf(animated_sprite.speed_scale, 0.001)


# [BARU - CROUCH IDLE] Intro "CROUNCH" selesai -> state berikutnya otomatis pindah ke "CROUNCH_IDLE"
func _on_animation_finished() -> void:
	if current_anim == &"CROUCH":
		crouch_intro_done = true
	# [BARU - CROUCH SHOOT] "DUCK" selesai -> state berikutnya otomatis pindah ke "CROUNCH_BOIL"
	elif current_anim == &"DUCK":
		crouch_shoot_intro_done = true


func _on_hurtbox_area_entered(area: Area2D) -> void:
	if is_invincible:
		return
	if area.is_in_group("enemy_hitbox"):
		take_damage(1)


func take_damage(amount: int) -> void:
	if is_invincible or state == State.DEAD:   # [DIUBAH] player yang sudah mati tidak bisa kena damage lagi
		return

	current_health = max(current_health - amount, 0)
	health_changed.emit(current_health, max_health)
	player_hurt.emit()

	if current_health <= 0:
		_die()
		return

	hit_anim_timer = hit_anim_duration   # [BARU - HIT] mulai animasi hit
	is_invincible = true
	invincibility_timer.start()
	_start_invincibility_flicker()


func _on_invincibility_timeout() -> void:
	is_invincible = false
	animated_sprite.modulate.a = 1.0


func _start_invincibility_flicker() -> void:
	var tween := create_tween()
	tween.set_loops(int(invincibility_duration / 0.2))
	tween.tween_property(animated_sprite, "modulate:a", 0.3, 0.1)
	tween.tween_property(animated_sprite, "modulate:a", 1.0, 0.1)


func _die() -> void:
	if state == State.DEAD:   # [BARU] cegah _die() terpanggil dua kali
		return
	player_died.emit()
	# [BARU - DEAD] Mainkan animasi mati sebelum physics process dimatikan
	# (physics process dimatikan, jadi _update_state tidak jalan lagi -> dipanggil manual di sini).
	is_dashing = false
	is_pre_dashing = false
	hit_anim_timer = 0.0
	state = State.DEAD
	_play_anim(&"DEAD")
	_play_death_effect()   # [BARU - DEATH EFFECT]
	set_physics_process(false)
	# TODO: delay, lalu reload level / tampilkan game over screen.


# [BARU - DEATH EFFECT] Sprite naik perlahan sambil memudar sampai hilang.
# Tween berjalan di idle process, jadi tetap jalan walau set_physics_process(false).
func _play_death_effect() -> void:
	animated_sprite.modulate.a = 1.0
	var tween := create_tween().set_parallel(true)
	tween.tween_property(animated_sprite, "position:y", animated_sprite.position.y - death_rise_distance, death_fade_duration) \
		.set_delay(death_fade_delay).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(animated_sprite, "modulate:a", 0.0, death_fade_duration) \
		.set_delay(death_fade_delay)
	# TODO: nanti sambungkan ke game over / reload level lewat tween.finished


# [BARU - COLLISION] ---------------------------------------------------------
# Mengubah tinggi collision badan player dan HurtBox sesuai state:
# berdiri = normal, crouch = pendek, lompat/jatuh = sedang.
func _setup_collision_shapes() -> void:
	# Badan: node "CollisionPlayer", atau CollisionShape2D pertama di bawah Player.
	body_shape = get_node_or_null("CollisionPlayer") as CollisionShape2D
	if body_shape == null:
		for child in get_children():
			if child is CollisionShape2D:
				body_shape = child
				break

	# HurtBox: CollisionShape2D pertama di dalam node HurtBox.
	for child in hurtbox.get_children():
		if child is CollisionShape2D:
			hurtbox_shape = child
			break

	# duplicate() supaya badan dan HurtBox tidak berbagi satu resource shape.
	if body_shape != null and body_shape.shape != null:
		body_shape.shape = body_shape.shape.duplicate()
		_base_body_height = _get_shape_height(body_shape.shape)
		_base_body_pos_y = body_shape.position.y
	if hurtbox_shape != null and hurtbox_shape.shape != null:
		hurtbox_shape.shape = hurtbox_shape.shape.duplicate()
		_base_hurt_height = _get_shape_height(hurtbox_shape.shape)
		_base_hurt_pos_y = hurtbox_shape.position.y
	else:
		push_warning("Player: Shape pada HurtBox masih kosong, isi dulu di Inspector.")


func _update_collision_shape() -> void:
	var ratio := 1.0
	match state:
		State.CROUCH:
			ratio = crouch_height_ratio
		State.JUMP, State.FALL:
			ratio = air_height_ratio

	# Hanya diubah kalau rasionya berganti, supaya tidak update physics tiap frame.
	if is_equal_approx(ratio, _current_collision_ratio):
		return
	_current_collision_ratio = ratio

	if resize_body_collision:
		_apply_collision_ratio(body_shape, _base_body_height, _base_body_pos_y, ratio)
	_apply_collision_ratio(hurtbox_shape, _base_hurt_height, _base_hurt_pos_y, ratio)


func _apply_collision_ratio(node: CollisionShape2D, base_height: float, base_pos_y: float, ratio: float) -> void:
	if node == null or node.shape == null or base_height <= 0.0:
		return
	_set_shape_height(node.shape, base_height * ratio)
	var new_height := _get_shape_height(node.shape)
	# Geser ke bawah setengah selisih tinggi supaya bagian kaki tetap di posisi yang sama.
	# [FIX - CROUCH GLITCH] Selisih tinggi harus dikali scale.y node: CollisionPlayer berskala (2.65, 5.5),
	# jadi tanpa ini kaki collision naik ~18 px saat jongkok -> player "melayang", dianggap jatuh,
	# lalu animasi CROUCH/JUMP bergantian terus tiap frame.
	node.position.y = base_pos_y + (base_height - new_height) * 0.5 * node.scale.y


func _get_shape_height(shape: Shape2D) -> float:
	var rect := shape as RectangleShape2D
	if rect != null:
		return rect.size.y
	var capsule := shape as CapsuleShape2D
	if capsule != null:
		return capsule.height
	return 0.0


func _set_shape_height(shape: Shape2D, new_height: float) -> void:
	var rect := shape as RectangleShape2D
	if rect != null:
		rect.size = Vector2(rect.size.x, new_height)
		return
	var capsule := shape as CapsuleShape2D
	if capsule != null:
		capsule.height = maxf(new_height, capsule.radius * 2.0)
# ---------------------------------------------------------------------------
