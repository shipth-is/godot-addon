## Config for ShipThis addon - reads domain from ProjectSettings and generates URLs

const PRIMARY_DOMAIN = "shipth.is"
const AuthConfig = preload("res://addons/shipthis/models/auth_config.gd")
const UserDetails = preload("res://addons/shipthis/models/user_details.gd")
const SelfWithJWT = preload("res://addons/shipthis/models/self_with_jwt.gd")

var domain: String = ""
var api_url: String = ""
var web_url: String = ""
var ws_url: String = ""
var environment: String = ""
var is_debug: bool = false


func get_urls_for_domain(url_domain: String) -> Dictionary:
	var is_public: bool = url_domain.contains(PRIMARY_DOMAIN)
	var api_domain: String = ("api." if is_public else "") + url_domain
	var ws_domain: String = ("ws." if is_public else "") + url_domain
	
	return {
		"api": "https://%s/api/1.0.0" % api_domain,
		"web": "https://%s/" % url_domain,
		"ws": "wss://%s" % ws_domain
	}


func load() -> void:
	domain = ProjectSettings.get_setting(
		"addons/shipthis/domain",
		PRIMARY_DOMAIN
	)
	
	var urls: Dictionary = get_urls_for_domain(domain)
	api_url = urls.api
	web_url = urls.web
	ws_url = urls.ws


func get_auth_config_path() -> String:
	var home: String = ""
	
	if OS.get_name() == "Windows":
		home = OS.get_environment("USERPROFILE")
	else:
		home = OS.get_environment("HOME")
	
	if home == "":
		home = OS.get_user_data_dir()
	
	return home.path_join(".shipthis.auth.json")


func set_auth_config(auth_config) -> Error:
	var json_string: String = JSON.stringify(auth_config.to_dict(), "  ")
	var file_path: String = get_auth_config_path()
	var file: FileAccess = FileAccess.open(file_path, FileAccess.WRITE)
	
	if file == null:
		return FileAccess.get_open_error()
	
	file.store_string(json_string)
	file.close()
	
	return OK


func get_auth_config(api_instance = null):
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
