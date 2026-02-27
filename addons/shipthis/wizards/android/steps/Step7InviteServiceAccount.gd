@tool
extends VBoxContainer

## Step 7: Invite Service Account
## The user enters their Google Play Developer Account ID so the service
## account can be invited to their Google Play account.

signal step_completed

const Config = preload("res://addons/shipthis/lib/config.gd")
const Api = preload("res://addons/shipthis/lib/api.gd")
const AddonContext = preload("res://addons/shipthis/lib/addon_context.gd")

var api: Api = null
var config: Config = null
var project_id: String = ""

# Node references
@onready var loading_label: Label = $LoadingLabel
@onready var content_container: VBoxContainer = $ContentContainer
@onready var instructions_notice: RichTextLabel = $ContentContainer/InstructionsNotice
@onready var account_id_input: LineEdit = $ContentContainer/InputContainer/AccountIdInput
@onready var invite_button: Button = $ContentContainer/InputContainer/InviteButton
@onready var error_label: Label = $ContentContainer/ErrorLabel
@onready var success_label: Label = $ContentContainer/SuccessLabel


func _ready() -> void:
	invite_button.pressed.connect(_on_invite_pressed)
	account_id_input.text_submitted.connect(_on_text_submitted)
	instructions_notice.meta_clicked.connect(_on_meta_clicked)


func initialize(context: AddonContext) -> void:
	api = context.api
	config = context.config

	var project_config = config.get_project_config()
	project_id = project_config.project_id

	await _check_already_invited()


func _on_meta_clicked(meta: Variant) -> void:
	OS.shell_open(str(meta))


# --- Initial check ---

func _check_already_invited() -> void:
	_set_loading("Checking invitation status...")

	var resp = await api.fetch_key_test_result(project_id)

	if resp.is_success:
		var status = resp.data.get("status", "")
		if status == "SUCCESS":
			step_completed.emit()
			return

	_show_form()


# --- Form display ---

func _show_form() -> void:
	_hide_all()
	content_container.visible = true

	var guide_url = api.client.web_url + "docs/guides/google-play-account-id"
	var play_console_url = "https://play.google.com/console"

	var bbcode = "[b]Invite the Service Account[/b]\n\n" \
		+ "Before the Service Account API Key can submit your games automatically, " \
		+ "you will need to invite the Service Account to your Google Play account. " \
		+ "To do this you will need your Google Play Account ID.\n\n" \
		+ "[b]How to find your Google Play Account ID[/b]\n\n" \
		+ "You can read our help page about this on the ShipThis Documentation: " \
		+ "[url=%s]Finding your Account ID[/url]\n\n" % guide_url \
		+ "1. Log in to the [url=%s]Google Play Console[/url]\n" % play_console_url \
		+ "2. Below your account name there is a label [b]Account ID[/b]\n" \
		+ "3. Copy this value and paste it below"

	instructions_notice.text = bbcode


# --- Invite action ---

func _on_text_submitted(_text: String) -> void:
	_on_invite_pressed()


func _on_invite_pressed() -> void:
	_clear_error()

	var account_id = account_id_input.text.strip_edges()

	# Validate: numeric only, 10-20 digits
	var regex = RegEx.new()
	regex.compile("^\\d{10,20}$")
	if not regex.search(account_id):
		_show_error("Please enter a valid Google Play Account ID (10-20 digits)")
		return

	invite_button.disabled = true
	account_id_input.editable = false

	var resp = await api.invite_service_account(project_id, account_id)

	invite_button.disabled = false
	account_id_input.editable = true

	if resp.is_success:
		step_completed.emit()
	else:
		_show_error("Failed to invite service account: %s" % resp.get("error", "unknown error"))


# --- UI helpers ---

func _hide_all() -> void:
	loading_label.visible = false
	content_container.visible = false


func _set_loading(message: String) -> void:
	_hide_all()
	loading_label.text = message
	loading_label.visible = true


func _show_error(message: String) -> void:
	error_label.text = message
	error_label.visible = true
	error_label.add_theme_color_override("font_color", Color.RED)


func _clear_error() -> void:
	error_label.text = ""
	error_label.visible = false
