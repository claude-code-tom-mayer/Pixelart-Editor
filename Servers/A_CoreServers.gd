extends Node
class_name A_CoreServers
## Abstract base every server extends: owns every server's data as shared statics, plus the one entity lifecycle. [br]
## register(), pre_unregister(), unregister() and release_removed_ids() live here; everything else stays in the concrete G_ server it belongs to.

#region SIGNALS

## A fresh id was handed out for the first time; nothing needs to react internally anymore, this is for outside listeners.
signal s_entitySlotAppended(p_id: int)

## An entity was announced for removal but is still fully active.
signal s_entityPreUnregistered(p_id: int)

## An entity was removed from every server; its id stays locked until it is released.
signal s_entityUnregistered(p_id: int)

## The id of a removed entity is handed back for reuse; every field of it was just reset to default.
signal s_entityReleased(p_id: int)

#endregion

#region CACHED_VARS

## Cached C_ChunkingServer.MAP_CHUNK_COLUMNS; shared by chunking, hit and targeting.
var MAP_CHUNK_COLUMNS: int

## Cached C_ChunkingServer.MAP_CHUNK_ROWS; shared by chunking and targeting.
var MAP_CHUNK_ROWS: int

## Cached C_ChunkingServer.CHUNK_COUNT; shared by chunking and the lifecycle container sizing below.
var CHUNK_COUNT: int

## Cached C_ChunkingServer.CHUNK_SIZE; shared by chunking's area math.
var CHUNK_SIZE: float

## Cached C_ChunkingServer.TEAM_COUNT; shared by chunking and the lifecycle container sizing below.
var TEAM_COUNT: int

## Cached C_CoreServers.NO_ID; the empty column, slot, center, target and curve sentinel every server shares.
var NO_ID: int

#endregion

#region EXPORTS_AND_VARS

# -----------------------------------------------------------------------
# CHUNKING DATA — the spatial index; G_ChunkingServer is its query surface.
# -----------------------------------------------------------------------

## Team per entity id, as a C_ChunkingServer.TEAM value.
static var _chunkEntityTeam: PackedByteArray = PackedByteArray()

## Bitmask of the groups an entity belongs to.
static var _chunkEntityGroups: PackedInt64Array = PackedInt64Array()

## Current position per entity id.
static var _chunkEntityPosition: PackedVector2Array = PackedVector2Array()

## Effect radius per entity id; decides in how many chunks the entity stands.
static var _chunkEntityRadius: PackedFloat32Array = PackedFloat32Array()

## 1 while an entity is announced for removal but still fully active.
static var _chunkEntityPreUnregistered: PackedByteArray = PackedByteArray()

## 1 while an entity is removed but its id stays locked until it is released.
static var _chunkEntityUnregistering: PackedByteArray = PackedByteArray()

## Chunk the center of an entity sits in; the whole entity is listed there exactly once.
static var _chunkEntityCenterChunk: PackedInt32Array = PackedInt32Array()

## Column of the center chunk of an entity; flat mirror for the targeting hot loop.
static var _chunkEntityCenterColumn: PackedInt32Array = PackedInt32Array()

## Row of the center chunk of an entity; flat mirror for the targeting hot loop.
static var _chunkEntityCenterRow: PackedInt32Array = PackedInt32Array()

## Chunk rectangle an entity covers as (minColumn, minRow, maxColumn, maxRow). [br]
## Lets set_position() and set_radius() drop out before touching any chunk.
static var _chunkEntityChunkArea: Array[Vector4i] = []

## First membership slot of every entity, or NO_ID while it stands nowhere. [br]
## Walking this chain lists every chunk one entity currently stands in.
static var _chunkEntitySlotHead: PackedInt32Array = PackedInt32Array()

## First membership slot of every chunk, or NO_ID while it is empty. [br]
## Walk a chunk with: slot = _chunkHead[c]; while slot != NO_ID: ... slot = _slotChunkNext[slot]
static var _chunkHead: PackedInt32Array = PackedInt32Array()

## Entity every membership slot belongs to; the id a chunk walk reads out.
static var _slotEntity: PackedInt32Array = PackedInt32Array()

## Chunk every membership slot belongs to.
static var _slotChunk: PackedInt32Array = PackedInt32Array()

## Next membership slot inside the chain of the same chunk.
static var _slotChunkNext: PackedInt32Array = PackedInt32Array()

## Previous membership slot inside the chain of the same chunk; makes unlinking O(1).
static var _slotChunkPrev: PackedInt32Array = PackedInt32Array()

## Next membership slot inside the chain of the same entity.
static var _slotEntityNext: PackedInt32Array = PackedInt32Array()

## Previous membership slot inside the chain of the same entity; makes unlinking O(1).
static var _slotEntityPrev: PackedInt32Array = PackedInt32Array()

## Membership slots that may be handed out again.
static var _freeSlots: PackedInt32Array = PackedInt32Array()

## First entity whose center sits in a chunk, or NO_ID while none does. [br]
## Walk it with: id = _centerHead[c]; while id != NO_ID: ... id = _centerNext[id]
static var _centerHead: PackedInt32Array = PackedInt32Array()

## Next entity inside the center chain of its chunk.
static var _centerNext: PackedInt32Array = PackedInt32Array()

## Previous entity inside the center chain of its chunk; makes unlinking O(1).
static var _centerPrev: PackedInt32Array = PackedInt32Array()

## Entity count per team and chunk, addressed by _get_team_chunk_index().
static var _chunkCounts: PackedInt32Array = PackedInt32Array()

## Entity count per team and column, addressed by _get_team_column_index().
static var _columnCounts: PackedInt32Array = PackedInt32Array()

