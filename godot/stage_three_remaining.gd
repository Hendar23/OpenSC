extends RefCounted
## Retail stage-three side jobs sharing the existing mission lifecycle.
var jobs: Node
var mission: RefCounted

func start() -> void:
	match jobs.id:
		"miners", "miners2": mission = preload("res://student_rescue.gd").new()
		"bomb": mission = preload("res://bomb_disposal.gd").new()
		"aliens", "aliens2": mission = preload("res://queen_jellyfish.gd").new()
	mission.jobs = jobs; mission.start()

func step(delta: float) -> void:
	mission.step(delta)

func target_body() -> CollisionObject3D:
	return mission.target_body()

func delivery(body: Node3D, city: int) -> bool:
	return mission.delivery(body,city) if mission.has_method("delivery") else false

func release_survivors() -> void:
	if mission.has_method("release_survivors"): mission.release_survivors()

func clear() -> void:
	if mission != null: mission.clear(); mission = null
