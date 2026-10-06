extends StaticBody3D

func _ready():
	# Start with collision disabled - water detector will handle entry
	$CollisionShape3D.disabled = true

func _on_area_3d_body_entered(body):
	if body.is_in_group("Player"):
		# Check if player is moving fast enough and parallel to surface
		var vel = body.velocity
		var speed = vel.length()
		var normal: Vector3 = global_transform.basis.y.normalized()
		if normal.length() < 0.001 and body.has_method("get_gravity_up"):
			var gravity_up_value = body.call("get_gravity_up")
			if gravity_up_value is Vector3:
				normal = (gravity_up_value as Vector3).normalized()
		if normal.length() < 0.001:
			normal = Vector3.UP
		
		# Use the same logic as SonicPlayer
		var tangent_speed = vel.slide(normal).length()
		var into_speed = -vel.dot(normal)
		var angle = rad_to_deg(atan2(max(into_speed, 0.0), max(tangent_speed, 0.001)))
		
		# Enable collision only if player can land on surface
		if speed >= 80.0 and tangent_speed >= 80.0 and angle <= 45.0:
			$CollisionShape3D.disabled = false

func _on_area_3d_body_exited(body):
	if body.is_in_group("Player"):
		# Disable collision when player exits
		$CollisionShape3D.disabled = true
