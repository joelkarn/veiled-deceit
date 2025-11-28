extends Node3D

## Arrow projectile that sticks to objects
class_name Arrow

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D

var target_position: Vector3 = Vector3.ZERO
var target_body: Node3D = null
var speed: float = 100.0 # Arrow visual speed
var lifetime: float = 10.0
var arrow_shooter: Node3D
var hit_success: bool = false

func set_target_position(pos: Vector3, body: Node3D) -> void:
	target_position = pos
	target_body = body

func set_arrow_shooter(player: Node3D) -> void:
	arrow_shooter = player

func _ready() -> void:
	set_physics_process(true)
	var lifetime_timer = Timer.new()
	lifetime_timer.wait_time = lifetime
	lifetime_timer.one_shot = true
	lifetime_timer.timeout.connect(_on_lifetime_timeout)
	add_child(lifetime_timer)
	lifetime_timer.start()

func _on_lifetime_timeout():
	queue_free()

func _physics_process(delta: float) -> void:
	if target_position != Vector3.ZERO:
		var to_target = (target_position - global_position)
		var distance = to_target.length()
		if distance > speed * delta:
			global_position += to_target.normalized() * speed * delta
		else:
			global_position = target_position
			set_physics_process(false)
			# Stick arrow to the hit body visually
			if not hit_success:
				queue_free()
				return
			if target_body:
				var arrow_global = global_transform
				var parent = get_parent()
				parent.call_deferred("remove_child", self)
				target_body.call_deferred("add_child", self)
				call_deferred("set_global_transform", arrow_global)
				# Apply damage if possible
				if target_body.has_method("take_damage"):
					var attacker_id = -1
					if arrow_shooter and arrow_shooter.has_method("get_player_id"):
						attacker_id = arrow_shooter.get_player_id()
					elif arrow_shooter and "player_id" in arrow_shooter:
						attacker_id = arrow_shooter.player_id
					target_body.take_damage(12.0, attacker_id)
