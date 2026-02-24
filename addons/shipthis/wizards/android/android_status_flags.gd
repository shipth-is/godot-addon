## Status flags for Android wizard - fetches actual persisted state from API

class_name AndroidStatusFlags
extends RefCounted

const AndroidEnums = preload("res://addons/shipthis/wizards/android/android_enums.gd")

var has_ship_this_project: bool = false
var has_game_name: bool = false
var has_android_package_name: bool = false
var has_android_keystore: bool = false
var has_google_connection: bool = false
var has_service_account_key: bool = false
var has_initial_build: bool = false
var has_google_play_game: bool = false
var has_invited_service_account: bool = false


static func fetch(api, project_id: String) -> AndroidStatusFlags:
	var flags = AndroidStatusFlags.new()
	
	if project_id == "":
		return flags
	
	# Fetch project
	var project_resp = await api.get_project(project_id)
	if project_resp.is_success:
		flags.has_ship_this_project = true
		flags.has_game_name = project_resp.data.get("name", "") != ""
		var details = project_resp.data.get("details", {})
		if details != null:
			flags.has_android_package_name = details.get("androidPackageName", "") != ""
	
	# Fetch credentials (paginated response: {data: [...], pageCount: N})
	var creds_resp = await api.get_project_credentials(project_id)
	if creds_resp.is_success:
		var credentials = creds_resp.data.get("data", [])
		for cred in credentials:
			var platform = cred.get("platform", "")
			var is_active = cred.get("isActive", false)
			var cred_type = cred.get("type", "")
			
			if platform == "ANDROID" and is_active:
				if cred_type == "CERTIFICATE":
					flags.has_android_keystore = true
				elif cred_type == "KEY":
					flags.has_service_account_key = true
	
	# Fetch Google status
	var google_resp = await api.get_google_status()
	if google_resp.is_success:
		flags.has_google_connection = google_resp.data.get("isAuthenticated", false)
	
	# Fetch builds (paginated response: {data: [...], pageCount: N})
	var builds_resp = await api.query_builds(project_id)
	if builds_resp.is_success:
		var builds = builds_resp.data.get("data", [])
		for build in builds:
			var platform = build.get("platform", "")
			var build_type = build.get("buildType", "")
			if platform == "ANDROID" and build_type == "AAB":
				flags.has_initial_build = true
				break
	
	# Fetch key test result
	var key_test_resp = await api.fetch_key_test_result(project_id)
	if key_test_resp.is_success:
		var status = key_test_resp.data.get("status", "")
		var error = key_test_resp.data.get("error", "")
		# API returns lowercase; NOT_INVITED means app exists but service account not invited yet
		flags.has_google_play_game = (status == "success") or (status == "error" and error == "not_invited")
		flags.has_invited_service_account = status == "success"
	
	return flags


func is_complete() -> bool:
	return has_ship_this_project and has_game_name and has_android_package_name \
		and has_android_keystore and has_service_account_key \
		and has_google_play_game and has_invited_service_account


func get_step_status(step: String) -> int:
	match step:
		"createGame":
			if has_game_name and has_android_package_name:
				return AndroidEnums.StepStatus.SUCCESS
			return AndroidEnums.StepStatus.PENDING
		"createKeystore":
			if has_android_keystore:
				return AndroidEnums.StepStatus.SUCCESS
			return AndroidEnums.StepStatus.PENDING
		"connectGoogle":
			# Not connected but we don't need to be since we have key and have invited service account
			if not has_google_connection and has_service_account_key and has_invited_service_account:
				return AndroidEnums.StepStatus.WARN
			if has_google_connection:
				return AndroidEnums.StepStatus.SUCCESS
			return AndroidEnums.StepStatus.PENDING
		"createServiceAccount":
			if has_service_account_key:
				return AndroidEnums.StepStatus.SUCCESS
			return AndroidEnums.StepStatus.PENDING
		"createInitialBuild":
			# App exists but we don't have an initial build (it is only needed to create the game in google play)
			if not has_initial_build and has_google_play_game:
				return AndroidEnums.StepStatus.WARN
			if has_initial_build:
				return AndroidEnums.StepStatus.SUCCESS
			return AndroidEnums.StepStatus.PENDING
		"createGooglePlayGame":
			if has_google_play_game:
				return AndroidEnums.StepStatus.SUCCESS
			return AndroidEnums.StepStatus.PENDING
		"inviteServiceAccount":
			if has_invited_service_account:
				return AndroidEnums.StepStatus.SUCCESS
			return AndroidEnums.StepStatus.PENDING
	
	return AndroidEnums.StepStatus.PENDING
