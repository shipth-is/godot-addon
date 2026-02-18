@tool
extends VBoxContainer

## Step 6: Create Game in Google Play
## Displays instructions for creating the app in Google Play Console,
## polls the key test endpoint to detect when the app has been created.

signal step_completed

const Config = preload("res://addons/shipthis/lib/config.gd")
const Api = preload("res://addons/shipthis/lib/api.gd")

var api: Api = null
var config: Config = null
var project_id: String = ""

# Polling
var _poll_timer: Timer = null
const POLL_INTERVAL_SEC: float = 15.0

# Node references
@onready var loading_label: Label = $LoadingLabel
@onready var content_container: VBoxContainer = $ContentContainer
@onready var status_label: Label = $ContentContainer/StatusLabel
@onready var instructions_notice: RichTextLabel = $ContentContainer/InstructionsNotice
@onready var check_again_button: Button = $ContentContainer/ButtonsContainer/CheckAgainButton
@onready var open_dashboard_button: Button = $ContentContainer/ButtonsContainer/OpenDashboardButton
@onready var error_label: Label = $ErrorLabel


func _ready() -> void:
	check_again_button.pressed.connect(_on_check_again_pressed)
	open_dashboard_button.pressed.connect(_on_open_dashboard_pressed)
	instructions_notice.meta_clicked.connect(_on_meta_clicked)


func _exit_tree() -> void:
	_stop_polling()


func initialize(api_ref: Api, config_ref: Config) -> void:
	api = api_ref
	config = config_ref

	var project_config = config.get_project_config()
	project_id = project_config.project_id

	await _check_app_exists()


func _on_meta_clicked(meta: Variant) -> void:
	OS.shell_open(str(meta))


# --- Key test check ---

func _check_app_exists() -> void:
	_set_loading("Checking if your game exists in Google Play...")
	check_again_button.disabled = true

	var resp = await api.fetch_key_test_result(project_id)

	check_again_button.disabled = false

	if not resp.is_success:
		_show_instructions()
		_show_error("Could not check Google Play status: %s" % resp.get("error", "unknown error"))
		return

	var status = resp.data.get("status", "")
	var error_code = resp.data.get("error", "")

	# App is found if test succeeds or if the error is just "not invited"
	var is_app_found = status == "SUCCESS" or error_code == "NOT_INVITED"

	if is_app_found:
		_stop_polling()
		step_completed.emit()
	else:
		_show_instructions()
		_start_polling()


func _show_instructions() -> void:
	_hide_all()
	content_container.visible = true

	status_label.text = "ShipThis has not detected your game in Google Play. Create it using the steps below, then click Check Again."

	var short_id = project_id.substr(0, 8)
	var dashboard_url = api.client.web_url + "games/%s/builds" % short_id
	var play_console_url = "https://play.google.com/console"

	var bbcode = "[b]Create the game in Google Play[/b]\n\n" \
		+ "1. Log into the [url=%s]Google Play Console[/url] with your Google account.\n" % play_console_url \
		+ "2. Create a developer account and payments profile if prompted.\n" \
		+ "3. Click [b]\"Create app\"[/b] on the Console dashboard.\n" \
		+ "4. Enter the app name, default language, and accept terms.\n" \
		+ "5. Go to [b]\"Test and release\"[/b] > [b]\"Testing\"[/b] > [b]\"Internal testing\"[/b] and create a new release.\n" \
		+ "6. Upload the initial build [b]AAB file[/b] of your game from the previous step.\n\n" \
		+ "You can download the AAB from your ShipThis Dashboard:\n" \
		+ "[url=%s]%s[/url]" % [dashboard_url, dashboard_url]

	instructions_notice.text = bbcode


func _on_check_again_pressed() -> void:
	await _check_app_exists()


func _on_open_dashboard_pressed() -> void:
	open_dashboard_button.disabled = true

	var short_id = project_id.substr(0, 8)
	var destination = "/games/%s/builds" % short_id

	var resp = await api.get_login_link(destination)

	open_dashboard_button.disabled = false

	if resp.is_success and resp.data.has("url"):
		OS.shell_open(resp.data.url)
	else:
		# Fallback to direct dashboard URL
		OS.shell_open(api.client.web_url + "games/%s/builds" % short_id)


# --- Polling ---

func _start_polling() -> void:
	_stop_polling()

	_poll_timer = Timer.new()
	_poll_timer.wait_time = POLL_INTERVAL_SEC
	_poll_timer.one_shot = false
	_poll_timer.timeout.connect(_on_poll_timeout)
	add_child(_poll_timer)
	_poll_timer.start()


func _stop_polling() -> void:
	if _poll_timer != null:
		_poll_timer.stop()
		_poll_timer.queue_free()
		_poll_timer = null


func _on_poll_timeout() -> void:
	await _check_app_exists()


# --- UI helpers ---

func _hide_all() -> void:
	loading_label.visible = false
	content_container.visible = false
	error_label.visible = false


func _set_loading(message: String) -> void:
	_hide_all()
	loading_label.text = message
	loading_label.visible = true


func _show_error(message: String) -> void:
	error_label.text = message
	error_label.visible = true
	error_label.add_theme_color_override("font_color", Color.RED)
