extends Control

@export var game_scene: PackedScene

func _on_start_game_pressed():
	get_tree().change_scene_to_packed(game_scene)

func _on_exit_pressed():
	get_tree().quit()


func _on_button_pressed() -> void:
	pass # Replace with function body.
