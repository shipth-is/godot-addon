@tool
extends VBoxContainer

## Shared shipping component: runs Ship, monitors job via JobSocket, and updates
## status, progress, log, job status, and optional error/retry. Used by Panel and Step 5.

signal ship_completed(job)
signal ship_failed(message: String)
signal retry_requested

const Config = preload("res://addons/shipthis/lib/config.gd")
const Api = preload("res://addons/shipthis/lib/api.gd")
const Ship = preload("res://addons/shipthis/lib/ship.gd")
const JobSocket = preload("res://addons/shipthis/lib/job_socket.gd")
const JobModel = preload("res://addons/shipthis/models/job.gd")
const LogOutputScript = preload("res://addons/shipthis/components/LogOutput.gd")

var config: Config = null
var api: Api = null

var _job_socket: JobSocket = null
var _is_shipping: bool = false

# Node references (set in _ready or by parent when scene is instanced)
@onready var status_label: Label = $StatusLabel
@onready var ship_button: Button = $ShipButton
@onready var progress_container: HBoxContainer = $ProgressContainer
@onready var progress_bar: ProgressBar = $ProgressContainer/ProgressBar
@onready var progress_label: Label = $ProgressContainer/ProgressLabel
@onready var log_output: LogOutputScript = $LogOutput
@onready var job_status_label: Label = $JobStatusLabel
@onready var error_container: VBoxContainer = $ErrorContainer
@onready var error_label: Label = $ErrorContainer/ErrorLabel
@onready var retry_button: Button = $ErrorContainer/RetryButton
@onready var copy_output_button: Button = $CopyOutputButton


func _ready() -> void:
	if ship_button != null:
		ship_button.pressed.connect(_on_ship_button_pressed)
	if retry_button != null:
		retry_button.pressed.connect(_on_retry_pressed)
	if copy_output_button != null:
		copy_output_button.pressed.connect(_on_copy_output_pressed)


func _exit_tree() -> void:
	_cleanup_job_socket()


func initialize(config_ref: Config, api_ref: Api) -> void:
	config = config_ref
	api = api_ref


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
	status_label.text = "Preparing build..."
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
		status_label.text = "Build submitted! Monitoring job..."
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
	status_label.text = "Monitoring existing build job..."
	status_label.visible = true
	if ship_button != null:
		ship_button.disabled = true
	_start_job_monitoring(job)


func _ship_logger(message: String) -> void:
	if log_output != null:
		log_output.log_message(message)


func _start_job_monitoring(job) -> void:
	_cleanup_job_socket()

	_job_socket = JobSocket.new()
	add_child(_job_socket)

	_job_socket.job_updated.connect(_on_job_updated)
	_job_socket.log_received.connect(_on_log_received)

	var project_config = config.get_project_config()
	_job_socket.connect_to_server(api.client.ws_url, api.client.token)
	_job_socket.subscribe_to_job(project_config.project_id, job.id)

	progress_container.visible = true
	job_status_label.visible = true
	job_status_label.text = "Job status: %s" % job.status_name()


func _on_job_updated(job) -> void:
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


func _on_retry_pressed() -> void:
	retry_requested.emit()


func _on_ship_button_pressed() -> void:
	ship({})


func _on_copy_output_pressed() -> void:
	DisplayServer.clipboard_set(get_log_text())


func _clear_ui() -> void:
	status_label.visible = true
	progress_container.visible = false
	if progress_bar != null:
		progress_bar.value = 0
	if progress_label != null:
		progress_label.text = "0%"
	job_status_label.visible = false
	if log_output != null:
		log_output.clear()


func _show_error(message: String) -> void:
	error_container.visible = true
	error_label.text = message
	error_label.add_theme_color_override("font_color", Color.RED)
