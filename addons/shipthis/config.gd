## Config for ShipThis addon - reads domain from ProjectSettings and generates URLs

const PRIMARY_DOMAIN = "shipth.is"
const AuthConfig = preload("res://addons/shipthis/models/auth_config.gd")
const UserDetails = preload("res://addons/shipthis/models/user_details.gd")
const SelfWithJWT = preload("res://addons/shipthis/models/self_with_jwt.gd")

var domain = ""
var api_url = ""
var web_url = ""
var ws_url = ""
var environment = ""
var debug = false


func get_urls_for_domain(domain: String) -> Dictionary:
	var is_public = domain.contains(PRIMARY_DOMAIN)
	var api_domain = ("api." if is_public else "") + domain
	var ws_domain = ("ws." if is_public else "") + domain
	
	return {
		"api": "https://%s/api/1.0.0" % api_domain,
		"web": "https://%s/" % domain,
		"ws": "wss://%s" % ws_domain
	}


func load() -> void:
	domain = ProjectSettings.get_setting(
		"addons/shipthis/domain",
		PRIMARY_DOMAIN
	)
	
	var urls = get_urls_for_domain(domain)
	api_url = urls.api
	web_url = urls.web
	ws_url = urls.ws


func get_auth_config_path() -> String:
	var home = ""
	
	if OS.get_name() == "Windows":
		home = OS.get_environment("USERPROFILE")
	else:
		home = OS.get_environment("HOME")
	
	if home == "":
		home = OS.get_user_data_dir()
	
	return home.path_join(".shipthis.auth.json")


func set_auth_config(config) -> Error:
	
	var json_string = JSON.stringify(config.to_dict(), "  ")
	
	var file_path = get_auth_config_path()
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	
	if file == null:
		return FileAccess.get_open_error()
	
	file.store_string(json_string)
	file.close()
	
	return OK


func get_auth_config(api_instance = null):
	var file_path = get_auth_config_path()
	
	if not FileAccess.file_exists(file_path):
		return AuthConfig.new()
	
	var file = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return AuthConfig.new()
	
	var json_string = file.get_as_text()
	file.close()
	
	if json_string == "":
		return AuthConfig.new()
	
	var json_result = JSON.parse_string(json_string)
	if json_result == null or not json_result is Dictionary:
		return AuthConfig.new()
	
	var config = AuthConfig.new()
	
	if json_result.has("appleCookies"):
		config.apple_cookies = json_result["appleCookies"]
	
	if json_result.has("shipThisUser"):
		var user_data = json_result["shipThisUser"]
		var details = UserDetails.new()
		if user_data.has("details"):
			var details_data = user_data["details"]
			details.has_accepted_terms = details_data.get("hasAcceptedTerms", false)
			details.source = details_data.get("source", "")
			details.terms_agreement_version_id = details_data.get("termsAgreementVersionId", "")
			details.privacy_agreement_version_id = details_data.get("privacyAgreementVersionId", "")
		
		var user = SelfWithJWT.new(
			user_data.get("createdAt", ""),
			details,
			user_data.get("email", ""),
			user_data.get("id", ""),
			user_data.get("updatedAt", ""),
			user_data.get("jwt", "")
		)
		config.ship_this_user = user
		
		if api_instance != null and config.ship_this_user != null and config.ship_this_user.jwt != "":
			api_instance.set_token(config.ship_this_user.jwt)
	
	return config

