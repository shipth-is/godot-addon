@tool
extends VBoxContainer

## Step 4: Create Service Account Key
## Checks org policy, triggers service account setup, and monitors progress
## via WebSocket + polling.

signal step_completed

const Config = preload("res://addons/shipthis/lib/config.gd")
const Api = preload("res://addons/shipthis/lib/api.gd")
const SocketIOScript = preload("res://addons/shipthis/third_party/godot-socketio/socketio.gd")

var api: Api = null
var config: Config = null
var project_id: String = ""

# State
var _setup_started: bool = false
var _prev_status: String = "unknown"

# WebSocket state
var _socket = null
var _event_pattern: String = ""
var _is_watching: bool = false

# Polling timer
var _poll_timer: Timer = null

# Node references
@onready var loading_label: Label = $LoadingLabel
@onready var content_container: VBoxContainer = $ContentContainer
@onready var status_message: Label = $ContentContainer/StatusMessage
@onready var progress_container: VBoxContainer = $ContentContainer/ProgressContainer
@onready var progress_bar: ProgressBar = $ContentContainer/ProgressContainer/ProgressBar
@onready var progress_label: Label = $ContentContainer/ProgressContainer/ProgressLabel
@onready var status_table: VBoxContainer = $ContentContainer/StatusTable
@onready var row_signed_in: RichTextLabel = $ContentContainer/StatusTable/RowSignedIn
@onready var row_project_created: RichTextLabel = $ContentContainer/StatusTable/RowProjectCreated/Label
@onready var row_project_created_link: LinkButton = $ContentContainer/StatusTable/RowProjectCreated/Link
@onready var row_service_account: RichTextLabel = $ContentContainer/StatusTable/RowServiceAccount/Label
@onready var row_service_account_link: LinkButton = $ContentContainer/StatusTable/RowServiceAccount/Link
@onready var row_key_created: RichTextLabel = $ContentContainer/StatusTable/RowKeyCreated/Label
@onready var row_key_created_link: LinkButton = $ContentContainer/StatusTable/RowKeyCreated/Link
@onready var row_key_uploaded: RichTextLabel = $ContentContainer/StatusTable/RowKeyUploaded/Label
@onready var row_key_uploaded_link: LinkButton = $ContentContainer/StatusTable/RowKeyUploaded/Link
@onready var row_api_enabled: RichTextLabel = $ContentContainer/StatusTable/RowApiEnabled/Label
@onready var row_api_enabled_link: LinkButton = $ContentContainer/StatusTable/RowApiEnabled/Link
@onready var policy_container: VBoxContainer = $PolicyContainer
@onready var policy_notice: RichTextLabel = $PolicyContainer/PolicyNotice
@onready var revoke_button: Button = $PolicyContainer/RevokeButton
@onready var error_label: Label = $ErrorLabel


func _ready() -> void:
	revoke_button.pressed.connect(_on_revoke_pressed)
	policy_notice.meta_clicked.connect(_on_meta_clicked)
	row_project_created_link.pressed.connect(_on_view_in_cloud_pressed.bind(row_project_created_link))
	row_service_account_link.pressed.connect(_on_view_in_cloud_pressed.bind(row_service_account_link))
	row_key_created_link.pressed.connect(_on_view_in_cloud_pressed.bind(row_key_created_link))
	row_key_uploaded_link.pressed.connect(_on_view_in_cloud_pressed.bind(row_key_uploaded_link))
	row_api_enabled_link.pressed.connect(_on_view_in_cloud_pressed.bind(row_api_enabled_link))


func _on_view_in_cloud_pressed(link_btn: LinkButton) -> void:
	if link_btn.uri != "":
		OS.shell_open(link_btn.uri)


func _exit_tree() -> void:
	_stop_watching()
	_stop_polling()


func initialize(api_ref: Api, config_ref: Config) -> void:
	api = api_ref
	config = config_ref

	var project_config = config.get_project_config()
	project_id = project_config.project_id

	await _check_google_status()


func _on_meta_clicked(meta: Variant) -> void:
	OS.shell_open(str(meta))


# --- Google status / policy check ---

func _check_google_status() -> void:
	_set_loading("Checking Google account status...")

	var response = await api.get_google_status()

	if not response.is_success:
		_show_error("Failed to check Google status: %s" % response.error)
		return

	var needs_policy_change = response.data.get("needsPolicyChange", false)

	if needs_policy_change:
		_show_policy_notice(response.data)
	else:
		await _start_setup()


