## Module for running the ship process

const Glob = preload("res://addons/shipthis/lib/glob.gd")
const Zip = preload("res://addons/shipthis/lib/zip.gd")
const Upload = preload("res://addons/shipthis/lib/upload.gd")
const Job = preload("res://addons/shipthis/models/job.gd")


## Returns Dictionary with {error: Error, job: Job or null}
func ship(config, api, logger: Callable, scene_tree: SceneTree) -> Dictionary:
	var project_config = config.get_project_config()
	
	logger.call("Finding files to include...")
	
	var glob = Glob.new()
	var files := glob.collect_files(
		project_config.shipped_files_globs,
		project_config.ignored_files_globs
	)
	
	logger.call("Found %d files" % files.size())
	
	# Create zip archive
	var zip_path := "user://shipthis_upload.zip"
	logger.call("Creating zip archive...")
	
	var zipper = Zip.new()
	var err := await zipper.create_zip(files, zip_path, func(p: Dictionary):
		logger.call("Zipping: %.0f%%" % [float(p.current) / p.total * 100])
	, scene_tree)
	
	if err != OK:
		logger.call("Failed to create zip: %s" % error_string(err))
		return {"error": err, "job": null}
	
	logger.call("Zip created successfully at: %s" % zip_path)
	
	# Get upload ticket
	logger.call("Requesting upload ticket...")
	var ticket_response: Dictionary = await api.get_upload_ticket(project_config.project_id)
	
	if not ticket_response.is_success:
		logger.call("Failed to get upload ticket: %s" % ticket_response.error)
		return {"error": ERR_CANT_CONNECT, "job": null}
	
	var upload_url: String = ticket_response.data.url
	
	# Upload zip file
	logger.call("Uploading...")
	
	var uploader = Upload.new()
	err = await uploader.upload_file(upload_url, zip_path, func(p: Dictionary):
		logger.call("Uploading: %.0f%% (%.1f MB/s)" % [p.progress * 100, p.speed_mbps])
	, scene_tree)
	
	if err != OK:
		logger.call("Failed to upload: %s" % error_string(err))
		return {"error": err, "job": null}
	
	logger.call("Upload complete!")
	
	# Start build jobs
	logger.call("Starting build jobs...")
	var start_response: Dictionary = await api.start_jobs(ticket_response.data.id)
	
	if not start_response.is_success:
		logger.call("Failed to start jobs: %s" % start_response.error)
		return {"error": ERR_CANT_CREATE, "job": null}
	
	# Parse the first job from the response array
	var job = Job.from_dict(start_response.data[0])
	
	logger.call("Jobs started successfully!")
	return {"error": OK, "job": job}
