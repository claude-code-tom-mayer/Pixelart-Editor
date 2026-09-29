@abstract
extends Node
class_name A_CoreServer
## Abstract base of every server: owns the entity data all servers share, plus the one entity lifecycle. [br]
## Call the lifecycle only as A_CoreServer.register() etc.; the G_ servers extend it just to reach the shared data.

#region CACHED_VARS

## Cached C_CoreServer.NO_ID.
static var NO_ID: int

## Cached C_CoreServer.TEAM_COUNT.
static var TEAM_COUNT: int

## Cached C_ChunkingServer.CHUNK_COLUMNS.
static var CHUNK_COLUMNS: int

## Cached C_ChunkingServer.CHUNK_ROWS.
static var CHUNK_ROWS: int

## Cached C_ChunkingServer.CHUNK_COUNT.
static var CHUNK_COUNT: int

## Cached C_ChunkingServer.CHUNK_SIZE.
static var CHUNK_SIZE: float

## Cached C_ChunkingServer.EMPTY_CHUNK_AREA.
static var EMPTY_CHUNK_AREA: Vector4i

## Cached C_HitServer.CURVE_SAMPLE_COUNT.
static var CURVE_SAMPLE_COUNT: int

#endregion

#region EXPORTS_AND_VARS

# -----------------------------------------------------------------------
# ENTITY CORE — read by every server.
# -----------------------------------------------------------------------

## Team per entity, as a C_CoreServer.TEAM value.
static var _entityTeam: PackedByteArray = PackedByteArray()

## Bitmask of the entity groups per entity: what the entity is, and what targeting searches for.
static var _entityGroups: PackedInt64Array = PackedInt64Array()

## Current position per entity.
static var _entityPosition: PackedVector2Array = PackedVector2Array()

## Radius per entity; decides how many chunks the entity stands in and how large it is to hits.
static var _entityRadius: PackedFloat32Array = PackedFloat32Array()

## 1 while an entity is announced for removal but still fully active.
static var _isEntityPendingRemoval: PackedByteArray = PackedByteArray()

## 1 from removal until release; the id stays locked meanwhile.
static var _isEntityRemoved: PackedByteArray = PackedByteArray()

## Ids removed since the last release; handed to _freeIds by release_removed_ids().
static var _removedIds: PackedInt32Array = PackedInt32Array()

## Ids that may be handed out again; only filled by release_removed_ids().
static var _freeIds: PackedInt32Array = PackedInt32Array()

## Profile every entity registered without one falls back to; carries no groups.
static var _defaultHitProfile: R_HitProfile = null

## Targeting setup every entity registered without one falls back to; carries no groups and never flees.
static var _defaultTargetingData: R_TargetingData = null

# -----------------------------------------------------------------------
# CHUNK INDEX — which entity stands in which chunk, plus per team summaries.
# -----------------------------------------------------------------------

## Chunk area per entity as (minColumn, minRow, maxColumn, maxRow); EMPTY_CHUNK_AREA while it stands nowhere.
static var _entityChunkArea: Array[Vector4i] = []

## First membership slot per entity, or NO_ID; its slot chain lists every chunk the entity stands in.
static var _entityFirstSlot: PackedInt32Array = PackedInt32Array()

## Chunk the center of an entity sits in, or NO_ID; the entity is listed there exactly once.
static var _entityCenterChunk: PackedInt32Array = PackedInt32Array()

## Column of the center chunk per entity; flat copy for the targeting hot loop.
static var _entityCenterColumn: PackedInt32Array = PackedInt32Array()

## Row of the center chunk per entity; flat copy for the targeting hot loop.
static var _entityCenterRow: PackedInt32Array = PackedInt32Array()

## Next entity in the center chain of the same chunk, or NO_ID.
static var _entityCenterNext: PackedInt32Array = PackedInt32Array()

## Previous entity in the center chain of the same chunk, or NO_ID; makes unlinking O(1).
static var _entityCenterPrev: PackedInt32Array = PackedInt32Array()

## First membership slot per chunk, or NO_ID; its slot chain lists every entity standing in the chunk.
static var _chunkFirstSlot: PackedInt32Array = PackedInt32Array()

## First entity whose center sits in a chunk, or NO_ID; walk on with _entityCenterNext.
static var _chunkFirstCenter: PackedInt32Array = PackedInt32Array()

## Entity every membership slot belongs to.
static var _slotEntity: PackedInt32Array = PackedInt32Array()

## Chunk every membership slot belongs to.
static var _slotChunk: PackedInt32Array = PackedInt32Array()

## Next slot in the slot chain of the same chunk, or NO_ID.
static var _slotChunkNext: PackedInt32Array = PackedInt32Array()

## Previous slot in the slot chain of the same chunk, or NO_ID; makes unlinking O(1).
static var _slotChunkPrev: PackedInt32Array = PackedInt32Array()

## Next slot in the slot chain of the same entity, or NO_ID.
static var _slotEntityNext: PackedInt32Array = PackedInt32Array()

## Previous slot in the slot chain of the same entity, or NO_ID; makes unlinking O(1).
static var _slotEntityPrev: PackedInt32Array = PackedInt32Array()

