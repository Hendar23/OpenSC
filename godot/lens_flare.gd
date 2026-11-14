extends MeshInstance3D
## A camera-facing optical flare; ordinary meshes/materials also replay it.
const FlareShader = preload("res://lens_flare.gdshader")
const Searchlight = preload("res://searchlight.gd")
static var effects_enabled := true
static var option_registered := false
var source: Node3D
var flare_material: ShaderMaterial
var previous_state: Array = []
var aperture: MeshInstance3D

static func set_enabled(on: bool) -> void:
	effects_enabled = on
	if not option_registered:
		RenderingServer.global_shader_parameter_add("osc_lens_flares_enabled",RenderingServer.GLOBAL_VAR_TYPE_BOOL,on)
		option_registered = true
	else: RenderingServer.global_shader_parameter_set("osc_lens_flares_enabled",on)

static func attach(light: Node3D) -> MeshInstance3D:
	var anchor: Node3D = light.pivot if light is Searchlight else light
	if anchor == null: return null
	var existing := anchor.get_node_or_null("LensFlare") as MeshInstance3D
	if existing != null: return existing
	var flare := load("res://lens_flare.gd").new() as MeshInstance3D
	flare.name = "LensFlare"; anchor.add_child(flare)
	return flare

func _ready() -> void:
	preload("res://natural_light.gd").ensure_globals()
	set_enabled(effects_enabled)
	source = get_parent() if get_parent() is Light3D else get_parent().get_parent()
	if source.name == "DeepSeaBeam":
		var lenses := source.get_parent().find_children("IlluminatedLens","MeshInstance3D",true,false)
		if not lenses.is_empty(): aperture = lenses[0]
	mesh = QuadMesh.new()
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ignore_occlusion_culling = true # Visibility is tested at the light aperture in the shader.
	extra_cull_margin = 2.0
	if source is DirectionalLight3D: custom_aabb = AABB(Vector3.ONE*-10000.0,Vector3.ONE*20000.0)
	flare_material = ShaderMaterial.new(); flare_material.shader = FlareShader
	material_override = flare_material
	update_light()

func _process(_delta: float) -> void: update_light()

func update_light() -> void:
	if not is_instance_valid(source): hide(); return
	var energy := 0.0; var reach := 5.0; var tint := Color(0.8,0.92,1.0)
	var directional := false; var cone := -1.0; var forward := 1.0
	var solar := source is DirectionalLight3D
	if source is Light3D:
		energy = source.light_energy; tint = source.light_color
		if source is SpotLight3D:
			reach = source.spot_range; directional = true; forward = -1.0
			cone = cos(deg_to_rad(minf(89.0,source.spot_angle)))
			position.z = -0.035
		elif source is OmniLight3D: reach = source.omni_range
	elif source is Searchlight:
		energy = float(source.tuning.beam_brightness) * lerpf(1.0,float(source.tuning.day_brightness),source.daylight) * 3.0
		reach = float(source.tuning.beam_length) * 4.0; directional = true; cone = 0.7
		position.z = 0.035
	if is_instance_valid(aperture):
		# The original spotlight sits inside the housing. Emit from the real
		# illuminated lens so its own metal casing cannot hide the optical effect.
		position = source.to_local(aperture.to_global(aperture.mesh.get_aabb().get_center())) + Vector3(0,0,-0.004)
	var state := [energy,reach,tint,directional,cone,forward,solar]
	if state == previous_state: return
	previous_state = state
	visible = energy > 0.25
	flare_material.set_shader_parameter("flare_color",Vector3(tint.r,tint.g,tint.b))
	flare_material.set_shader_parameter("brightness",clampf(energy-0.1,0.0,1.0))
	flare_material.set_shader_parameter("reach",maxf(1.0,reach*4.0))
	flare_material.set_shader_parameter("diameter",clampf(reach*0.16,0.4,2.0))
	flare_material.set_shader_parameter("cone_cosine",cone if directional else -1.0)
	flare_material.set_shader_parameter("forward_sign",forward)
	flare_material.set_shader_parameter("solar",solar)
