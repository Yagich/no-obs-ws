# NoOBSWS
An [obs-websocket](https://github.com/obsproject/obs-websocket) client and translation layer for Godot 4.0. Currently very barebones, and only supports authentication, events sent from OBS, and requests.

# Quick setup
- Install the addon
- Add the `NoOBSWS` node to your preferred scene
- Call `NoOBSWS.connect_to_obsws()` function with the port and password provided in the obs-websocket menu in OBS
- Await or connect to the `connection_ready` signal. You are now able to receive the `event_received` signal or make a request using the `make_generic_request()` method.

## Making requests
After authorizing, you can make a request using the aforementioned `make_generic_request()` method. It expects at least one argument: a `String` being the request type, and an optional `Dictionary` containing request parameters. For a list of request types, [see the obs-websocket protocol description.](https://github.com/obsproject/obs-websocket/blob/master/docs/generated/protocol.md#requests)

The `make_generic_request()` method returns a special object, `RequestResponse`, that promises to contain the request response. To make sure it is received in time, you should await that object's `response_received` signal. After that, you can access its' data from the `message` property.

# Setup example

```gdscript
@onready var no_obs_ws: NoOBSWS = $NoOBSWS

func _ready():
	no_obs_ws.event_received.connect(_on_no_obs_ws_event_received)
	no_obs_ws.connect_to_obsws(4455, "your_password_here")
	# Wait for the connection
	await no_obs_ws.connection_ready
	# At this point, the connection is ready and you have access to the events sent by obs-websocket and making requests.

	# Making a request
	var request = no_obs_ws.make_generic_request("GetStats")
	await request.response_received

	print request.message.get_data()


func _on_no_obs_ws_event_received(event: NoOBSWS.Message):
	var event_data = event.get_data() # Returns a Dictionary conforming to the message format specified by the obs-websocket protocol, with keys transformed to snake_case from camelCase to be more Godot-like.
```