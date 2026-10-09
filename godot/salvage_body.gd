extends RigidBody3D
var stats: Dictionary = {}
var health := 1.0
var dead := false
var shard := 0
var surface_height := 0.0
var enabled := true
func setup(definition: Dictionary, visual: Node3D, _fragment: int, water: float, running: bool) -> void:
 stats = definition.duplicate(true); surface_height = water; enabled = running
 name = str(stats.id).capitalize(); health = float(stats.health); mass = float(stats.mass)
 collision_layer = 9; collision_mask = 11; freeze = not running; continuous_cd = true
 gravity_scale = 0.0; linear_damp = 0.3; angular_damp = 0.5
 var material := PhysicsMaterial.new(); material.friction = 0.45; material.bounce = 0.0; physics_material_override = material
 add_child(visual); set_meta("metal_tow_target",bool(stats.get("magnet_compatible",stats.get("id","") != "cigarette_end")))
 set_meta("grapple_tow_target",bool(stats.get("grapple_compatible",stats.get("id","") == "cigarette_end")))
 var points := PackedVector3Array()
 for entry in preload("res://submarine_equipment.gd")._meshes(visual,Transform3D.IDENTITY):
  for surface in range(entry.mesh.get_surface_count()):
   var arrays: Array = entry.mesh.surface_get_arrays(surface)
   for vertex in arrays[Mesh.ARRAY_VERTEX]: points.append(entry.pose * vertex)
 var shape: Shape3D
 if points.size() >= 4:
  var hull := ConvexPolygonShape3D.new(); hull.points = points; shape = hull
 else:
  var sphere := SphereShape3D.new(); sphere.radius = float(stats.size) * 0.5; shape = sphere
 var collider := CollisionShape3D.new(); collider.shape = shape; add_child(collider)
func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
 if not enabled or dead: return
 var submerged := state.transform.origin.y < surface_height
 state.linear_velocity += Vector3.DOWN * (1.2 if submerged else 9.8) * state.step
 if submerged:
  state.linear_velocity *= exp(-(1.8 + state.linear_velocity.length() * 1.2) * state.step)
  state.angular_velocity *= exp(-4.5 * state.step)
