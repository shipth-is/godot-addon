@tool
extends EditorPlugin


func _enter_tree() -> void:
	add_custom_type("SocketIO", "Node", preload("res://addons/shipthis/third_party/godot-socketio/socketio.gd"), preload("res://addons/shipthis/third_party/godot-socketio/icon.png"))


func _exit_tree() -> void:
	remove_custom_type("SocketIO")
