extends Node3D
## Organic burst with short-lived gore and sinking, persistent model fragments.
static var settings := {"gore_amount":20,"gore_settle_speed":1.0,"gore_lifetime":2.0,"chunk_lifetime":60.0}
var pieces: Array[Dictionary] = []
var age := 0.0
var lifetime := 61.0
var bubbles: CPUParticles3D
var gore: Array[Dictionary] = []
var gore_frames: Array[Texture2D] = []
var gore_lifetime := 2.0
var gore_settle_speed := 1.0
var chunk_fade_time := 60.0

static func load_gore(folder: String) -> Array[Texture2D]:
	var frames: Array[Texture2D] = []; var cache := {}
	for index in range(1,13):
		var texture := preload("res://clump_loader.gd")._load_texture(folder,"FLAK%d" % index,"FLAK%dM" % index,cache)
		if texture != null: frames.append(texture)
	return frames

func setup(creature: Node3D, bubble_texture: Texture2D, sound: AudioStream, blood_frames: Array[Texture2D] = [], flesh_texture: Texture2D = null, visual_source: Node3D = null, additional_sources: Array[Node3D] = []) -> void:
	name = "CreatureBurst"
	chunk_fade_time = maxf(0,float(settings.chunk_lifetime))
	lifetime = chunk_fade_time + 1.0
	gore_lifetime = maxf(0.2,float(settings.get("gore_lifetime",2.0)))
	gore_settle_speed = maxf(0.1,float(settings.get("gore_settle_speed",1.0)))
	lifetime = maxf(lifetime,gore_lifetime)
	var random := RandomNumberGenerator.new(); random.randomize()
	gore_frames = blood_frames
	if not gore_frames.is_empty():
		for index in range(clampi(int(settings.gore_amount),0,100)):
			var sprite := Sprite3D.new(); sprite.texture = gore_frames[mini(2,gore_frames.size() - 1)]
			sprite.material_override = preload("res://natural_light.gd").billboard_material(sprite.texture)
			sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED; sprite.no_depth_test = false
			sprite.pixel_size = random.randf_range(0.0015,0.004); sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(sprite)
			var direction := Vector3(random.randf_range(-1,1),random.randf_range(-1,1),random.randf_range(-1,1)).normalized()
			gore.append({"node":sprite,"velocity":direction * random.randf_range(1.2,3.5),"phase":random.randf_range(0,0.2)})
	# Animation tracks only morph meshes; rigid bodies and articulated parts
	# (including turtles and seahorses) must also become debris.
	var visual_meshes: Array[MeshInstance3D] = []
	_collect_meshes(visual_source if visual_source != null else creature.get_child(1),visual_meshes)
	for source in additional_sources: _collect_meshes(source,visual_meshes)
	for node in visual_meshes:
		var pose: Transform3D = global_transform.affine_inverse() * node.global_transform
		for surface in range(node.mesh.get_surface_count()):
			var source: Array = node.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = source[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = source[Mesh.ARRAY_INDEX]
			if indices.is_empty():
				for index in range(vertices.size()): indices.append(index)
			var groups := {}
			var center: Vector3 = node.mesh.get_aabb().get_center()
			for triangle in range(0,indices.size() - 2,3):
				var midpoint := (vertices[indices[triangle]] + vertices[indices[triangle + 1]] + vertices[indices[triangle + 2]]) / 3.0 - center
				var octant := (1 if midpoint.x > 0 else 0) + (2 if midpoint.y > 0 else 0) + (4 if midpoint.z > 0 else 0)
				if not groups.has(octant): groups[octant] = []
				for corner in range(3): groups[octant].append(indices[triangle + corner])
			for octant in groups:
				var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
				var positions := PackedVector3Array(); var normals := PackedVector3Array(); var uvs := PackedVector2Array(); var colors := PackedColorArray()
				for index in groups[octant]:
					positions.append(pose * vertices[index])
					if source[Mesh.ARRAY_NORMAL] != null: normals.append((pose.basis.inverse().transposed() * source[Mesh.ARRAY_NORMAL][index]).normalized())
					if source[Mesh.ARRAY_TEX_UV] != null: uvs.append(source[Mesh.ARRAY_TEX_UV][index])
					if source[Mesh.ARRAY_COLOR] != null: colors.append(source[Mesh.ARRAY_COLOR][index])
				var pivot := Vector3.ZERO
				for point in positions: pivot += point
				pivot /= positions.size()
				for index in range(positions.size()): positions[index] -= pivot
				arrays[Mesh.ARRAY_VERTEX] = positions
				if not normals.is_empty(): arrays[Mesh.ARRAY_NORMAL] = normals
				if not uvs.is_empty(): arrays[Mesh.ARRAY_TEX_UV] = uvs
				if not colors.is_empty(): arrays[Mesh.ARRAY_COLOR] = colors
				var mesh := ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
				var part := MeshInstance3D.new(); part.mesh = mesh; part.position = pivot; part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				var material: Material = node.get_active_material(surface)
				if material != null and material.has_meta("natural_original"): material = material.get_meta("natural_original")
				if material != null:
					material = material.duplicate(); material.next_pass = null
					if material is StandardMaterial3D: material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; material.cull_mode = BaseMaterial3D.CULL_DISABLED
				part.material_override = material
				add_child(part)
				var outward := pivot.normalized() if pivot.length_squared() > 0.001 else Vector3(random.randf_range(-1,1),random.randf_range(-1,1),random.randf_range(-1,1)).normalized()
				pieces.append({"node":part,"velocity":outward * random.randf_range(2.5,5.0),"spin":Vector3(random.randf_range(-6,6),random.randf_range(-6,6),random.randf_range(-6,6)),"material":material,"settled":false})
	var natural := preload("res://natural_light.gd").new(); natural.attach(self)
	for piece in pieces:
		piece.material = piece.node.get_active_material(0)
		if flesh_texture != null and piece.material is ShaderMaterial:
			piece.material.set_shader_parameter("backface_texture",flesh_texture)
			piece.material.set_shader_parameter("has_backface_texture",true)
	if bubble_texture != null:
		bubbles = CPUParticles3D.new(); bubbles.amount = 24; bubbles.lifetime = 1.2; bubbles.one_shot = true; bubbles.explosiveness = 1.0; bubbles.direction = Vector3.UP; bubbles.spread = 180
		bubbles.initial_velocity_min = 0.5; bubbles.initial_velocity_max = 2.0; bubbles.gravity = Vector3(0,1,0); bubbles.scale_amount_min = 0.04; bubbles.scale_amount_max = 0.11
		var quad := QuadMesh.new(); quad.size = Vector2.ONE
		var material := preload("res://natural_light.gd").billboard_material(bubble_texture)
		quad.material = material; bubbles.mesh = quad; add_child(bubbles); bubbles.emitting = true
	if sound != null:
		var audio := AudioStreamPlayer3D.new(); audio.stream = sound; audio.volume_db = -12; audio.pitch_scale = random.randf_range(0.9,1.1); audio.max_distance = 35; add_child(audio); audio.play()

func _collect_meshes(node: Node, result: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D and node.mesh != null: result.append(node)
	for child in node.get_children(): _collect_meshes(child,result)

func _process(delta: float) -> void:
	age += delta
	for particle in gore:
		particle.velocity *= exp(-1.8 * delta * gore_settle_speed); particle.velocity.y -= delta * 0.15 * gore_settle_speed
		particle.node.position += particle.velocity * delta
		particle.node.texture = gore_frames[clampi(2 + int((age + particle.phase) * 10),0,gore_frames.size() - 1)]
		particle.node.material_override.set_shader_parameter("albedo_texture",particle.node.texture)
		particle.node.modulate.a = clampf((gore_lifetime - age) / minf(0.8,gore_lifetime),0,1)
		particle.node.material_override.set_shader_parameter("opacity",particle.node.modulate.a)
	if age >= gore_lifetime and not gore.is_empty():
		for particle in gore: particle.node.queue_free()
		gore.clear()
	for piece in pieces:
		if age >= chunk_fade_time + 1.0:
			piece.node.hide()
			continue
		if not piece.settled: _move_chunk(piece,delta)
		if piece.material is StandardMaterial3D: piece.material.albedo_color.a = clampf(chunk_fade_time + 1.0 - age,0,1)
		elif piece.material is ShaderMaterial: piece.material.set_shader_parameter("opacity",clampf(chunk_fade_time + 1.0 - age,0,1))
	if age >= lifetime: queue_free()

func _move_chunk(piece: Dictionary, delta: float) -> void:
	var part: MeshInstance3D = piece.node
	piece.velocity *= exp(-1.3 * delta); piece.velocity.y -= delta * 0.9
	var previous := part.global_position
	var next: Vector3 = previous + piece.velocity * delta
	part.rotation += piece.spin * delta * exp(-age)
	# Support height uses the rotated fragment, so it rests on the floor.
	var box := part.mesh.get_aabb(); var bottom := 0.0
	for corner in range(8): bottom = minf(bottom,(part.global_basis * box.get_endpoint(corner)).y)
	var support := -bottom + 0.005
	var space := get_world_3d().direct_space_state
	var motion := PhysicsRayQueryParameters3D.create(previous,next,1); motion.hit_back_faces = true
	var hit := space.intersect_ray(motion)
	if not hit.is_empty():
		next = hit.position + hit.normal * 0.01
		piece.velocity = piece.velocity.slide(hit.normal) * 0.3
	var floor_ray := PhysicsRayQueryParameters3D.create(next + Vector3.UP * support,next - Vector3.UP * support,1); floor_ray.hit_back_faces = true
	var floor_hit := space.intersect_ray(floor_ray)
	if not floor_hit.is_empty() and floor_hit.normal.y > 0.25 and piece.velocity.y <= 0:
		next.y = floor_hit.position.y + support
		piece.settled = true; piece.velocity = Vector3.ZERO
	part.global_position = next
