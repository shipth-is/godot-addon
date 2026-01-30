## Glob utilities for file matching and directory walking


## Convert a glob pattern to a regex pattern
## Supports: * (any chars except /), ** (any path depth), ? (single char)
func glob_to_regex(pattern: String) -> String:
	var regex_str := "^"
	var i := 0
	while i < pattern.length():
		var c := pattern[i]
		if c == "*":
			if i + 1 < pattern.length() and pattern[i + 1] == "*":
				# ** matches any path depth
				if i + 2 < pattern.length() and pattern[i + 2] == "/":
					regex_str += "(?:.*/)?"; i += 3
				else:
					regex_str += ".*"; i += 2
			else:
				regex_str += "[^/]*"; i += 1
		elif c == "?":
			regex_str += "[^/]"; i += 1
		elif c in [".", "(", ")", "[", "]", "{", "}", "+", "^", "$", "|", "\\"]:
			regex_str += "\\" + c; i += 1
		else:
			regex_str += c; i += 1
	return regex_str + "$"


## Recursively find all files starting from base directory
func find_files(base: String, out := []) -> Array:
	var dir := DirAccess.open(base)
	if dir == null:
		return out
	
	dir.list_dir_begin()
	var name := dir.get_next()
	
	while name != "":
		if name != "." and name != "..":
			var path := base.path_join(name)
			if dir.current_is_dir():
				find_files(path, out)
			else:
				out.append(path)
		name = dir.get_next()
	
	dir.list_dir_end()
	return out


## Collect files matching shipped globs, excluding ignored globs
func collect_files(shipped_globs: PackedStringArray, ignored_globs: PackedStringArray) -> Array:
	var all_files := find_files("res://")
	var matched := []
	
	# Convert globs to regex patterns
	var shipped_patterns := []
	for glob in shipped_globs:
		var regex := RegEx.new()
		var regex_str := glob_to_regex(glob)
		regex.compile(regex_str)
		shipped_patterns.append(regex)
	
	var ignored_patterns := []
	for glob in ignored_globs:
		var regex := RegEx.new()
		var regex_str := glob_to_regex(glob)
		regex.compile(regex_str)
		ignored_patterns.append(regex)
	
	# Filter files
	for file_path in all_files:
		var rel_path: String = file_path.trim_prefix("res://")
		
		# Check if matches any shipped pattern
		var is_shipped := false
		for pattern in shipped_patterns:
			if pattern.search(rel_path):
				is_shipped = true
				break
		
		if not is_shipped:
			continue
		
		# Check if matches any ignored pattern
		var is_ignored := false
		for pattern in ignored_patterns:
			if pattern.search(rel_path):
				is_ignored = true
				break
		
		if not is_ignored:
			matched.append(file_path)
	
	return matched
