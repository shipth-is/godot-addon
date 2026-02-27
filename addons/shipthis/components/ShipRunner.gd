@tool
extends VBoxContainer

## Shared shipping component: runs Ship, monitors job via JobSocket, and updates
## status, progress, log, job status, and optional error/retry. Used by Panel and Step 5.

signal ship_completed(job)
signal ship_failed(message: String)
signal retry_requested

const Config = preload("res://addons/shipthis/lib/config.gd")
const Api = preload("res://addons/shipthis/lib/api.gd")
const AddonContext = preload("res://addons/shipthis/lib/addon_context.gd")
const Ship = preload("res://addons/shipthis/lib/ship.gd")
const JobSocket = preload("res://addons/shipthis/lib/job_socket.gd")
const JobModel = preload("res://addons/shipthis/models/job.gd")
const LogOutputScript = preload("res://addons/shipthis/components/LogOutput.gd")

var config: Config = null
var api: Api = null

var _job_socket: JobSocket = null
var _is_shipping: bool = false

# Node references (set in _ready or by parent when scene is instanced)
@onready var status_label: Label = $StatusRow/StatusLabel
@onready var view_job_link: LinkButton = $StatusRow/ViewJobLink
@onready var ship_button: Button = $ShipButton
@onready var progress_container: HBoxContainer = $RunningSection/ProgressContainer
@onready var progress_bar: ProgressBar = $RunningSection/ProgressContainer/ProgressBar
@onready var progress_label: Label = $RunningSection/ProgressContainer/ProgressLabel
@onready var job_status_row: HBoxContainer = $RunningSection/JobStatusRow
@onready var job_status_label: Label = $RunningSection/JobStatusRow/JobStatusLabel
@onready var connection_status_label: Label = $RunningSection/JobStatusRow/ConnectionStatus
@onready var log_output: LogOutputScript = $LogContainer/LogOutput
@onready var copy_output_button: Button = $LogContainer/CopyOutputButton
@onready var error_container: VBoxContainer = $ErrorContainer
@onready var error_label: Label = $ErrorContainer/ErrorLabel
@onready var retry_button: Button = $ErrorContainer/RetryButton

var _current_job_id: String = ""


func _ready() -> void:
	if ship_button != null:
		ship_button.pressed.connect(_on_ship_button_pressed)
	if retry_button != null:
		retry_button.pressed.connect(_on_retry_pressed)
	if copy_output_button != null:
		copy_output_button.pressed.connect(_on_copy_output_pressed)
	if view_job_link != null:
		view_job_link.pressed.connect(_on_view_job_pressed)


func _exit_tree() -> void:
	_cleanup_job_socket()


func initialize(context: AddonContext) -> void:
	config = context.config
	api = context.api
	var editor_theme: Theme = context.get_editor_theme()
	if copy_output_button != null and editor_theme != null:
		copy_output_button.theme = editor_theme
		copy_output_button.icon = editor_theme.get_icon("ActionCopy", "EditorIcons")
		copy_output_button.text = ""


func set_show_ship_button(show_button: bool) -> void:
	if ship_button != null:
		ship_button.visible = show_button


## Start the ship flow. Options are passed to Ship.ship (e.g. {} or {platform: "ANDROID", skipPublish: true}).
func ship(options: Dictionary = {}) -> void:
	if _is_shipping:
		return
	_is_shipping = true

	_clear_ui()
	error_container.visible = false
	status_label.text = "Preparing…"
	status_label.visible = true
	if ship_button != null:
		ship_button.disabled = true

	var ship_instance = Ship.new()
	var result = await ship_instance.ship(config, api, _ship_logger, get_tree(), options)

	if result.error != OK:
		_is_shipping = false
		if ship_button != null:
			ship_button.disabled = false
		if result.job == null:
			_show_error("Build failed. Please check the log output above and try again.")
			ship_failed.emit("Build failed.")
		return

	if result.job != null:
		_start_job_monitoring(result.job)
	else:
		_is_shipping = false
		if ship_button != null:
			ship_button.disabled = false
		_show_error("No job was created. Please check your game configuration.")
		ship_failed.emit("No job was created.")


func get_log_text() -> String:
	if log_output != null:
		return log_output.get_log_text()
	return ""


## Monitor an existing job (e.g. when Step 5 finds a job already in progress). Emits ship_completed/ship_failed like ship().
func monitor_job(job) -> void:
	if _is_shipping:
		return
	_is_shipping = true
	_clear_ui()
	error_container.visible = false
	status_label.visible = true
	if ship_button != null:
		ship_button.disabled = true
	_start_job_monitoring(job)


