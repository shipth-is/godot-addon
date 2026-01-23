## Module for running the ship process

const Glob = preload("res://addons/shipthis/glob.gd")


func ship(config, logger: Callable) -> Error:
	var project_config = config.get_project_config()
	
	logger.call("Finding files to include...")
	
	var glob = Glob.new()
	var files := glob.collect_files(
		project_config.shipped_files_globs,
		project_config.ignored_files_globs,
		logger
	)
	
	logger.call("Found %d files" % files.size())
	
	# Files are now collected, ready for next steps
	return OK
