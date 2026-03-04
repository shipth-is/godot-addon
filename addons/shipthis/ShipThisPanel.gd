@tool
extends VBoxContainer

const Config = preload("res://addons/shipthis/lib/config.gd")
const Api = preload("res://addons/shipthis/lib/api.gd")
const AddonContext = preload("res://addons/shipthis/lib/addon_context.gd")
const AuthConfig = preload("res://addons/shipthis/models/auth_config.gd")
const SelfWithJWT = preload("res://addons/shipthis/models/self_with_jwt.gd")
const AndroidWizardScene = preload("res://addons/shipthis/wizards/android/AndroidWizard.tscn")

const DISCORD_URL := "https://discord.gg/suUxDZhu"

enum View { EMAIL, CODE, AGREEMENT, AUTHENTICATED }

# Node references
@onready var email_container: VBoxContainer = $EmailContainer
@onready var email_input: LineEdit = $EmailContainer/EmailInput
@onready var send_code_button: Button = $EmailContainer/SendCodeButton

@onready var code_container: VBoxContainer = $CodeContainer
@onready var code_prompt_label: Label = $CodeContainer/CodePromptLabel
@onready var code_input: LineEdit = $CodeContainer/CodeInput
@onready var verify_button: Button = $CodeContainer/VerifyButton
@onready var back_link: LinkButton = $CodeContainer/BackLink

@onready var agreement_container: MarginContainer = $AgreementWrapper
@onready var agreement_check: CheckBox = $AgreementWrapper/AgreementContainer/CheckBox
@onready var agreement_continue_button: Button = $AgreementWrapper/AgreementContainer/ContinueButton
@onready var terms_link: LinkButton = $AgreementWrapper/AgreementContainer/LinksList/TermsLink
@onready var privacy_link: LinkButton = $AgreementWrapper/AgreementContainer/LinksList/PrivacyLink
@onready var dpa_link: LinkButton = $AgreementWrapper/AgreementContainer/LinksList/DpaLink
@onready var learn_more_link: LinkButton = $AgreementWrapper/AgreementContainer/FooterHBox/LearnMoreLink

@onready var authenticated_container: VBoxContainer = $AuthenticatedContainer
@onready var header_container: HBoxContainer = $AuthenticatedContainer/HeaderContainer
@onready var welcome_label: Label = $AuthenticatedContainer/HeaderContainer/WelcomeLabel
@onready var docs_link: LinkButton = $AuthenticatedContainer/HeaderContainer/LinksContainer/DocsLink
@onready var dashboard_link: LinkButton = $AuthenticatedContainer/HeaderContainer/LinksContainer/DashboardLink
@onready var discord_link: LinkButton = $AuthenticatedContainer/HeaderContainer/LinksContainer/DiscordLink
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
var _agreement_user: SelfWithJWT = null


func _ready() -> void:
	send_code_button.pressed.connect(_on_send_code_pressed)
	email_input.submitted.connect(_on_send_code_pressed)
	verify_button.pressed.connect(_on_verify_pressed)
	code_input.submitted.connect(_on_verify_pressed)
	back_link.pressed.connect(_on_back_pressed)
	agreement_continue_button.pressed.connect(_on_agreement_continue_pressed)
	terms_link.pressed.connect(_open_agreement_link.bind("https://shipth.is/terms"))
	privacy_link.pressed.connect(_open_agreement_link.bind("https://shipth.is/privacy"))
	dpa_link.pressed.connect(_open_agreement_link.bind("https://shipth.is/dpa"))
	learn_more_link.pressed.connect(_open_agreement_link.bind("https://shipth.is/security"))
	docs_link.pressed.connect(_on_header_docs_pressed)
	dashboard_link.pressed.connect(_on_header_dashboard_pressed)
	discord_link.pressed.connect(_on_header_discord_pressed)
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
		var user = auth_config.ship_this_user
		var needs_agreement: bool = user.details == null || !user.details.has_accepted_terms
		if needs_agreement:
			api.set_token(user.jwt)
			_show_view(View.AGREEMENT, user)
		else:
			_show_view(View.AUTHENTICATED, user)
	else:
		_show_view(View.EMAIL)


