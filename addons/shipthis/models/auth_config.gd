## Auth config for storing authentication state

const SelfWithJWT = preload("res://addons/shipthis/models/self_with_jwt.gd")

var apple_cookies = {}
var ship_this_user: SelfWithJWT = null


func _init(
	apple_cookies: Dictionary = {},
	ship_this_user: SelfWithJWT = null
) -> void:
	self.apple_cookies = apple_cookies
	self.ship_this_user = ship_this_user


func to_dict() -> Dictionary:
	var result = {}
	if apple_cookies.size() > 0:
		result["appleCookies"] = apple_cookies
	if ship_this_user != null:
		result["shipThisUser"] = ship_this_user.to_dict()
	return result


static func from_dict(data: Dictionary):
	var config = load("res://addons/shipthis/models/auth_config.gd").new()
	
	if data.has("appleCookies"):
		config.apple_cookies = data["appleCookies"]
	
	if data.has("shipThisUser"):
		config.ship_this_user = SelfWithJWT.from_dict(data["shipThisUser"])
	
	return config

