extends "res://addons/shipthis/models/self.gd"

## Self model with JWT token

var jwt: String = ""


func _init(
	created_at: String,
	details: UserDetails,
	email: String,
	id: String,
	updated_at: String,
	jwt: String
) -> void:
	super._init(created_at, details, email, id, updated_at)
	self.jwt = jwt


func to_dict() -> Dictionary:
	var result: Dictionary = super.to_dict()
	result["jwt"] = jwt
	return result


static func from_dict(data: Dictionary):
	const UserDetails = preload("res://addons/shipthis/models/user_details.gd")
	return load("res://addons/shipthis/models/self_with_jwt.gd").new(
		data.get("createdAt", ""),
		UserDetails.from_dict(data.get("details", {})),
		data.get("email", ""),
		data.get("id", ""),
		data.get("updatedAt", ""),
		data.get("jwt", "")
	)
