## Job log entry model for representing log messages from a job

enum LogLevel {
	INFO,
	WARN,
	ERROR
}

enum JobStage {
	SETUP,
	CONFIGURE,
	BUILD,
	EXPORT,
	PUBLISH
}

var id: String = ""
var job_id: String = ""
var message: String = ""
var level: LogLevel = LogLevel.INFO
var stage: JobStage = JobStage.SETUP
var progress: float = -1.0  # -1 means not set
var sequence: int = 0
var created_at: String = ""
var sent_at: String = ""
var details: Dictionary = {}


func _init(
	id: String = "",
	job_id: String = "",
	message: String = "",
	level: LogLevel = LogLevel.INFO,
	stage: JobStage = JobStage.SETUP,
	progress: float = -1.0,
	sequence: int = 0,
	created_at: String = "",
	sent_at: String = "",
	details: Dictionary = {}
) -> void:
	self.id = id
	self.job_id = job_id
	self.message = message
	self.level = level
	self.stage = stage
	self.progress = progress
	self.sequence = sequence
	self.created_at = created_at
	self.sent_at = sent_at
	self.details = details


func level_name() -> String:
	match level:
		LogLevel.INFO: return "INFO"
		LogLevel.WARN: return "WARN"
		LogLevel.ERROR: return "ERROR"
		_: return "INFO"


func stage_name() -> String:
	match stage:
		JobStage.SETUP: return "SETUP"
		JobStage.CONFIGURE: return "CONFIGURE"
		JobStage.BUILD: return "BUILD"
		JobStage.EXPORT: return "EXPORT"
		JobStage.PUBLISH: return "PUBLISH"
		_: return "UNKNOWN"


func to_dict() -> Dictionary:
	var result: Dictionary = {
		"id": id,
		"jobId": job_id,
		"message": message,
		"level": level_name(),
		"stage": stage_name(),
		"sequence": sequence,
		"createdAt": created_at,
		"sentAt": sent_at,
		"details": details
	}
	if progress >= 0:
		result["progress"] = progress
	return result


static func _parse_level(level_str: String) -> LogLevel:
	match level_str:
		"INFO": return LogLevel.INFO
		"WARN": return LogLevel.WARN
		"ERROR": return LogLevel.ERROR
		_: return LogLevel.INFO


static func _parse_stage(stage_str: String) -> JobStage:
	match stage_str:
		"SETUP": return JobStage.SETUP
		"CONFIGURE": return JobStage.CONFIGURE
		"BUILD": return JobStage.BUILD
		"EXPORT": return JobStage.EXPORT
		"PUBLISH": return JobStage.PUBLISH
		_: return JobStage.SETUP


static func from_dict(data: Dictionary):
	return load("res://addons/shipthis/models/job_log_entry.gd").new(
		data.get("id", ""),
		data.get("jobId", ""),
		data.get("message", ""),
		_parse_level(data.get("level", "INFO")),
		_parse_stage(data.get("stage", "SETUP")),
		data.get("progress", -1.0),
		data.get("sequence", 0),
		data.get("createdAt", ""),
		data.get("sentAt", ""),
		data.get("details", {})
	)
