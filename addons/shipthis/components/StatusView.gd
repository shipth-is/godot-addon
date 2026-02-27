@tool
extends ScrollContainer

## Status view: game details, Android/iOS platform status, next steps.
## Fetches real data; emits configure_android_pressed and ship_pressed.

const Config = preload("res://addons/shipthis/lib/config.gd")
const Api = preload("res://addons/shipthis/lib/api.gd")
const AddonContext = preload("res://addons/shipthis/lib/addon_context.gd")

signal configure_android_pressed
signal ship_pressed(platform: String)

# Dependencies
var config: Config = null
var api: Api = null

# Set when we have a linked project (for View builds/jobs)
var _project_id: String = ""

# No project state
@onready var no_project_container: VBoxContainer = $ContentMargin/MainColumn/NoProjectContainer
@onready var no_project_label: Label = $ContentMargin/MainColumn/NoProjectContainer/NoGameLabel
@onready var no_project_configure_button: Button = $ContentMargin/MainColumn/NoProjectContainer/ConfigureAndroidButton

# Has project state
@onready var has_project_container: VBoxContainer = $ContentMargin/MainColumn/HasProjectContainer
@onready var loading_label: Label = $ContentMargin/MainColumn/LoadingLabel

# Game details
@onready var game_id_value: Label = $ContentMargin/MainColumn/HasProjectContainer/ColumnsRow/LeftColumn/GameDetailsSection/GameDetailsRows/GameIdRow/Value
@onready var name_value: Label = $ContentMargin/MainColumn/HasProjectContainer/ColumnsRow/LeftColumn/GameDetailsSection/GameDetailsRows/NameRow/Value
@onready var version_value: Label = $ContentMargin/MainColumn/HasProjectContainer/ColumnsRow/LeftColumn/GameDetailsSection/GameDetailsRows/VersionRow/Value
@onready var build_number_value: Label = $ContentMargin/MainColumn/HasProjectContainer/ColumnsRow/LeftColumn/GameDetailsSection/GameDetailsRows/BuildNumberRow/Value
@onready var created_at_value: Label = $ContentMargin/MainColumn/HasProjectContainer/ColumnsRow/LeftColumn/GameDetailsSection/GameDetailsRows/CreatedAtRow/Value
@onready var game_engine_value: Label = $ContentMargin/MainColumn/HasProjectContainer/ColumnsRow/LeftColumn/GameDetailsSection/GameDetailsRows/GameEngineRow/Value

# iOS status
@onready var ios_status_section: VBoxContainer = $ContentMargin/MainColumn/HasProjectContainer/ColumnsRow/PlatformColumn/IosStatusSection
@onready var ios_not_enabled_label: Label = $ContentMargin/MainColumn/HasProjectContainer/ColumnsRow/PlatformColumn/IosStatusSection/IosNotEnabledLabel
@onready var ios_status_rows: VBoxContainer = $ContentMargin/MainColumn/HasProjectContainer/ColumnsRow/PlatformColumn/IosStatusSection/IosStatusRows

# Android status
@onready var android_status_rows: VBoxContainer = $ContentMargin/MainColumn/HasProjectContainer/ColumnsRow/PlatformColumn/AndroidStatusSection/AndroidStatusRows

# Next steps (right column)
@onready var next_steps_configure_button: Button = $ContentMargin/MainColumn/HasProjectContainer/ColumnsRow/NextStepsColumn/NextStepsSection/NextStepsButtons/ConfigureAndroidButton
@onready var next_steps_ship_android_button: Button = $ContentMargin/MainColumn/HasProjectContainer/ColumnsRow/NextStepsColumn/NextStepsSection/NextStepsButtons/ShipAndroidButton
@onready var next_steps_ship_ios_button: Button = $ContentMargin/MainColumn/HasProjectContainer/ColumnsRow/NextStepsColumn/NextStepsSection/NextStepsButtons/ShipIosButton
@onready var view_builds_button: LinkButton = $ContentMargin/MainColumn/HasProjectContainer/ColumnsRow/NextStepsColumn/NextStepsSection/NextStepsButtons/ViewBuildsButton
@onready var view_jobs_button: LinkButton = $ContentMargin/MainColumn/HasProjectContainer/ColumnsRow/NextStepsColumn/NextStepsSection/NextStepsButtons/ViewJobsButton
@onready var next_steps_hint: Label = $ContentMargin/MainColumn/HasProjectContainer/ColumnsRow/NextStepsColumn/NextStepsSection/NextStepsHint

func _ready() -> void:
	no_project_configure_button.pressed.connect(_on_no_project_configure_pressed)
	next_steps_configure_button.pressed.connect(_on_next_steps_configure_pressed)
	next_steps_ship_android_button.pressed.connect(_on_ship_android_pressed)
	next_steps_ship_ios_button.pressed.connect(_on_ship_ios_pressed)
	view_builds_button.pressed.connect(_on_view_builds_pressed)
	view_jobs_button.pressed.connect(_on_view_jobs_pressed)


func initialize(context: AddonContext) -> void:
	config = context.config
	api = context.api
	refresh()


func refresh() -> void:
	if config == null or api == null:
		return
	await _fetch_and_apply()


