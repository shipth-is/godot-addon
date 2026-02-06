## Config for ShipThis addon - reads domain from ProjectSettings and generates URLs


const AuthConfig = preload("res://addons/shipthis/models/auth_config.gd")
const ProjectConfig = preload("res://addons/shipthis/models/project_config.gd")
const UserDetails = preload("res://addons/shipthis/models/user_details.gd")
const SelfWithJWT = preload("res://addons/shipthis/models/self_with_jwt.gd")

# Default globs for new projects
const DEFAULT_SHIPPED_FILES_GLOBS: Array[String] = ["**/*"]

# Generated from the Godot gitignore https://github.com/github/gitignore/blob/main/Godot.gitignore
const DEFAULT_IGNORED_FILES_GLOBS: Array[String] = [
	".git",
	".gitignore",
	"shipthis.json",
	"shipthis-*.zip",
	".godot/**",
	".nomedia",
	".import/**",
	"export.cfg",
	"export_credentials.cfg",
	"*.translation",
	".mono/**",
	"data_*/**",
	"mono_crash.*.json",
	"*.apk",
	"*.aab",
	# OS cruft
	".DS_Store",
	"Thumbs.db",
	# IDE project files
	"*.iml",
	".idea/",
	".vscode/",
	# Gradle + build outputs
	".gradle/",
	"**/build/",
	# Android local config
	"local.properties",
	# Signing (keep secrets out of git)
	"*.jks",
	"*.keystore",
	"keystore.properties",
	# NDK
	".cxx/",
	".externalNativeBuild/",
	# Misc temp
	"*.log",
	"*.tmp",
	"*.temp",
	"*.swp",
	"*.swo",
	"*~",
	".env",
]


func get_auth_config_path() -> String:
	var home: String = ""
	
	if OS.get_name() == "Windows":
		home = OS.get_environment("USERPROFILE")
	else:
		home = OS.get_environment("HOME")
	
	if home == "":
		home = OS.get_user_data_dir()
	
	return home.path_join(".shipthis.auth.json")


func set_auth_config(auth_config: AuthConfig) -> Error:
	var json_string: String = JSON.stringify(auth_config.to_dict(), "  ")
	var file_path: String = get_auth_config_path()
	var file: FileAccess = FileAccess.open(file_path, FileAccess.WRITE)
	
	if file == null:
		return FileAccess.get_open_error()
	
	file.store_string(json_string)
	file.close()
	
	return OK


func get_auth_config(api_instance = null) -> AuthConfig:
	var file_path: String = get_auth_config_path()
	
	if not FileAccess.file_exists(file_path):
		return AuthConfig.new()
	
	var file: FileAccess = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return AuthConfig.new()
	
	var json_string: String = file.get_as_text()
	file.close()
	
	if json_string == "":
		return AuthConfig.new()
	
	var json_result = JSON.parse_string(json_string)
	if json_result == null or not json_result is Dictionary:
		return AuthConfig.new()
	
	var auth_config = AuthConfig.new()
	
	if json_result.has("appleCookies"):
		auth_config.apple_cookies = json_result["appleCookies"]
	
	if json_result.has("shipThisUser"):
		var user_data: Dictionary = json_result["shipThisUser"]
		var details = UserDetails.new()
		if user_data.has("details"):
			var details_data: Dictionary = user_data["details"]
			details.has_accepted_terms = details_data.get("hasAcceptedTerms", false)
			details.source = details_data.get("source", "")
			details.terms_agreement_version_id = int(details_data.get("termsAgreementVersionId", 0))
			details.privacy_agreement_version_id = int(details_data.get("privacyAgreementVersionId", 0))
		
		var user = SelfWithJWT.new(
			user_data.get("createdAt", ""),
			details,
			user_data.get("email", ""),
			user_data.get("id", ""),
			user_data.get("updatedAt", ""),
			user_data.get("jwt", "")
		)
		auth_config.ship_this_user = user
		
		if api_instance != null and auth_config.ship_this_user != null and auth_config.ship_this_user.jwt != "":
			api_instance.set_token(auth_config.ship_this_user.jwt)
	
	return auth_config


func get_project_config_path() -> String:
	return ProjectSettings.globalize_path("res://shipthis.json")


func set_project_config(project_config: ProjectConfig) -> Error:
	var json_string: String = JSON.stringify(project_config.to_dict(), "  ")
	var file_path: String = get_project_config_path()
	var file: FileAccess = FileAccess.open(file_path, FileAccess.WRITE)
	
	if file == null:
		return FileAccess.get_open_error()
	
	file.store_string(json_string)
	file.close()
	
	return OK


func get_project_config() -> ProjectConfig:
	var file_path: String = get_project_config_path()
	
	if not FileAccess.file_exists(file_path):
		return ProjectConfig.new()
	
	var file: FileAccess = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return ProjectConfig.new()
	
	var json_string: String = file.get_as_text()
	file.close()
	
	if json_string == "":
		return ProjectConfig.new()
	
	var json_result = JSON.parse_string(json_string)
	if json_result == null or not json_result is Dictionary:
		return ProjectConfig.new()
	
	return ProjectConfig.from_dict(json_result)
