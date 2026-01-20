## API client for ShipThis backend

var base_url = ""
var token = ""


func _init(config):
	base_url = config.api_url
	token = ""


func set_token(token_value: String) -> void:
	token = token_value


func get_headers(include_content_type: bool = false) -> Array[String]:
	var headers: Array[String] = []
	
	if include_content_type:
		headers.append("Content-Type: application/json")
	
	if token != "":
		headers.append("Authorization: Bearer %s" % token)
	
	return headers


func _make_request(method: HTTPClient.Method, path: String, body: Dictionary = {}) -> Dictionary:
	var http := HTTPRequest.new()
	var tree := Engine.get_main_loop() as SceneTree
	tree.root.add_child(http)
	
	var url = base_url + path
	var headers = get_headers(body.size() > 0)
	var request_body = ""
	
	if body.size() > 0:
		request_body = JSON.stringify(body)
	
	var err = http.request(url, headers, method, request_body)
	
	if err != OK:
		http.queue_free()
		return {
			"success": false,
			"data": {},
			"error": "Failed to create request: error code %d" % err,
			"code": 0
		}
	
	var response = await http.request_completed
	var code = response[1]
	var response_headers = response[2]
	var body_data = response[3]
	
	http.queue_free()
	
	var result = {
		"success": false,
		"data": {},
		"error": "",
		"code": code
	}
	
	if code < 200 or code >= 300:
		result.error = "HTTP error: %d" % code
		return result
	
	if body_data == null or body_data.size() == 0:
		result.success = true
		return result
	
	var json_string = body_data.get_string_from_utf8()
	if json_string == "":
		result.success = true
		return result
	
	var json_result = JSON.parse_string(json_string)
	if json_result == null:
		result.error = "Failed to parse JSON response"
		return result
	
	result.success = true
	result.data = json_result
	return result


func api_get(path: String) -> Dictionary:
	return await _make_request(HTTPClient.METHOD_GET, path)


func post(path: String, body: Dictionary = {}) -> Dictionary:
	return await _make_request(HTTPClient.METHOD_POST, path, body)


func put(path: String, body: Dictionary = {}) -> Dictionary:
	return await _make_request(HTTPClient.METHOD_PUT, path, body)


func delete(path: String) -> Dictionary:
	return await _make_request(HTTPClient.METHOD_DELETE, path)

