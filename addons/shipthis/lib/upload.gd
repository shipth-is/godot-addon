## Upload utilities for HTTP PUT with real progress tracking via StreamPeerTCP

const CHUNK_SIZE := 65536  # 64KB chunks
const PROGRESS_THROTTLE_MS := 100  # Max 10 progress updates per second


## Uploads a file via HTTP PUT with progress reporting.
## Progress info dictionary contains: progress, sent_bytes, total_bytes,
## elapsed_seconds, speed_mbps
func upload_file(
	url: String,
	file_path: String,
	on_progress: Callable,  # func(progress_info: Dictionary)
	scene_tree: SceneTree
) -> Error:
	var start_time := Time.get_ticks_msec()
	
	# Parse URL
	var url_parts := _parse_url(url)
	if url_parts.is_empty():
		return ERR_INVALID_PARAMETER
	
	# Open file
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return ERR_FILE_NOT_FOUND
	
	var total_bytes := file.get_length()
	
	# Connect TCP
	var tcp := StreamPeerTCP.new()
	var err := tcp.connect_to_host(url_parts.host, url_parts.port)
	if err != OK:
		file.close()
		return ERR_CANT_CONNECT
	
	# Wait for connection
	while tcp.get_status() == StreamPeerTCP.STATUS_CONNECTING:
		tcp.poll()
		await scene_tree.process_frame
	
	if tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		file.close()
		return ERR_CANT_CONNECT
	
	# Get the stream (TCP or TLS)
	var stream: StreamPeer = tcp
	var tls: StreamPeerTLS = null
	
	# TLS handshake for HTTPS
	if url_parts.is_https:
		tls = StreamPeerTLS.new()
		err = tls.connect_to_stream(tcp, url_parts.host)
		if err != OK:
			file.close()
			tcp.disconnect_from_host()
			return ERR_CONNECTION_ERROR
		
		while tls.get_status() == StreamPeerTLS.STATUS_HANDSHAKING:
			tls.poll()
			await scene_tree.process_frame
		
		if tls.get_status() != StreamPeerTLS.STATUS_CONNECTED:
			file.close()
			tcp.disconnect_from_host()
			return ERR_CONNECTION_ERROR
		
		stream = tls
	
	# Send HTTP headers
	var headers := "PUT %s HTTP/1.1\r\n" % url_parts.path
	headers += "Host: %s\r\n" % url_parts.host
	headers += "Content-Type: application/octet-stream\r\n"
	headers += "Content-Length: %d\r\n" % total_bytes
	headers += "Connection: close\r\n"
	headers += "\r\n"
	
	var header_bytes := headers.to_utf8_buffer()
	err = stream.put_data(header_bytes)
	if err != OK:
		file.close()
		tcp.disconnect_from_host()
		return ERR_CONNECTION_ERROR
	
	# Send body in chunks with progress
	var sent_bytes := 0
	var last_progress_time := 0
	
	while sent_bytes < total_bytes:
		# Poll TLS to process any pending data
		if tls != null:
			tls.poll()
		
		var remaining := total_bytes - sent_bytes
		var chunk_size := mini(CHUNK_SIZE, remaining)
		var chunk := file.get_buffer(chunk_size)
		
		if chunk.size() == 0:
			break
		
		var result := stream.put_partial_data(chunk)
		if result[0] != OK:
			file.close()
			tcp.disconnect_from_host()
			return ERR_CONNECTION_ERROR
		
		var bytes_written: int = result[1]
		sent_bytes += bytes_written
		
		# If partial write, seek back in file for remaining data
		if bytes_written < chunk.size():
			file.seek(file.get_position() - (chunk.size() - bytes_written))
		
		# Throttled progress reporting
		var now := Time.get_ticks_msec()
		if now - last_progress_time >= PROGRESS_THROTTLE_MS:
			last_progress_time = now
			var elapsed_seconds := (now - start_time) / 1000.0
			var speed_mbps := 0.0 if elapsed_seconds < 0.001 else sent_bytes / elapsed_seconds / 1024.0 / 1024.0
			
			on_progress.call({
				"progress": float(sent_bytes) / total_bytes,
				"sent_bytes": sent_bytes,
				"total_bytes": total_bytes,
				"elapsed_seconds": elapsed_seconds,
				"speed_mbps": speed_mbps,
			})
			
			await scene_tree.process_frame  # Let UI update
	
	file.close()
	
	# Final progress (100%)
	var elapsed_seconds := (Time.get_ticks_msec() - start_time) / 1000.0
	on_progress.call({
		"progress": 1.0,
		"sent_bytes": sent_bytes,
		"total_bytes": total_bytes,
		"elapsed_seconds": elapsed_seconds,
		"speed_mbps": sent_bytes / elapsed_seconds / 1024.0 / 1024.0 if elapsed_seconds > 0.001 else 0.0,
	})
	
	# Read response
	var response := await _read_response(stream, tls, scene_tree)
	tcp.disconnect_from_host()
	
	if response.code >= 200 and response.code < 300:
		return OK
	else:
		return ERR_QUERY_FAILED


