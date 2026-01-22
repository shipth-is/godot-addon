@tool
extends VBoxContainer

const AuthConfig = preload("res://addons/shipthis/models/auth_config.gd")
const SelfWithJWT = preload("res://addons/shipthis/models/self_with_jwt.gd")

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

@onready var status_label: Label = $StatusLabel

# Dependencies
var config = null
var api = null

# State
var current_email: String = ""


func _ready() -> void:
	send_code_button.pressed.connect(_on_send_code_pressed)
	verify_button.pressed.connect(_on_verify_pressed)
	back_button.pressed.connect(_on_back_pressed)


func initialize(new_config, new_api) -> void:
	config = new_config
	api = new_api
	
	# Check if already authenticated
	var auth_config = config.get_auth_config(api)
	
	if auth_config != null and auth_config.ship_this_user != null:
		_show_authenticated(auth_config.ship_this_user)
	else:
		_show_email_form()


func _show_email_form() -> void:
	email_container.visible = true
	code_container.visible = false
	authenticated_container.visible = false
	_clear_status()


func _show_code_form() -> void:
	email_container.visible = false
	code_container.visible = true
	authenticated_container.visible = false
	_clear_status()


func _show_authenticated(user: SelfWithJWT) -> void:
	email_container.visible = false
	code_container.visible = false
	authenticated_container.visible = true
	welcome_label.text = "Welcome, %s!" % user.email
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
		_show_code_form()
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
		
		_show_authenticated(user)
	else:
		_set_status("Verification failed: %s" % response.error, true)


func _on_back_pressed() -> void:
	code_input.text = ""
	_show_email_form()