func _on_no_project_configure_pressed() -> void:
	configure_android_pressed.emit()


func _on_next_steps_configure_pressed() -> void:
	configure_android_pressed.emit()


func _on_ship_android_pressed() -> void:
	ship_pressed.emit("ANDROID")


func _on_ship_ios_pressed() -> void:
	ship_pressed.emit("IOS")


func _on_view_builds_pressed() -> void:
	_open_dashboard_path("/games/%s/builds" % _project_id.substr(0, 8))


func _on_view_jobs_pressed() -> void:
	_open_dashboard_path("/games/%s/jobs" % _project_id.substr(0, 8))


func _open_dashboard_path(destination: String) -> void:
	if _project_id == "" or api == null:
		return
	var resp = await api.get_login_link(destination)
	if resp.is_success and resp.data.has("url"):
		OS.shell_open(resp.data.url)
	else:
		OS.shell_open(api.client.web_url + destination.trim_prefix("/"))


func _fetch_and_apply() -> void:
	var project_config = config.get_project_config()
	var project_id: String = project_config.project_id

	loading_label.visible = true
	no_project_container.visible = false
	has_project_container.visible = false

	if project_id == "":
		_project_id = ""
		loading_label.visible = false
		no_project_container.visible = true
		return

	var project_resp = await api.get_project(project_id)
	if not project_resp.is_success:
		_project_id = ""
		loading_label.visible = false
		no_project_label.text = "Failed to load game."
		no_project_container.visible = true
		return

	_project_id = project_id
	var project: Dictionary = project_resp.data
	var details: Dictionary = project.get("details", {}) if project.get("details") else {}

	# Game details
	game_id_value.text = project_id.substr(0, 8) if project_id.length() >= 8 else project_id
	name_value.text = project.get("name", "")
	version_value.text = details.get("semanticVersion", "0.0.1")
	build_number_value.text = str(details.get("buildNumber", 1))
	created_at_value.text = _format_short_date(project.get("createdAt", ""))
	var engine: String = details.get("gameEngine", "godot")
	var engine_ver: String = details.get("gameEngineVersion", "4.3")
	game_engine_value.text = "%s %s" % [engine, engine_ver]

	# Android progress
	var android_resp = await api.get_project_platform_progress(project_id, "ANDROID")
	var android_data: Dictionary = android_resp.data if android_resp.is_success else {}
	_apply_platform_rows(android_status_rows, android_data)

	# iOS progress (only if enabled)
	var ios_bundle_id: String = details.get("iosBundleId", "") if details else ""
	var ios_configured: bool = false
	if ios_bundle_id != "":
		ios_not_enabled_label.visible = false
		ios_status_rows.visible = true
		var ios_resp = await api.get_project_platform_progress(project_id, "IOS")
		var ios_data: Dictionary = ios_resp.data if ios_resp.is_success else {}
		_apply_platform_rows(ios_status_rows, ios_data)
		ios_configured = _is_platform_configured(ios_data)
	else:
		ios_not_enabled_label.visible = true
		ios_status_rows.visible = false

	# Next steps: Configure Android when Android not configured; Ship buttons per platform; View builds/jobs when we have a project
	var android_configured: bool = _is_platform_configured(android_data)

	next_steps_configure_button.visible = not android_configured
	next_steps_ship_android_button.visible = android_configured
	next_steps_ship_android_button.disabled = false
	next_steps_ship_ios_button.visible = true
	next_steps_ship_ios_button.disabled = not ios_configured
	view_builds_button.visible = true
	view_jobs_button.visible = true
	view_builds_button.disabled = _project_id == ""
	view_jobs_button.disabled = _project_id == ""
	if not android_configured:
		next_steps_hint.visible = true
		next_steps_hint.text = "Run the Android wizard to set up keystore and service account."
	else:
		next_steps_hint.visible = false

	loading_label.visible = false
	has_project_container.visible = true


func _is_platform_configured(data: Dictionary) -> bool:
	return bool(data.get("hasBundleSet", false)) \
		and bool(data.get("hasCredentialsForPlatform", false)) \
		and bool(data.get("hasApiKeyForPlatform", false))


func _apply_platform_rows(rows_container: VBoxContainer, data: Dictionary) -> void:
	var keys: Array[String] = [
		"hasBundleSet",
		"hasCredentialsForPlatform",
		"hasApiKeyForPlatform",
		"hasSuccessfulJobForPlatform",
	]
	var row_nodes: Array[Node] = []
	for c in rows_container.get_children():
		if c is HBoxContainer:
			row_nodes.append(c)
	for i in range(min(keys.size(), row_nodes.size())):
		var value: bool = data.get(keys[i], false)
		var value_label: Label = row_nodes[i].get_node_or_null("Value")
		if value_label != null:
			value_label.text = "YES" if value else "NO"


func _format_short_date(iso_string: String) -> String:
	if iso_string == "":
		return "—"
	# ISO 8601 date or datetime; show date part only in short form
	var parts: PackedStringArray = iso_string.split("T")
	var date_part: String = parts[0] if parts.size() > 0 else iso_string
	# Optionally reorder for locale (e.g. DD/MM/YYYY); keep simple YYYY-MM-DD or parse
	return date_part
