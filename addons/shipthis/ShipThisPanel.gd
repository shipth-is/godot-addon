@tool
extends VBoxContainer

const Config = preload("res://addons/shipthis/lib/config.gd")
const Api = preload("res://addons/shipthis/lib/api.gd")
const Ship = preload("res://addons/shipthis/lib/ship.gd")
const JobSocket = preload("res://addons/shipthis/lib/job_socket.gd")
const AuthConfig = preload("res://addons/shipthis/models/auth_config.gd")
const SelfWithJWT = preload("res://addons/shipthis/models/self_with_jwt.gd")
const Job = preload("res://addons/shipthis/models/job.gd")
const LogOutputScript = preload("res://addons/shipthis/components/LogOutput.gd")
const AndroidWizardScene = preload("res://addons/shipthis/wizards/android/AndroidWizard.tscn")

enum View { EMAIL, CODE, AUTHENTICATED }

# Node references
@onready var email_container: VBoxContainer = $EmailContainer
@onready var email_input: LineEdit = $EmailContainer/EmailInput
@onready var send_code_button: Button = $EmailContainer/SendCodeButton

@onready var code_container: VBoxContainer = $CodeContainer
@onready var code_input: LineEdit = $CodeContainer/CodeInput
@onready var verify_button: Button = $CodeContainer/VerifyButton
@onready var back_button: Button = $CodeContainer/BackButton

@onready var authenticated_container: VBoxContainer = $AuthenticatedContainer
@onready var welcome_label: Label = $AuthenticatedContainer/WelcomeLabel
@onready var ship_button: Button = $AuthenticatedContainer/ActionsContainer/ShipButton
@onready var configure_android_button: Button = $AuthenticatedContainer/ActionsContainer/ConfigureAndroidButton
@onready var connection_status: Label = $AuthenticatedContainer/ActionsContainer/ConnectionStatus
@onready var log_output: LogOutputScript = $AuthenticatedContainer/LogOutput
@onready var copy_output_button: Button = $AuthenticatedContainer/CopyOutputButton

@onready var wizard_container: MarginContainer = $WizardContainer
@onready var status_label: Label = $StatusLabel

# Dependencies
var config: Config = null
var api: Api = null

# State
var current_email: String = ""
var job_socket: JobSocket = null
var current_wizard: Control = null


func _ready() -> void:
	send_code_button.pressed.connect(_on_send_code_pressed)
	verify_button.pressed.connect(_on_verify_pressed)
	back_button.pressed.connect(_on_back_pressed)
	ship_button.pressed.connect(_on_ship_pressed)
	copy_output_button.pressed.connect(_on_copy_output_pressed)
	configure_android_button.pressed.connect(_on_configure_android_pressed)


func initialize(new_config: Config, new_api: Api) -> void:
	config = new_config
	api = new_api
	
	var auth_config := config.get_auth_config(api)
	
	if auth_config != null and auth_config.ship_this_user != null:
		_show_view(View.AUTHENTICATED, auth_config.ship_this_user)
	else:
		_show_view(View.EMAIL)


func _show_view(view: View, user: SelfWithJWT = null) -> void:
	email_container.visible = (view == View.EMAIL)
	code_container.visible = (view == View.CODE)
	authenticated_container.visible = (view == View.AUTHENTICATED)
	wizard_container.visible = false
	
	if view == View.AUTHENTICATED and user != null:
		welcome_label.text = "Welcome, %s!" % user.email
		# Connect WebSocket when entering authenticated view
		_connect_websocket()
	
	_clear_status()


func _set_status(message: String, is_error: bool = false) -> void:
	status_label.text = message
	status_label.visible = true
	if is_error:
		status_label.add_theme_color_override("font_color", Color.RED)
	else:
		status_label.remove_theme_color_override("font_color")


func _clear_status() -> void:
	status_label.text = ""
	status_label.visible = false


func _set_loading(is_loading: bool) -> void:
	send_code_button.disabled = is_loading
	verify_button.disabled = is_loading
	back_button.disabled = is_loading


func _on_send_code_pressed() -> void:
	var email: String = email_input.text.strip_edges()
	
	if email == "":
		_set_status("Please enter your email address.", true)
		return
	
	if not email.contains("@"):
		_set_status("Please enter a valid email address.", true)
		return
	
	current_email = email
	_set_loading(true)
	_set_status("Sending code...")
	
	var response: Dictionary = await api.post("/auth/email/send", {"email": email})
	
	_set_loading(false)
	
	if response.is_success:
		_show_view(View.CODE)
		_set_status("Check your email for the code.")
	else:
		_set_status("Failed to send code: %s" % response.error, true)


