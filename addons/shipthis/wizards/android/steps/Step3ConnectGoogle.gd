@tool
extends VBoxContainer

## Step 3: Connect with Google
## Opens OAuth flow in browser and watches WebSocket for authentication status.

signal step_completed

const Config = preload("res://addons/shipthis/lib/config.gd")
const Api = preload("res://addons/shipthis/lib/api.gd")
const AddonContext = preload("res://addons/shipthis/lib/addon_context.gd")
const SocketIOScript = preload("res://addons/shipthis/third_party/godot-socketio/socketio.gd")

var api: Api = null
var config: Config = null
var project_id: String = ""

# WebSocket state
var _socket = null
var _event_pattern: String = ""
var _is_watching: bool = false

# Node references
@onready var loading_label: Label = $LoadingLabel
@onready var content_container: VBoxContainer = $ContentContainer
@onready var privacy_notice: RichTextLabel = $ContentContainer/PrivacyNotice
@onready var connect_button: Button = $ContentContainer/ConnectButton
@onready var url_label: RichTextLabel = $ContentContainer/UrlLabel
@onready var status_label: Label = $StatusLabel


func _ready() -> void:
	connect_button.pressed.connect(_on_connect_pressed)
	privacy_notice.meta_clicked.connect(_on_meta_clicked)
	url_label.meta_clicked.connect(_on_meta_clicked)


func _exit_tree() -> void:
	_stop_watching()


func initialize(context: AddonContext) -> void:
	api = context.api
	config = context.config
	
	var project_config = config.get_project_config()
	project_id = project_config.project_id
	
	_populate_privacy_notice()
	_show_content()
	_start_watching()


func _populate_privacy_notice() -> void:
	var privacy_url = api.client.web_url + "privacy"
	var bbcode = "[b]Connect ShipThis with Google[/b]\n\n" \
		+ "By connecting your Google account, ShipThis will generate a short-lived " \
		+ "access token for the Google APIs. With this token, ShipThis will be able to:\n\n" \
		+ "- Set up a Google Cloud project, Service Account, and API Key in your Google account.\n" \
		+ "- Enable the required APIs for uploading new builds to Google Play.\n" \
		+ "- Securely store your Service Account API Key in the ShipThis backend for deploying new game builds.\n" \
		+ "- Invite the Service Account to your Google Play account.\n\n" \
		+ "To learn more, review our Privacy Policy: [url=%s]%s[/url]" % [privacy_url, privacy_url]
	privacy_notice.text = bbcode


func _on_meta_clicked(meta: Variant) -> void:
	OS.shell_open(str(meta))


func _show_content() -> void:
	loading_label.visible = false
	content_container.visible = true
	_clear_status()


func _set_loading(message: String) -> void:
	loading_label.text = message
	loading_label.visible = true
	content_container.visible = false
	connect_button.disabled = true


func _show_status(message: String, is_error: bool = false) -> void:
	status_label.text = message
	if is_error:
		status_label.add_theme_color_override("font_color", Color.RED)
	else:
		status_label.remove_theme_color_override("font_color")
	status_label.visible = true


func _clear_status() -> void:
	status_label.text = ""
	status_label.visible = false


func _on_connect_pressed() -> void:
	_clear_status()
	await _open_google_auth()


func _open_google_auth() -> void:
	_set_loading("Getting authentication URL...")
	
	# Build redirect URI
	var redirect_uri = api.client.web_url + "google/redirect/"
	
	# Step 1: Get Google OAuth URL
	var auth_response = await api.get_google_auth_url(project_id, redirect_uri)
	
	if not auth_response.is_success:
		_show_content()
		_show_status("Failed to get auth URL: %s" % auth_response.error, true)
		return
	
	var google_url = auth_response.data.get("url", "")
	if google_url == "":
		_show_content()
		_show_status("No OAuth URL returned", true)
		return
	
	# Step 2: Wrap with login link for auth
	_set_loading("Preparing secure link...")
	var link_response = await api.get_login_link(google_url)
	
	if not link_response.is_success:
		_show_content()
		_show_status("Failed to create login link: %s" % link_response.error, true)
		return
	
	var final_url = link_response.data.get("url", "")
	if final_url == "":
		_show_content()
		_show_status("No login URL returned", true)
		return
	
	# Step 3: Open in browser
	print("[Google Auth] Opening browser: %s" % final_url)
	OS.shell_open(final_url)
	
	_show_content()
	url_label.text = "Authentication URL: [url=%s]%s[/url]" % [final_url, final_url]
	url_label.visible = true
	_show_status("Waiting for Google authentication...")
	connect_button.text = "Open Google Auth Again"


func _start_watching() -> void:
	if _is_watching:
		return
	
	_event_pattern = "project.%s:google-status" % project_id
	
	# Create socket
	_socket = SocketIOScript.new()
	_socket.autoconnect = false
	
	# Convert wss:// to https://
	var base_url = api.client.ws_url
	if base_url.begins_with("wss://"):
		base_url = base_url.replace("wss://", "https://")
	elif base_url.begins_with("ws://"):
		base_url = base_url.replace("ws://", "http://")
	
	_socket.base_url = base_url
	add_child(_socket)
	
	# Connect signals
	_socket.socket_connected.connect(_on_socket_connected)
	_socket.socket_disconnected.connect(_on_socket_disconnected)
	_socket.namespace_connection_error.connect(_on_socket_error)
	_socket.event_received.connect(_on_event_received)
	
	# Connect with auth
	print("[Google Auth] Connecting to WebSocket...")
	_socket.connect_socket({"token": api.client.token})
	_is_watching = true


func _stop_watching() -> void:
	if _socket != null:
		_socket.disconnect_socket()
		_socket.queue_free()
		_socket = null
	_is_watching = false


func _on_socket_connected(ns: String) -> void:
	print("[Google Auth] WebSocket connected to namespace: %s" % ns)
	print("[Google Auth] Watching for event: %s" % _event_pattern)


func _on_socket_disconnected() -> void:
	print("[Google Auth] WebSocket disconnected")


func _on_socket_error(ns: String, data: Variant) -> void:
	print("[Google Auth] WebSocket error on %s: %s" % [ns, str(data)])


func _on_event_received(event: String, data: Variant, _ns: String) -> void:
	print("[Google Auth] Event received: %s" % event)
	
	if event != _event_pattern:
		return
	
	# Extract data from array if needed (Socket.IO sends [data])
	var event_data = data
	if data is Array and data.size() > 0:
		event_data = data[0]
	
	if not event_data is Dictionary:
		print("[Google Auth] Unexpected event data type")
		return
	
	print("[Google Auth] Google status update: %s" % str(event_data))
	
	var is_authenticated = event_data.get("isAuthenticated", false)
	if is_authenticated:
		print("[Google Auth] Authentication successful!")
		_stop_watching()
		step_completed.emit()
