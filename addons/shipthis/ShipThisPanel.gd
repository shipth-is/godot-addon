@tool
extends VBoxContainer

const Config = preload("res://addons/shipthis/lib/config.gd")
const Api = preload("res://addons/shipthis/lib/api.gd")
const AddonContext = preload("res://addons/shipthis/lib/addon_context.gd")
const AuthConfig = preload("res://addons/shipthis/models/auth_config.gd")
const SelfWithJWT = preload("res://addons/shipthis/models/self_with_jwt.gd")
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
@onready var header_container: VBoxContainer = $AuthenticatedContainer/HeaderContainer
@onready var welcome_label: Label = $AuthenticatedContainer/HeaderContainer/WelcomeLabel
@onready var status_view = $AuthenticatedContainer/StatusView
@onready var ship_runner = $AuthenticatedContainer/ShipRunner

@onready var wizard_container: MarginContainer = $WizardContainer
@onready var status_label: Label = $StatusLabel

# Dependencies
var config: Config = null
var api: Api = null
var _context: AddonContext = null

# State
var current_email: String = ""
var current_wizard: Control = null


func _ready() -> void:
	send_code_button.pressed.connect(_on_send_code_pressed)
	verify_button.pressed.connect(_on_verify_pressed)
	back_button.pressed.connect(_on_back_pressed)
	ship_runner.ship_completed.connect(_on_ship_completed)
	ship_runner.ship_failed.connect(_on_ship_failed)


func initialize(context: AddonContext) -> void:
	_context = context
	config = context.config
	api = context.api
	var auth_config := config.get_auth_config(api)
	ship_runner.initialize(context)
	ship_runner.set_show_ship_button(false)
	status_view.initialize(context)
	status_view.configure_android_pressed.connect(_on_configure_android_pressed)
	status_view.ship_pressed.connect(_on_status_view_ship_pressed)

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
		status_view.refresh()
	
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


func _show_toast_or_status(message: String, is_error: bool) -> void:
	var toaster: Object = null
	if _context != null and _context.editor_interface != null and _context.editor_interface.has_method("get_editor_toaster"):
		toaster = _context.editor_interface.get_editor_toaster()
	if toaster != null and toaster.has_method("push_toast"):
		var severity := 2 if is_error else 0  # SEVERITY_ERROR = 2, SEVERITY_INFO = 0
		toaster.push_toast(message, severity, "")
		_clear_status()
	else:
		_set_status(message, is_error)


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


func _on_ship_completed(_job) -> void:
	ship_runner.visible = false
	status_view.visible = true
	header_container.visible = true
	_show_toast_or_status("Build completed successfully.", false)


func _on_ship_failed(_message: String) -> void:
	ship_runner.visible = false
	status_view.visible = true
	header_container.visible = true
	_show_toast_or_status("Build failed.", true)


func _on_configure_android_pressed() -> void:
	_show_wizard()


func _show_wizard() -> void:
	# Hide main views
	email_container.visible = false
	code_container.visible = false
	authenticated_container.visible = false
	
	_clear_status()
	
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
	current_wizard.initialize(_context)


func _hide_wizard() -> void:
	# Clean up wizard
	if current_wizard != null:
		current_wizard.queue_free()
		current_wizard = null
	
	wizard_container.visible = false
	
	# Show authenticated view
	authenticated_container.visible = true


func _on_status_view_ship_pressed(platform: String) -> void:
	header_container.visible = false
	status_view.visible = false
	ship_runner.visible = true
	ship_runner.ship({ "platform": platform })


func _on_wizard_completed() -> void:
	_hide_wizard()
	status_view.refresh()
	_show_toast_or_status("Android configuration completed!", false)


func _on_wizard_cancelled() -> void:
	_hide_wizard()
	status_view.refresh()
