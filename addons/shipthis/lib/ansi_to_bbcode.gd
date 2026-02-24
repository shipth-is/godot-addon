## ANSI to BBCode converter for RichTextLabel display
##
## Converts ANSI escape sequences into BBCode that Godot's RichTextLabel can
## render. This is the inverse of the BBCode-to-ANSI approach.
##
## Inspired by Hugo Locurcio's (Calinou) BBCode-to-ANSI converter:
## https://github.com/Calinou/godot-bbcode-to-ansi
##
## Thanks Calinou for the original work that made this possible!

const TAB_SPACES := "    "  # 4 spaces for terminal-style table alignment

## Converts ANSI escape sequences to BBCode with balanced tags.
## Tracks open/close state to prevent orphaned closing tags.
static func convert(p_ansi: String) -> String:
	# State tracking
	var color_open := false
	var bold_open := false
	
	# Find all ANSI escape sequences
	var regex := RegEx.new()
	regex.compile("\u001b\\[([0-9;]*)([A-Za-z])")
	
	var result := ""
	var last_end := 0
	
	for match in regex.search_all(p_ansi):
		# Append text before this escape sequence
		result += p_ansi.substr(last_end, match.get_start() - last_end)
		last_end = match.get_end()
		
		var params := match.get_string(1)  # e.g., "1;32" or "0" or "39"
		var command := match.get_string(2)  # e.g., "m"
		
		# Only handle SGR (Select Graphic Rendition) commands
		if command != "m":
			continue
		
		# Parse the parameters
		var code := params if params != "" else "0"
		
		# Handle the ANSI code
		match code:
			# Reset all - close in reverse order (inner tags first)
			"0":
				if color_open:
					result += "[/color]"
					color_open = false
				if bold_open:
					result += "[/b]"
					bold_open = false
			
			# Bold on
			"1":
				if not bold_open:
					result += "[b]"
					bold_open = true
			
			# Dim/faint - treat as gray color
			"2":
				if color_open:
					result += "[/color]"
				result += "[color=gray]"
				color_open = true
			
			# Bold off
			"22":
				if bold_open:
					result += "[/b]"
					bold_open = false
			
			# Standard colors (30-37)
			"30":
				if color_open: result += "[/color]"
				result += "[color=black]"
				color_open = true
			"31":
				if color_open: result += "[/color]"
				result += "[color=red]"
				color_open = true
			"32":
				if color_open: result += "[/color]"
				result += "[color=green]"
				color_open = true
			"33":
				if color_open: result += "[/color]"
				result += "[color=yellow]"
				color_open = true
			"34":
				if color_open: result += "[/color]"
				result += "[color=blue]"
				color_open = true
			"35":
				if color_open: result += "[/color]"
				result += "[color=magenta]"
				color_open = true
			"36":
				if color_open: result += "[/color]"
				result += "[color=cyan]"
				color_open = true
			"37":
				if color_open: result += "[/color]"
				result += "[color=white]"
				color_open = true
			
			# Reset foreground color
			"39":
				if color_open:
					result += "[/color]"
					color_open = false
			
			# Bright colors (90-97)
			"90":
				if color_open: result += "[/color]"
				result += "[color=gray]"
				color_open = true
			"91":
				if color_open: result += "[/color]"
				result += "[color=red]"
				color_open = true
			"92":
				if color_open: result += "[/color]"
				result += "[color=green]"
				color_open = true
			"93":
				if color_open: result += "[/color]"
				result += "[color=yellow]"
				color_open = true
			"94":
				if color_open: result += "[/color]"
				result += "[color=blue]"
				color_open = true
			"95":
				if color_open: result += "[/color]"
				result += "[color=magenta]"
				color_open = true
			"96":
				if color_open: result += "[/color]"
				result += "[color=cyan]"
				color_open = true
			"97":
				if color_open: result += "[/color]"
				result += "[color=white]"
				color_open = true
			
			# Combined codes (e.g., "1;32" for bold green)
			"1;30", "1;90":
				if color_open: result += "[/color]"
				if not bold_open: result += "[b]"
				result += "[color=black]" if code == "1;30" else "[color=gray]"
				color_open = true
				bold_open = true
			"1;31", "1;91":
				if color_open: result += "[/color]"
				if not bold_open: result += "[b]"
				result += "[color=red]"
				color_open = true
				bold_open = true
			"1;32", "1;92":
				if color_open: result += "[/color]"
				if not bold_open: result += "[b]"
				result += "[color=green]"
				color_open = true
				bold_open = true
			"1;33", "1;93":
				if color_open: result += "[/color]"
				if not bold_open: result += "[b]"
				result += "[color=yellow]"
				color_open = true
				bold_open = true
			"1;34", "1;94":
				if color_open: result += "[/color]"
				if not bold_open: result += "[b]"
				result += "[color=blue]"
				color_open = true
				bold_open = true
			"1;35", "1;95":
				if color_open: result += "[/color]"
				if not bold_open: result += "[b]"
				result += "[color=magenta]"
				color_open = true
				bold_open = true
			"1;36", "1;96":
				if color_open: result += "[/color]"
				if not bold_open: result += "[b]"
				result += "[color=cyan]"
				color_open = true
				bold_open = true
			"1;37", "1;97":
				if color_open: result += "[/color]"
				if not bold_open: result += "[b]"
				result += "[color=white]"
				color_open = true
				bold_open = true
	
	# Append any remaining text after the last escape sequence
	result += p_ansi.substr(last_end)
	
	# Close any remaining open tags (inner tags first)
	if color_open:
		result += "[/color]"
	if bold_open:
		result += "[/b]"

	# Normalize tabs so ASCII-art tables (e.g. fastlane summary) align in RichTextLabel
	result = result.replace("\t", TAB_SPACES)

	return result
