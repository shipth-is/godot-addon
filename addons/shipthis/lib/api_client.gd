## API client for ShipThis backend

const PRIMARY_DOMAIN = "shipth.is"

var domain: String = ""
var api_url: String = ""
var web_url: String = ""
var ws_url: String = ""

var token: String = ""


func _init() -> void:
	domain = ProjectSettings.get_setting(
		"addons/shipthis/domain",
		PRIMARY_DOMAIN
	)

	var is_public: bool = domain.contains(PRIMARY_DOMAIN)
	var api_domain: String = ("api." if is_public else "") + domain
	var ws_domain: String = ("ws." if is_public else "") + domain
	
	api_url =  "https://%s/api/1.0.0" % api_domain
	web_url =  "https://%s/" % domain
	ws_url = "wss://%s" % ws_domain

	token = ""


func set_token(token_value: String) -> void:
	token = token_value
	print("[API] Token set: %s..." % token.substr(0, 20) if token.length() > 20 else "[API] Token set: (empty or short)")


func get_headers() -> Array[String]:
	var headers: Array[String] = []
	
	headers.append("Content-Type: application/json")
	
	if token != "":
		headers.append("Authorization: Bearer %s" % token)
	
	return headers


func _parse_error_message(response_code: int, body_data: PackedByteArray) -> String:
	# Try to parse the response body for error details
	if body_data == null or body_data.size() == 0:
		return "HTTP error: %d" % response_code
	
	var json_string: String = body_data.get_string_from_utf8()
	if json_string == "":
		return "HTTP error: %d" % response_code
	
	# Use JSON.new() to avoid noisy error logging when response isn't JSON
	var json = JSON.new()
	if json.parse(json_string) != OK:
		return "HTTP error: %d" % response_code
	var json_result = json.data
	
	# Handle array of validation errors (Zod format)
	if json_result is Array:
		var messages: Array[String] = []
		for item in json_result:
			if item is Dictionary and item.has("message"):
				messages.append(item.message)
		if messages.size() > 0:
			return " ".join(messages)
	
	# Handle object with error field
	if json_result is Dictionary and json_result.has("error"):
		return json_result.error
	
	return "HTTP error: %d" % response_code


func _make_request(method: HTTPClient.Method, path: String, body: Dictionary = {}) -> Dictionary:
	var http := HTTPRequest.new()
	var tree := Engine.get_main_loop() as SceneTree
	tree.root.add_child(http)
	
	var url: String = api_url + path
	var headers: Array[String] = get_headers()
	var request_body: String = ""
	
	if body.size() > 0:
		request_body = JSON.stringify(body)
	
	var method_name = ["GET", "HEAD", "POST", "PUT", "DELETE", "OPTIONS", "TRACE", "CONNECT", "PATCH"][method]
	print("[API] %s %s" % [method_name, url])
	print("[API] Token present: %s" % (token != ""))
	
	var err := http.request(url, headers, method, request_body)
	
	if err != OK:
		http.queue_free()
		return {
			"is_success": false,
			"data": {},
			"error": "Please check your internet connection.",
			"code": 0
		}
	
	var response = await http.request_completed
	var response_code: int = response[1]
	var body_data: PackedByteArray = response[3]
	
	http.queue_free()
	
	print("[API] Response: %d" % response_code)
	
	var result: Dictionary = {
		"is_success": false,
		"data": {},
		"error": "",
		"code": response_code
	}
	
	if response_code < 200 or response_code >= 300:
		var raw_body = body_data.get_string_from_utf8() if body_data != null else "(null)"
		print("[API] Error body: %s" % raw_body)
		result.error = _parse_error_message(response_code, body_data)
		return result
	
	if body_data == null or body_data.size() == 0:
		result.is_success = true
		return result
	
	var json_string: String = body_data.get_string_from_utf8()
	if json_string == "":
		result.is_success = true
		return result
	
	var json_result = JSON.parse_string(json_string)
	if json_result == null:
		result.error = "Failed to parse JSON response"
		return result
	
	result.is_success = true
	result.data = json_result
	return result


func fetch(path: String) -> Dictionary:
	return await _make_request(HTTPClient.METHOD_GET, path)


func post(path: String, body: Dictionary = {}) -> Dictionary:
	return await _make_request(HTTPClient.METHOD_POST, path, body)


func put(path: String, body: Dictionary = {}) -> Dictionary:
	return await _make_request(HTTPClient.METHOD_PUT, path, body)


func delete(path: String) -> Dictionary:
	return await _make_request(HTTPClient.METHOD_DELETE, path)
