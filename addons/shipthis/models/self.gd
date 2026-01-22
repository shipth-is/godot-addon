## Self model with required fields

const UserDetails = preload("res://addons/shipthis/models/user_details.gd")

var created_at: String = ""
var details: UserDetails = null
var email: String = ""
var id: String = ""
var updated_at: String = ""


func _init(
	created_at: String,
	details: UserDetails,
	email: String,
	id: String,
	updated_at: String
) -> void:
	self.created_at = created_at
	self.details = details
	self.email = email
	self.id = id
	self.updated_at = updated_at


func to_dict() -> Dictionary:
	return {
		"createdAt": created_at,
		"details": details.to_dict() if details != null else {},
		"email": email,
		"id": id,
		"updatedAt": updated_at
	}


static func from_dict(data: Dictionary):
	return load("res://addons/shipthis/models/self.gd").new(
		data.get("createdAt", ""),
		UserDetails.from_dict(data.get("details", {})),
		data.get("email", ""),
		data.get("id", ""),
		data.get("updatedAt", "")
	)
