@tool
extends VBoxContainer

## Step 5: Create Initial Build
## Checks for Gradle build mode, triggers the ship flow, and monitors the
## resulting job until an Android AAB build appears.

signal step_completed

const Config = preload("res://addons/shipthis/lib/config.gd")
const Api = preload("res://addons/shipthis/lib/api.gd")
const AddonContext = preload("res://addons/shipthis/lib/addon_context.gd")
const JobModel = preload("res://addons/shipthis/models/job.gd")

var api: Api = null
var config: Config = null
var project_id: String = ""

# Node references
@onready var loading_label: Label = $LoadingLabel
@onready var gradle_container: VBoxContainer = $GradleContainer
@onready var gradle_notice: RichTextLabel = $GradleContainer/GradleNotice
@onready var enable_gradle_button: Button = $GradleContainer/EnableGradleButton
@onready var ship_container: VBoxContainer = $ShipContainer
@onready var ship_runner = $ShipContainer/ShipRunner
@onready var error_container: VBoxContainer = $ErrorContainer
@onready var error_label: Label = $ErrorContainer/ErrorLabel
@onready var retry_button: Button = $ErrorContainer/RetryButton


func _ready() -> void:
	enable_gradle_button.pressed.connect(_on_enable_gradle_pressed)
	retry_button.pressed.connect(_on_retry_pressed)
	gradle_notice.meta_clicked.connect(_on_meta_clicked)


func initialize(context: AddonContext) -> void:
	api = context.api
	config = context.config
	ship_runner.initialize(context)
	ship_runner.set_show_ship_button(false)
	ship_runner.ship_completed.connect(_on_ship_completed)
	ship_runner.ship_failed.connect(_on_ship_failed)
	ship_runner.retry_requested.connect(_on_retry_pressed)

	var project_config = config.get_project_config()
	project_id = project_config.project_id

	await _check_existing_state()


func _on_meta_clicked(meta: Variant) -> void:
	OS.shell_open(str(meta))


# --- Initial state check ---

func _check_existing_state() -> void:
	_set_loading("Checking existing builds...")

	# Check for existing Android AAB build
	var builds_resp = await api.query_builds(project_id)
	if builds_resp.is_success:
		var builds = builds_resp.data.get("data", [])
		for build in builds:
			if build.get("platform", "") == "ANDROID" and build.get("buildType", "") == "AAB":
				step_completed.emit()
				return

	# Check for a running Android job
	_set_loading("Checking existing jobs...")
	var jobs_resp = await api.query_jobs(project_id)
	if jobs_resp.is_success:
		var jobs = jobs_resp.data.get("data", [])
		for job_data in jobs:
			var job_type = job_data.get("type", "")
			var job_status = job_data.get("status", "")
			if job_type == "ANDROID" and job_status in ["PENDING", "PROCESSING"]:
				var job = JobModel.from_dict(job_data)
				_show_ship_container()
				ship_runner.monitor_job(job)
				return

	# No build and no running job -- check Gradle
	_check_gradle_build()


# --- Gradle check ---

func _check_gradle_build() -> void:
	var is_gradle = _is_gradle_build_enabled()

	if not is_gradle:
		_show_gradle_prompt()
	else:
		_run_ship()


func _is_gradle_build_enabled() -> bool:
	var presets_path = ProjectSettings.globalize_path("res://export_presets.cfg")

	if not FileAccess.file_exists(presets_path):
		# No presets file -- Gradle is not configured
		return false

	var cfg = ConfigFile.new()
	var err = cfg.load(presets_path)
	if err != OK:
		return false

	# Scan sections for an Android preset and check Gradle build option
	for section in cfg.get_sections():
		if not section.begins_with("preset."):
			continue

		var platform = cfg.get_value(section, "platform", "")
		if platform != "Android":
			continue

		# Check both Godot 4 and Godot 3 keys
		var options_section = section + ".options"
		var gradle_v4 = cfg.get_value(options_section, "gradle_build/use_gradle_build", null)
		var gradle_v3 = cfg.get_value(options_section, "custom_build/use_custom_build", null)

		if gradle_v4 != null:
			return str(gradle_v4).to_lower() == "true" or gradle_v4 == true
		if gradle_v3 != null:
			return str(gradle_v3).to_lower() == "true" or gradle_v3 == true

		# Android preset found but no Gradle setting -- default is false
		return false

	# No Android preset found
	return false