func _ship_logger(message: String) -> void:
	if log_output != null:
		log_output.log_message(message)


func _start_job_monitoring(job) -> void:
	_cleanup_job_socket()

	_current_job_id = job.id
	var project_config = config.get_project_config()
	var short_id: String = project_config.project_id.substr(0, 8) if project_config.project_id.length() >= 8 else project_config.project_id
	status_label.text = "Job %s is in progress." % short_id
	if job_status_label != null:
		job_status_label.text = "Job status: %s" % job.status_name()
	if view_job_link != null:
		view_job_link.visible = true
		view_job_link.uri = _job_url_for(short_id)

	_job_socket = JobSocket.new()
	add_child(_job_socket)

	_job_socket.job_updated.connect(_on_job_updated)
	_job_socket.log_received.connect(_on_log_received)
	_job_socket.connection_status_changed.connect(_on_connection_status_changed)

	_job_socket.connect_to_server(api.client.ws_url, api.client.token)
	_job_socket.subscribe_to_job(project_config.project_id, job.id)

	if progress_container != null:
		progress_container.visible = true
	if job_status_row != null:
		job_status_row.visible = true


func _on_job_updated(job) -> void:
	if job_status_label != null:
		job_status_label.text = "Job status: %s" % job.status_name()

	if job.status == JobModel.JobStatus.COMPLETED:
		_cleanup_job_socket()
		_is_shipping = false
		if ship_button != null:
			ship_button.disabled = false
		ship_completed.emit(job)
	elif job.status == JobModel.JobStatus.FAILED:
		_cleanup_job_socket()
		_is_shipping = false
		if ship_button != null:
			ship_button.disabled = false
		_show_error("Build job failed. Check the logs above for details.")
		ship_failed.emit("Build job failed.")


func _on_log_received(entry) -> void:
	if log_output != null:
		log_output.log_entry(entry)
	if entry.progress >= 0 and progress_bar != null and progress_label != null:
		progress_bar.value = entry.progress
		progress_label.text = "%d%%" % int(entry.progress)


func _cleanup_job_socket() -> void:
	if _job_socket != null:
		_job_socket.disconnect_socket()
		_job_socket.queue_free()
		_job_socket = null
	_current_job_id = ""
	if connection_status_label != null:
		connection_status_label.visible = false
	if view_job_link != null:
		view_job_link.visible = false


func _on_connection_status_changed(connected: bool, message: String) -> void:
	if connection_status_label == null:
		return
	connection_status_label.visible = true
	if connected:
		connection_status_label.text = "● Connected"
		connection_status_label.add_theme_color_override("font_color", Color.GREEN)
	elif message == "Connecting...":
		connection_status_label.text = "● Connecting..."
		connection_status_label.add_theme_color_override("font_color", Color.YELLOW)
	else:
		connection_status_label.text = "● Disconnected"
		connection_status_label.add_theme_color_override("font_color", Color.RED)


func _on_retry_pressed() -> void:
	retry_requested.emit()


func _on_ship_button_pressed() -> void:
	ship({})


func _on_copy_output_pressed() -> void:
	DisplayServer.clipboard_set(get_log_text())


func _on_view_job_pressed() -> void:
	if api == null:
		return
	var project_config = config.get_project_config()
	var short_id: String = project_config.project_id.substr(0, 8) if project_config.project_id.length() >= 8 else project_config.project_id
	var destination := "/games/%s/jobs" % short_id
	var resp = await api.get_login_link(destination)
	if resp.is_success and resp.data.has("url"):
		OS.shell_open(resp.data.url)
	else:
		OS.shell_open(api.client.web_url + destination.trim_prefix("/"))


func _job_url_for(short_id: String) -> String:
	if api == null:
		return ""
	return api.client.web_url + "games/" + short_id + "/jobs"


func _clear_ui() -> void:
	status_label.visible = true
	if connection_status_label != null:
		connection_status_label.visible = false
	if progress_container != null:
		progress_container.visible = false
	if progress_bar != null:
		progress_bar.value = 0
	if progress_label != null:
		progress_label.text = "0%"
	if job_status_row != null:
		job_status_row.visible = false
	if view_job_link != null:
		view_job_link.visible = false
	if log_output != null:
		log_output.clear()


func _show_error(message: String) -> void:
	error_container.visible = true
	error_label.text = message
	error_label.add_theme_color_override("font_color", Color.RED)