func _show_policy_notice(google_status: Dictionary) -> void:
	var org_name = google_status.get("orgName", "Unknown")
	var org_resource = google_status.get("orgResourceName", "Unknown")
	var org_created = google_status.get("orgCreatedAt", "Unknown")

	var docs_url = "https://cloud.google.com/resource-manager/docs/organization-policy/restricting-service-accounts"

	var bbcode = "[b]Google Organization Policy Change Needed[/b]\n\n" \
		+ "Organization: %s\n" % org_name \
		+ "Resource: %s\n" % org_resource \
		+ "Created: %s\n\n" % str(org_created) \
		+ "Before ShipThis can create a Service Account API key for your game, " \
		+ "your Google Organization Policy must allow Service Account key creation. " \
		+ "This is a security measure on some Google accounts.\n\n" \
		+ "If your organization was created on or after May 3, 2024, this policy is enforced by default.\n\n" \
		+ "Learn more: [url=%s]Google Cloud docs[/url]\n\n" % docs_url \
		+ "Click the button below to let ShipThis change the policy for you."
	policy_notice.text = bbcode

	loading_label.visible = false
	content_container.visible = false
	policy_container.visible = true
	error_label.visible = false


func _on_revoke_pressed() -> void:
	revoke_button.disabled = true
	_set_loading("Updating organization policy...")

	var response = await api.revoke_google_org_policy()

	if not response.is_success:
		_show_error("Failed to revoke policy: %s" % response.error)
		revoke_button.disabled = false
		return

	# Re-check Google status after policy change
	await _check_google_status()


# --- Setup process ---

func _start_setup() -> void:
	if _setup_started:
		return
	_setup_started = true

	_set_loading("Starting service account setup...")

	var response = await api.start_service_account_setup(project_id)

	if not response.is_success:
		_show_error("Failed to start setup: %s" % response.error)
		_setup_started = false
		return

	# Show progress UI
	loading_label.visible = false
	content_container.visible = true
	policy_container.visible = false
	progress_container.visible = true
	status_table.visible = true
	error_label.visible = false

	# Handle initial status from start response
	if response.data is Dictionary:
		_handle_setup_status(response.data)

	# Start monitoring
	_start_watching()
	_start_polling()


func _handle_setup_status(data: Dictionary) -> void:
	var status = data.get("status", "unknown")
	var progress = data.get("progress", 0.0)

	# Update progress bar
	progress_bar.value = progress * 100.0
	progress_label.text = "%.0f%%" % (progress * 100.0)

	# Update status table rows
	_update_status_row(row_signed_in, "Signed In", data.get("hasSignedIn", false))

	var gcp_project_id = data.get("gcpProjectId", "")
	var sa_unique_id = data.get("serviceAccountUniqueId", "")

	if data.get("hasProject", false) and gcp_project_id != "" and gcp_project_id != null:
		var url = "https://console.cloud.google.com/home/dashboard?project=%s" % gcp_project_id
		_update_status_row(row_project_created, "Project Created", true, url, "View in Google Cloud", row_project_created_link)
	else:
		_update_status_row(row_project_created, "Project Created", data.get("hasProject", false), "", "", row_project_created_link)

	if data.get("hasServiceAccount", false) and sa_unique_id != "" and sa_unique_id != null and gcp_project_id != "" and gcp_project_id != null:
		var url = "https://console.cloud.google.com/iam-admin/serviceaccounts/details/%s?project=%s" % [sa_unique_id, gcp_project_id]
		_update_status_row(row_service_account, "Service Account Created", true, url, "View in Google Cloud", row_service_account_link)
	else:
		_update_status_row(row_service_account, "Service Account Created", data.get("hasServiceAccount", false), "", "", row_service_account_link)

	if data.get("hasKey", false) and sa_unique_id != "" and sa_unique_id != null and gcp_project_id != "" and gcp_project_id != null:
		var url = "https://console.cloud.google.com/iam-admin/serviceaccounts/details/%s/keys?project=%s" % [sa_unique_id, gcp_project_id]
		_update_status_row(row_key_created, "Key Created", true, url, "View in Google Cloud", row_key_created_link)
	else:
		_update_status_row(row_key_created, "Key Created", data.get("hasKey", false), "", "", row_key_created_link)

	_update_status_row(row_key_uploaded, "Key Uploaded", data.get("hasUploadedKey", false), "", "", row_key_uploaded_link)

	if data.get("hasEnabledApi", false) and gcp_project_id != "" and gcp_project_id != null:
		var url = "https://console.cloud.google.com/apis/dashboard?project=%s" % gcp_project_id
		_update_status_row(row_api_enabled, "API Enabled", true, url, "View in Google Cloud", row_api_enabled_link)
	else:
		_update_status_row(row_api_enabled, "API Enabled", data.get("hasEnabledApi", false), "", "", row_api_enabled_link)

	# Check terminal states only after setup was previously running/queued
	if _prev_status in ["queued", "running"]:
		if status == "complete":
			_stop_watching()
			_stop_polling()
			step_completed.emit()
			return
		if status == "error":
			_stop_watching()
			_stop_polling()
			var error_msg = data.get("errorMessage", "An unknown error occurred during setup")
			_show_error(error_msg)
			return

	_prev_status = status


