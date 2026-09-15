extends SceneTree
## Times one simulation frame per entity count, split into the phases a frame really runs. [br]
## Run it headless: godot --headless --script res://scripts/benchmarks/FrameBenchmark.gd
class_name FrameBenchmark

#region CONFIGURATION

## Entity counts every pass is measured at.
const ENTITY_COUNTS: Array[int] = [300, 500, 750, 1000, 3000, 5000, 10000]

## Frames every pass averages over.
const FRAME_COUNT: int = 20

## Searches one frame is allowed to run, however many entities exist.
const SEARCH_BUDGET: int = 150

## How many chunks in each direction the measured searches cover.
const SEARCH_CHUNKS: int = 4

## Radii handed out in turn, so entities span a realistic mix of chunk counts.
const ENTITY_RADII: Array[float] = [12.0, 24.0, 40.0, 90.0]

## How far a front stands from the map edge, as a share of the map width.
const FRONT_OFFSET: float = 0.35

## How wide a front is spread, as a share of the map width.
const FRONT_SPREAD: float = 0.08

## How far an entity drifts per frame, in world units.
const FRAME_DRIFT: float = 6.0

#endregion

#region LIFECYCLE

## Runs every pass and prints one table, then quits.
func _init() -> void:
	print("")
	print("entities | move ms | update ms | move-to ms | search ms | TOTAL ms | sim only fps")
	print("---------+---------+-----------+------------+-----------+----------+-------------")
	
	for l_count: int in ENTITY_COUNTS:
		_run_pass(l_count)
	
	print("")
	print("Simulation only, single threaded, no hit resolution and no rendering.")
	print("Search budget: %d entities per frame, so each one re-searches every N/%d frames."
		% [SEARCH_BUDGET, SEARCH_BUDGET])
	quit()

#endregion

#region PRIVATE_METHODS

## Builds a world of two fronts and times the phases of one frame in it. [br]
## @param p_count How many entities the pass registers
func _run_pass(p_count: int) -> void:
	var l_chunking: ChunkingServer = ChunkingServer.new()
	var l_targeting: TargetingServer = TargetingServer.new(l_chunking)
	var l_random: RandomNumberGenerator = RandomNumberGenerator.new()
	l_random.seed = 11
	
	var l_ids: PackedInt32Array = _build_world(l_chunking, l_targeting, p_count, l_random)
	var l_moveTime: int = 0
	var l_updateTime: int = 0
	var l_positionTime: int = 0
	var l_searchTime: int = 0
	var l_budget: int = mini(SEARCH_BUDGET, p_count)
	var l_cursor: int = 0
	l_random.seed = 12
	
	for l_frame: int in FRAME_COUNT:
		var l_start: int = Time.get_ticks_usec()
		for l_id: int in l_ids:
			l_chunking.set_position(l_id, _get_drifted_position(l_chunking, l_id, l_random))
		l_moveTime += Time.get_ticks_usec() - l_start
		
		l_start = Time.get_ticks_usec()
		for l_id: int in l_ids:
			l_targeting.update_entity(l_id)
		l_updateTime += Time.get_ticks_usec() - l_start
		
		l_start = Time.get_ticks_usec()
		for l_id: int in l_ids:
			l_targeting.get_target_position(l_id)
		l_positionTime += Time.get_ticks_usec() - l_start
		
		l_start = Time.get_ticks_usec()
		for l_step: int in l_budget:
			l_targeting.search_target(l_ids[(l_cursor + l_step) % p_count])
		l_searchTime += Time.get_ticks_usec() - l_start
		
		l_cursor = (l_cursor + l_budget) % p_count
	
	var l_frames: float = float(FRAME_COUNT)
	var l_total: float = (l_moveTime + l_updateTime + l_positionTime + l_searchTime) / 1000.0 / l_frames
	
	print("%8d | %7.2f | %9.2f | %10.2f | %9.2f | %8.2f | %12.0f" % [p_count,
		l_moveTime / 1000.0 / l_frames, l_updateTime / 1000.0 / l_frames,
		l_positionTime / 1000.0 / l_frames, l_searchTime / 1000.0 / l_frames,
		l_total, 1000.0 / maxf(l_total, 0.001)])


## Registers two fronts facing each other along x. [br]
## @param p_chunking The index to register in [br]
## @param p_targeting The targeting server to register in [br]
## @param p_count How many entities to build [br]
## @param p_random Source of every position [br]
## @return The assigned entity ids
func _build_world(p_chunking: ChunkingServer, p_targeting: TargetingServer, p_count: int,
		p_random: RandomNumberGenerator) -> PackedInt32Array:
	var l_ids: PackedInt32Array = PackedInt32Array()
	var l_width: float = C_ChunkingServer.MAP_SIZE.x
	var l_height: float = C_ChunkingServer.MAP_SIZE.y
	
	var l_targetingData: R_TargetingData = R_TargetingData.new()
	l_targetingData.targetedGroups = 0b111
	l_targetingData.searchChunks = SEARCH_CHUNKS
	
	for l_index: int in p_count:
		var l_team: int = l_index % C_ChunkingServer.TEAM_COUNT
		var l_frontX: float = l_width * (FRONT_OFFSET if l_team == 0 else 1.0 - FRONT_OFFSET)
		var l_position: Vector2 = Vector2(
			clampf(p_random.randfn(l_frontX, l_width * FRONT_SPREAD), 0.0, l_width - 1.0),
			clampf(p_random.randfn(l_height * 0.5, l_height * 0.17), 0.0, l_height - 1.0))
		
		var l_id: int = p_chunking.register_entity(l_position, ENTITY_RADII[l_index % ENTITY_RADII.size()],
			l_team, 1 << (l_index % 3))
		p_targeting.register(l_id, l_targetingData)
		l_ids.append(l_id)
	
	return l_ids


## Drifts an entity a little, the way a moving unit does between two frames. [br]
## @param p_chunking The index the current position is read from [br]
## @param p_id The entity to drift [br]
## @param p_random Source of the drift [br]
## @return The position for this frame
func _get_drifted_position(p_chunking: ChunkingServer, p_id: int,
		p_random: RandomNumberGenerator) -> Vector2:
	var l_position: Vector2 = p_chunking._entityPosition[p_id]
	
	return Vector2(
		clampf(l_position.x + p_random.randf_range(-FRAME_DRIFT, FRAME_DRIFT), 0.0, C_ChunkingServer.MAP_SIZE.x - 1.0),
		clampf(l_position.y + p_random.randf_range(-FRAME_DRIFT, FRAME_DRIFT), 0.0, C_ChunkingServer.MAP_SIZE.y - 1.0))

#endregion