func _set_gradle_build_enabled() -> bool:
	var presets_path = ProjectSettings.globalize_path("res://export_presets.cfg")

	var cfg = ConfigFile.new()
	if FileAccess.file_exists(presets_path):
		var err = cfg.load(presets_path)
		if err != OK:
			return false

	# Find or note the Android preset
	for section in cfg.get_sections():
		if not section.begins_with("preset."):
			continue

		var platform = cfg.get_value(section, "platform", "")
		if platform != "Android":
			continue

		var options_section = section + ".options"

		# Determine Godot version for correct key
		var version = Engine.get_version_info()
		if version.major >= 4:
			cfg.set_value(options_section, "gradle_build/use_gradle_build", true)
		else:
			cfg.set_value(options_section, "custom_build/use_custom_build", true)

		var err = cfg.save(presets_path)
		return err == OK

	# No Android preset found -- cannot enable
	return false


func _show_gradle_prompt() -> void:
	var docs_url = "https://shipth.is/docs/guides/android-build-methods"
	var version = Engine.get_version_info()
	var godot_version = "%d.%d.%d" % [version.major, version.minor, version.patch]
	var option_key = "gradle_build/use_gradle_build" if version.major >= 4 else "custom_build/use_custom_build"

	var bbcode = "[b]Gradle Build Required[/b]\n\n" \
		+ "To create an Android App Bundle (AAB) for Google Play, " \
		+ "Gradle build must be enabled in your export presets.\n\n" \
		+ "Godot version: %s\n" % godot_version \
		+ "Setting: %s\n\n" % option_key \
		+ "Click the button below to enable Gradle build in your export_presets.cfg.\n\n" \
		+ "Learn more: [url=%s]Android Build Methods[/url]" % docs_url
	gradle_notice.text = bbcode

	_hide_all()
	gradle_container.visible = true


func _on_enable_gradle_pressed() -> void:
	enable_gradle_button.disabled = true
	_set_loading("Enabling Gradle build...")

	var success = _set_gradle_build_enabled()
	if not success:
		_show_error("Failed to update export_presets.cfg. Please enable Gradle build manually.")
		return

	_run_ship()


# --- Ship flow ---

func _run_ship() -> void:
	_show_ship_container()
	ship_runner.ship({
		"platform": "ANDROID",
		"skipPublish": true
	})


func _on_ship_completed(_job) -> void:
	await _verify_build_exists()


func _on_ship_failed(_message: String) -> void:
	pass  # ShipRunner shows error inline; step-level handling if needed


func _verify_build_exists() -> void:
	_set_loading("Verifying build...")
	var builds_resp = await api.query_builds(project_id)
	if builds_resp.is_success:
		var builds = builds_resp.data.get("data", [])
		for build in builds:
			if build.get("platform", "") == "ANDROID" and build.get("buildType", "") == "AAB":
				step_completed.emit()
				return

	# Build completed but AAB not found -- still complete the step
	step_completed.emit()


# --- Retry ---

func _on_retry_pressed() -> void:
	_hide_all()
	await _check_existing_state()


# --- UI helpers ---

func _hide_all() -> void:
	loading_label.visible = false
	gradle_container.visible = false
	ship_container.visible = false
	error_container.visible = false


func _set_loading(message: String) -> void:
	_hide_all()
	loading_label.text = message
	loading_label.visible = true


func _show_ship_container() -> void:
	_hide_all()
	ship_container.visible = true


func _show_error(message: String) -> void:
	_hide_all()
	error_container.visible = true
	error_label.text = message
	error_label.add_theme_color_override("font_color", Color.RED)