func _show_view(view: View, user: SelfWithJWT = null) -> void:
	email_container.visible = (view == View.EMAIL)
	code_container.visible = (view == View.CODE)
	agreement_container.visible = (view == View.AGREEMENT)
	authenticated_container.visible = (view == View.AUTHENTICATED)
	wizard_container.visible = false
	
	if view == View.CODE:
		code_prompt_label.text = "Please enter the code we sent to %s." % current_email
		code_input.call_deferred("grab_focus")
	elif view == View.EMAIL:
		email_input.call_deferred("grab_focus")
	elif view == View.AGREEMENT and user != null:
		_agreement_user = user
		agreement_check.button_pressed = false
	elif view == View.AUTHENTICATED and user != null:
		_agreement_user = null
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
	back_link.disabled = is_loading
	agreement_continue_button.disabled = is_loading
	agreement_check.disabled = is_loading


func _on_send_code_pressed(_text: String = "") -> void:
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
	else:
		_set_status("Failed to send code: %s" % response.error, true)


func _on_verify_pressed(_text: String = "") -> void:
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
		
		# If user has not accepted terms, show agreement step; otherwise show authenticated view
		var needs_agreement: bool = user.details == null || !user.details.has_accepted_terms
		if needs_agreement:
			_show_view(View.AGREEMENT, user)
		else:
			_show_view(View.AUTHENTICATED, user)
	else:
		_set_status("Verification failed: %s" % response.error, true)


func _on_back_pressed() -> void:
	code_input.text = ""
	_show_view(View.EMAIL)


func _open_agreement_link(uri: String) -> void:
	OS.shell_open(uri)


func _on_header_docs_pressed() -> void:
	if api != null:
		OS.shell_open(api.client.web_url + "docs")


func _on_header_dashboard_pressed() -> void:
	_open_header_dashboard_games()


func _on_header_discord_pressed() -> void:
	OS.shell_open(DISCORD_URL)


func _open_header_dashboard_games() -> void:
	if api == null:
		return
	var resp = await api.get_login_link("/games")
	if resp.is_success and resp.data.has("url"):
		OS.shell_open(resp.data.url)
	else:
		OS.shell_open(api.client.web_url + "games")


func _on_agreement_continue_pressed() -> void:
	if !agreement_check.button_pressed:
		_set_status("You must agree to the terms and conditions, privacy policy, and data processing agreement to continue.", true)
		return
	
	_set_loading(true)
	_set_status("Saving…")
	
	var response: Dictionary = await api.post("/me/terms", {})
	
	_set_loading(false)
	
	if response.is_success:
		var updated = SelfWithJWT.from_dict(response.data)
		if updated.jwt.is_empty() and _agreement_user != null:
			updated.jwt = _agreement_user.jwt
		var auth_config = AuthConfig.new()
		auth_config.ship_this_user = updated
		var save_error = config.set_auth_config(auth_config)
		if save_error != OK:
			_set_status("Failed to save credentials.", true)
			return
		_clear_status()
		_show_view(View.AUTHENTICATED, updated)
	else:
		_set_status("Failed to save agreement: %s" % response.error, true)


func _on_ship_completed(_job) -> void:
	ship_runner.visible = false
	status_view.visible = true
	header_container.visible = true
	_show_toast_or_status("Build completed successfully.", false)


func _on_ship_failed(_message: String) -> void:
	ship_runner.visible = false
	status_view.visible = true
	header_container.visible = true
	_show_toast_or_status("Build failed. %s" % _message, true)


func _on_configure_android_pressed() -> void:
	_show_wizard()


func _show_wizard() -> void:
	# Hide main views
	email_container.visible = false
	code_container.visible = false
	agreement_container.visible = false
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