## Membership slots that may be handed out again.
static var _freeSlots: PackedInt32Array = PackedInt32Array()

## Membership count per team and chunk, at team * CHUNK_COUNT + chunk.
static var _teamChunkMembershipCount: PackedInt32Array = PackedInt32Array()

## Membership count per team and column, at team * CHUNK_COLUMNS + column. [br]
## An entity counts once per chunk it stands in, so a hit reaching only its edge still finds it.
static var _teamColumnMembershipCount: PackedInt32Array = PackedInt32Array()

## Entity group mask per team and chunk, at team * CHUNK_COUNT + chunk.
static var _teamChunkGroups: PackedInt64Array = PackedInt64Array()

## Entity group mask per team and column — the OR of its chunk masks. [br]
## Columns are the middle level because the two bases face each other along x.
static var _teamColumnGroups: PackedInt64Array = PackedInt64Array()

## Entity group mask per team over the whole map — the OR of its column masks.
static var _teamMapGroups: PackedInt64Array = PackedInt64Array()

## Leftmost column a team occupies, or NO_ID while it holds nothing.
static var _teamMinColumn: PackedInt32Array = PackedInt32Array()

## Rightmost column a team occupies, or NO_ID while it holds nothing.
static var _teamMaxColumn: PackedInt32Array = PackedInt32Array()

# -----------------------------------------------------------------------
# HIT DATA — the hit side of every entity.
# -----------------------------------------------------------------------

## Module manager per entity that receives every hit connecting with it, or null.
static var _entityModuleManager: Array[M_ModuleManager] = []

## Vertical extent per entity above the ground, as (bottom, top).
static var _entityHeightBand: PackedVector2Array = PackedVector2Array()

## Bitmask of the hit groups an entity can be harmed by.
static var _entityHurtGroups: PackedInt64Array = PackedInt64Array()

## Bitmask of the hit groups the hits of an entity carry.
static var _entityHitGroups: PackedInt64Array = PackedInt64Array()

## Bitmask of the hurt groups that end an ordered hit of this entity on the target they match.
static var _entityStopGroups: PackedInt64Array = PackedInt64Array()

## Radius curve id per entity, or NO_ID while its radius is constant over the height.
static var _entityCurveId: PackedInt32Array = PackedInt32Array()

## Curve stored under every curve id; kept only to recognise it again and to free the id.
static var _curveById: Array[Curve] = []

## Curve id every stored curve sits under, so one archetype never takes more than one id.
static var _curveIdByCurve: Dictionary[Curve, int] = {}

## Entities using each curve id; the id is freed once it drops to zero.
static var _curveUserCount: PackedInt32Array = PackedInt32Array()

## Curve ids that may be handed out again.
static var _freeCurveIds: PackedInt32Array = PackedInt32Array()

## Radius factors (0 to 1) of every curve id, CURVE_SAMPLE_COUNT samples per id. [br]
## A hit reads two floats and interpolates, instead of calling into the Curve object.
static var _curveRadiusFactors: PackedFloat32Array = PackedFloat32Array()

# -----------------------------------------------------------------------
# TARGETING DATA — the targeting side of every entity.
# -----------------------------------------------------------------------

## Current C_TargetingServer.STATE per entity.
static var _entityTargetingState: PackedByteArray = PackedByteArray()

## Bitmask of the entity groups an entity may go after.
static var _entityTargetedGroups: PackedInt64Array = PackedInt64Array()

## Bitmask of the entity groups an entity goes after before it considers the normal ones.
static var _entityPriorityTargetedGroups: PackedInt64Array = PackedInt64Array()

## How many chunk rings a search of this entity covers.
static var _entitySearchRadiusChunks: PackedInt32Array = PackedInt32Array()

## A targeter within this many chunk steps makes the entity flee, or C_TargetingServer.NEVER_FLEE.
static var _entityFleeRadiusChunks: PackedInt32Array = PackedInt32Array()

## Real distance at which approaching turns into combat, measured to the silhouette of the target.
static var _entityCombatRange: PackedFloat32Array = PackedFloat32Array()

## Invisibility and focus flags per entity, as C_TargetingServer.FLAG_ bits.
static var _entityTargetingFlags: PackedByteArray = PackedByteArray()

## Target per entity, or NO_ID.
static var _entityTarget: PackedInt32Array = PackedInt32Array()

## First entity targeting this one, or NO_ID; walk on with _entityTargeterNext.
static var _entityFirstTargeter: PackedInt32Array = PackedInt32Array()

## Next entity in the targeter chain this entity sits in (the chain of its target), or NO_ID.
static var _entityTargeterNext: PackedInt32Array = PackedInt32Array()

## Previous entity in the targeter chain this entity sits in, or NO_ID; makes dropping a target O(1).
static var _entityTargeterPrev: PackedInt32Array = PackedInt32Array()

## How many entities target this one; the crowding count.
static var _entityTargeterCount: PackedInt32Array = PackedInt32Array()

#endregion

#region LIFECYCLE_AND_METHODS

