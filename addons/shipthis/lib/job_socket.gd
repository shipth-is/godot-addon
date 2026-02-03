## WebSocket manager for job progress tracking via Socket.IO
extends Node

const Job = preload("res://addons/shipthis/models/job.gd")
const JobLogEntry = preload("res://addons/shipthis/models/job_log_entry.gd")
const SocketIOScript = preload("res://addons/shipthis/third_party/godot-socketio/socketio.gd")

signal job_updated(job)
signal log_received(entry)
signal connection_status_changed(connected: bool, message: String)

var _socket = null
var _project_id: String = ""
var _job_id: String = ""
var _subscribed_events: Array[String] = []
var _logger: Callable = Callable()  # Optional logger for UI output


func set_logger(logger: Callable) -> void:
	_logger = logger


func _debug(message: String) -> void:
	var formatted = "[WS] %s" % message
	print(formatted)  # Always print to console
	if _logger.is_valid():
		_logger.call(formatted)


func connect_to_server(ws_url: String, token: String) -> void:
	if _socket != null:
		_debug("Socket already exists, disconnecting first")
		disconnect_socket()
	
	# Create the SocketIO node
	_socket = SocketIOScript.new()
	_socket.autoconnect = false
	
	# Convert wss:// URL to https:// for the base_url (EngineIO handles the conversion)
	var base_url = ws_url
	if base_url.begins_with("wss://"):
		base_url = base_url.replace("wss://", "https://")
	elif base_url.begins_with("ws://"):
		base_url = base_url.replace("ws://", "http://")
	
	_socket.base_url = base_url
	_debug("Connecting to %s" % base_url)
	
	# Add to tree so it can process
	add_child(_socket)
	
	# Connect signals
	_socket.socket_connected.connect(_on_socket_connected)
	_socket.socket_disconnected.connect(_on_socket_disconnected)
	_socket.namespace_connection_error.connect(_on_connection_error)
	_socket.event_received.connect(_on_event_received)
	
	connection_status_changed.emit(false, "Connecting...")
	
	# Connect with auth token
	_debug("Authenticating with token...")
	_socket.connect_socket({"token": token})


func subscribe_to_job(project_id: String, job_id: String) -> void:
	_project_id = project_id
	_job_id = job_id
	
	# Build the event patterns we want to listen for
	_subscribed_events.clear()
	_subscribed_events.append("project.%s:job:created" % project_id)
	_subscribed_events.append("project.%s:job:updated" % project_id)
	_subscribed_events.append("project.%s:job.%s:log" % [project_id, job_id])
	
	_debug("Subscribed to events:")
	for event_pattern in _subscribed_events:
		_debug("  - %s" % event_pattern)


func disconnect_socket() -> void:
	_debug("Disconnecting socket...")
	if _socket != null:
		_socket.disconnect_socket()
		_socket.queue_free()
		_socket = null
	
	_subscribed_events.clear()
	_project_id = ""
	_job_id = ""


func _on_socket_connected(ns: String) -> void:
	_debug("Connected to namespace: %s" % ns)
	connection_status_changed.emit(true, "Connected")


func _on_socket_disconnected() -> void:
	_debug("Socket disconnected")
	connection_status_changed.emit(false, "Disconnected")


func _on_connection_error(ns: String, data: Variant) -> void:
	_debug("Connection error on namespace %s: %s" % [ns, str(data)])
	connection_status_changed.emit(false, "Connection error")


func _on_event_received(event: String, data: Variant, _ns: String) -> void:
	# Check if this event matches any of our subscribed patterns
	if not event in _subscribed_events:
		return
	
	# Extract the actual data from the array (Socket.IO sends [data])
	var event_data = data
	if data is Array and data.size() > 0:
		event_data = data[0]
	
	if not event_data is Dictionary:
		push_warning("Received non-dictionary event data for %s" % event)
		return
	
	# Determine event type and emit appropriate signal
	if event.ends_with(":log"):
		var entry = JobLogEntry.from_dict(event_data)
		log_received.emit(entry)
	elif event.ends_with(":job:created") or event.ends_with(":job:updated"):
		# Check if this job matches our tracked job
		if event_data.get("id", "") == _job_id:
			var job = Job.from_dict(event_data)
			job_updated.emit(job)
