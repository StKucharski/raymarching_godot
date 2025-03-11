extends OmniLight3D


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	var time = Time.get_ticks_msec() / 1000.0
	var speed = 3
	var radius = 2
	var x = radius * cos(speed * time)
	var z = radius * sin(speed * time)
	position = Vector3(x, position.y, z)
	pass
