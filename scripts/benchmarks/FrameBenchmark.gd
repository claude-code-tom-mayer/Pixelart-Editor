extends SceneTree
## Times one simulation frame per entity count, split into the phases a frame really runs. [br]
## Run it headless: godot --headless --script res://scripts/benchmarks/FrameBenchmark.gd
class_name FrameBenchmark

#region CONFIGURATION

## Entity counts every pass is measured at.
const ENTITY_COUNTS: Array[int] = [300, 500, 750, 1000, 3000, 5000, 10000]

## Frames every pass averages over.
const FRAME_COUNT: int = 10

## Searches one frame is allowed to run, however many entities exist.
const SEARCH_BUDGET: int = 150

## How many chunks in each direction the measured searches cover.
const SEARCH_CHUNKS: int = 4

## Radii handed out in turn, so entities span a realistic mix of chunk counts.
const ENTITY_RADII: Array[float] = [12.0, 24.0, 40.0, 90.0]

## Reach of the single target hit every entity fires once per frame.
const HIT_RADIUS: float = 64.0

## Vertical extent every entity occupies and every hit covers.
const HIT_Y_BAND: Vector2 = Vector2(0.0, 64.0)

## How far a front stands from the map edge, as a share of the map width.
const FRONT_OFFSET: float = 0.35

## How wide a front is spread, as a share of the map width.
const FRONT_SPREAD: float = 0.08

## How far an entity drifts per frame, in world units.
const FRAME_DRIFT: float = 6.0

#endregion

#region PRIVATE_VARIABLES

## Position of every entity, kept here so the benchmark never reads server internals.
var _positions: PackedVector2Array = PackedVector2Array()

#endregion

#region LIFECYCLE

## Runs every pass and prints one table, then quits.
func _init() -> void:
	print("")
	print("entities | move ms | update ms | move-to ms | search ms | hit ms | TOTAL ms | fps | landed")
	print("---------+---------+-----------+------------+-----------+--------+----------+-----+-------")
	
	for l_count: int in ENTITY_COUNTS:
		_run_pass(l_count)
	
	print("")
	print("Simulation only, single threaded, no rendering. One single target hit per entity per frame.")
	print("Search budget: %d entities per frame, so each one re-searches every N/%d frames."
		% [SEARCH_BUDGET, SEARCH_BUDGET])
	quit()

#endregion

#region PRIVATE_METHODS

## Builds a world of two fronts and times the phases of one frame in it. [br]
## @param p_count How many entities the pass registers
func _run_pass(p_count: int) -> void:
	var l_api: ApiServer = ApiServer.new()
	var l_random: RandomNumberGenerator = RandomNumberGenerator.new()
	l_random.seed = 11
	
	var l_ids: PackedInt32Array = _build_world(l_api, p_count, l_random)
	var l_hitData: R_HitData = R_HitData.new()
	l_hitData.damage = 1.0
	
	var l_moveTime: int = 0
	var l_updateTime: int = 0
	var l_positionTime: int = 0
	var l_searchTime: int = 0
	var l_hitTime: int = 0
	var l_landed: int = 0
	var l_budget: int = mini(SEARCH_BUDGET, p_count)
	var l_cursor: int = 0
	l_random.seed = 12
	
	for l_frame: int in FRAME_COUNT:
		var l_start: int = Time.get_ticks_usec()
		for l_id: int in l_ids:
			_positions[l_id] = _get_drifted_position(l_id, l_random)
			l_api.set_position(l_id, _positions[l_id])
		l_moveTime += Time.get_ticks_usec() - l_start
		
		l_start = Time.get_ticks_usec()
		for l_id: int in l_ids:
			l_api.update_entity(l_id)
		l_updateTime += Time.get_ticks_usec() - l_start
		
		l_start = Time.get_ticks_usec()
		for l_id: int in l_ids:
			l_api.get_target_position(l_id)
		l_positionTime += Time.get_ticks_usec() - l_start
		
		l_start = Time.get_ticks_usec()
		for l_step: int in l_budget:
			l_api.search_target(l_ids[(l_cursor + l_step) % p_count])
		l_searchTime += Time.get_ticks_usec() - l_start
		l_cursor = (l_cursor + l_budget) % p_count
		
		l_start = Time.get_ticks_usec()
		for l_id: int in l_ids:
			l_landed += l_api.hit_circle_ordered(l_id, _positions[l_id], HIT_RADIUS, HIT_Y_BAND,
				1, C_HitServer.NO_PREFERRED_TARGET, l_hitData).size()
		l_hitTime += Time.get_ticks_usec() - l_start
	
	var l_frames: float = float(FRAME_COUNT)
	var l_total: float = (l_moveTime + l_updateTime + l_positionTime + l_searchTime + l_hitTime) / 1000.0 / l_frames
	
	print("%8d | %7.2f | %9.2f | %10.2f | %9.2f | %6.2f | %8.2f | %3.0f | %6d" % [p_count,
		l_moveTime / 1000.0 / l_frames, l_updateTime / 1000.0 / l_frames,
		l_positionTime / 1000.0 / l_frames, l_searchTime / 1000.0 / l_frames,
		l_hitTime / 1000.0 / l_frames, l_total, 1000.0 / maxf(l_total, 0.001),
		int(l_landed / l_frames)])


