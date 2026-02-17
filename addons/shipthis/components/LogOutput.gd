@tool
extends RichTextLabel

## Reusable log output component with ANSI-to-BBCode conversion and
## color-coded job log entries.

const JobLogEntry = preload("res://addons/shipthis/models/job_log_entry.gd")
const AnsiToBBCode = preload("res://addons/shipthis/lib/ansi_to_bbcode.gd")


func log_message(message: String) -> void:
	append_text(message + "\n")


func log_with_color(message: String, color: Color) -> void:
	push_color(color)
	append_text(message)
	pop()


func log_entry(entry) -> void:
	var color = _get_level_color(entry.level)
	var prefix = "[%s/%s] " % [entry.stage_name(), entry.level_name()]
	log_with_color(prefix, color)
	append_text(AnsiToBBCode.convert(entry.message) + "\n")


func get_log_text() -> String:
	return get_parsed_text()


func _get_level_color(level: int) -> Color:
	match level:
		JobLogEntry.LogLevel.WARN: return Color.YELLOW
		JobLogEntry.LogLevel.ERROR: return Color.RED
		_: return Color.WHITE
