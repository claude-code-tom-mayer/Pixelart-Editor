extends SceneTree
## Compares one shared centre bucket per chunk against one per team and chunk.
class_name TeamBucketCompare

const COUNTS: Array[int] = [500, 1000, 3000, 5000]
const REACH: int = 4
const FRAMES: int = 10
const RADII: Array[float] = [12.0, 24.0, 40.0, 90.0]

func _init() -> void:
	print("")
	print("    N | variant   | us/search | total ms (500 searches) | same target")
	print("------+-----------+-----------+-------------------------+------------")
	for l_count: int in COUNTS:
		var l_shared: Array = _run_shared(l_count)
		var l_perTeam: Array = _run_per_team(l_count)
		var l_same: bool = l_shared[1] == l_perTeam[1]
		print("%5d | shared    | %9.2f | %23.2f |" % [l_count, l_shared[0], l_shared[0] * l_count / 1000.0])
		print("%5d | per team  | %9.2f | %23.2f | %s" % [l_count, l_perTeam[0],
			l_perTeam[0] * l_count / 1000.0, ("yes" if l_same else "NO - DIFFERS")])
		print("%5d | speedup   | %8.2fx |                         |" % [l_count, l_shared[0] / l_perTeam[0]])
		print("------+-----------+-----------+-------------------------+------------")
	quit()


func _positions_for(p_count: int) -> Array:
	var l_random: RandomNumberGenerator = RandomNumberGenerator.new()
	l_random.seed = 11
	var l_width: float = C_ChunkingServer.MAP_SIZE.x
	var l_height: float = C_ChunkingServer.MAP_SIZE.y
	var l_out: Array = []
	for l_index: int in p_count:
		var l_team: int = l_index % C_ChunkingServer.TEAM_COUNT
		var l_frontX: float = l_width * (0.35 if l_team == 0 else 0.65)
		l_out.append(Vector2(
			clampf(l_random.randfn(l_frontX, l_width * 0.08), 0.0, l_width - 1.0),
			clampf(l_random.randfn(l_height * 0.5, l_height * 0.17), 0.0, l_height - 1.0)))
	return l_out


func _run_shared(p_count: int) -> Array:
	var l_chunking: ChunkingServer = ChunkingServer.new()
	var l_targeting: TargetingServer = TargetingServer.new(l_chunking)
	var l_data: R_TargetingData = R_TargetingData.new()
	l_data.targetedGroups = 0b111
	l_data.searchChunks = REACH
	var l_positions: Array = _positions_for(p_count)
	var l_ids: PackedInt32Array = PackedInt32Array()
	for l_index: int in p_count:
		var l_id: int = l_chunking.register_entity(l_positions[l_index],
			RADII[l_index % RADII.size()], l_index % C_ChunkingServer.TEAM_COUNT, 1 << (l_index % 3))
		l_targeting.register(l_id, l_data)
		l_ids.append(l_id)
	var l_time: int = 0
	var l_targets: PackedInt32Array = PackedInt32Array()
	for l_frame: int in FRAMES:
		var l_start: int = Time.get_ticks_usec()
		for l_id: int in l_ids:
			l_targeting.search_target(l_id)
		l_time += Time.get_ticks_usec() - l_start
	for l_id: int in l_ids:
		l_targets.append(l_targeting.get_target(l_id))
	return [l_time / float(FRAMES * p_count), l_targets]


func _run_per_team(p_count: int) -> Array:
	var l_chunking: ExpChunkingServer = ExpChunkingServer.new()
	var l_targeting: ExpTargetingServer = ExpTargetingServer.new(l_chunking)
	var l_data: R_TargetingData = R_TargetingData.new()
	l_data.targetedGroups = 0b111
	l_data.searchChunks = REACH
	var l_positions: Array = _positions_for(p_count)
	var l_ids: PackedInt32Array = PackedInt32Array()
	for l_index: int in p_count:
		var l_id: int = l_chunking.register_entity(l_positions[l_index],
			RADII[l_index % RADII.size()], l_index % C_ChunkingServer.TEAM_COUNT, 1 << (l_index % 3))
		l_targeting.register(l_id, l_data)
		l_ids.append(l_id)
	var l_time: int = 0
	var l_targets: PackedInt32Array = PackedInt32Array()
	for l_frame: int in FRAMES:
		var l_start: int = Time.get_ticks_usec()
		for l_id: int in l_ids:
			l_targeting.search_target(l_id)
		l_time += Time.get_ticks_usec() - l_start
	for l_id: int in l_ids:
		l_targets.append(l_targeting.get_target(l_id))
	return [l_time / float(FRAMES * p_count), l_targets]
