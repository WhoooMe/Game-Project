extends Camera2D

## ============================================================
## KAMERA SATU ARAH (Endless Runner)
## ============================================================
## - Kamera hanya boleh maju ke kanan, TIDAK pernah ikut mundur.
## - Tepi kiri layar menjadi border: player tidak bisa mundur melewatinya,
##   jadi background yang sudah lewat tidak pernah terlihat "terpotong".
## - Jarak terjauh yang dicapai dipakai sebagai skor (lihat get_distance()).
##
## Pasang di Camera2D yang menjadi child dari Player (seperti sekarang).
## ============================================================

## Jarak border dari tepi kiri layar (px). Makin besar = player makin sempit ruang mundurnya.
@export var left_margin: float = 40.0

var initial_y: float
var start_x: float
var max_x: float   # posisi x terjauh yang pernah dicapai player


func _ready() -> void:
	# top_level = true memutus kamera dari pergerakan Player; kita atur sendiri posisinya.
	top_level = true
	initial_y = global_position.y
	start_x = get_parent().global_position.x
	max_x = start_x


func _physics_process(_delta: float) -> void:
	var player := get_parent() as CharacterBody2D

	# Kamera hanya maju: simpan posisi x terjauh player.
	max_x = max(max_x, player.global_position.x)
	global_position = Vector2(max_x, initial_y)

	# Border kiri: player tidak boleh melewati tepi kiri layar.
	var limit_x := get_left_limit()
	if player.global_position.x < limit_x:
		player.global_position.x = limit_x
		if player.velocity.x < 0.0:
			player.velocity.x = 0.0


## Batas x paling kiri yang boleh dipijak player (koordinat dunia).
func get_left_limit() -> float:
	var half_width := get_viewport_rect().size.x * 0.5 / zoom.x
	return global_position.x + offset.x - half_width + left_margin


## Batas x paling kanan layar, berguna untuk menentukan titik spawn musuh.
func get_right_edge() -> float:
	var half_width := get_viewport_rect().size.x * 0.5 / zoom.x
	return global_position.x + offset.x + half_width


## Jarak tempuh dalam piksel (bagi dengan angka tertentu kalau mau jadi "meter").
func get_distance() -> float:
	return max_x - start_x
