## High-level API methods for ShipThis backend

const ApiClient = preload("res://addons/shipthis/lib/api_client.gd")

var client: ApiClient = null


func _init() -> void:
	client = ApiClient.new()


func set_token(token: String) -> void:
	client.set_token(token)


## Low-level POST request passthrough for auth and other generic calls
func post(path: String, body: Dictionary = {}) -> Dictionary:
	return await client.post(path, body)


## Get an upload ticket for a project. Returns {is_success, data: {id, url}} on success.
func get_upload_ticket(project_id: String) -> Dictionary:
	return await client.post("/upload/%s/url" % project_id, {})


## Start jobs for an uploaded file. Returns {is_success, data: Job[]} on success.
func start_jobs(upload_ticket_id: String) -> Dictionary:
	return await client.post("/upload/start/%s" % upload_ticket_id, {})
