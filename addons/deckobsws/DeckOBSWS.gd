extends Node

const Authenticator := preload("res://addons/deckobsws/Authenticator.gd")

var _ws: WebSocketPeer

const WS_URL := "127.0.0.1:%s"

signal _auth_required()


func connect_to_obsws(port: int, password: String = "") -> void:
	_ws = WebSocketPeer.new()
	_ws.connect_to_url(WS_URL % port)
	_auth_required.connect(_authenticate.bind(password))


func _process(_delta: float) -> void:
	if is_instance_valid(_ws):
		_poll_socket()


func _poll_socket() -> void:
	_ws.poll()

	var state = _ws.get_ready_state()
	match state:
		WebSocketPeer.STATE_OPEN:
			while _ws.get_available_packet_count():
				_handle_packet(_ws.get_packet())
		WebSocketPeer.STATE_CLOSING:
			pass
		WebSocketPeer.STATE_CLOSED:
			print("closed, ", _ws.get_close_code())
			print("closed, ", _ws.get_close_reason())
			_ws = null


func _handle_packet(packet: PackedByteArray) -> void:
	var message = Message.from_json(packet.get_string_from_utf8())
	print("got message with code ", message.op_code)
	_handle_message(message)


func _handle_message(message: Message) -> void:
	print(message)
	match message.op_code:
		# authenticate
		0:
			_auth_required.emit(message)


func _authenticate(message: Message, password: String) -> void:
	var authenticator = Authenticator.new(
		password,
		message.authentication.challenge,
		message.authentication.salt,
	)
	var auth_string = authenticator.get_auth_string()
	var m = Message.new()
	m.op_code = 1
	m._d["authentication"] = auth_string
	print("MY RESPONSE: ")
	print(m)
	_ws.send_text(m.to_obsws_json())


class Message:
	var op_code: int
	var _d: Dictionary = {"rpc_version": 1}

	func _get(property: StringName):
		if property in _d:
			return _d[property]
		else:
			return null


	func _get_property_list() -> Array:
		var prop_list = []
		_d.keys().map(
			func(x):
				var d = {
					"name": x,
					"type": typeof(_d[x])
				}
				prop_list.append(d)
		)
		return prop_list


	func to_obsws_json() -> String:
		var data = {
			"op": op_code,
			"d": {}
		}

		data.d = snake_to_camel_recursive(_d)

		return JSON.stringify(data)


	func _to_string() -> String:
		return to_obsws_json()


	static func from_json(json: String) -> Message:
		var ev = Message.new()
		var dictified = JSON.parse_string(json)

		if dictified == null:
			return null

		dictified = dictified as Dictionary
		ev.op_code = dictified.get("op", -1)
		var data = dictified.get("d", null)
		if data == null:
			return null

		data = data as Dictionary
		ev._d = camel_to_snake_recursive(data)

		return ev


	static func camel_to_snake_recursive(d: Dictionary) -> Dictionary:
		var snaked = {}
		for prop in d:
			prop = prop as String
			if d[prop] is Dictionary:
				snaked[prop.to_snake_case()] = camel_to_snake_recursive(d[prop])
			else:
				snaked[prop.to_snake_case()] = d[prop]
		return snaked


	static func snake_to_camel_recursive(d: Dictionary) -> Dictionary:
		var cameled = {}
		for prop in d:
			prop = prop as String
			if d[prop] is Dictionary:
				cameled[prop.to_camel_case()] = snake_to_camel_recursive(d[prop])
			else:
				cameled[prop.to_camel_case()] = d[prop]
		return cameled
