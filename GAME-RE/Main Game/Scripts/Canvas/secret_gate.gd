extends CanvasLayer

# ------------------------------------------------------------------
# Secret gate: debug mode (kode tombol) + hadiah di skor 1.000.000.
# Pasang HANYA SATU cara: script pada node CanvasLayer "SecretGate" di scene_1.tscn,
# ATAU sebagai Autoload "SecretGate". Jangan keduanya (skor akan bertambah dua kali).
# Memakai ScoreManager milik game, jadi skor = poin dari membunuh musuh.
# Kunci dekripsi diturunkan dari KODE TOMBOL, bukan dari skor, jadi
# mengubah skor lewat Cheat Engine saja tidak memunculkan flag.
# ------------------------------------------------------------------

const SCORE_TARGET: int = 1_000_000
const BASE_RATE: float = 1.0          # poin per detik, kondisi normal
const CHEAT_MULT: float = 100000.0    # pengali saat debug mode aktif
const CODE_LEN: int = 10
const CHECK: int = 563965720
const BLOB: Array = [51, 17, 208, 78, 38, 198, 157, 255, 93, 80, 121, 144, 161, 115, 31, 209, 157, 115, 152, 84, 187, 102, 234, 155, 164, 82, 131, 149, 119, 202, 138, 248, 56, 69, 254, 87, 48, 214, 217, 191, 14, 86]

var history: Array[int] = []
var cheat_on: bool = false
var unlocked_code: String = ""
var revealed: bool = false

var _accum: float = 0.0
var goal_label: Label
var status_label: Label


func _ready() -> void:
	layer = 100

	goal_label = Label.new()
	goal_label.position = Vector2(24, 16)
	goal_label.add_theme_font_size_override("font_size", 22)
	add_child(goal_label)

	status_label = Label.new()
	status_label.position = Vector2(24, 48)
	status_label.add_theme_font_size_override("font_size", 22)
	add_child(status_label)

	_refresh_goal(ScoreManager.score)


func _process(delta: float) -> void:
	if revealed:
		return

	# Poin pasif (dan jauh lebih cepat saat debug mode) masuk ke ScoreManager milik game.
	var rate: float = BASE_RATE
	if cheat_on:
		rate *= CHEAT_MULT
	_accum += rate * delta
	var whole: int = int(_accum)
	if whole > 0:
		_accum -= whole
		ScoreManager.score += whole
		ScoreManager.score_changed.emit(ScoreManager.score)

	var s: int = ScoreManager.score
	_refresh_goal(s)

	# Flag hanya bisa didekripsi kalau kode tombol sudah benar (kunci berasal dari kode).
	if cheat_on and s >= SCORE_TARGET:
		revealed = true
		status_label.text = _decrypt(unlocked_code)


func _unhandled_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return

	var t: int = _token_for(event)
	if t == 0:
		return

	history.append(t)
	if history.size() > CODE_LEN:
		history.pop_front()

	if not cheat_on and history.size() == CODE_LEN and _mix(history) == CHECK:
		cheat_on = true
		unlocked_code = _code_string(history)
		status_label.text = "DEBUG MODE: ON"


func _token_for(event: InputEvent) -> int:
	if event.is_action_pressed("move_left"):
		return 1
	if event.is_action_pressed("move_right"):
		return 2
	if event.is_action_pressed("crouch"):
		return 3
	if event.is_action_pressed("jump"):
		return 4
	if event.is_action_pressed("dash"):
		return 5
	if event.is_action_pressed("shoot"):
		return 6
	return 0


func _mix(codes: Array) -> int:
	var h: int = 0x1F2E3D4C
	for c in codes:
		h = (h ^ int(c)) & 0xFFFFFFFF
		h = (h * 0x01000193) & 0xFFFFFFFF
	h = h ^ (h >> 15)
	return h & 0xFFFFFFFF


func _code_string(codes: Array) -> String:
	var s := ""
	for c in codes:
		s += str(int(c))
	return s


func _decrypt(code_str: String) -> String:
	var key: PackedByteArray = ("RE26:" + code_str).sha256_buffer()
	var out := ""
	for i in BLOB.size():
		var b: int = int(BLOB[i]) ^ key[i % key.size()]
		if b >= 32 and b < 127:
			out += char(b)
		else:
			out += "?"
	return out


func _refresh_goal(s: int) -> void:
	goal_label.text = "GOAL: %d / %d" % [s, SCORE_TARGET]
