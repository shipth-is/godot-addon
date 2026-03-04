@tool
extends LineEdit

## LineEdit that emits [signal submitted] when the user presses Enter (or Keypad Enter).
## Handles Enter in gui_input so it works in editor docks where the editor may consume the key.
## Also forwards the built-in text_submitted signal so callers can connect only to [signal submitted].

signal submitted(text: String)


func _ready() -> void:
	gui_input.connect(_on_gui_input)
	text_submitted.connect(_on_text_submitted)


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER):
		accept_event()
		submitted.emit(text)


func _on_text_submitted(submitted_text: String) -> void:
	submitted.emit(submitted_text)
