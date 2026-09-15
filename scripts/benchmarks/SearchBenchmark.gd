extends SceneTree
## Measures what the targeting search costs, so the index choices can be checked against numbers. [br]
## Run it headless: godot --headless --script res://scripts/benchmarks/SearchBenchmark.gd
class_name SearchBenchmark

#region CONFIGURATION

## Entity counts every pass is measured at.
const ENTITY_COUNTS: PackedInt32Array = PackedInt32Array([500, 2000, 8000])

## How many chunks in each direction the measured searches cover.
const SEARCH_CHUNKS: int = 4

## Radii handed out in turn, so entities span a realistic mix of chunk counts.
const ENTITY_RADII: PackedFloat32Array = PackedFloat32Array([12.0, 24.0, 40.0, 90.0])

## How far the two fronts stand apart, as a share of the map width.
const FRONT_SPREAD: float = 0.16

#endregion

#region LIFECYCLE

## Runs every pass and prints one table, then quits.
func _init() -> void:
	print("entities | build ms | search ms | per search us | move ms | centers | touched")
	print("---------+----------+-----------+---------------+---------+---------+--------")
	
	for l_count: int in ENTITY_COUNTS:
		_run_pass(l_count)
	
	quit()

#endregion

#region PRIVATE_METHODS

## Builds a world of two fronts and measures building, searching and moving in it. [br]
## @param p_count How many entities the pass registers
func _run_pass(p_count: int) -> void:
	var l_chunking: ChunkingServer = ChunkingServer.new()
	var l_targeting: TargetingServer = TargetingServer.new(l_chunking)
	var l_ids: PackedInt32Array = PackedInt32Array()
	var l_random: RandomNumberGenerator = RandomNumberGenerator.new()
	l_random.seed = 11
	
	var l_buildStart: int = Time.get_ticks_usec()
	
	for l_index: int in p_count:
		var l_team: int = l_index % C_ChunkingServer.TEAM_COUNT
		l_ids.append(_register_entity(l_chunking, l_targeting, l_team, l_index, l_random))
	
	var l_buildTime: float = (Time.get_ticks_usec() - l_buildStart) / 1000.0
	
	var l_searchStart: int = Time.get_ticks_usec()
	
	for l_id: int in l_ids:
		l_targeting.search_target(l_id)
	
	var l_searchTime: float = (Time.get_ticks_usec() - l_searchStart) / 1000.0
	
	var l_moveStart: int = Time.get_ticks_usec()
	
	for l_id: int in l_ids:
		var l_position: Vector2 = l_chunking._entityPosition[l_id]
		l_chunking.set_position(l_id, l_position + Vector2(l_random.randf_range(-8.0, 8.0), l_random.randf_range(-8.0, 8.0)))
	
	var l_moveTime: float = (Time.get_ticks_usec() - l_moveStart) / 1000.0
	var l_centerEntries: int = _count_entries(l_chunking._centersInChunk)
	var l_touchedEntries: int = _count_entries(l_chunking._entitiesInChunk)
	
	print("%8d | %8.2f | %9.2f | %13.2f | %7.2f | %7d | %7d" % [p_count, l_buildTime, l_searchTime,
		l_searchTime * 1000.0 / p_count, l_moveTime, l_centerEntries, l_touchedEntries])


## Registers one entity of a front into both servers. [br]
## @param p_chunking The index to register in [br]
## @param p_targeting The targeting server to register in [br]
## @param p_team Team of the entity, a C_ChunkingServer.TEAM value [br]
## @param p_index Running number of the entity, picks its radius [br]
## @param p_random Source of its position [br]
## @return The assigned entity id
func _register_entity(p_chunking: ChunkingServer, p_targeting: TargetingServer, p_team: int,
		p_index: int, p_random: RandomNumberGenerator) -> int:
	var l_width: float = C_ChunkingServer.MAP_SIZE.x
	var l_frontX: float = l_width * (0.35 if p_team == 0 else 0.65)
	var l_position: Vector2 = Vector2(
		clampf(p_random.randfn(l_frontX, l_width * FRONT_SPREAD * 0.5), 0.0, l_width - 1.0),
		clampf(p_random.randfn(C_ChunkingServer.MAP_SIZE.y * 0.5, C_ChunkingServer.MAP_SIZE.y * 0.17),
			0.0, C_ChunkingServer.MAP_SIZE.y - 1.0))
	
	var l_radius: float = ENTITY_RADII[p_index % ENTITY_RADII.size()]
	var l_id: int = p_chunking.register_entity(l_position, l_radius, p_team, 1 << (p_index % 3))
	
	var l_targetingData: R_TargetingData = R_TargetingData.new()
	l_targetingData.targetedGroups = 0b111
	l_targetingData.searchChunks = SEARCH_CHUNKS
	p_targeting.register(l_id, l_targetingData)
	
	return l_id


## Counts how many entries all chunk lists hold together. [br]
## @param p_lists The per chunk lists to count [br]
## @return The total number of entries
func _count_entries(p_lists: Array[PackedInt32Array]) -> int:
	var l_total: int = 0
	
	for l_list: PackedInt32Array in p_lists:
		l_total += l_list.size()
	
	return l_total

#endregion
