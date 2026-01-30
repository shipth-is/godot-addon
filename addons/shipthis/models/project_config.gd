## Project config for storing project settings

var ignored_files_globs: PackedStringArray = []
var project_id: String = ""
var shipped_files_globs: PackedStringArray = []


func _init(
	ignored_files_globs: PackedStringArray = [],
	project_id: String = "",
	shipped_files_globs: PackedStringArray = []
) -> void:
	self.ignored_files_globs = ignored_files_globs
	self.project_id = project_id
	self.shipped_files_globs = shipped_files_globs


func to_dict() -> Dictionary:
	var result: Dictionary = {}
	if ignored_files_globs.size() > 0:
		result["ignoredFilesGlobs"] = Array(ignored_files_globs)
	if project_id != "":
		result["project"] = { "id": project_id }
	if shipped_files_globs.size() > 0:
		result["shippedFilesGlobs"] = Array(shipped_files_globs)
	return result


static func from_dict(data: Dictionary):
	var project_config = load("res://addons/shipthis/models/project_config.gd").new()
	
	if data.has("ignoredFilesGlobs") and data["ignoredFilesGlobs"] is Array:
		project_config.ignored_files_globs = PackedStringArray(data["ignoredFilesGlobs"])
	
	if data.has("project") and data["project"] is Dictionary:
		var project_data: Dictionary = data["project"]
		if project_data.has("id"):
			project_config.project_id = project_data["id"]
	
	if data.has("shippedFilesGlobs") and data["shippedFilesGlobs"] is Array:
		project_config.shipped_files_globs = PackedStringArray(data["shippedFilesGlobs"])
	
	return project_config
