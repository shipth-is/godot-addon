@tool
extends VBoxContainer

## Android wizard controller - manages step navigation based on status flags

const Config = preload("res://addons/shipthis/lib/config.gd")
const Api = preload("res://addons/shipthis/lib/api.gd")
const AndroidEnums = preload("res://addons/shipthis/wizards/android/android_enums.gd")
const AndroidStatusFlags = preload("res://addons/shipthis/wizards/android/android_status_flags.gd")

signal wizard_completed
signal wizard_cancelled

const STEPS: Array[String] = [
	"createGame",
	"createKeystore",
	"connectGoogle",
	"createServiceAccount",
	"createInitialBuild",
	"createGooglePlayGame",
	"inviteServiceAccount",
]

const STEP_TITLES: Dictionary = {
	"createGame": "Create Game",
	"createKeystore": "Create or Import Keystore",
	"connectGoogle": "Connect with Google",
	"createServiceAccount": "Create Service Account",
	"createInitialBuild": "Create Initial Build",
	"createGooglePlayGame": "Create Game in Google Play",
	"inviteServiceAccount": "Invite Service Account",
}

const STEP_SCENES: Dictionary = {
	"createGame": preload("res://addons/shipthis/wizards/android/steps/Step1CreateGame.tscn"),
	"createKeystore": preload("res://addons/shipthis/wizards/android/steps/Step2Keystore.tscn"),
	"connectGoogle": preload("res://addons/shipthis/wizards/android/steps/Step3ConnectGoogle.tscn"),
	# Additional steps will be added here as they are implemented
}

# Node references
@onready var title_label: Label = $Header/Title
@onready var cancel_button: Button = $Header/CancelButton
@onready var step_indicator: Label = $ProgressContainer/StepIndicator
@onready var help_text: RichTextLabel = $HelpText
@onready var step_container: MarginContainer = $StepContainer

# Dependencies
var config: Config = null
var api: Api = null

# State
var status_flags: AndroidStatusFlags = null
var current_step_index: int = 0
var current_step_node: Control = null
var is_loading: bool = false


func _ready() -> void:
	cancel_button.pressed.connect(_on_cancel_pressed)


func initialize(new_config: Config, new_api: Api) -> void:
	config = new_config
	api = new_api
	
	# Start loading status
	await _refresh_status()
	_load_current_step()


func _refresh_status() -> void:
	is_loading = true
	_update_ui_loading_state()
	
	var project_config = config.get_project_config()
	var project_id = project_config.project_id
	
	status_flags = await AndroidStatusFlags.fetch(api, project_id)
	
	# Determine which step we should be on
	current_step_index = _get_current_step_index()
	
	is_loading = false
	_update_ui_loading_state()
	_update_progress_indicator()


func _get_current_step_index() -> int:
	# Return index of first PENDING step
	for i in range(STEPS.size()):
		var step_status = status_flags.get_step_status(STEPS[i])
		if step_status == AndroidEnums.StepStatus.PENDING:
			return i
	# All complete
	return STEPS.size()


func _load_current_step() -> void:
	# Clear existing step
	if current_step_node != null:
		current_step_node.queue_free()
		current_step_node = null
	
	# Check if wizard is complete
	if current_step_index >= STEPS.size():
		_on_wizard_complete()
		return
	
	var step_name = STEPS[current_step_index]
	
	# Check if step scene exists
	if not STEP_SCENES.has(step_name):
		# Step not implemented yet - show placeholder message
		var placeholder = Label.new()
		placeholder.text = "Step '%s' not yet implemented" % step_name
		placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		step_container.add_child(placeholder)
		current_step_node = placeholder
		return
	
	# Load the step scene
	var step_scene = STEP_SCENES[step_name]
	current_step_node = step_scene.instantiate()
	step_container.add_child(current_step_node)
	
	# Connect step completion signal
	if current_step_node.has_signal("step_completed"):
		current_step_node.step_completed.connect(_on_step_completed)
	
	# Initialize the step
	if current_step_node.has_method("initialize"):
		current_step_node.initialize(api, config)


func _update_progress_indicator() -> void:
	if current_step_index >= STEPS.size():
		step_indicator.text = "Complete!"
		return
	
	var step_name = STEPS[current_step_index]
	var step_title = STEP_TITLES.get(step_name, step_name)
	step_indicator.text = "Step %d of %d: %s" % [current_step_index + 1, STEPS.size(), step_title]


func _update_ui_loading_state() -> void:
	cancel_button.disabled = is_loading


func _on_step_completed() -> void:
	# Re-fetch status to verify completion and advance to next step
	await _refresh_status()
	_load_current_step()


func _on_cancel_pressed() -> void:
	wizard_cancelled.emit()


func _on_wizard_complete() -> void:
	help_text.text = "[b]Android configuration complete![/b]\n\nYour game is now configured for Android deployment."
	_update_progress_indicator()
