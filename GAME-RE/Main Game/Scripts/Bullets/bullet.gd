extends Area2D

# -- Pengaturan peluru (bisa diubah di Inspector) --
@export var speed: float = 650.0
@export var max_lifetime: float = 2.0                 # cadangan: peluru hilang sendiri setelah X detik
@export var fly_animation: StringName = &"FLY"        # nama animasi peluru di SpriteFrames (Loop ON)

var direction: int = 1      # 1 = kanan, -1 = kiri (diisi oleh player lewat setup())
var damage: int = 1         # diisi oleh player lewat setup()
var _has_hit: bool = false  # supaya satu peluru tidak memberi damage dua kali

@onready var animated_sprite: AnimatedSprite2D = $AnimateBullets
@onready var screen_notifier: VisibleOnScreenNotifier2D = $VisibleOnScreenNotifier2D


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	screen_notifier.screen_exited.connect(queue_free)

	# Cadangan kalau peluru tidak pernah keluar layar / menabrak apa pun.
	get_tree().create_timer(max_lifetime).timeout.connect(queue_free)

	if animated_sprite.sprite_frames != null and animated_sprite.sprite_frames.has_animation(fly_animation):
		animated_sprite.play(fly_animation)


# Dipanggil oleh player.gd -> bullet.setup(facing_direction, bullet_damage)
# (dipanggil setelah add_child, jadi semua @onready sudah siap)
func setup(dir: int, dmg: int) -> void:
	direction = 1 if dir >= 0 else -1
	damage = dmg
	animated_sprite.flip_h = direction < 0


func _physics_process(delta: float) -> void:
	global_position.x += direction * speed * delta


func _on_body_entered(body: Node2D) -> void:
	_hit(body)


func _on_area_entered(area: Area2D) -> void:
	_hit(area)


func _hit(target: Node) -> void:
	# [BARU] Peluru player tidak boleh mengenai player (cek target dan parent-nya, karena HurtBox ada di dalam Player)
	if target.is_in_group("player") or (target.get_parent() != null and target.get_parent().is_in_group("player")):
		return
	if _has_hit:
		return
	_has_hit = true

	# Musuh bisa berupa body-nya langsung atau Area2D (hurtbox) di dalam musuh,
	# jadi cek target itu sendiri lalu parent-nya.
	var receiver: Node = null
	if target.has_method("take_damage"):
		receiver = target
	elif target.get_parent() != null and target.get_parent().has_method("take_damage"):
		receiver = target.get_parent()

	if receiver != null:
		receiver.take_damage(damage)

	# Menabrak musuh ATAU dinding/tanah (apa pun yang ada di Collision Mask) -> peluru hancur.
	# TODO: nanti di sini bisa ditambah animasi/efek ledakan peluru.
	queue_free()