## Group bitmask per team and chunk, addressed by _get_team_chunk_index().
static var _chunkGroups: PackedInt64Array = PackedInt64Array()

## Group bitmask per team and column — the OR of the chunk masks of that column. [br]
## Columns are the aggregation level because the two bases face each other along x.
static var _columnGroups: PackedInt64Array = PackedInt64Array()

## Group bitmask per team over the whole map — the OR of all column masks.
static var _mapGroups: PackedInt64Array = PackedInt64Array()

## Entity count per team over the whole map.
static var _mapCounts: PackedInt32Array = PackedInt32Array()

## Lowest column a team occupies, or NO_ID while it holds nothing. [br]
## Answers "is anything of that team further left" without walking the columns.
static var _teamMinColumn: PackedInt32Array = PackedInt32Array()

## Highest column a team occupies, or NO_ID while it holds nothing.
static var _teamMaxColumn: PackedInt32Array = PackedInt32Array()

## Ids removed since the last release; moved into the free list by release_removed_ids().
static var _pendingFreeIds: PackedInt32Array = PackedInt32Array()

## Entity ids that may be reused; only filled by release_removed_ids().
static var _freeIds: PackedInt32Array = PackedInt32Array()

# -----------------------------------------------------------------------
# HIT DATA — the hit side of every entity; G_HitServer is its query surface.
# -----------------------------------------------------------------------

## Module management per entity id; receives every hit that connects with it.
static var _hitEntityModules: Array[M_ModuleManager] = []

## Vertical extent per entity as (bottom, top); the third axis next to the 2D position.
static var _hitEntityYBand: PackedVector2Array = PackedVector2Array()

## Bitmask of the hit groups an entity can be harmed by.
static var _hitEntityHurtGroups: PackedInt64Array = PackedInt64Array()

## Bitmask of the hit groups the hits of an entity carry.
static var _hitEntityHitGroups: PackedInt64Array = PackedInt64Array()

## Bitmask of the hurt groups that end a hit of this entity on the target they match.
static var _hitEntityStopGroups: PackedInt64Array = PackedInt64Array()

## Curve slot per entity, or NO_ID while its radius is constant over the height.
static var _hitEntityCurveIndex: PackedInt32Array = PackedInt32Array()

## Hit query that last looked at an entity; turns the candidate dedup into one compare.
static var _hitEntityVisitStamp: PackedInt32Array = PackedInt32Array()

## Curve stored in every slot; kept only to recognise it again and to free the slot.
static var _radiiCurves: Array[Curve] = []

## Every curve slot baked into C_HitServer.CURVE_SAMPLE_COUNT samples, one block per slot. [br]
## A hit reads two floats and interpolates, instead of calling into the Curve object.
static var _curveSamples: PackedFloat32Array = PackedFloat32Array()

## Slot every stored curve sits in, so one archetype never fills more than one slot.
static var _curveSlotOf: Dictionary[Curve, int] = {}

## Entities using each curve slot; the slot returns to the free list when it drops to zero.
static var _curveUsers: PackedInt32Array = PackedInt32Array()

## Curve slots of dropped profiles, ready to be handed out again.
static var _freeCurveIndices: PackedInt32Array = PackedInt32Array()

## Profile every entity registered without one falls back to.
static var _defaultHitProfile: R_HitProfile = null

## Set once a preferred target was passed with a hit limit other than one. [br]
## Keeps the warning about that out of the per hit path after it was reported.
static var _hasWarnedPreferredMisuse: bool = false

## Candidates of the running hit, live up to _hitCandidateCount.
static var _hitCandidateIds: PackedInt32Array = PackedInt32Array()

## How many candidates of _hitCandidateIds belong to the running hit.
static var _hitCandidateCount: int = 0

## Targets the shape accepted, live up to _hitCount.
static var _hitIds: PackedInt32Array = PackedInt32Array()

## Sort key of every accepted target, parallel to _hitIds.
static var _hitKeys: PackedFloat32Array = PackedFloat32Array()

## Impact position of every accepted target, parallel to _hitIds.
static var _hitPositions: PackedVector3Array = PackedVector3Array()

## How many targets of the hit buffers belong to the running hit.
static var _hitCount: int = 0

## Indices into the hit buffers in the order an ordered hit applies them.
static var _hitOrder: PackedInt32Array = PackedInt32Array()

## Counter handed to every gather, so stamps of earlier hits can never collide.
static var _hitVisitStamp: int = 0

# -----------------------------------------------------------------------
# TARGETING DATA — the targeting side of every entity; G_TargetingServer is its query surface.
# -----------------------------------------------------------------------

## Bitmask of the groups an entity may go after.
static var _targetingEntityTargetedGroups: PackedInt64Array = PackedInt64Array()

## Current C_TargetingServer.STATE per entity.
static var _targetingEntityState: PackedByteArray = PackedByteArray()

## How many chunks in each direction a search of this entity covers.
static var _targetingEntitySearchChunks: PackedInt32Array = PackedInt32Array()

## A targeter closer than this many chunks makes the entity flee.
static var _targetingEntityFleeChunks: PackedInt32Array = PackedInt32Array()

## Real distance at which approaching turns into combat, measured to the edge of the target.
static var _targetingEntityHitRange: PackedFloat32Array = PackedFloat32Array()

## Bitmask of the groups an entity goes after before it considers the normal ones.
static var _targetingEntityPriorityTargetedGroups: PackedInt64Array = PackedInt64Array()

## Invisibility and focus flags of an entity, as C_TargetingServer.FLAG bits.
static var _targetingEntityFlags: PackedByteArray = PackedByteArray()

## Target of an entity, or NO_ID.
static var _targetingEntityTarget: PackedInt32Array = PackedInt32Array()

