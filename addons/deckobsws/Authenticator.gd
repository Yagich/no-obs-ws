extends RefCounted

# The result of the authentication string creation process. Use getter for public access.
var _auth_string: String:
	get = get_auth_string


func _init(password: String, challenge: String, salt: String) -> void:
	var salted := password + salt
	var base64_secret := Marshalls.raw_to_base64(salted.sha256_buffer())
	var b64_secret_plus_challenge = base64_secret + challenge
	_auth_string = Marshalls.raw_to_base64(b64_secret_plus_challenge.sha256_buffer())


func get_auth_string() -> String:
	return _auth_string
