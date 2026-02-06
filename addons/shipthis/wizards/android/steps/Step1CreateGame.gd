@tool
extends VBoxContainer

## Step 1: Create Game
## Creates a new project or updates an existing one with the Android package name.

signal step_completed

const Config = preload("res://addons/shipthis/lib/config.gd")
const Api = preload("res://addons/shipthis/lib/api.gd")
const ProjectConfig = preload("res://addons/shipthis/models/project_config.gd")

var api: Api = null
var config: Config = null

# State
var existing_project_id: String = ""
var is_loading: bool = false

# Regex for validating Android package name: com.example.game
var package_regex: RegEx = null

@onready var form_container: VBoxContainer = $FormContainer
@onready var game_name_input: LineEdit = $FormContainer/GameNameInput
@onready var package_name_input: LineEdit = $FormContainer/PackageNameInput
@onready var submit_button: Button = $FormContainer/SubmitButton
@onready var status_label: Label = $StatusLabel
@onready var loading_label: Label = $LoadingLabel


func _ready() -> void:
	submit_button.pressed.connect(_on_submit_pressed)
	
	# Compile the package name regex
	# Must start with letter, have at least two segments separated by dots
	# Each segment must start with letter and contain only word characters
	package_regex = RegEx.new()
	package_regex.compile("^[A-Za-z]\\w*(\\.[A-Za-z]\\w*)+$")


func initialize(api_ref: Api, config_ref: Config) -> void:
	api = api_ref
	config = config_ref
	
	# Check if project already exists
	var project_config = config.get_project_config()
	existing_project_id = project_config.project_id
	
	if existing_project_id != "":
		# Fetch existing project to pre-populate form
		await _fetch_existing_project()
	else:
		_show_form()


func _fetch_existing_project() -> void:
	_set_loading(true, "Loading project...")
	
	var response = await api.get_project(existing_project_id)
	
	_set_loading(false)
	
	if response.is_success:
		# Pre-populate form with existing data
		var project_name = response.data.get("name", "")
		var details = response.data.get("details", {})
		var android_package = ""
		if details != null:
			android_package = details.get("androidPackageName", "")
		
		game_name_input.text = project_name
		package_name_input.text = android_package
		
		# Update button text since we're updating
		submit_button.text = "Update Game"
	else:
		_show_error("Failed to load project: %s" % response.error)
	
	_show_form()


func _show_form() -> void:
	form_container.visible = true
	loading_label.visible = false


func _set_loading(loading: bool, message: String = "Loading...") -> void:
	is_loading = loading
	loading_label.text = message
	loading_label.visible = loading
	form_container.visible = not loading
	submit_button.disabled = loading
	_clear_error()


func _show_error(message: String) -> void:
	status_label.text = message
	status_label.add_theme_color_override("font_color", Color.RED)
	status_label.visible = true


func _clear_error() -> void:
	status_label.text = ""
	status_label.visible = false


func _validate_inputs() -> bool:
	var game_name = game_name_input.text.strip_edges()
	var package_name = package_name_input.text.strip_edges()
	
	# Validate game name
	if game_name == "":
		_show_error("Please enter a name for your game")
		return false
	
	# Validate package name format
	if package_name == "":
		_show_error("Please enter an Android package name")
		return false
	
	var match_result = package_regex.search(package_name)
	if match_result == null:
		_show_error("Please enter a valid package name (e.g. com.example.mygame)")
		return false
	
	return true


func _on_submit_pressed() -> void:
	_clear_error()
	
	if not _validate_inputs():
		return
	
	var game_name = game_name_input.text.strip_edges()
	var package_name = package_name_input.text.strip_edges()
	
	if existing_project_id != "":
		await _update_existing_project(game_name, package_name)
	else:
		await _create_new_project(game_name, package_name)


func _update_existing_project(game_name: String, package_name: String) -> void:
	_set_loading(true, "Updating project...")
	
	var data = {
		"name": game_name,
		"details": {
			"androidPackageName": package_name
		}
	}
	
	var response = await api.update_project(existing_project_id, data)
	
	if response.is_success:
		# Don't set loading false - wizard will remove this node
		step_completed.emit()
	else:
		_set_loading(false)
		_show_error("Failed to update project: %s" % response.error)


func _create_new_project(game_name: String, package_name: String) -> void:
	_set_loading(true, "Creating project...")
	
	var godot_version = _get_godot_version()
	
	var details = {
		"androidPackageName": package_name,
		"gameEngine": "GODOT",
		"gameEngineVersion": godot_version
	}
	
	var response = await api.create_project(game_name, details)
	
	if not response.is_success:
		_set_loading(false)
		_show_error("Failed to create project: %s" % response.error)
		_show_form()
		return
	
	# Save project config locally
	var new_project_id = response.data.get("id", "")
	if new_project_id == "":
		_set_loading(false)
		_show_error("Project created but no ID returned")
		_show_form()
		return
	
	var project_config = ProjectConfig.new(
		PackedStringArray(Config.DEFAULT_IGNORED_FILES_GLOBS),
		new_project_id,
		PackedStringArray(Config.DEFAULT_SHIPPED_FILES_GLOBS)
	)
	
	var save_error = config.set_project_config(project_config)
	
	if save_error != OK:
		_set_loading(false)
		_show_error("Project created but failed to save config locally")
		return
	
	# Don't set loading false - wizard will remove this node
	step_completed.emit()


func _get_godot_version() -> String:
	var version = Engine.get_version_info()
	return "%d.%d.%d" % [version.major, version.minor, version.patch]