## Own slot inside the targeter list of the target; makes dropping a target O(1).
static var _targetingEntityTargeterIndex: PackedInt32Array = PackedInt32Array()

## Ids that currently target this entity; its size is the crowding count.
static var _targetersOf: Array[PackedInt32Array] = []

## The entity the running search belongs to.
static var _searchId: int = C_CoreServers.NO_ID

## Team of the searcher, a C_ChunkingServer.TEAM value.
static var _searchTeam: int = 0

## Column of the center chunk of the searcher.
static var _searchColumn: int = 0

## Row of the center chunk of the searcher.
static var _searchRow: int = 0

## Flags of the searcher, as C_TargetingServer.FLAG bits.
static var _searchFlags: int = 0

## How many chunks in each direction the running search covers.
static var _searchReach: int = 0

## Direction the searcher marches in along x; decides what counts as behind it.
static var _searchForwardSign: int = 1

## Every group the searcher accepts, priority ones included.
static var _searchGroups: int = 0

## Groups the searcher goes after before it considers the normal ones.
static var _searchPriorityGroups: int = 0

## Best priority candidate so far, or NO_ID.
static var _searchBestPriorityId: int = C_CoreServers.NO_ID

## Score of the best priority candidate so far.
static var _searchBestPriorityScore: float = 0.0

## Best normal candidate so far, or NO_ID.
static var _searchBestNormalId: int = C_CoreServers.NO_ID

## Score of the best normal candidate so far.
static var _searchBestNormalScore: float = 0.0

#endregion

#region LIFECYCLE_AND_METHODS

## Caches the constants shared by more than one server, including the C_CoreServers.NO_ID sentinel every server uses, and allocates the chunk, column and map containers. [br]
## Runs once per server instance; the resizes it performs are idempotent, so it is harmless that all three run it.
func _init() -> void:
	MAP_CHUNK_COLUMNS = C_ChunkingServer.MAP_CHUNK_COLUMNS
	MAP_CHUNK_ROWS = C_ChunkingServer.MAP_CHUNK_ROWS
	CHUNK_COUNT = C_ChunkingServer.CHUNK_COUNT
	CHUNK_SIZE = C_ChunkingServer.CHUNK_SIZE
	TEAM_COUNT = C_ChunkingServer.TEAM_COUNT
	NO_ID = C_CoreServers.NO_ID

	var l_chunkSlots: int = TEAM_COUNT * CHUNK_COUNT
	var l_columnSlots: int = TEAM_COUNT * MAP_CHUNK_COLUMNS

	_chunkGroups.resize(l_chunkSlots)
	_chunkCounts.resize(l_chunkSlots)
	_columnGroups.resize(l_columnSlots)
	_columnCounts.resize(l_columnSlots)
	_mapGroups.resize(TEAM_COUNT)
	_mapCounts.resize(TEAM_COUNT)

	_teamMinColumn.resize(TEAM_COUNT)
	_teamMaxColumn.resize(TEAM_COUNT)
	_teamMinColumn.fill(NO_ID)
	_teamMaxColumn.fill(NO_ID)

	_chunkHead.resize(CHUNK_COUNT)
	_centerHead.resize(CHUNK_COUNT)
	_chunkHead.fill(NO_ID)
	_centerHead.fill(NO_ID)


## Registers a new entity on every server at once; the returned id is what every server addresses it by. [br]
## A null hit profile or targeting data falls back to defaults, which carry no groups — the entity is then inert. [br]
## @param p_position Start position of the entity [br]
## @param p_radius Effect radius of the entity [br]
## @param p_team Team of the entity, a C_ChunkingServer.TEAM value [br]
## @param p_groups Bitmask of the chunking groups the entity belongs to [br]
## @param p_module Module management that receives its hits, or null [br]
## @param p_hitProfile Band, groups and radius profile of its hit side, or null for the default [br]
## @param p_targetingData Groups, ranges and flags of its targeting side, or null for the default [br]
## @return The assigned entity id
func register(p_position: Vector2, p_radius: float, p_team: int, p_groups: int,
		p_module: M_ModuleManager, p_hitProfile: R_HitProfile, p_targetingData: R_TargetingData) -> int:
	assert(p_team >= 0 and p_team < TEAM_COUNT, "A_CoreServers: register() got an unknown team.")

	var l_id: int = _acquire_id()

	_register_chunking_side(l_id, p_position, p_radius, p_team, p_groups)
	_register_hit_side(l_id, p_module, p_hitProfile)
	_register_targeting_side(l_id, p_targetingData)

	return l_id


## Marks an entity for removal on every server; it stays fully active and queryable. [br]
## @param p_id The entity id to mark
func pre_unregister(p_id: int) -> void:
	_chunkEntityPreUnregistered[p_id] = 1
	drop_targeters(p_id)

	s_entityPreUnregistered.emit(p_id)


## Removes an entity from every server and locks its id until it is released. [br]
## Does nothing for an id that is already removed, so a double removal cannot free it twice. [br]
## @param p_id The entity id to remove
func unregister(p_id: int) -> void:
	if (_chunkEntityUnregistering[p_id] == 1):
		return

	_chunkEntityUnregistering[p_id] = 1
	_drop_target(p_id)
	drop_targeters(p_id)

	s_entityUnregistered.emit(p_id)

	var l_slot: int = _chunkEntitySlotHead[p_id]
	while (l_slot != NO_ID):
		var l_nextSlot: int = _slotEntityNext[l_slot]
		_remove_slot_from_chunk(l_slot)
		l_slot = l_nextSlot

	_remove_center_from_chunk(p_id)
	_pendingFreeIds.append(p_id)


