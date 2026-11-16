extends Node
# ScoreManager -- daftarkan sebagai Autoload (Project Settings > Globals > Autoload) dengan nama "ScoreManager".
# Menyimpan total poin dan memberi tahu UI kalau poin berubah.

signal score_changed(new_score: int)
signal points_gained(amount: int)

var score: int = 0


func add_points(amount: int) -> void:
	score += amount
	points_gained.emit(amount)
	score_changed.emit(score)


func reset_score() -> void:
	score = 0
	score_changed.emit(score)
