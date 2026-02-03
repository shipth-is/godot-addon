## Job model for representing a build job

enum JobStatus {
	PENDING,
	PROCESSING,
	COMPLETED,
	FAILED
}

enum Platform {
	ANDROID,
	IOS
}

var id: String = ""
var type: Platform = Platform.ANDROID
var status: JobStatus = JobStatus.PENDING
var created_at: String = ""
var updated_at: String = ""
var details: Dictionary = {}
var project: Dictionary = {}
var upload: Dictionary = {}


func _init(
	id: String = "",
	type: Platform = Platform.ANDROID,
	status: JobStatus = JobStatus.PENDING,
	created_at: String = "",
	updated_at: String = "",
	details: Dictionary = {},
	project: Dictionary = {},
	upload: Dictionary = {}
) -> void:
	self.id = id
	self.type = type
	self.status = status
	self.created_at = created_at
	self.updated_at = updated_at
	self.details = details
	self.project = project
	self.upload = upload


func status_name() -> String:
	match status:
		JobStatus.PENDING: return "PENDING"
		JobStatus.PROCESSING: return "PROCESSING"
		JobStatus.COMPLETED: return "COMPLETED"
		JobStatus.FAILED: return "FAILED"
		_: return "UNKNOWN"


func platform_name() -> String:
	match type:
		Platform.ANDROID: return "ANDROID"
		Platform.IOS: return "IOS"
		_: return "UNKNOWN"


func to_dict() -> Dictionary:
	return {
		"id": id,
		"type": platform_name(),
		"status": status_name(),
		"createdAt": created_at,
		"updatedAt": updated_at,
		"details": details,
		"project": project,
		"upload": upload
	}


static func _parse_status(status_str: String) -> JobStatus:
	match status_str:
		"PENDING": return JobStatus.PENDING
		"PROCESSING": return JobStatus.PROCESSING
		"COMPLETED": return JobStatus.COMPLETED
		"FAILED": return JobStatus.FAILED
		_: return JobStatus.PENDING


static func _parse_platform(platform_str: String) -> Platform:
	match platform_str:
		"ANDROID": return Platform.ANDROID
		"IOS": return Platform.IOS
		_: return Platform.ANDROID


static func from_dict(data: Dictionary):
	return load("res://addons/shipthis/models/job.gd").new(
		data.get("id", ""),
		_parse_platform(data.get("type", "ANDROID")),
		_parse_status(data.get("status", "PENDING")),
		data.get("createdAt", ""),
		data.get("updatedAt", ""),
		data.get("details", {}),
		data.get("project", {}),
		data.get("upload", {})
	)