## Hands the ids of removed entities back for reuse and resets every field of every server for them. [br]
## Call once after every server that could still hold a removed id has run.
func release_removed_ids() -> void:
	for l_id: int in _pendingFreeIds:
		_chunkEntityUnregistering[l_id] = 0
		_chunkEntityPreUnregistered[l_id] = 0

		_hitEntityModules[l_id] = null
		_hitEntityYBand[l_id] = Vector2.ZERO
		_hitEntityHurtGroups[l_id] = 0
		_hitEntityHitGroups[l_id] = 0
		_hitEntityStopGroups[l_id] = 0
		_hitEntityVisitStamp[l_id] = 0
		_release_curve(l_id)

		_targetingEntityTargetedGroups[l_id] = 0
		_targetingEntityState[l_id] = C_TargetingServer.STATE.SEARCH
		_targetingEntitySearchChunks[l_id] = 0
		_targetingEntityFleeChunks[l_id] = 0
		_targetingEntityHitRange[l_id] = 0.0
		_targetingEntityPriorityTargetedGroups[l_id] = 0
		_targetingEntityFlags[l_id] = 0
		_targetingEntityTarget[l_id] = NO_ID
		_targetingEntityTargeterIndex[l_id] = 0
		_targetersOf[l_id] = PackedInt32Array()

		_freeIds.append(l_id)
		s_entityReleased.emit(l_id)

	_pendingFreeIds.clear()


## Makes every entity that targets this one drop it and look for something else. [br]
## Public because set_invisible() also drops targeters that lose sight of an entity, outside registration. [br]
## @param p_id The entity that is no longer worth targeting
func drop_targeters(p_id: int) -> void:
	var l_targeters: PackedInt32Array = _targetersOf[p_id].duplicate()

	for l_targeterId: int in l_targeters:
		_drop_target(l_targeterId)


## Sets the radius profile of an entity; null gives it a constant radius again. [br]
## Entities sharing one curve share its slot, so profiles cost per archetype, not per entity. [br]
## @param p_id The entity to change [br]
## @param p_curve The profile to sample, or null
func _apply_radius_curve(p_id: int, p_curve: Curve) -> void:
	if (p_curve == null):
		_release_curve(p_id)
		return

	var l_curveIndex: int = _curveSlotOf.get(p_curve, NO_ID)

	if (l_curveIndex != NO_ID and l_curveIndex == _hitEntityCurveIndex[p_id]):
		return

	_release_curve(p_id)

	if (l_curveIndex == NO_ID):
		l_curveIndex = _acquire_curve_slot(p_curve)

	_curveUsers[l_curveIndex] += 1
	_hitEntityCurveIndex[p_id] = l_curveIndex


## Fills in the chunking side of a freshly acquired id: team, groups, position, radius and its chunk membership. [br]
## @param p_id The id to fill in [br]
## @param p_position Start position of the entity [br]
## @param p_radius Effect radius of the entity [br]
## @param p_team Team of the entity, a C_ChunkingServer.TEAM value [br]
## @param p_groups Bitmask of the chunking groups the entity belongs to
func _register_chunking_side(p_id: int, p_position: Vector2, p_radius: float, p_team: int, p_groups: int) -> void:
	_chunkEntityTeam[p_id] = p_team
	_chunkEntityGroups[p_id] = p_groups
	_chunkEntityPosition[p_id] = p_position
	_chunkEntityRadius[p_id] = p_radius

	var l_area: Vector4i = _compute_chunk_area(p_position, p_radius)
	_chunkEntityChunkArea[p_id] = l_area

	for l_row: int in range(l_area.y, l_area.w + 1):
		var l_rowOffset: int = l_row * MAP_CHUNK_COLUMNS

		for l_column: int in range(l_area.x, l_area.z + 1):
			_add_entity_to_chunk(p_id, l_rowOffset + l_column)

	_chunkEntityCenterChunk[p_id] = NO_ID
	_apply_center_chunk(p_id, p_position)


## Fills in the hit side of a freshly acquired id, falling back to the shared default profile. [br]
## @param p_id The id to fill in [br]
## @param p_module Module management that receives its hits, or null [br]
## @param p_hitProfile Band, groups and radius profile of its hit side, or null for the default
func _register_hit_side(p_id: int, p_module: M_ModuleManager, p_hitProfile: R_HitProfile) -> void:
	var l_hitProfile: R_HitProfile = p_hitProfile

	if (l_hitProfile == null):
		l_hitProfile = _get_default_hit_profile()

	_hitEntityModules[p_id] = p_module
	_hitEntityYBand[p_id] = l_hitProfile.yBand
	_hitEntityHurtGroups[p_id] = l_hitProfile.hurtGroups
	_hitEntityHitGroups[p_id] = l_hitProfile.hitGroups
	_hitEntityStopGroups[p_id] = l_hitProfile.stopGroups

	_apply_radius_curve(p_id, l_hitProfile.radiusCurve)


## Fills in the targeting side of a freshly acquired id, falling back to plain defaults. [br]
## @param p_id The id to fill in [br]
## @param p_targetingData Groups, ranges and flags of its targeting side, or null for the default
func _register_targeting_side(p_id: int, p_targetingData: R_TargetingData) -> void:
	var l_targetingData: R_TargetingData = p_targetingData

	if (l_targetingData == null):
		l_targetingData = R_TargetingData.new()

	_targetingEntityTargetedGroups[p_id] = l_targetingData.targetedGroups
	_targetingEntitySearchChunks[p_id] = l_targetingData.searchChunks
	_targetingEntityFleeChunks[p_id] = l_targetingData.fleeChunks
	_targetingEntityHitRange[p_id] = l_targetingData.hitRange
	_targetingEntityPriorityTargetedGroups[p_id] = l_targetingData.priorityTargetedGroups
	_targetingEntityFlags[p_id] = _build_flags(l_targetingData)


