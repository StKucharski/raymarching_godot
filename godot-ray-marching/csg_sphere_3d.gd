extends CSGSphere3D

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	var time = Time.get_ticks_msec() / 1000.0
	var speed = 2
	var radius = 1
	var x = radius * cos(speed * time)
	var z = radius * sin(speed * time)
	#position = Vector3(x, position.y, z)
	#rotation = Vector3(rotation.x + 0.1 * sin(time / 200.0), rotation.y, rotation.z)
	
	var inverse_model_matrix = global_transform.affine_inverse()
	material.set_shader_parameter("inverse_model_matrix", inverse_model_matrix)
	
	pass
