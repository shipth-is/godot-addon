@tool
extends EditorPlugin

const Config = preload("res://addons/shipthis/config.gd")
const API = preload("res://addons/shipthis/api.gd")

var config: RefCounted
var api: RefCounted


func _enable_plugin() -> void:
	# Add autoloads here.
	pass


func _disable_plugin() -> void:
	# Remove autoloads here.
	pass


func _enter_tree() -> void:
	# Initialization of the plugin goes here.
	_initialize_plugin()


func _exit_tree() -> void:
	# Clean-up of the plugin goes here.
	pass


func _initialize_plugin() -> void:

	config = Config.new()
	config.load()
	
	# Create API instance with config (gets base_url)
	api = API.new(config)
	
	# Load auth config and set token if authenticated
	var auth_config = config.get_auth_config(api)
	
	# Check if authenticated and output user info
	if auth_config != null and auth_config.ship_this_user != null:
		var user = auth_config.ship_this_user
		var separator = "=".repeat(80)
		print(separator)
		print("SHIPTHIS: AUTHENTICATED")
		print(separator)
		print("User ID: ", user.id)
		print("Email: ", user.email)
		print("Created: ", user.created_at)
		print("Updated: ", user.updated_at)
		if user.details != null:
			print("Has Accepted Terms: ", user.details.has_accepted_terms)
			if user.details.source != "":
				print("Source: ", user.details.source)
		print(separator)
	else:
		print("SHIPTHIS: Not authenticated")