## Caches the shared constants and allocates the per chunk and per team containers, once on class load. [br]
## Also builds the two fallback setups for entities registered without their own.
static func _static_init() -> void:
	NO_ID = C_CoreServer.NO_ID
	TEAM_COUNT = C_CoreServer.TEAM_COUNT
	CHUNK_COLUMNS = C_ChunkingServer.CHUNK_COLUMNS
	CHUNK_ROWS = C_ChunkingServer.CHUNK_ROWS
	CHUNK_COUNT = C_ChunkingServer.CHUNK_COUNT
	CHUNK_SIZE = C_ChunkingServer.CHUNK_SIZE
	EMPTY_CHUNK_AREA = C_ChunkingServer.EMPTY_CHUNK_AREA
	CURVE_SAMPLE_COUNT = C_HitServer.CURVE_SAMPLE_COUNT

	_teamChunkMembershipCount.resize(TEAM_COUNT * CHUNK_COUNT)
	_teamChunkGroups.resize(TEAM_COUNT * CHUNK_COUNT)
	_teamColumnMembershipCount.resize(TEAM_COUNT * CHUNK_COLUMNS)
	_teamColumnGroups.resize(TEAM_COUNT * CHUNK_COLUMNS)
	_teamMapGroups.resize(TEAM_COUNT)

	_teamMinColumn.resize(TEAM_COUNT)
	_teamMaxColumn.resize(TEAM_COUNT)
	_teamMinColumn.fill(NO_ID)
	_teamMaxColumn.fill(NO_ID)

	_chunkFirstSlot.resize(CHUNK_COUNT)
	_chunkFirstCenter.resize(CHUNK_COUNT)
	_chunkFirstSlot.fill(NO_ID)
	_chunkFirstCenter.fill(NO_ID)

	_defaultHitProfile = R_HitProfile.new()
	_defaultTargetingData = R_TargetingData.new()
	_defaultTargetingData.fleeRadiusChunks = C_TargetingServer.NEVER_FLEE


## Registers a new entity on every server at once; the returned id is what every server addresses it by. [br]
## A null hit profile or targeting data falls back to defaults without groups — the entity is then inert. [br]
## @param p_position Start position of the entity [br]
## @param p_radius Radius of the entity [br]
## @param p_team Team of the entity [br]
## @param p_groups Bitmask of the entity groups the entity belongs to [br]
## @param p_moduleManager Module manager that receives its hits, or null [br]
## @param p_hitProfile Height band, hit groups and radius curve, or null for the default [br]
## @param p_targetingData Targeted groups, radii and flags, or null for the default [br]
## @return The assigned entity id
static func register(p_position: Vector2, p_radius: float, p_team: C_CoreServer.TEAM, p_groups: int,
		p_moduleManager: M_ModuleManager, p_hitProfile: R_HitProfile, p_targetingData: R_TargetingData) -> int:
	assert(p_team >= 0 and p_team < TEAM_COUNT, "A_CoreServer: register() got an unknown team.")

	var l_id: int = _acquire_id()

	_register_chunk_side(l_id, p_position, p_radius, p_team, p_groups)
	_register_hit_side(l_id, p_moduleManager, p_hitProfile if p_hitProfile != null else _defaultHitProfile)
	_register_targeting_side(l_id, p_targetingData if p_targetingData != null else _defaultTargetingData)

	return l_id


## Announces an entity for removal: it stays fully active, but can no longer be targeted or hit. [br]
## @param p_id The entity to announce
static func pre_unregister(p_id: int) -> void:
	_isEntityPendingRemoval[p_id] = 1
	_release_targeters(p_id, 0)


## Removes an entity from every server and locks its id until release_removed_ids(). [br]
## Does nothing for an id that is already removed, so a double removal cannot free it twice. [br]
## @param p_id The entity to remove
static func unregister(p_id: int) -> void:
	if (_isEntityRemoved[p_id] == 1):
		return

	_isEntityRemoved[p_id] = 1
	_clear_target(p_id)
	_release_targeters(p_id, 0)
	_move_to_chunk_area(p_id, EMPTY_CHUNK_AREA)
	_unlink_center(p_id)
	_removedIds.append(p_id)


## Hands the ids of removed entities back for reuse and drops the references they still hold. [br]
## Call once per tick, after every server that could still hold a removed id has run.
static func release_removed_ids() -> void:
	for l_id: int in _removedIds:
		_isEntityRemoved[l_id] = 0
		_isEntityPendingRemoval[l_id] = 0
		_entityModuleManager[l_id] = null
		_release_curve(l_id)
		_freeIds.append(l_id)

	_removedIds.clear()


## Checks whether an entity is removed and warns about it, so a public call can drop out early. [br]
## Changing a removed entity would link it back into the chunk index or a targeter chain. [br]
## @param p_id The entity to check [br]
## @param p_callerName Name of the public function that got the id, for the warning [br]
## @return true if the entity is removed and must not be changed
static func _reject_removed_id(p_id: int, p_callerName: String) -> bool:
	if (_isEntityRemoved[p_id] == 0):
		return false

	push_warning("%s() got the removed entity %d, ignoring it." % [p_callerName, p_id])
	return true


