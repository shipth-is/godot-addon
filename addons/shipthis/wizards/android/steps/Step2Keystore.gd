@tool
extends VBoxContainer

## Step 2: Create or Import Keystore
## Either creates a new keystore via API or imports an existing JKS file.

signal step_completed

const Config = preload("res://addons/shipthis/lib/config.gd")
const Api = preload("res://addons/shipthis/lib/api.gd")
const AddonContext = preload("res://addons/shipthis/lib/addon_context.gd")
const Upload = preload("res://addons/shipthis/lib/upload.gd")

enum Stage { CHOOSE, CREATE, IMPORT_FORM, IMPORT }

var api: Api = null
var config: Config = null
var current_stage: Stage = Stage.CHOOSE

# Import form state
var selected_jks_path: String = ""

# Node references
@onready var loading_label: Label = $LoadingLabel
@onready var choose_container: VBoxContainer = $ChooseContainer
@onready var create_button: Button = $ChooseContainer/ButtonContainer/CreateButton
@onready var import_button: Button = $ChooseContainer/ButtonContainer/ImportButton
@onready var import_form_container: VBoxContainer = $ImportFormContainer
@onready var file_path_input: LineEdit = $ImportFormContainer/FilePathContainer/FilePathInput
@onready var browse_button: Button = $ImportFormContainer/FilePathContainer/BrowseButton
@onready var password_input: LineEdit = $ImportFormContainer/PasswordInput
@onready var import_submit_button: Button = $ImportFormContainer/ImportSubmitButton
@onready var file_dialog: FileDialog = $FileDialog
@onready var status_label: Label = $StatusLabel


func _ready() -> void:
	create_button.pressed.connect(_on_create_pressed)
	import_button.pressed.connect(_on_import_pressed)
	browse_button.pressed.connect(_on_browse_pressed)
	import_submit_button.pressed.connect(_on_import_submit_pressed)
	file_dialog.file_selected.connect(_on_file_selected)


func initialize(context: AddonContext) -> void:
	api = context.api
	config = context.config
	_show_stage(Stage.CHOOSE)


func _show_stage(stage: Stage) -> void:
	current_stage = stage
	
	choose_container.visible = (stage == Stage.CHOOSE)
	import_form_container.visible = (stage == Stage.IMPORT_FORM)
	loading_label.visible = (stage == Stage.CREATE or stage == Stage.IMPORT)
	
	_clear_error()


func _set_loading(message: String) -> void:
	loading_label.text = message
	loading_label.visible = true
	choose_container.visible = false
	import_form_container.visible = false


func _show_error(message: String) -> void:
	status_label.text = message
	status_label.add_theme_color_override("font_color", Color.RED)
	status_label.visible = true


func _clear_error() -> void:
	status_label.text = ""
	status_label.visible = false


func _on_create_pressed() -> void:
	await _create_keystore()


func _on_import_pressed() -> void:
	_show_stage(Stage.IMPORT_FORM)


func _on_browse_pressed() -> void:
	file_dialog.popup_centered()


func _on_file_selected(path: String) -> void:
	selected_jks_path = path
	file_path_input.text = path


func _on_import_submit_pressed() -> void:
	_clear_error()
	
	# Validate inputs
	if selected_jks_path == "":
		_show_error("Please select a .jks file")
		return
	
	if not FileAccess.file_exists(selected_jks_path):
		_show_error("The selected file does not exist")
		return
	
	var password = password_input.text
	if password == "":
		_show_error("Please enter the keystore password")
		return
	
	await _import_keystore(selected_jks_path, password)


func _create_keystore() -> void:
	_set_loading("Creating keystore...")
	
	var project_config = config.get_project_config()
	var project_id = project_config.project_id
	
	if project_id == "":
		_show_error("No project configured")
		_show_stage(Stage.CHOOSE)
		return
	
	var response = await api.create_android_keystore(project_id)
	
	if response.is_success:
		step_completed.emit()
	else:
		_show_error("Failed to create keystore: %s" % response.error)
		_show_stage(Stage.CHOOSE)


func _import_keystore(jks_path: String, password: String) -> void:
	_set_loading("Preparing keystore for import...")
	
	var project_config = config.get_project_config()
	var project_id = project_config.project_id
	
	if project_id == "":
		_show_error("No project configured")
		_show_stage(Stage.IMPORT_FORM)
		return
	
	# Step 1: Create the ZIP file
	var zip_path = _create_keystore_zip(jks_path, password)
	if zip_path == "":
		_show_error("Failed to create keystore package")
		_show_stage(Stage.IMPORT_FORM)
		return
	
	# Step 2: Get import ticket
	_set_loading("Getting upload URL...")
	var ticket_response = await api.get_credential_import_ticket(project_id)
	
	if not ticket_response.is_success:
		_cleanup_temp_zip(zip_path)
		_show_error("Failed to get upload URL: %s" % ticket_response.error)
		_show_stage(Stage.IMPORT_FORM)
		return
	
	var upload_url: String = ticket_response.data.url
	var import_uuid: String = ticket_response.data.uuid
	
	# Step 3: Upload the ZIP file
	_set_loading("Uploading keystore...")
	var uploader = Upload.new()
	var upload_error = await uploader.upload_file(
		upload_url,
		zip_path,
		func(p: Dictionary):
			_set_loading("Uploading keystore... %.0f%%" % [p.progress * 100]),
		get_tree()
	)
	
	if upload_error != OK:
		_cleanup_temp_zip(zip_path)
		_show_error("Failed to upload keystore: %s" % error_string(upload_error))
		_show_stage(Stage.IMPORT_FORM)
		return
	
	# Step 4: Trigger the import
	_set_loading("Importing keystore...")
	var import_response = await api.trigger_credential_import(
		project_id,
		"ANDROID",
		"CERTIFICATE",
		import_uuid
	)
	
	# Clean up temp file
	_cleanup_temp_zip(zip_path)
	
	if import_response.is_success:
		step_completed.emit()
	else:
		_show_error("Failed to import keystore: %s" % import_response.error)
		_show_stage(Stage.IMPORT_FORM)


func _create_keystore_zip(jks_path: String, password: String) -> String:
	var temp_zip_path = OS.get_user_data_dir().path_join("shipthis_keystore_import.zip")
	
	var zip = ZIPPacker.new()
	var err = zip.open(temp_zip_path)
	if err != OK:
		return ""
	
	# Add the JKS file as keyStore.jks
	var jks_data = FileAccess.get_file_as_bytes(jks_path)
	if jks_data.size() == 0:
		zip.close()
		return ""
	
	zip.start_file("keyStore.jks")
	zip.write_file(jks_data)
	zip.close_file()
	
	# Add password.txt (keystore password)
	zip.start_file("password.txt")
	zip.write_file(password.to_utf8_buffer())
	zip.close_file()
	
	# Add keyPassword.txt (key password - same as keystore for Godot exports)
	zip.start_file("keyPassword.txt")
	zip.write_file(password.to_utf8_buffer())
	zip.close_file()
	
	zip.close()
	
	return temp_zip_path


func _cleanup_temp_zip(zip_path: String) -> void:
	if zip_path != "" and FileAccess.file_exists(zip_path):
		DirAccess.remove_absolute(zip_path)