## Packs the flag booleans of a targeting setup into one byte. [br]
## @param p_targetingData The setup to read [br]
## @return The packed flags
func _build_flags(p_targetingData: R_TargetingData) -> int:
	var l_flags: int = 0

	if (p_targetingData.isInvisible):
		l_flags |= C_TargetingServer.FLAG_INVISIBLE

	if (p_targetingData.canTargetInvisible):
		l_flags |= C_TargetingServer.FLAG_TARGETS_INVISIBLE

	if (p_targetingData.hasFocus):
		l_flags |= C_TargetingServer.FLAG_HAS_FOCUS

	if (p_targetingData.isIgnoringFocus):
		l_flags |= C_TargetingServer.FLAG_IGNORES_FOCUS

	return l_flags


## Unlinks an entity from its target by swap-and-pop and sends it back to searching. [br]
## @param p_id The entity that gives up its target
func _drop_target(p_id: int) -> void:
	var l_targetId: int = _targetingEntityTarget[p_id]

	if (l_targetId == NO_ID):
		return

	var l_targeters: PackedInt32Array = _targetersOf[l_targetId]
	var l_slot: int = _targetingEntityTargeterIndex[p_id]
	var l_lastSlot: int = l_targeters.size() - 1
	var l_movedId: int = l_targeters[l_lastSlot]

	l_targeters[l_slot] = l_movedId
	l_targeters.resize(l_lastSlot)
	_targetersOf[l_targetId] = l_targeters
	_targetingEntityTargeterIndex[l_movedId] = l_slot

	_targetingEntityTarget[p_id] = NO_ID
	_targetingEntityState[p_id] = C_TargetingServer.STATE.SEARCH


## Takes a free entity id or appends a fresh slot to every container of every server. [br]
## @return The id the next entity is stored under
func _acquire_id() -> int:
	var l_lastFreeIndex: int = _freeIds.size() - 1

	if (l_lastFreeIndex >= 0):
		var l_reusedId: int = _freeIds[l_lastFreeIndex]
		_freeIds.remove_at(l_lastFreeIndex)
		return l_reusedId

	_chunkEntityTeam.append(0)
	_chunkEntityGroups.append(0)
	_chunkEntityPosition.append(Vector2.ZERO)
	_chunkEntityRadius.append(0.0)
	_chunkEntityPreUnregistered.append(0)
	_chunkEntityUnregistering.append(0)
	_chunkEntityChunkArea.append(Vector4i.ZERO)
	_chunkEntitySlotHead.append(NO_ID)
	_chunkEntityCenterChunk.append(NO_ID)
	_chunkEntityCenterColumn.append(0)
	_chunkEntityCenterRow.append(0)
	_centerNext.append(NO_ID)
	_centerPrev.append(NO_ID)

	_hitEntityModules.append(null)
	_hitEntityYBand.append(Vector2.ZERO)
	_hitEntityHurtGroups.append(0)
	_hitEntityHitGroups.append(0)
	_hitEntityStopGroups.append(0)
	_hitEntityCurveIndex.append(NO_ID)
	_hitEntityVisitStamp.append(0)

	_targetingEntityTargetedGroups.append(0)
	_targetingEntityState.append(C_TargetingServer.STATE.SEARCH)
	_targetingEntitySearchChunks.append(0)
	_targetingEntityFleeChunks.append(0)
	_targetingEntityHitRange.append(0.0)
	_targetingEntityPriorityTargetedGroups.append(0)
	_targetingEntityFlags.append(0)
	_targetingEntityTarget.append(NO_ID)
	_targetingEntityTargeterIndex.append(0)
	_targetersOf.append(PackedInt32Array())

	var l_id: int = _chunkEntityTeam.size() - 1
	s_entitySlotAppended.emit(l_id)

	return l_id


## Builds the fallback profile for entities registered without one, once. [br]
## @return The shared default profile
func _get_default_hit_profile() -> R_HitProfile:
	if (_defaultHitProfile == null):
		_defaultHitProfile = R_HitProfile.new()

	return _defaultHitProfile


## Calculates the chunk rectangle a position and radius cover, clamped to the map. [br]
## Allocation free, so callers can compare it against the last area before doing any work. [br]
## @param p_position Center of the covered area [br]
## @param p_radius Radius of the covered area [br]
## @return The rectangle as (minColumn, minRow, maxColumn, maxRow)
func _compute_chunk_area(p_position: Vector2, p_radius: float) -> Vector4i:
	var l_extent: Vector2 = Vector2(p_radius, p_radius)
	return G_ChunkingServer.compute_chunk_area_from_bounds(p_position - l_extent, p_position + l_extent)


## Moves an entity onto a new chunk rectangle, touching only the chunks it entered or left. [br]
## Returns at once while it is unchanged; otherwise a bounds test per chunk tells both sides apart. [br]
## @param p_id The entity id to update [br]
## @param p_area The new rectangle as (minColumn, minRow, maxColumn, maxRow)
func _apply_chunk_area(p_id: int, p_area: Vector4i) -> void:
	var l_oldArea: Vector4i = _chunkEntityChunkArea[p_id]

	if (p_area == l_oldArea):
		return

	_chunkEntityChunkArea[p_id] = p_area

	var l_slot: int = _chunkEntitySlotHead[p_id]
	while (l_slot != NO_ID):
		var l_nextSlot: int = _slotEntityNext[l_slot]

		if (not _is_chunk_in_area(_slotChunk[l_slot], p_area)):
			_remove_slot_from_chunk(l_slot)

		l_slot = l_nextSlot

	for l_row: int in range(p_area.y, p_area.w + 1):
		var l_rowOffset: int = l_row * MAP_CHUNK_COLUMNS
		var l_isRowNew: bool = l_row < l_oldArea.y or l_row > l_oldArea.w

		for l_column: int in range(p_area.x, p_area.z + 1):
			if (l_isRowNew or l_column < l_oldArea.x or l_column > l_oldArea.z):
				_add_entity_to_chunk(p_id, l_rowOffset + l_column)