## Takes a free entity id, or appends a fresh id to every per entity container. [br]
## A fresh id starts standing nowhere, exactly like a removed one, so register() can treat both alike. [br]
## @return The id the next entity is stored under
static func _acquire_id() -> int:
	var l_lastFreeIndex: int = _freeIds.size() - 1

	if (l_lastFreeIndex >= 0):
		var l_reusedId: int = _freeIds[l_lastFreeIndex]
		_freeIds.resize(l_lastFreeIndex)
		return l_reusedId

	_entityTeam.append(0)
	_entityGroups.append(0)
	_entityPosition.append(Vector2.ZERO)
	_entityRadius.append(0.0)
	_isEntityPendingRemoval.append(0)
	_isEntityRemoved.append(0)

	_entityChunkArea.append(EMPTY_CHUNK_AREA)
	_entityFirstSlot.append(NO_ID)
	_entityCenterChunk.append(NO_ID)
	_entityCenterColumn.append(0)
	_entityCenterRow.append(0)
	_entityCenterNext.append(NO_ID)
	_entityCenterPrev.append(NO_ID)

	_entityModuleManager.append(null)
	_entityHeightBand.append(Vector2.ZERO)
	_entityHurtGroups.append(0)
	_entityHitGroups.append(0)
	_entityStopGroups.append(0)
	_entityCurveId.append(NO_ID)

	_entityTargetingState.append(C_TargetingServer.STATE.SEARCH)
	_entityTargetedGroups.append(0)
	_entityPriorityTargetedGroups.append(0)
	_entitySearchRadiusChunks.append(0)
	_entityFleeRadiusChunks.append(0)
	_entityCombatRange.append(0.0)
	_entityTargetingFlags.append(0)
	_entityTarget.append(NO_ID)
	_entityFirstTargeter.append(NO_ID)
	_entityTargeterNext.append(NO_ID)
	_entityTargeterPrev.append(NO_ID)
	_entityTargeterCount.append(0)

	return _entityTeam.size() - 1


## Fills in the core and chunk index side of an id that stands nowhere yet. [br]
## @param p_id The id to fill in [br]
## @param p_position Start position of the entity [br]
## @param p_radius Radius of the entity [br]
## @param p_team Team of the entity, a C_CoreServer.TEAM value [br]
## @param p_groups Bitmask of the entity groups the entity belongs to
static func _register_chunk_side(p_id: int, p_position: Vector2, p_radius: float, p_team: int, p_groups: int) -> void:
	_entityTeam[p_id] = p_team
	_entityGroups[p_id] = p_groups
	_entityPosition[p_id] = p_position
	_entityRadius[p_id] = p_radius

	var l_extent: Vector2 = Vector2(p_radius, p_radius)
	_move_to_chunk_area(p_id, _compute_chunk_area(p_position - l_extent, p_position + l_extent))
	_update_center_chunk(p_id, p_position)


## Fills in the hit side of a freshly acquired id. [br]
## @param p_id The id to fill in [br]
## @param p_moduleManager Module manager that receives its hits, or null [br]
## @param p_hitProfile Height band, hit groups and radius curve of the entity
static func _register_hit_side(p_id: int, p_moduleManager: M_ModuleManager, p_hitProfile: R_HitProfile) -> void:
	_entityModuleManager[p_id] = p_moduleManager
	_entityHeightBand[p_id] = p_hitProfile.heightBand
	_entityHurtGroups[p_id] = p_hitProfile.hurtGroups
	_entityHitGroups[p_id] = p_hitProfile.hitGroups
	_entityStopGroups[p_id] = p_hitProfile.stopGroups

	_set_radius_curve(p_id, p_hitProfile.radiusCurve)


## Fills in the targeting side of a freshly acquired id; it starts out searching. [br]
## @param p_id The id to fill in [br]
## @param p_targetingData Targeted groups, radii and flags of the entity
static func _register_targeting_side(p_id: int, p_targetingData: R_TargetingData) -> void:
	_entityTargetingState[p_id] = C_TargetingServer.STATE.SEARCH
	_entityTargetedGroups[p_id] = p_targetingData.targetedGroups
	_entityPriorityTargetedGroups[p_id] = p_targetingData.priorityTargetedGroups
	_entitySearchRadiusChunks[p_id] = p_targetingData.searchRadiusChunks
	_entityFleeRadiusChunks[p_id] = p_targetingData.fleeRadiusChunks
	_entityCombatRange[p_id] = p_targetingData.combatRange
	_entityTargetingFlags[p_id] = _pack_targeting_flags(p_targetingData)


## Packs the flag booleans of a targeting setup into one byte. [br]
## @param p_targetingData The setup to read [br]
## @return The packed C_TargetingServer.FLAG_ bits
static func _pack_targeting_flags(p_targetingData: R_TargetingData) -> int:
	var l_flags: int = 0

	if (p_targetingData.isInvisible):
		l_flags |= C_TargetingServer.FLAG_IS_INVISIBLE

	if (p_targetingData.canTargetInvisible):
		l_flags |= C_TargetingServer.FLAG_CAN_TARGET_INVISIBLE

	if (p_targetingData.hasFocus):
		l_flags |= C_TargetingServer.FLAG_HAS_FOCUS

	if (p_targetingData.isIgnoringFocus):
		l_flags |= C_TargetingServer.FLAG_IS_IGNORING_FOCUS

	return l_flags


