extends SceneTree
class_name TeamBucketCompare
## Compares one shared centre bucket per chunk against one per team and chunk. [br]
## Run it headless: godot --headless --script res://Experiments/TeamBuckets/TeamBucketCompare.gd

#region CACHED_VARS

## Cached C_TeamBucketCompare.ENTITY_COUNTS.
var ENTITY_COUNTS: Array[int]

## Cached C_TeamBucketCompare.SEARCH_CHUNKS.
var SEARCH_CHUNKS: int

## Cached C_TeamBucketCompare.FRAME_COUNT.
var FRAME_COUNT: int

## Cached C_TeamBucketCompare.ENTITY_RADII.
var ENTITY_RADII: Array[float]

## Cached C_TeamBucketCompare.FRONT_OFFSET.
var FRONT_OFFSET: float

## Cached C_TeamBucketCompare.FRONT_SPREAD.
var FRONT_SPREAD: float

## Cached C_ChunkingServer.MAP_SIZE.
var MAP_SIZE: Vector2

## Cached C_ChunkingServer.TEAM_COUNT.
var TEAM_COUNT: int

#endregion

#region LIFECYCLE_AND_METHODS

## Caches the configuration, measures both variants at every count and prints one table, then quits.
func _init() -> void:
	ENTITY_COUNTS = C_TeamBucketCompare.ENTITY_COUNTS
	SEARCH_CHUNKS = C_TeamBucketCompare.SEARCH_CHUNKS
	FRAME_COUNT = C_TeamBucketCompare.FRAME_COUNT
	ENTITY_RADII = C_TeamBucketCompare.ENTITY_RADII
	FRONT_OFFSET = C_TeamBucketCompare.FRONT_OFFSET
	FRONT_SPREAD = C_TeamBucketCompare.FRONT_SPREAD
	MAP_SIZE = C_ChunkingServer.MAP_SIZE
	TEAM_COUNT = C_ChunkingServer.TEAM_COUNT
	
	print("")
	print("    N | variant   | us/search | total ms (500 searches) | same target")
	print("------+-----------+-----------+-------------------------+------------")
	
	for l_count: int in ENTITY_COUNTS:
		var l_shared: Array = _run_shared(l_count)
		var l_perTeam: Array = _run_per_team(l_count)
		var l_isSameTarget: bool = l_shared[1] == l_perTeam[1]
		
		print("%5d | shared    | %9.2f | %23.2f |" % [l_count, l_shared[0], l_shared[0] * l_count / 1000.0])
		print("%5d | per team  | %9.2f | %23.2f | %s" % [l_count, l_perTeam[0],
			l_perTeam[0] * l_count / 1000.0, ("yes" if l_isSameTarget else "NO - DIFFERS")])
		print("%5d | speedup   | %8.2fx |                         |" % [l_count, l_shared[0] / l_perTeam[0]])
		print("------+-----------+-----------+-------------------------+------------")
	
	quit()


## Places two fronts facing each other along x, the same way for both variants. [br]
## @param p_count How many positions to build [br]
## @return The start position of every entity
func _build_positions(p_count: int) -> Array[Vector2]:
	var l_random: RandomNumberGenerator = RandomNumberGenerator.new()
	l_random.seed = 11
	
	var l_width: float = MAP_SIZE.x
	var l_height: float = MAP_SIZE.y
	var l_positions: Array[Vector2] = []
	
	for l_index: int in p_count:
		var l_team: int = l_index % TEAM_COUNT
		var l_frontX: float = l_width * (FRONT_OFFSET if l_team == 0 else 1.0 - FRONT_OFFSET)
		
		l_positions.append(Vector2(
			clampf(l_random.randfn(l_frontX, l_width * FRONT_SPREAD), 0.0, l_width - 1.0),
			clampf(l_random.randfn(l_height * 0.5, l_height * 0.17), 0.0, l_height - 1.0)))
	
	return l_positions


## Builds the world on the shipped servers, with one shared centre bucket per chunk. [br]
## @param p_count How many entities to register [br]
## @return The microseconds per search and the target every entity ended up with
func _run_shared(p_count: int) -> Array:
	var l_chunking: G_ChunkingServer = G_ChunkingServer.new()
	var l_targeting: G_TargetingServer = G_TargetingServer.new(l_chunking)
	var l_targetingData: R_TargetingData = _build_targeting_data()
	var l_positions: Array[Vector2] = _build_positions(p_count)
	var l_ids: PackedInt32Array = PackedInt32Array()
	
	for l_index: int in p_count:
		var l_id: int = l_chunking.register_entity(l_positions[l_index],
			ENTITY_RADII[l_index % ENTITY_RADII.size()], l_index % TEAM_COUNT, 1 << (l_index % 3))
		l_targeting.register(l_id, l_targetingData)
		l_ids.append(l_id)
	
	var l_time: int = 0
	for l_frame: int in FRAME_COUNT:
		var l_start: int = Time.get_ticks_usec()
		for l_id: int in l_ids:
			l_targeting.search_target(l_id)
		l_time += Time.get_ticks_usec() - l_start
	
	var l_targets: PackedInt32Array = PackedInt32Array()
	for l_id: int in l_ids:
		l_targets.append(l_targeting.get_target(l_id))
	
	return [l_time / float(FRAME_COUNT * p_count), l_targets]


## Builds the same world on the experiment servers, with one centre bucket per team and chunk. [br]
## @param p_count How many entities to register [br]
## @return The microseconds per search and the target every entity ended up with
func _run_per_team(p_count: int) -> Array:
	var l_chunking: ExpChunkingServer = ExpChunkingServer.new()
	var l_targeting: ExpTargetingServer = ExpTargetingServer.new(l_chunking)
	var l_targetingData: R_TargetingData = _build_targeting_data()
	var l_positions: Array[Vector2] = _build_positions(p_count)
	var l_ids: PackedInt32Array = PackedInt32Array()
	
	for l_index: int in p_count:
		var l_id: int = l_chunking.register_entity(l_positions[l_index],
			ENTITY_RADII[l_index % ENTITY_RADII.size()], l_index % TEAM_COUNT, 1 << (l_index % 3))
		l_targeting.register(l_id, l_targetingData)
		l_ids.append(l_id)
	
	var l_time: int = 0
	for l_frame: int in FRAME_COUNT:
		var l_start: int = Time.get_ticks_usec()
		for l_id: int in l_ids:
			l_targeting.search_target(l_id)
		l_time += Time.get_ticks_usec() - l_start
	
	var l_targets: PackedInt32Array = PackedInt32Array()
	for l_id: int in l_ids:
		l_targets.append(l_targeting.get_target(l_id))
	
	return [l_time / float(FRAME_COUNT * p_count), l_targets]


## Builds the targeting setup every entity of both variants shares. [br]
## @return The shared setup
func _build_targeting_data() -> R_TargetingData:
	var l_targetingData: R_TargetingData = R_TargetingData.new()
	l_targetingData.targetedGroups = 0b111
	l_targetingData.searchChunks = SEARCH_CHUNKS
	
	return l_targetingData

#endregion