## Checks whether a chunk lies inside a chunk rectangle. [br]
## @param p_chunkId The chunk to place [br]
## @param p_area The rectangle as (minColumn, minRow, maxColumn, maxRow) [br]
## @return true if the chunk is part of the rectangle
func _is_chunk_in_area(p_chunkId: int, p_area: Vector4i) -> bool:
	var l_column: int = p_chunkId % MAP_CHUNK_COLUMNS

	if (l_column < p_area.x or l_column > p_area.z):
		return false

	@warning_ignore("integer_division")
	var l_row: int = p_chunkId / MAP_CHUNK_COLUMNS

	return l_row >= p_area.y and l_row <= p_area.w


## Moves the center of an entity into the chunk its position falls into. [br]
## Drops out while the center chunk is unchanged, which is the common case when moving. [br]
## @param p_id The entity id to update [br]
## @param p_position The position the center is taken from
func _apply_center_chunk(p_id: int, p_position: Vector2) -> void:
	var l_column: int = clampi(floori(p_position.x / CHUNK_SIZE), 0, MAP_CHUNK_COLUMNS - 1)
	var l_row: int = clampi(floori(p_position.y / CHUNK_SIZE), 0, MAP_CHUNK_ROWS - 1)
	var l_chunkId: int = l_row * MAP_CHUNK_COLUMNS + l_column

	if (l_chunkId == _chunkEntityCenterChunk[p_id]):
		return

	_remove_center_from_chunk(p_id)

	var l_head: int = _centerHead[l_chunkId]
	_centerPrev[p_id] = NO_ID
	_centerNext[p_id] = l_head

	if (l_head != NO_ID):
		_centerPrev[l_head] = p_id

	_centerHead[l_chunkId] = p_id
	_chunkEntityCenterChunk[p_id] = l_chunkId
	_chunkEntityCenterColumn[p_id] = l_column
	_chunkEntityCenterRow[p_id] = l_row


## Unlinks the center of an entity from the chain of its chunk. [br]
## @param p_id The entity whose center is removed
func _remove_center_from_chunk(p_id: int) -> void:
	var l_chunkId: int = _chunkEntityCenterChunk[p_id]

	if (l_chunkId == NO_ID):
		return

	var l_next: int = _centerNext[p_id]
	var l_prev: int = _centerPrev[p_id]

	if (l_prev == NO_ID):
		_centerHead[l_chunkId] = l_next
	else:
		_centerNext[l_prev] = l_next

	if (l_next != NO_ID):
		_centerPrev[l_next] = l_prev

	_chunkEntityCenterChunk[p_id] = NO_ID


## Adds an entity to a chunk and cascades its groups upwards while they change. [br]
## Links one membership slot into the chain of the chunk and of the entity; no list is ever copied. [br]
## @param p_id The entity id to add [br]
## @param p_chunkId The target chunk
func _add_entity_to_chunk(p_id: int, p_chunkId: int) -> void:
	var l_slot: int = _acquire_slot()

	_slotEntity[l_slot] = p_id
	_slotChunk[l_slot] = p_chunkId

	var l_chunkHead: int = _chunkHead[p_chunkId]
	_slotChunkPrev[l_slot] = NO_ID
	_slotChunkNext[l_slot] = l_chunkHead

	if (l_chunkHead != NO_ID):
		_slotChunkPrev[l_chunkHead] = l_slot

	_chunkHead[p_chunkId] = l_slot

	var l_entityHead: int = _chunkEntitySlotHead[p_id]
	_slotEntityPrev[l_slot] = NO_ID
	_slotEntityNext[l_slot] = l_entityHead

	if (l_entityHead != NO_ID):
		_slotEntityPrev[l_entityHead] = l_slot

	_chunkEntitySlotHead[p_id] = l_slot

	var l_team: int = _chunkEntityTeam[p_id]
	var l_groups: int = _chunkEntityGroups[p_id]
	var l_chunkIndex: int = _get_team_chunk_index(l_team, p_chunkId)
	var l_mergedGroups: int = _chunkGroups[l_chunkIndex] | l_groups

	_apply_count_delta(p_chunkId, l_team, 1)

	if (l_mergedGroups == _chunkGroups[l_chunkIndex]):
		return

	_chunkGroups[l_chunkIndex] = l_mergedGroups

	if (_apply_group_to_column(_get_column_index(p_chunkId), l_team, l_groups)):
		_apply_group_to_map(l_team, l_groups)


## Unlinks one membership slot and rebuilds the masks upwards while they change. [br]
## Unlinking is a fixed number of integer writes, whatever the chunk holds. [br]
## @param p_slot The membership slot to drop
func _remove_slot_from_chunk(p_slot: int) -> void:
	var l_id: int = _slotEntity[p_slot]
	var l_chunkId: int = _slotChunk[p_slot]

	var l_next: int = _slotChunkNext[p_slot]
	var l_prev: int = _slotChunkPrev[p_slot]

	if (l_prev == NO_ID):
		_chunkHead[l_chunkId] = l_next
	else:
		_slotChunkNext[l_prev] = l_next

	if (l_next != NO_ID):
		_slotChunkPrev[l_next] = l_prev

	l_next = _slotEntityNext[p_slot]
	l_prev = _slotEntityPrev[p_slot]

	if (l_prev == NO_ID):
		_chunkEntitySlotHead[l_id] = l_next
	else:
		_slotEntityNext[l_prev] = l_next

	if (l_next != NO_ID):
		_slotEntityPrev[l_next] = l_prev

	_freeSlots.append(p_slot)

	var l_team: int = _chunkEntityTeam[l_id]
	_apply_count_delta(l_chunkId, l_team, -1)

	if (_rebuild_chunk_groups(l_chunkId, l_team)):
		if (_rebuild_column_groups(_get_column_index(l_chunkId), l_team)):
			_rebuild_map_groups(l_team)