## Unlinks an entity from the targeter chain of its target and sends it back to searching. [br]
## @param p_id The entity that gives up its target
static func _clear_target(p_id: int) -> void:
	var l_targetId: int = _entityTarget[p_id]

	if (l_targetId == NO_ID):
		return

	var l_next: int = _entityTargeterNext[p_id]
	var l_prev: int = _entityTargeterPrev[p_id]

	if (l_prev == NO_ID):
		_entityFirstTargeter[l_targetId] = l_next
	else:
		_entityTargeterNext[l_prev] = l_next

	if (l_next != NO_ID):
		_entityTargeterPrev[l_next] = l_prev

	_entityTargeterCount[l_targetId] -= 1
	_entityTarget[p_id] = NO_ID
	_entityTargetingState[p_id] = C_TargetingServer.STATE.SEARCH


## Makes the targeters of an entity drop it, except those carrying one of the exempt flags. [br]
## @param p_id The entity that is no longer worth targeting [br]
## @param p_exemptFlags C_TargetingServer.FLAG_ bits that let a targeter keep it; 0 drops every targeter
static func _release_targeters(p_id: int, p_exemptFlags: int) -> void:
	var l_targeterId: int = _entityFirstTargeter[p_id]

	while (l_targeterId != NO_ID):
		var l_nextTargeterId: int = _entityTargeterNext[l_targeterId]

		if ((_entityTargetingFlags[l_targeterId] & p_exemptFlags) == 0):
			_clear_target(l_targeterId)

		l_targeterId = l_nextTargeterId


## Gives an entity a radius curve; null gives it a constant radius again. [br]
## Entities sharing one curve share its curve id, so curves cost per archetype, not per entity. [br]
## @param p_id The entity to change [br]
## @param p_curve The curve to sample, or null
static func _set_radius_curve(p_id: int, p_curve: Curve) -> void:
	if (p_curve == null):
		_release_curve(p_id)
		return

	var l_curveId: int = _curveIdByCurve.get(p_curve, NO_ID)

	if (l_curveId != NO_ID and l_curveId == _entityCurveId[p_id]):
		return

	_release_curve(p_id)

	if (l_curveId == NO_ID):
		l_curveId = _acquire_curve_id(p_curve)

	_curveUserCount[l_curveId] += 1
	_entityCurveId[p_id] = l_curveId


## Takes a free curve id or appends one, and bakes the curve under it. [br]
## @param p_curve The curve to store [br]
## @return The curve id the curve is stored under
static func _acquire_curve_id(p_curve: Curve) -> int:
	var l_lastFreeIndex: int = _freeCurveIds.size() - 1
	var l_curveId: int = 0

	if (l_lastFreeIndex >= 0):
		l_curveId = _freeCurveIds[l_lastFreeIndex]
		_freeCurveIds.resize(l_lastFreeIndex)
		_curveById[l_curveId] = p_curve
	else:
		l_curveId = _curveById.size()
		_curveById.append(p_curve)
		_curveUserCount.append(0)
		_curveRadiusFactors.resize(_curveById.size() * CURVE_SAMPLE_COUNT)

	_curveUserCount[l_curveId] = 0
	_curveIdByCurve[p_curve] = l_curveId
	_bake_radius_factors(l_curveId, p_curve)

	return l_curveId


## Samples a curve over its whole domain into the radius factors of its curve id, divided down to 0 to 1. [br]
## The max_value of the curve is the full radius, so any authored domain and value range works. [br]
## @param p_curveId The curve id to fill [br]
## @param p_curve The curve to read
static func _bake_radius_factors(p_curveId: int, p_curve: Curve) -> void:
	assert(p_curve.max_value > 0.0, "A_CoreServer: a radius curve needs a max_value above 0.")

	p_curve.bake()

	var l_firstFactorIndex: int = p_curveId * CURVE_SAMPLE_COUNT
	var l_sampleCountBelowLast: float = CURVE_SAMPLE_COUNT - 1
	var l_minDomain: float = p_curve.min_domain
	var l_domainLength: float = p_curve.max_domain - l_minDomain
	var l_maxValue: float = p_curve.max_value

	for l_sampleIndex: int in CURVE_SAMPLE_COUNT:
		var l_height: float = l_minDomain + l_sampleIndex / l_sampleCountBelowLast * l_domainLength
		var l_factor: float = clampf(p_curve.sample_baked(l_height) / l_maxValue, 0.0, 1.0)
		_curveRadiusFactors[l_firstFactorIndex + l_sampleIndex] = l_factor


## Drops the radius curve of an entity, and frees the curve id once nobody uses it. [br]
## @param p_id The entity whose curve is dropped
static func _release_curve(p_id: int) -> void:
	var l_curveId: int = _entityCurveId[p_id]

	if (l_curveId == NO_ID):
		return

	_entityCurveId[p_id] = NO_ID
	_curveUserCount[l_curveId] -= 1

	if (_curveUserCount[l_curveId] > 0):
		return

	_curveIdByCurve.erase(_curveById[l_curveId])
	_curveById[l_curveId] = null
	_freeCurveIds.append(l_curveId)


