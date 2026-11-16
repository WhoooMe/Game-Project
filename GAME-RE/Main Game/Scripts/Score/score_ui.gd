extends CanvasLayer
# Tampilan poin. Pasang di node CanvasLayer dengan anak:
#   ScoreLabel (Label)  -> total poin
#   GainLabel  (Label)  -> OPSIONAL, menampilkan "+450" sesaat setelah membunuh musuh

@export var count_up_duration: float = 0.4   # lama angka naik ke total baru
@export var gain_show_time: float = 1.0      # lama "+N" terlihat sebelum memudar

@onready var score_label: Label = $ScoreLabel
@onready var gain_label: Label = get_node_or_null("GainLabel")

var _displayed: int = 0
var _count_tween: Tween
var _gain_tween: Tween


func _ready() -> void:
	if gain_label != null:
		gain_label.modulate.a = 0.0

	var score_manager := get_node_or_null("/root/ScoreManager")
	if score_manager == null:
		push_warning("ScoreUI: ScoreManager belum didaftarkan sebagai Autoload.")
		_set_displayed(0.0)
		return

	score_manager.connect("score_changed", _on_score_changed)
	score_manager.connect("points_gained", _on_points_gained)
	_set_displayed(float(score_manager.get("score")))


func _on_score_changed(new_score: int) -> void:
	if _count_tween != null:
		_count_tween.kill()
	_count_tween = create_tween()
	_count_tween.tween_method(_set_displayed, float(_displayed), float(new_score), count_up_duration)


func _on_points_gained(amount: int) -> void:
	if gain_label == null:
		return
	if _gain_tween != null:
		_gain_tween.kill()
	gain_label.text = "+%d" % amount
	gain_label.modulate.a = 1.0
	_gain_tween = create_tween()
	_gain_tween.tween_interval(gain_show_time)
	_gain_tween.tween_property(gain_label, "modulate:a", 0.0, 0.4)


func _set_displayed(value: float) -> void:
	_displayed = int(round(value))
	score_label.text = "SCORE  %06d" % _displayed
