## Shared context for ShipThis addon UI: config, api, and optional editor interface.
## Passed to initialize(context) on panel and complex components.

const Config = preload("res://addons/shipthis/lib/config.gd")
const Api = preload("res://addons/shipthis/lib/api.gd")

var config: Config
var api: Api
var editor_interface: Object = null  # EditorInterface when in editor; null otherwise


func _init(p_config: Config, p_api: Api, p_editor_interface: Object = null) -> void:
	config = p_config
	api = p_api
	editor_interface = p_editor_interface


## Returns the editor theme when editor_interface is set; otherwise null.
func get_editor_theme() -> Theme:
	if editor_interface != null and editor_interface.has_method("get_editor_theme"):
		return editor_interface.get_editor_theme()
	return null