## Calculates the chunk area an axis aligned box covers, clamped to the map. [br]
## Entities stand in every chunk their radius touches, so walking this area finds them all. [br]
## @param p_minCorner Upper left corner of the box [br]
## @param p_maxCorner Lower right corner of the box [br]
## @return The area as (minColumn, minRow, maxColumn, maxRow)
static func _compute_chunk_area(p_minCorner: Vector2, p_maxCorner: Vector2) -> Vector4i:
	var l_lastColumn: int = CHUNK_COLUMNS - 1
	var l_lastRow: int = CHUNK_ROWS - 1

	return Vector4i(
		clampi(floori(p_minCorner.x / CHUNK_SIZE), 0, l_lastColumn),
		clampi(floori(p_minCorner.y / CHUNK_SIZE), 0, l_lastRow),
		clampi(floori(p_maxCorner.x / CHUNK_SIZE), 0, l_lastColumn),
		clampi(floori(p_maxCorner.y / CHUNK_SIZE), 0, l_lastRow))


## Moves an entity onto a new chunk area, touching only the chunks it entered or left. [br]
## EMPTY_CHUNK_AREA as the new area removes every membership; as the old one, every chunk counts as entered. [br]
## @param p_id The entity to move [br]
## @param p_area The new area as (minColumn, minRow, maxColumn, maxRow)
static func _move_to_chunk_area(p_id: int, p_area: Vector4i) -> void:
	var l_oldArea: Vector4i = _entityChunkArea[p_id]

	if (p_area == l_oldArea):
		return

	_entityChunkArea[p_id] = p_area

	var l_slot: int = _entityFirstSlot[p_id]
	while (l_slot != NO_ID):
		var l_nextSlot: int = _slotEntityNext[l_slot]

		if (not _is_chunk_in_area(_slotChunk[l_slot], p_area)):
			_remove_membership(l_slot)

		l_slot = l_nextSlot

	for l_row: int in range(p_area.y, p_area.w + 1):
		var l_rowFirstChunk: int = l_row * CHUNK_COLUMNS
		var l_isRowEntered: bool = l_row < l_oldArea.y or l_row > l_oldArea.w

		for l_column: int in range(p_area.x, p_area.z + 1):
			if (l_isRowEntered or l_column < l_oldArea.x or l_column > l_oldArea.z):
				_add_membership(p_id, l_rowFirstChunk + l_column)


## Checks whether a chunk lies inside a chunk area. [br]
## @param p_chunkId The chunk to place [br]
## @param p_area The area as (minColumn, minRow, maxColumn, maxRow) [br]
## @return true if the chunk is part of the area
static func _is_chunk_in_area(p_chunkId: int, p_area: Vector4i) -> bool:
	var l_column: int = p_chunkId % CHUNK_COLUMNS

	if (l_column < p_area.x or l_column > p_area.z):
		return false

	@warning_ignore("integer_division")
	var l_row: int = p_chunkId / CHUNK_COLUMNS

	return l_row >= p_area.y and l_row <= p_area.w


## Moves the center of an entity into the chunk its position falls into. [br]
## Drops out while the center chunk is unchanged, which is the common case when moving. [br]
## @param p_id The entity to update [br]
## @param p_position The position the center is taken from
static func _update_center_chunk(p_id: int, p_position: Vector2) -> void:
	var l_column: int = clampi(floori(p_position.x / CHUNK_SIZE), 0, CHUNK_COLUMNS - 1)
	var l_row: int = clampi(floori(p_position.y / CHUNK_SIZE), 0, CHUNK_ROWS - 1)
	var l_chunkId: int = l_row * CHUNK_COLUMNS + l_column

	if (l_chunkId == _entityCenterChunk[p_id]):
		return

	_unlink_center(p_id)

	var l_firstCenter: int = _chunkFirstCenter[l_chunkId]
	_entityCenterPrev[p_id] = NO_ID
	_entityCenterNext[p_id] = l_firstCenter

	if (l_firstCenter != NO_ID):
		_entityCenterPrev[l_firstCenter] = p_id

	_chunkFirstCenter[l_chunkId] = p_id
	_entityCenterChunk[p_id] = l_chunkId
	_entityCenterColumn[p_id] = l_column
	_entityCenterRow[p_id] = l_row


## Unlinks the center of an entity from the center chain of its chunk. [br]
## @param p_id The entity whose center is removed
static func _unlink_center(p_id: int) -> void:
	var l_chunkId: int = _entityCenterChunk[p_id]

	if (l_chunkId == NO_ID):
		return

	var l_next: int = _entityCenterNext[p_id]
	var l_prev: int = _entityCenterPrev[p_id]

	if (l_prev == NO_ID):
		_chunkFirstCenter[l_chunkId] = l_next
	else:
		_entityCenterNext[l_prev] = l_next

	if (l_next != NO_ID):
		_entityCenterPrev[l_next] = l_prev

	_entityCenterChunk[p_id] = NO_ID


