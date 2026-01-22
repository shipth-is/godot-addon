## API client for ShipThis backend

var base_url: String = ""
var token: String = ""


func _init(config) -> void:
	base_url = config.api_url
	token = ""


func set_token(token_value: String) -> void:
	token = token_value


func get_headers(is_json: bool = false) -> Array[String]:
	var headers: Array[String] = []
	
	if is_json:
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
	
	var json_result = JSON.parse_string(json_string)
	if json_result == null:
		return "HTTP error: %d" % response_code
	
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
	
	var url: String = base_url + path
	var is_json: bool = body.size() > 0
	var headers: Array[String] = get_headers(is_json)
	var request_body: String = ""
	
	if body.size() > 0:
		request_body = JSON.stringify(body)
	
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
	
	var result: Dictionary = {
		"is_success": false,
		"data": {},
		"error": "",
		"code": response_code
	}
	
	if response_code < 200 or response_code >= 300:
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
