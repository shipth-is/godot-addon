@tool
extends EditorPlugin

const Config = preload("res://addons/shipthis/lib/config.gd")
const Api = preload("res://addons/shipthis/lib/api.gd")
const ShipThisPanel = preload("res://addons/shipthis/ShipThisPanel.gd")

var config: Config = null
var api: Api = null

var panel: ShipThisPanel = null
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
	api = Api.new()
	
	# Initialize panel with config and api
	panel.initialize(config, api)


func _initialize_panel() -> void:
	panel = SHIP_THIS_PANEL.instantiate()
	add_control_to_bottom_panel(panel, PANEL_TITLE)


func _terminate_panel() -> void:
	remove_control_from_bottom_panel(panel)
	panel.queue_free()