func _update_status_row(row: RichTextLabel, label: String, is_done: bool, link_url: String = "", link_text: String = "", link_button: LinkButton = null) -> void:
	var icon = "[x]" if is_done else "[ ]"
	row.text = "%s %s" % [icon, label]
	if link_button != null:
		if is_done and link_url != "":
			link_button.visible = true
			link_button.uri = link_url
			link_button.text = link_text
		else:
			link_button.visible = false


# --- WebSocket monitoring ---

func _start_watching() -> void:
	if _is_watching:
		return

	_event_pattern = "project.%s:android-setup-status" % project_id

	_socket = SocketIOScript.new()
	_socket.autoconnect = false

	var base_url = api.client.ws_url
	if base_url.begins_with("wss://"):
		base_url = base_url.replace("wss://", "https://")
	elif base_url.begins_with("ws://"):
		base_url = base_url.replace("ws://", "http://")

	_socket.base_url = base_url
	add_child(_socket)

	_socket.socket_connected.connect(_on_socket_connected)
	_socket.socket_disconnected.connect(_on_socket_disconnected)
	_socket.namespace_connection_error.connect(_on_socket_error)
	_socket.event_received.connect(_on_event_received)

	print("[Service Account] Connecting to WebSocket...")
	_socket.connect_socket({"token": api.client.token})
	_is_watching = true


func _stop_watching() -> void:
	if _socket != null:
		_socket.disconnect_socket()
		_socket.queue_free()
		_socket = null
	_is_watching = false


func _on_socket_connected(ns: String) -> void:
	print("[Service Account] WebSocket connected to namespace: %s" % ns)
	print("[Service Account] Watching for event: %s" % _event_pattern)


func _on_socket_disconnected() -> void:
	print("[Service Account] WebSocket disconnected")


func _on_socket_error(ns: String, data: Variant) -> void:
	print("[Service Account] WebSocket error on %s: %s" % [ns, str(data)])


func _on_event_received(event: String, data: Variant, _ns: String) -> void:
	if event != _event_pattern:
		return

	var event_data = data
	if data is Array and data.size() > 0:
		event_data = data[0]

	if not event_data is Dictionary:
		return

	print("[Service Account] Setup status update via WebSocket")
	_handle_setup_status(event_data)


# --- Polling fallback ---

func _start_polling() -> void:
	if _poll_timer != null:
		return

	_poll_timer = Timer.new()
	_poll_timer.wait_time = 5.0
	_poll_timer.autostart = true
	_poll_timer.timeout.connect(_on_poll_timeout)
	add_child(_poll_timer)


func _stop_polling() -> void:
	if _poll_timer != null:
		_poll_timer.stop()
		_poll_timer.queue_free()
		_poll_timer = null


func _on_poll_timeout() -> void:
	var response = await api.get_service_account_setup_status(project_id)
	if response.is_success and response.data is Dictionary:
		_handle_setup_status(response.data)


# --- UI helpers ---

func _set_loading(message: String) -> void:
	loading_label.text = message
	loading_label.visible = true
	content_container.visible = false
	policy_container.visible = false
	error_label.visible = false


func _show_error(message: String) -> void:
	error_label.text = message
	error_label.add_theme_color_override("font_color", Color.RED)
	error_label.visible = true
	loading_label.visible = false
