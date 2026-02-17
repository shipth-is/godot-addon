@tool
extends VBoxContainer

## Step 5: Create Initial Build
## Checks for Gradle build mode, triggers the ship flow, and monitors the
## resulting job until an Android AAB build appears.

signal step_completed

const Config = preload("res://addons/shipthis/lib/config.gd")
const Api = preload("res://addons/shipthis/lib/api.gd")
const Ship = preload("res://addons/shipthis/lib/ship.gd")
const JobSocket = preload("res://addons/shipthis/lib/job_socket.gd")
const JobModel = preload("res://addons/shipthis/models/job.gd")
const LogOutputScript = preload("res://addons/shipthis/components/LogOutput.gd")

var api: Api = null
var config: Config = null
var project_id: String = ""

# State
var _job_socket: JobSocket = null
var _is_shipping: bool = false

# Node references
@onready var loading_label: Label = $LoadingLabel
@onready var gradle_container: VBoxContainer = $GradleContainer
@onready var gradle_notice: RichTextLabel = $GradleContainer/GradleNotice
@onready var enable_gradle_button: Button = $GradleContainer/EnableGradleButton
@onready var ship_container: VBoxContainer = $ShipContainer
@onready var ship_status_label: Label = $ShipContainer/ShipStatusLabel
@onready var progress_container: HBoxContainer = $ShipContainer/ProgressContainer
@onready var progress_bar: ProgressBar = $ShipContainer/ProgressContainer/ProgressBar
@onready var progress_label: Label = $ShipContainer/ProgressContainer/ProgressLabel
@onready var log_output: LogOutputScript = $ShipContainer/LogOutput
@onready var job_status_label: Label = $ShipContainer/JobStatusLabel
@onready var error_container: VBoxContainer = $ErrorContainer
@onready var error_label: Label = $ErrorContainer/ErrorLabel
@onready var retry_button: Button = $ErrorContainer/RetryButton


func _ready() -> void:
	enable_gradle_button.pressed.connect(_on_enable_gradle_pressed)
	retry_button.pressed.connect(_on_retry_pressed)
	gradle_notice.meta_clicked.connect(_on_meta_clicked)


func _exit_tree() -> void:
	_cleanup_job_socket()


func initialize(api_ref: Api, config_ref: Config) -> void:
	api = api_ref
	config = config_ref

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
				_show_ship_container("Monitoring existing build job...")
				_start_job_monitoring(job)
				return

	# No build and no running job -- check Gradle
	_check_gradle_build()


# --- Gradle check ---

func _check_gradle_build() -> void:
	var is_gradle = _is_gradle_build_enabled()

	if not is_gradle:
		_show_gradle_prompt()
	else:
		await _run_ship()


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

	await _run_ship()


# --- Ship flow ---

func _run_ship() -> void:
	if _is_shipping:
		return
	_is_shipping = true

	_show_ship_container("Starting build process...")

	var ship_instance = Ship.new()
	var result = await ship_instance.ship(config, api, _ship_logger, get_tree(), {
		"platform": "ANDROID",
		"skipPublish": true
	})

	if result.error != OK:
		_is_shipping = false
		if result.job == null:
			_show_error_inline("Build failed. Please check the log output above and try again.")
		return

	if result.job != null:
		ship_status_label.text = "Build submitted! Monitoring job..."
		_start_job_monitoring(result.job)
	else:
		_is_shipping = false
		_show_error_inline("No job was created. Please check your game configuration.")


func _ship_logger(message: String) -> void:
	log_output.log_message(message)


# --- Job monitoring ---

func _start_job_monitoring(job) -> void:
	_cleanup_job_socket()

	_job_socket = JobSocket.new()
	add_child(_job_socket)

	_job_socket.job_updated.connect(_on_job_updated)
	_job_socket.log_received.connect(_on_log_received)

	_job_socket.connect_to_server(api.client.ws_url, api.client.token)
	_job_socket.subscribe_to_job(project_id, job.id)

	# Show job progress
	progress_container.visible = true
	job_status_label.visible = true
	job_status_label.text = "Job status: %s" % job.status_name()


func _on_job_updated(job) -> void:
	job_status_label.text = "Job status: %s" % job.status_name()

	if job.status == JobModel.JobStatus.COMPLETED:
		_cleanup_job_socket()
		_is_shipping = false
		# Verify the build exists
		await _verify_build_exists()
	elif job.status == JobModel.JobStatus.FAILED:
		_cleanup_job_socket()
		_is_shipping = false
		_show_error_inline("Build job failed. Check the logs above for details.")


func _on_log_received(entry) -> void:
	log_output.log_entry(entry)
	if entry.progress >= 0:
		progress_bar.value = entry.progress
		progress_label.text = "%d%%" % int(entry.progress)


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


func _cleanup_job_socket() -> void:
	if _job_socket != null:
		_job_socket.disconnect_socket()
		_job_socket.queue_free()
		_job_socket = null


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


func _show_ship_container(status: String) -> void:
	_hide_all()
	ship_container.visible = true
	ship_status_label.text = status
	log_output.clear()
	progress_container.visible = false
	progress_bar.value = 0
	progress_label.text = "0%"
	job_status_label.visible = false


func _show_error(message: String) -> void:
	_hide_all()
	error_container.visible = true
	error_label.text = message
	error_label.add_theme_color_override("font_color", Color.RED)


func _show_error_inline(message: String) -> void:
	error_container.visible = true
	error_label.text = message
	error_label.add_theme_color_override("font_color", Color.RED)
