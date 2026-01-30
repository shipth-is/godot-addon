## Zip utilities for creating archives with progress reporting

const PROGRESS_THROTTLE_MS := 100  # Max 10 progress updates per second


## Creates a zip file from an array of file paths with throttled progress reporting.
## Progress info dictionary contains: current (file index), total (file count)
func create_zip(
	files: Array,
	output_path: String,
	on_progress: Callable,  # func(progress_info: Dictionary)
	scene_tree: SceneTree  # Required for cooperative yielding
) -> Error:
	var zip := ZIPPacker.new()
	var err := zip.open(output_path)
	if err != OK:
		return err
	
	var total := files.size()
	var current := 0
	var last_progress_time := 0
	
	for file_path in files:
		var file := FileAccess.open(file_path, FileAccess.READ)
		if file == null:
			continue
		
		var content := file.get_buffer(file.get_length())
		file.close()
		
		# Use relative path in zip
		var zip_path: String = file_path.trim_prefix("res://")
		
		zip.start_file(zip_path)
		zip.write_file(content)
		zip.close_file()
		
		current += 1
		
		# Throttled progress reporting
		var now := Time.get_ticks_msec()
		if now - last_progress_time >= PROGRESS_THROTTLE_MS:
			last_progress_time = now
			on_progress.call({"current": current, "total": total})
		
		await scene_tree.process_frame
	
	# Final progress (100%)
	on_progress.call({"current": total, "total": total})
	
	zip.close()
	return OK