## Makes an entity stand in one more chunk and merges its groups upwards while they change. [br]
## Links one membership slot into the slot chain of the chunk and of the entity; no list is ever copied. [br]
## @param p_id The entity to add [br]
## @param p_chunkId The chunk it now stands in
static func _add_membership(p_id: int, p_chunkId: int) -> void:
	var l_slot: int = _acquire_slot()

	_slotEntity[l_slot] = p_id
	_slotChunk[l_slot] = p_chunkId

	var l_chunkFirstSlot: int = _chunkFirstSlot[p_chunkId]
	_slotChunkPrev[l_slot] = NO_ID
	_slotChunkNext[l_slot] = l_chunkFirstSlot

	if (l_chunkFirstSlot != NO_ID):
		_slotChunkPrev[l_chunkFirstSlot] = l_slot

	_chunkFirstSlot[p_chunkId] = l_slot

	var l_entityFirstSlot: int = _entityFirstSlot[p_id]
	_slotEntityPrev[l_slot] = NO_ID
	_slotEntityNext[l_slot] = l_entityFirstSlot

	if (l_entityFirstSlot != NO_ID):
		_slotEntityPrev[l_entityFirstSlot] = l_slot

	_entityFirstSlot[p_id] = l_slot

	var l_team: int = _entityTeam[p_id]
	var l_groups: int = _entityGroups[p_id]

	_change_membership_counts(p_chunkId, l_team, 1)

	if (_merge_groups_into_chunk(p_chunkId, l_team, l_groups)):
		if (_merge_groups_into_column(p_chunkId % CHUNK_COLUMNS, l_team, l_groups)):
			_merge_groups_into_map(l_team, l_groups)


## Unlinks one membership slot and rebuilds the group masks upwards while they change. [br]
## Unlinking is a fixed number of integer writes, whatever the chunk holds. [br]
## @param p_slot The membership slot to drop
static func _remove_membership(p_slot: int) -> void:
	var l_id: int = _slotEntity[p_slot]
	var l_chunkId: int = _slotChunk[p_slot]

	var l_next: int = _slotChunkNext[p_slot]
	var l_prev: int = _slotChunkPrev[p_slot]

	if (l_prev == NO_ID):
		_chunkFirstSlot[l_chunkId] = l_next
	else:
		_slotChunkNext[l_prev] = l_next

	if (l_next != NO_ID):
		_slotChunkPrev[l_next] = l_prev

	l_next = _slotEntityNext[p_slot]
	l_prev = _slotEntityPrev[p_slot]

	if (l_prev == NO_ID):
		_entityFirstSlot[l_id] = l_next
	else:
		_slotEntityNext[l_prev] = l_next

	if (l_next != NO_ID):
		_slotEntityPrev[l_next] = l_prev

	_freeSlots.append(p_slot)

	var l_team: int = _entityTeam[l_id]
	_change_membership_counts(l_chunkId, l_team, -1)

	if (_rebuild_chunk_groups(l_chunkId, l_team)):
		if (_rebuild_column_groups(l_chunkId % CHUNK_COLUMNS, l_team)):
			_rebuild_map_groups(l_team)


## Takes a free membership slot or appends a fresh one to every per slot container. [br]
## @return The slot the next membership is stored under
static func _acquire_slot() -> int:
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


## Writes a membership count change through to chunk and column, and keeps the column span current. [br]
## @param p_chunkId The chunk an entity entered or left [br]
## @param p_team Team whose counts change, a C_CoreServer.TEAM value [br]
## @param p_delta 1 when entering, -1 when leaving
static func _change_membership_counts(p_chunkId: int, p_team: int, p_delta: int) -> void:
	var l_column: int = p_chunkId % CHUNK_COLUMNS
	var l_teamColumnIndex: int = p_team * CHUNK_COLUMNS + l_column
	var l_columnCountBefore: int = _teamColumnMembershipCount[l_teamColumnIndex]

	_teamChunkMembershipCount[p_team * CHUNK_COUNT + p_chunkId] += p_delta
	_teamColumnMembershipCount[l_teamColumnIndex] = l_columnCountBefore + p_delta

	if (p_delta > 0 and l_columnCountBefore == 0):
		_extend_team_column_span(p_team, l_column)
	elif (p_delta < 0 and l_columnCountBefore + p_delta == 0):
		_shrink_team_column_span(p_team, l_column)


## Widens the column span of a team by a column that just got its first entity. [br]
## @param p_team The team whose span grows [br]
## @param p_column The column that now holds entities
static func _extend_team_column_span(p_team: int, p_column: int) -> void:
	if (_teamMinColumn[p_team] == NO_ID or p_column < _teamMinColumn[p_team]):
		_teamMinColumn[p_team] = p_column

	if (_teamMaxColumn[p_team] == NO_ID or p_column > _teamMaxColumn[p_team]):
		_teamMaxColumn[p_team] = p_column


