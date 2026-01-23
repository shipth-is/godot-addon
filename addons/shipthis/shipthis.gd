@tool
extends EditorPlugin

const Config = preload("res://addons/shipthis/config.gd")
const API = preload("res://addons/shipthis/api.gd")

var config = null
var api = null

var panel: VBoxContainer = null
const SHIP_THIS_PANEL = preload("res://addons/shipthis/ShipThisPanel.tscn")

const PANEL_TITLE = "🚀 ShipThis"


func _enable_plugin() -> void:
	pass


func _disable_plugin() -> void:
	pass


func _enter_tree() -> void:
	_initialize_panel()
	_initialize_plugin()


func _exit_tree() -> void:
	_terminate_panel()


func _initialize_plugin() -> void:
	config = Config.new()
	api = API.new()
	
	# Initialize panel with config and api
	panel.initialize(config, api)


func _initialize_panel() -> void:
	panel = SHIP_THIS_PANEL.instantiate()
	add_control_to_bottom_panel(panel, PANEL_TITLE)


func _terminate_panel() -> void:
	remove_control_from_bottom_panel(panel)
	panel.queue_free()
