extends Node
class_name NoOBSWS

const Authenticator := preload("res://addons/no-obs-ws/Authenticator.gd")
const Enums := preload("res://addons/no-obs-ws/Utility/Enums.gd")

@export var subscriptions: Enums.EventSubscription = Enums.EventSubscription.ALL

var _ws: WebSocketPeer
# {request_id: RequestResponse}
var _requests: Dictionary = {}
var _batch_requests: Dictionary = {}

const WS_URL := "127.0.0.1:%s"

signal connection_ready()
signal connection_failed()
signal connection_closed_clean(code: int, reason: String)

signal error(message: String)

signal event_received(event: Message)

signal _auth_required()


func connect_to_obsws(port: int, password: String = "") -> void:
	_ws = WebSocketPeer.new()
	_ws.connect_to_url(WS_URL % port)
	_auth_required.connect(_authenticate.bind(password))


func disconnect_from_obsws() -> void:
	if _ws == null:
		return

	_auth_required.disconnect(_authenticate)
	_ws = null


func make_generic_request(request_type: String, request_data: Dictionary = {}) -> RequestResponse:
	var response := RequestResponse.new()
	var message := Message.new()

	var crypto := Crypto.new()
	var request_id := crypto.generate_random_bytes(16).hex_encode()

	var data := {
		"request_type": request_type,
		"request_id": request_id,
		"request_data": request_data,
	}
	message._d.merge(data, true)

	message.op_code = Enums.WebSocketOpCode.REQUEST

	response.id = request_id
	response.type = request_type

	_requests[request_id] = response

	_send_message(message)

	return response


func make_batch_request(halt_on_failure: bool = false, execution_type: Enums.RequestBatchExecutionType = Enums.RequestBatchExecutionType.SERIAL_REALTIME) -> BatchRequest:
	var batch_request := BatchRequest.new()

	var crypto := Crypto.new()
	var request_id := crypto.generate_random_bytes(16).hex_encode()

	batch_request._id = request_id
	batch_request._send_callback = _send_message

	batch_request.halt_on_failure = halt_on_failure
	batch_request.execution_type = execution_type

	_batch_requests[request_id] = batch_request

	return batch_request


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
			if _ws.get_close_code() == -1:
				connection_failed.emit()
			else:
				connection_closed_clean.emit(_ws.get_close_code(), _ws.get_close_reason())
			_ws = null


func _handle_packet(packet: PackedByteArray) -> void:
	var message = Message.from_json(packet.get_string_from_utf8())
	#print("got message with code ", message.op_code)
	_handle_message(message)


func _handle_message(message: Message) -> void:
#	print(message)
	match message.op_code:
		Enums.WebSocketOpCode.HELLO:
			if message.get("authentication") != null:
				_auth_required.emit(message)
			else:
				var m = Message.new()
				m.op_code = Enums.WebSocketOpCode.IDENTIFY
				m._d["event_subscriptions"] = subscriptions
				_send_message(m)

		Enums.WebSocketOpCode.IDENTIFIED:
			connection_ready.emit()

		Enums.WebSocketOpCode.EVENT:
			event_received.emit(message)

		Enums.WebSocketOpCode.REQUEST_RESPONSE:
			#print("Req Response")
			var id = message.get_data().get("request_id")
			if id == null:
				error.emit("Received request response, but there was no request id field.")
				return

			var response = _requests.get(id) as RequestResponse
			if response == null:
				error.emit("Received request response, but there was no request made with that id.")
				return

			response.message = message

			response.response_received.emit()
			_requests.erase(id)

		Enums.WebSocketOpCode.REQUEST_BATCH_RESPONSE:
			var id = message.get_data().get("request_id")
			if id == null:
				error.emit("Received batch request response, but there was no request id field.")
				return

			var response = _batch_requests.get(id) as BatchRequest
			if response == null:
				error.emit("Received batch request response, but there was no request made with that id.")
				return

			response.response = message

			response.response_received.emit()
			_batch_requests.erase(id)


func _send_message(message: Message) -> void:
	_ws.send_text(message.to_obsws_json())


func _authenticate(message: Message, password: String) -> void:
	var authenticator = Authenticator.new(
		password,
		message.authentication.challenge,
		message.authentication.salt,
	)
	var auth_string = authenticator.get_auth_string()
	var m = Message.new()
	m.op_code = Enums.WebSocketOpCode.IDENTIFY
	m._d["authentication"] = auth_string
	m._d["event_subscriptions"] = subscriptions
	#print("MY RESPONSE: ")
	#print(m)
	_send_message(m)


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


	func get_data() -> Dictionary:
		return _d


	func _to_string() -> String:
		return var_to_str(_d)


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
			if d[prop] is Dictionary and prop != "inputSettings":
				cameled[prop.to_camel_case()] = snake_to_camel_recursive(d[prop])
			else:
				cameled[prop.to_camel_case()] = d[prop]
		return cameled


class RequestResponse:
	signal response_received()

	var id: String
	var type: String
	var message: Message


class BatchRequest:
	signal response_received()

	var _id: String
	var _send_callback: Callable

	var halt_on_failure: bool = false
	var execution_type: Enums.RequestBatchExecutionType = Enums.RequestBatchExecutionType.SERIAL_REALTIME

	var requests: Array[Message]
	# {String: int}
	var request_ids: Dictionary

	var response: Message = null

	func send() -> void:
		var message = Message.new()
		message.op_code = Enums.WebSocketOpCode.REQUEST_BATCH
		message._d["halt_on_failure"] = halt_on_failure
		message._d["execution_type"] = execution_type
		message._d["request_id"] = _id
		message._d["requests"] = []
		for r in requests:
			message._d.requests.append(Message.snake_to_camel_recursive(r.get_data()))

		_send_callback.call(message)


	func add_request(request_type: String, request_id: String = "", request_data: Dictionary = {}) -> int:
		var message = Message.new()

		if request_id == "":
			var crypto := Crypto.new()
			request_id = crypto.generate_random_bytes(16).hex_encode()

		var data := {
			"request_type": request_type,
			"request_id": request_id,
			"request_data": request_data,
		}

		message._d.merge(data, true)
		message.op_code = Enums.WebSocketOpCode.REQUEST

		requests.append(message)
		request_ids[request_id] = requests.size() - 1

		return request_ids[request_id]