## Narrows the column span of a team after a column lost its last entity. [br]
## Only scans when that column was an edge of the span itself; a span of one column empties the team. [br]
## @param p_team The team whose span shrinks [br]
## @param p_column The column that ran empty
static func _shrink_team_column_span(p_team: int, p_column: int) -> void:
	if (_teamMinColumn[p_team] == _teamMaxColumn[p_team]):
		_teamMinColumn[p_team] = NO_ID
		_teamMaxColumn[p_team] = NO_ID
		return

	var l_teamFirstColumnIndex: int = p_team * CHUNK_COLUMNS

	if (p_column == _teamMinColumn[p_team]):
		var l_column: int = p_column + 1

		while (_teamColumnMembershipCount[l_teamFirstColumnIndex + l_column] == 0):
			l_column += 1

		_teamMinColumn[p_team] = l_column

	if (p_column == _teamMaxColumn[p_team]):
		var l_column: int = p_column - 1

		while (_teamColumnMembershipCount[l_teamFirstColumnIndex + l_column] == 0):
			l_column -= 1

		_teamMaxColumn[p_team] = l_column


## Merges group bits into the mask of a team in one chunk — first step of the add path. [br]
## @param p_chunkId The chunk to extend [br]
## @param p_team Team whose mask is extended [br]
## @param p_groups The entity group bits to merge in [br]
## @return true if the mask changed
static func _merge_groups_into_chunk(p_chunkId: int, p_team: int, p_groups: int) -> bool:
	var l_teamChunkIndex: int = p_team * CHUNK_COUNT + p_chunkId
	var l_mergedGroups: int = _teamChunkGroups[l_teamChunkIndex] | p_groups

	if (l_mergedGroups == _teamChunkGroups[l_teamChunkIndex]):
		return false

	_teamChunkGroups[l_teamChunkIndex] = l_mergedGroups
	return true


## Merges group bits into the mask of a team in one column — second step of the add path. [br]
## @param p_column The column to extend [br]
## @param p_team Team whose mask is extended [br]
## @param p_groups The entity group bits to merge in [br]
## @return true if the mask changed
static func _merge_groups_into_column(p_column: int, p_team: int, p_groups: int) -> bool:
	var l_teamColumnIndex: int = p_team * CHUNK_COLUMNS + p_column
	var l_mergedGroups: int = _teamColumnGroups[l_teamColumnIndex] | p_groups

	if (l_mergedGroups == _teamColumnGroups[l_teamColumnIndex]):
		return false

	_teamColumnGroups[l_teamColumnIndex] = l_mergedGroups
	return true


## Merges group bits into the map mask of a team — last step of the add path. [br]
## @param p_team Team whose mask is extended [br]
## @param p_groups The entity group bits to merge in
static func _merge_groups_into_map(p_team: int, p_groups: int) -> void:
	_teamMapGroups[p_team] |= p_groups


## Rebuilds the mask of a team in one chunk from the entities still standing there — first step of the remove path. [br]
## The mask can only shrink here, so the walk stops once it reaches the old value again. [br]
## @param p_chunkId The chunk to rebuild [br]
## @param p_team Team whose mask is rebuilt [br]
## @return true if the mask changed
static func _rebuild_chunk_groups(p_chunkId: int, p_team: int) -> bool:
	var l_teamChunkIndex: int = p_team * CHUNK_COUNT + p_chunkId
	var l_oldGroups: int = _teamChunkGroups[l_teamChunkIndex]
	var l_groups: int = 0

	var l_slot: int = _chunkFirstSlot[p_chunkId]
	while (l_slot != NO_ID):
		var l_id: int = _slotEntity[l_slot]

		if (_entityTeam[l_id] == p_team):
			l_groups |= _entityGroups[l_id]

			if (l_groups == l_oldGroups):
				return false

		l_slot = _slotChunkNext[l_slot]

	if (l_groups == l_oldGroups):
		return false

	_teamChunkGroups[l_teamChunkIndex] = l_groups
	return true


## Rebuilds the mask of a team in one column from its chunk masks — second step of the remove path. [br]
## The mask can only shrink here, so the scan stops once it reaches the old value again. [br]
## @param p_column The column to rebuild [br]
## @param p_team Team whose mask is rebuilt [br]
## @return true if the mask changed
static func _rebuild_column_groups(p_column: int, p_team: int) -> bool:
	var l_teamColumnIndex: int = p_team * CHUNK_COLUMNS + p_column
	var l_oldGroups: int = _teamColumnGroups[l_teamColumnIndex]
	var l_groups: int = 0
	var l_teamFirstChunkIndex: int = p_team * CHUNK_COUNT

	for l_row: int in CHUNK_ROWS:
		l_groups |= _teamChunkGroups[l_teamFirstChunkIndex + l_row * CHUNK_COLUMNS + p_column]

		if (l_groups == l_oldGroups):
			return false

	_teamColumnGroups[l_teamColumnIndex] = l_groups
	return true


## Rebuilds the map mask of a team from its column masks — last step of the remove path. [br]
## The mask can only shrink here, so the scan stops once it reaches the old value again. [br]
## @param p_team Team whose mask is rebuilt
static func _rebuild_map_groups(p_team: int) -> void:
	var l_oldGroups: int = _teamMapGroups[p_team]
	var l_groups: int = 0
	var l_teamFirstColumnIndex: int = p_team * CHUNK_COLUMNS

	for l_column: int in CHUNK_COLUMNS:
		l_groups |= _teamColumnGroups[l_teamFirstColumnIndex + l_column]

		if (l_groups == l_oldGroups):
			return

	_teamMapGroups[p_team] = l_groups

#endregion