## Takes a free membership slot or appends a fresh one to every slot column. [br]
## @return The slot the next membership is stored under
func _acquire_slot() -> int:
	var l_lastFreeIndex: int = _freeSlots.size() - 1

	if (l_lastFreeIndex >= 0):
		var l_reusedSlot: int = _freeSlots[l_lastFreeIndex]
		_freeSlots.resize(l_lastFreeIndex)
		return l_reusedSlot

	_slotEntity.append(0)
	_slotChunk.append(0)
	_slotChunkNext.append(NO_ID)
	_slotChunkPrev.append(NO_ID)
	_slotEntityNext.append(NO_ID)
	_slotEntityPrev.append(NO_ID)

	return _slotEntity.size() - 1


## Writes a count change through to chunk, column and map and keeps the column span current. [br]
## @param p_chunkId The chunk the entity was added to or removed from [br]
## @param p_team Team whose counts change, a C_ChunkingServer.TEAM value [br]
## @param p_delta The change to apply, 1 when adding and -1 when removing
func _apply_count_delta(p_chunkId: int, p_team: int, p_delta: int) -> void:
	var l_column: int = p_chunkId % MAP_CHUNK_COLUMNS
	var l_columnIndex: int = p_team * MAP_CHUNK_COLUMNS + l_column
	var l_columnCountBefore: int = _columnCounts[l_columnIndex]

	_chunkCounts[p_team * CHUNK_COUNT + p_chunkId] += p_delta
	_columnCounts[l_columnIndex] = l_columnCountBefore + p_delta
	_mapCounts[p_team] += p_delta

	if (p_delta > 0 and l_columnCountBefore == 0):
		_extend_team_columns(p_team, l_column)
	elif (p_delta < 0 and l_columnCountBefore + p_delta == 0):
		_shrink_team_columns(p_team, l_column)


## Widens the occupied column span of a team by a column that just filled up. [br]
## @param p_team The team whose span grows [br]
## @param p_columnIndex The column that now holds entities
func _extend_team_columns(p_team: int, p_columnIndex: int) -> void:
	if (_teamMinColumn[p_team] == NO_ID or p_columnIndex < _teamMinColumn[p_team]):
		_teamMinColumn[p_team] = p_columnIndex

	if (_teamMaxColumn[p_team] == NO_ID or p_columnIndex > _teamMaxColumn[p_team]):
		_teamMaxColumn[p_team] = p_columnIndex


## Pulls the occupied column span of a team in after a column ran empty. [br]
## Only scans when the emptied column was the span edge itself, so the cost amortises away. [br]
## @param p_team The team whose span shrinks [br]
## @param p_columnIndex The column that ran empty
func _shrink_team_columns(p_team: int, p_columnIndex: int) -> void:
	if (_mapCounts[p_team] == 0):
		_teamMinColumn[p_team] = NO_ID
		_teamMaxColumn[p_team] = NO_ID
		return

	var l_firstColumnIndex: int = p_team * MAP_CHUNK_COLUMNS

	if (p_columnIndex == _teamMinColumn[p_team]):
		var l_column: int = p_columnIndex + 1

		while (_columnCounts[l_firstColumnIndex + l_column] == 0):
			l_column += 1

		_teamMinColumn[p_team] = l_column

	if (p_columnIndex == _teamMaxColumn[p_team]):
		var l_column: int = p_columnIndex - 1

		while (_columnCounts[l_firstColumnIndex + l_column] == 0):
			l_column -= 1

		_teamMaxColumn[p_team] = l_column


## Rebuilds the group mask of a chunk from the entities still standing in it. [br]
## Only reached while removing, so the mask can only shrink and the scan stops once it reaches the old value. [br]
## @param p_chunkId The chunk to rebuild [br]
## @param p_team Team whose mask is rebuilt, a C_ChunkingServer.TEAM value [br]
## @return true if the mask value changed
func _rebuild_chunk_groups(p_chunkId: int, p_team: int) -> bool:
	var l_chunkIndex: int = _get_team_chunk_index(p_team, p_chunkId)
	var l_oldGroups: int = _chunkGroups[l_chunkIndex]
	var l_groups: int = 0

	var l_slot: int = _chunkHead[p_chunkId]
	while (l_slot != NO_ID):
		var l_id: int = _slotEntity[l_slot]

		if (_chunkEntityTeam[l_id] == p_team):
			l_groups |= _chunkEntityGroups[l_id]

			if (l_groups == l_oldGroups):
				break

		l_slot = _slotChunkNext[l_slot]

	if (l_groups == l_oldGroups):
		return false

	_chunkGroups[l_chunkIndex] = l_groups
	return true


## Merges a group mask into a column mask — counterpart of the add path. [br]
## @param p_columnIndex The column to extend [br]
## @param p_team Team whose mask is extended, a C_ChunkingServer.TEAM value [br]
## @param p_groups The group bits to merge in [br]
## @return true if the mask value changed
func _apply_group_to_column(p_columnIndex: int, p_team: int, p_groups: int) -> bool:
	var l_columnIndex: int = _get_team_column_index(p_team, p_columnIndex)
	var l_mergedGroups: int = _columnGroups[l_columnIndex] | p_groups

	if (l_mergedGroups == _columnGroups[l_columnIndex]):
		return false

	_columnGroups[l_columnIndex] = l_mergedGroups
	return true