## Parses a URL into its components.
## Returns: {host, port, path, is_https} or empty dict on error
func _parse_url(url: String) -> Dictionary:
	var is_https := url.begins_with("https://")
	var is_http := url.begins_with("http://")
	
	if not is_https and not is_http:
		return {}
	
	# Remove protocol
	var remainder := url.substr(8 if is_https else 7)
	
	# Split path from host
	var path_start := remainder.find("/")
	var host_port: String
	var path: String
	
	if path_start == -1:
		host_port = remainder
		path = "/"
	else:
		host_port = remainder.substr(0, path_start)
		path = remainder.substr(path_start)
	
	# Split port from host
	var port_start := host_port.rfind(":")
	var host: String
	var port: int
	
	if port_start == -1:
		host = host_port
		port = 443 if is_https else 80
	else:
		host = host_port.substr(0, port_start)
		port = host_port.substr(port_start + 1).to_int()
	
	return {
		"host": host,
		"port": port,
		"path": path,
		"is_https": is_https,
	}


## Reads the HTTP response from the stream.
## Returns: {code, headers, body}
func _read_response(stream: StreamPeer, tls: StreamPeerTLS, scene_tree: SceneTree) -> Dictionary:
	var response_data := PackedByteArray()
	var timeout_start := Time.get_ticks_msec()
	var timeout_ms := 30000  # 30 second timeout
	
	# Read until we have the full response or timeout
	while Time.get_ticks_msec() - timeout_start < timeout_ms:
		# Poll TLS to process incoming encrypted data
		if tls != null:
			tls.poll()
		
		var available := stream.get_available_bytes()
		if available > 0:
			var chunk := stream.get_data(available)
			if chunk[0] == OK:
				response_data.append_array(chunk[1])
		else:
			# Check if we have a complete response (ends with body or connection closed)
			var response_str := response_data.get_string_from_utf8()
			if response_str.contains("\r\n\r\n"):
				# We have at least headers, check if body is complete
				# For simplicity, we'll just return what we have after a short wait
				await scene_tree.process_frame
				if tls != null:
					tls.poll()
				await scene_tree.process_frame
				if tls != null:
					tls.poll()
				# Try one more read
				available = stream.get_available_bytes()
				if available > 0:
					var chunk := stream.get_data(available)
					if chunk[0] == OK:
						response_data.append_array(chunk[1])
				break
		
		await scene_tree.process_frame
	
	# Parse response
	var response_str := response_data.get_string_from_utf8()
	var header_end := response_str.find("\r\n\r\n")
	
	if header_end == -1:
		return {"code": 0, "headers": {}, "body": ""}
	
	var header_section := response_str.substr(0, header_end)
	var body := response_str.substr(header_end + 4)
	
	# Parse status line
	var lines := header_section.split("\r\n")
	if lines.size() == 0:
		return {"code": 0, "headers": {}, "body": body}
	
	var status_line := lines[0]
	var status_parts := status_line.split(" ")
	var code := 0
	if status_parts.size() >= 2:
		code = status_parts[1].to_int()
	
	# Parse headers
	var headers := {}
	for i in range(1, lines.size()):
		var colon := lines[i].find(":")
		if colon != -1:
			var key := lines[i].substr(0, colon).strip_edges()
			var value := lines[i].substr(colon + 1).strip_edges()
			headers[key] = value
	
	return {"code": code, "headers": headers, "body": body}