## Registers two fronts facing each other along x, armed so their hits connect. [br]
## @param p_api The server every entity is created through [br]
## @param p_count How many entities to build [br]
## @param p_random Source of every position [br]
## @return The assigned entity ids
func _build_world(p_api: ApiServer, p_count: int, p_random: RandomNumberGenerator) -> PackedInt32Array:
	var l_ids: PackedInt32Array = PackedInt32Array()
	var l_mapSize: Vector2 = C_ChunkingServer.get_map_size()
	var l_width: float = l_mapSize.x
	var l_height: float = l_mapSize.y
	_positions = PackedVector2Array()
	
	var l_hitProfile: R_HitProfile = R_HitProfile.new()
	l_hitProfile.yBand = HIT_Y_BAND
	l_hitProfile.hurtGroups = 0b1
	l_hitProfile.hitGroups = 0b1
	
	var l_targetingData: R_TargetingData = R_TargetingData.new()
	l_targetingData.targetedGroups = 0b111
	l_targetingData.searchChunks = SEARCH_CHUNKS
	
	for l_index: int in p_count:
		var l_entityData: R_EntityData = R_EntityData.new()
		l_entityData.radius = ENTITY_RADII[l_index % ENTITY_RADII.size()]
		l_entityData.groups = 1 << (l_index % 3)
		l_entityData.hitProfile = l_hitProfile
		l_entityData.targetingData = l_targetingData
		
		var l_team: int = l_index % C_ChunkingServer.TEAM_COUNT
		var l_frontX: float = l_width * (FRONT_OFFSET if l_team == 0 else 1.0 - FRONT_OFFSET)
		var l_position: Vector2 = Vector2(
			clampf(p_random.randfn(l_frontX, l_width * FRONT_SPREAD), 0.0, l_width - 1.0),
			clampf(p_random.randfn(l_height * 0.5, l_height * 0.17), 0.0, l_height - 1.0))
		
		_positions.append(l_position)
		l_ids.append(p_api.create_entity(l_position, l_team, M_ModuleManager.new(), l_entityData))
	
	return l_ids


## Drifts an entity a little, the way a moving unit does between two frames. [br]
## @param p_id The entity to drift [br]
## @param p_random Source of the drift [br]
## @return The position for this frame
func _get_drifted_position(p_id: int, p_random: RandomNumberGenerator) -> Vector2:
	var l_position: Vector2 = _positions[p_id]
	var l_mapSize: Vector2 = C_ChunkingServer.get_map_size()
	
	return Vector2(
		clampf(l_position.x + p_random.randf_range(-FRAME_DRIFT, FRAME_DRIFT), 0.0, l_mapSize.x - 1.0),
		clampf(l_position.y + p_random.randf_range(-FRAME_DRIFT, FRAME_DRIFT), 0.0, l_mapSize.y - 1.0))

#endregion