## Rebuilds a column mask from the chunk masks of that column — counterpart of the remove path. [br]
## Stops as soon as the old value is reached again, because the mask can only shrink here. [br]
## @param p_columnIndex The column to rebuild [br]
## @param p_team Team whose mask is rebuilt, a C_ChunkingServer.TEAM value [br]
## @return true if the mask value changed
func _rebuild_column_groups(p_columnIndex: int, p_team: int) -> bool:
	var l_columnIndex: int = _get_team_column_index(p_team, p_columnIndex)
	var l_oldGroups: int = _columnGroups[l_columnIndex]
	var l_groups: int = 0
	var l_firstChunkIndex: int = _get_team_chunk_index(p_team, p_columnIndex)

	for l_rowOffset: int in MAP_CHUNK_ROWS:
		l_groups |= _chunkGroups[l_firstChunkIndex + l_rowOffset * MAP_CHUNK_COLUMNS]

		if (l_groups == l_oldGroups):
			break

	if (l_groups == l_oldGroups):
		return false

	_columnGroups[l_columnIndex] = l_groups
	return true


## Merges a group mask into the map mask — last step of the add cascade. [br]
## @param p_team Team whose mask is extended, a C_ChunkingServer.TEAM value [br]
## @param p_groups The group bits to merge in
func _apply_group_to_map(p_team: int, p_groups: int) -> void:
	_mapGroups[p_team] |= p_groups


## Rebuilds the map mask from all column masks, never from chunks directly. [br]
## Stops as soon as the old value is reached again, because the mask can only shrink here. [br]
## @param p_team Team whose mask is rebuilt, a C_ChunkingServer.TEAM value
func _rebuild_map_groups(p_team: int) -> void:
	var l_oldGroups: int = _mapGroups[p_team]
	var l_groups: int = 0
	var l_firstColumnIndex: int = _get_team_column_index(p_team, 0)

	for l_columnOffset: int in MAP_CHUNK_COLUMNS:
		l_groups |= _columnGroups[l_firstColumnIndex + l_columnOffset]

		if (l_groups == l_oldGroups):
			return

	_mapGroups[p_team] = l_groups


## Determines the column a chunk belongs to. [br]
## @param p_chunkId The chunk to resolve [br]
## @return The column index of that chunk
func _get_column_index(p_chunkId: int) -> int:
	return p_chunkId % MAP_CHUNK_COLUMNS


## Maps team and chunk onto the slot inside the per team chunk containers. [br]
## @param p_team Team block to address, a C_ChunkingServer.TEAM value [br]
## @param p_chunkId The chunk inside that block [br]
## @return The flat container index
func _get_team_chunk_index(p_team: int, p_chunkId: int) -> int:
	return p_team * CHUNK_COUNT + p_chunkId


## Maps team and column onto the slot inside the per team column containers. [br]
## @param p_team Team block to address, a C_ChunkingServer.TEAM value [br]
## @param p_columnIndex The column inside that block [br]
## @return The flat container index
func _get_team_column_index(p_team: int, p_columnIndex: int) -> int:
	return p_team * MAP_CHUNK_COLUMNS + p_columnIndex


## Takes a free curve slot or appends one, and remembers which curve sits in it. [br]
## @param p_curve The profile to store [br]
## @return The slot the curve was stored in
func _acquire_curve_slot(p_curve: Curve) -> int:
	p_curve.bake()

	var l_lastFreeIndex: int = _freeCurveIndices.size() - 1
	var l_curveIndex: int = 0

	if (l_lastFreeIndex >= 0):
		l_curveIndex = _freeCurveIndices[l_lastFreeIndex]
		_freeCurveIndices.resize(l_lastFreeIndex)
		_radiiCurves[l_curveIndex] = p_curve
	else:
		l_curveIndex = _radiiCurves.size()
		_radiiCurves.append(p_curve)
		_curveUsers.append(0)
		_curveSamples.resize(_radiiCurves.size() * C_HitServer.CURVE_SAMPLE_COUNT)

	_curveUsers[l_curveIndex] = 0
	_curveSlotOf[p_curve] = l_curveIndex
	_bake_curve_samples(l_curveIndex, p_curve)

	return l_curveIndex


## Reads a curve into the flat sample block of its slot, once when the slot is taken. [br]
## @param p_curveIndex The slot to fill [br]
## @param p_curve The profile to read
func _bake_curve_samples(p_curveIndex: int, p_curve: Curve) -> void:
	var l_base: int = p_curveIndex * C_HitServer.CURVE_SAMPLE_COUNT
	var l_lastSample: float = C_HitServer.CURVE_SAMPLE_COUNT - 1

	for l_sample: int in C_HitServer.CURVE_SAMPLE_COUNT:
		var l_percent: float = l_sample / l_lastSample * C_HitServer.CURVE_PERCENT_MAX
		_curveSamples[l_base + l_sample] = p_curve.sample_baked(l_percent)


## Gives the curve slot of an entity back, and frees the slot once nobody uses it. [br]
## @param p_id The entity whose profile is dropped
func _release_curve(p_id: int) -> void:
	var l_curveIndex: int = _hitEntityCurveIndex[p_id]

	if (l_curveIndex == NO_ID):
		return

	_hitEntityCurveIndex[p_id] = NO_ID
	_curveUsers[l_curveIndex] -= 1

	if (_curveUsers[l_curveIndex] > 0):
		return

	_curveSlotOf.erase(_radiiCurves[l_curveIndex])
	_radiiCurves[l_curveIndex] = null
	_freeCurveIndices.append(l_curveIndex)

#endregion