func _on_verify_pressed() -> void:
	var otp: String = code_input.text.strip_edges()
	
	if otp == "":
		_set_status("Please enter the code from your email.", true)
		return
	
	_set_loading(true)
	_set_status("Verifying...")
	
	var response: Dictionary = await api.post("/auth/email/verify", {
		"email": current_email,
		"otp": otp,
		"source": "shipthis-godot-addon"
	})
	
	_set_loading(false)
	
	if response.is_success:
		var user = SelfWithJWT.from_dict(response.data)
		# Save auth config
		var auth_config = AuthConfig.new()
		auth_config.ship_this_user = user
		var save_error = config.set_auth_config(auth_config)
		
		if save_error != OK:
			_set_status("Authenticated but failed to save credentials.", true)
			return
		
		# Set token on API for future requests
		api.set_token(user.jwt)
		
		_show_view(View.AUTHENTICATED, user)
	else:
		_set_status("Verification failed: %s" % response.error, true)


func _on_back_pressed() -> void:
	code_input.text = ""
	_show_view(View.EMAIL)


func _on_ship_pressed() -> void:
	log_output.clear()
	ship_button.disabled = true
	
	var ship := Ship.new()
	var result = await ship.ship(config, api, log_output.log_message, get_tree())
	
	if result.error == OK and result.job != null:
		# Subscribe to job events (WebSocket already connected)
		var project_config = config.get_project_config()
		if job_socket != null:
			job_socket.subscribe_to_job(project_config.project_id, result.job.id)
	else:
		ship_button.disabled = false


func _connect_websocket() -> void:
	# Clean up existing socket if any
	if job_socket != null:
		job_socket.disconnect_socket()
		job_socket.queue_free()
	
	job_socket = JobSocket.new()
	add_child(job_socket)
	
	# Set up logger for debug output
	job_socket.set_logger(log_output.log_message)
	
	# Connect signals
	job_socket.job_updated.connect(_on_job_updated)
	job_socket.log_received.connect(_on_log_received)
	job_socket.connection_status_changed.connect(_on_connection_status_changed)
	
	# Connect to server (but don't subscribe to any job yet)
	job_socket.connect_to_server(api.client.ws_url, api.client.token)


func _on_job_updated(job) -> void:
	log_output.log_message("[JOB] Status changed to: %s" % job.status_name())


func _on_log_received(entry) -> void:
	log_output.log_entry(entry)


func _on_connection_status_changed(connected: bool, message: String) -> void:
	connection_status.visible = true
	if connected:
		connection_status.text = "● Connected"
		connection_status.add_theme_color_override("font_color", Color.GREEN)
	elif message == "Connecting...":
		connection_status.text = "● Connecting..."
		connection_status.add_theme_color_override("font_color", Color.YELLOW)
	else:
		connection_status.text = "● Disconnected"
		connection_status.add_theme_color_override("font_color", Color.RED)


func _on_copy_output_pressed() -> void:
	DisplayServer.clipboard_set(log_output.get_log_text())


func _on_configure_android_pressed() -> void:
	_show_wizard()


func _show_wizard() -> void:
	# Hide main views
	email_container.visible = false
	code_container.visible = false
	authenticated_container.visible = false
	
	# Clean up existing wizard if any
	if current_wizard != null:
		current_wizard.queue_free()
		current_wizard = null
	
	# Create and show wizard
	current_wizard = AndroidWizardScene.instantiate()
	wizard_container.add_child(current_wizard)
	wizard_container.visible = true
	
	# Connect wizard signals
	current_wizard.wizard_completed.connect(_on_wizard_completed)
	current_wizard.wizard_cancelled.connect(_on_wizard_cancelled)
	
	# Initialize wizard
	current_wizard.initialize(config, api)


func _hide_wizard() -> void:
	# Clean up wizard
	if current_wizard != null:
		current_wizard.queue_free()
		current_wizard = null
	
	wizard_container.visible = false
	
	# Show authenticated view
	authenticated_container.visible = true


func _on_wizard_completed() -> void:
	_hide_wizard()
	log_output.log_message("Android configuration completed!")


func _on_wizard_cancelled() -> void:
	_hide_wizard()
