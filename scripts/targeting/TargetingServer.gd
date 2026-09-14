extends ChunkingServer
## Picks and holds a target per entity and reports where it should move. [br]
## Searches are chunk counted and event driven: a target is only ever lost, never re-checked.
class_name TargetingServer

#region PRIVATE_VARIABLES

## Current C_TargetingServer.STATE per entity.
var _entityState: PackedByteArray = PackedByteArray()

## How many chunks in each direction a search of this entity covers.
var _entitySearchChunks: PackedInt32Array = PackedInt32Array()

## A targeter closer than this many chunks makes the entity flee.
var _entityFleeChunks: PackedInt32Array = PackedInt32Array()

## Squared real distance at which approaching turns into combat.
var _entitySquaredHitRange: PackedFloat32Array = PackedFloat32Array()

## Bitmask of the groups an entity goes after before it considers the normal ones.
var _entityPriorityTargetedGroups: PackedInt64Array = PackedInt64Array()

## Invisibility and focus flags of an entity, as C_TargetingServer.FLAG bits.
var _entityFlags: PackedByteArray = PackedByteArray()

## Target of an entity, or C_TargetingServer.NO_TARGET.
var _entityTarget: PackedInt32Array = PackedInt32Array()

## Own slot inside the targeter list of the target; makes dropping a target O(1).
var _entityTargeterIndex: PackedInt32Array = PackedInt32Array()

## Ids that currently target this entity; its size is the crowding count.
var _targetersOf: Array[PackedInt32Array] = []

#endregion

#region LIFECYCLE

## Takes an id from the chunking server and clears the targeting data of that slot. [br]
## Without the reset a recycled id would inherit the target and flags of its predecessor. [br]
## @return The id the next entity is stored under
func _acquire_id() -> int:
	var l_id: int = super()
	
	if (l_id == _entityState.size()):
		_entityState.append(C_TargetingServer.STATE.SEARCH)
		_entitySearchChunks.append(0)
		_entityFleeChunks.append(0)
		_entitySquaredHitRange.append(0.0)
		_entityPriorityTargetedGroups.append(0)
		_entityFlags.append(0)
		_entityTarget.append(C_TargetingServer.NO_TARGET)
		_entityTargeterIndex.append(0)
		_targetersOf.append(PackedInt32Array())
		return l_id
	
	_entityState[l_id] = C_TargetingServer.STATE.SEARCH
	_entitySearchChunks[l_id] = 0
	_entityFleeChunks[l_id] = 0
	_entitySquaredHitRange[l_id] = 0.0
	_entityPriorityTargetedGroups[l_id] = 0
	_entityFlags[l_id] = 0
	_entityTarget[l_id] = C_TargetingServer.NO_TARGET
	_entityTargeterIndex[l_id] = 0
	_targetersOf[l_id] = PackedInt32Array()
	
	return l_id

#endregion

#region PUBLIC_METHODS

## Registers an entity with its full targeting setup in one call. [br]
## @param p_position Start position of the entity [br]
## @param p_radius Effect radius of the entity [br]
## @param p_team Team of the entity, a C_ChunkingServer.TEAM value [br]
## @param p_groups Bitmask of the groups the entity belongs to [br]
## @param p_targetedGroups Bitmask of the groups the entity may go after [br]
## @param p_module Module management of the entity [br]
## @param p_targetingData Ranges, priority groups and flags of the entity [br]
## @return The assigned entity id
func register_entity_with_targeting(p_position: Vector2, p_radius: float, p_team: int, p_groups: int,
		p_targetedGroups: int, p_module: M_ModuleManager, p_targetingData: R_TargetingData) -> int:
	var l_id: int = register_entity(p_position, p_radius, p_team, p_groups, p_targetedGroups, p_module)
	
	_entitySearchChunks[l_id] = p_targetingData.searchChunks
	_entityFleeChunks[l_id] = p_targetingData.fleeChunks
	_entitySquaredHitRange[l_id] = p_targetingData.hitRange * p_targetingData.hitRange
	_entityPriorityTargetedGroups[l_id] = p_targetingData.priorityTargetedGroups
	_entityFlags[l_id] = _build_flags(p_targetingData)
	
	return l_id


## Advances the state of one entity; cheap enough to run every tick. [br]
## Never searches — the entity asks for that itself through search_target(). [br]
## @param p_id The entity to advance [br]
## @return Its new C_TargetingServer.STATE
func update_entity(p_id: int) -> int:
	var l_state: int = _evaluate_state(p_id)
	_entityState[p_id] = l_state
	
	return l_state


## Scans the search area of an entity and gives it the best scoring target. [br]
## @param p_id The entity that searches [br]
## @return The target it got, or C_TargetingServer.NO_TARGET
func search_target(p_id: int) -> int:
	var l_targetId: int = _find_best_target(p_id)
	
	if (l_targetId != C_TargetingServer.NO_TARGET):
		_assign_target(p_id, l_targetId)
	
	return l_targetId


## Makes every entity that targets this one drop it and look for something else. [br]
## @param p_id The entity that is no longer worth targeting
func drop_targeters(p_id: int) -> void:
	var l_targeters: PackedInt32Array = _targetersOf[p_id].duplicate()
	
	for l_targeterId: int in l_targeters:
		_drop_target(l_targeterId)


## Hides an entity from searchers, or reveals it again. [br]
## Hiding drops every targeter that cannot see invisible entities. [br]
## @param p_id The entity to change [br]
## @param p_invisible Whether it becomes invisible
func set_invisible(p_id: int, p_invisible: bool) -> void:
	_set_flag(p_id, C_TargetingServer.FLAG_INVISIBLE, p_invisible)
	
	if (not p_invisible):
		return
	
	var l_targeters: PackedInt32Array = _targetersOf[p_id].duplicate()
	for l_targeterId: int in l_targeters:
		if ((_entityFlags[l_targeterId] & C_TargetingServer.FLAG_TARGETS_INVISIBLE) == 0):
			_drop_target(l_targeterId)


## Sets whether an entity can see invisible enemies. [br]
## @param p_id The entity to change [br]
## @param p_enabled Whether it sees them
func set_targets_invisible(p_id: int, p_enabled: bool) -> void:
	_set_flag(p_id, C_TargetingServer.FLAG_TARGETS_INVISIBLE, p_enabled)


## Sets whether an entity is a focus target other entities prefer. [br]
## @param p_id The entity to change [br]
## @param p_enabled Whether it carries focus
func set_focused(p_id: int, p_enabled: bool) -> void:
	_set_flag(p_id, C_TargetingServer.FLAG_HAS_FOCUS, p_enabled)


## Sets whether an entity scores candidates without the focus bonus. [br]
## @param p_id The entity to change [br]
## @param p_enabled Whether it ignores focus
func set_ignores_focus(p_id: int, p_enabled: bool) -> void:
	_set_flag(p_id, C_TargetingServer.FLAG_IGNORES_FOCUS, p_enabled)


## Sets how far a search of this entity reaches. [br]
## @param p_id The entity to change [br]
## @param p_searchChunks Reach in chunks per direction
func set_search_chunks(p_id: int, p_searchChunks: int) -> void:
	_entitySearchChunks[p_id] = p_searchChunks


## Sets how close a targeter has to come before the entity flees. [br]
## @param p_id The entity to change [br]
## @param p_fleeChunks Threat distance in chunks
func set_flee_chunks(p_id: int, p_fleeChunks: int) -> void:
	_entityFleeChunks[p_id] = p_fleeChunks


## Sets the real distance at which the entity enters combat. [br]
## @param p_id The entity to change [br]
## @param p_hitRange The distance, squared internally
func set_hit_range(p_id: int, p_hitRange: float) -> void:
	_entitySquaredHitRange[p_id] = p_hitRange * p_hitRange


## Sets the groups the entity goes after before it considers the normal ones. [br]
## @param p_id The entity to change [br]
## @param p_priorityTargetedGroups Bitmask of the preferred groups
func set_priority_targeted_groups(p_id: int, p_priorityTargetedGroups: int) -> void:
	_entityPriorityTargetedGroups[p_id] = p_priorityTargetedGroups

#endregion

#region PUBLIC_QUERIES

## Returns where the entity should move this tick. [br]
## Fleeing and marching aim at a fixed x of the map, fighting aims at the target itself. [br]
## @param p_id The entity to move [br]
## @return The position the movement should head for
func get_target_position(p_id: int) -> Vector2:
	var l_team: int = _entityTeam[p_id]
	var l_ownY: float = _entityPosition[p_id].y
	
	if (_entityState[p_id] == C_TargetingServer.STATE.FLEE):
		return Vector2(C_TargetingServer.TEAM_BASE_X[l_team], l_ownY)
	
	var l_targetId: int = _entityTarget[p_id]
	if (l_targetId != C_TargetingServer.NO_TARGET):
		return _entityPosition[l_targetId]
	
	if (_has_enemy_behind(p_id) or not _has_opponent_on_map(p_id)):
		return Vector2(C_TargetingServer.TEAM_BASE_X[l_team], l_ownY)
	
	return Vector2(C_TargetingServer.TEAM_MARCH_X[l_team], l_ownY)


## Returns the current state of an entity. [br]
## @param p_id The entity to read [br]
## @return Its C_TargetingServer.STATE
func get_state(p_id: int) -> int:
	return _entityState[p_id]


## Returns the target of an entity. [br]
## @param p_id The entity to read [br]
## @return Its target, or C_TargetingServer.NO_TARGET
func get_target(p_id: int) -> int:
	return _entityTarget[p_id]


## Returns everyone targeting an entity; the array is live, treat it as read only. [br]
## @param p_id The entity to read [br]
## @return The ids currently targeting it
func get_targeters(p_id: int) -> PackedInt32Array:
	return _targetersOf[p_id]

#endregion

#region OVERRIDES

## Marks an entity for removal and sends everyone targeting it back to searching. [br]
## @param p_id The entity id to mark
func pre_unregister_entity(p_id: int) -> void:
	super(p_id)
	drop_targeters(p_id)


## Removes an entity and unlinks it from both sides of the targeting graph. [br]
## @param p_id The entity id to remove
func unregister_entity(p_id: int) -> void:
	_drop_target(p_id)
	drop_targeters(p_id)
	super(p_id)

#endregion

#region PRIVATE_METHODS

## Packs the flag booleans of a targeting setup into one byte. [br]
## @param p_targetingData The setup to read [br]
## @return The packed flags
static func _build_flags(p_targetingData: R_TargetingData) -> int:
	var l_flags: int = 0
	
	if (p_targetingData.invisible):
		l_flags |= C_TargetingServer.FLAG_INVISIBLE
	
	if (p_targetingData.targetsInvisible):
		l_flags |= C_TargetingServer.FLAG_TARGETS_INVISIBLE
	
	if (p_targetingData.hasFocus):
		l_flags |= C_TargetingServer.FLAG_HAS_FOCUS
	
	if (p_targetingData.ignoresFocus):
		l_flags |= C_TargetingServer.FLAG_IGNORES_FOCUS
	
	return l_flags


## Switches one flag of an entity on or off. [br]
## @param p_id The entity to change [br]
## @param p_flag The C_TargetingServer.FLAG bit [br]
## @param p_enabled Whether the bit is set
func _set_flag(p_id: int, p_flag: int, p_enabled: bool) -> void:
	if (p_enabled):
		_entityFlags[p_id] |= p_flag
	else:
		_entityFlags[p_id] &= ~p_flag


## Decides what an entity is doing right now, fleeing first and searching last. [br]
## @param p_id The entity to judge [br]
## @return Its C_TargetingServer.STATE
func _evaluate_state(p_id: int) -> int:
	if (_can_still_flee(p_id) and _is_threatened(p_id)):
		_drop_target(p_id)
		return C_TargetingServer.STATE.FLEE
	
	var l_targetId: int = _entityTarget[p_id]
	if (l_targetId == C_TargetingServer.NO_TARGET):
		return C_TargetingServer.STATE.SEARCH
	
	var l_squaredDistance: float = _entityPosition[p_id].distance_squared_to(_entityPosition[l_targetId])
	if (l_squaredDistance <= _entitySquaredHitRange[p_id]):
		return C_TargetingServer.STATE.COMBAT
	
	return C_TargetingServer.STATE.APPROACH


## Checks whether the entity is still away from its own base and may keep fleeing. [br]
## @param p_id The entity to check [br]
## @return true while it has not reached its own side
func _can_still_flee(p_id: int) -> bool:
	var l_baseX: float = C_TargetingServer.TEAM_BASE_X[_entityTeam[p_id]]
	return absf(_entityPosition[p_id].x - l_baseX) > C_TargetingServer.BASE_REACHED_EPSILON


## Checks whether any entity targeting this one is inside its flee distance. [br]
## @param p_id The entity to check [br]
## @return true if it should run
func _is_threatened(p_id: int) -> bool:
	var l_fleeChunks: int = _entityFleeChunks[p_id]
	
	for l_targeterId: int in _targetersOf[p_id]:
		if (_get_chunk_distance(p_id, l_targeterId) <= l_fleeChunks):
			return true
	
	return false


## Scans the search area once and keeps the best priority and the best normal candidate. [br]
## @param p_id The entity that searches [br]
## @return The best target, or C_TargetingServer.NO_TARGET
func _find_best_target(p_id: int) -> int:
	var l_priorityGroups: int = _entityPriorityTargetedGroups[p_id]
	var l_normalGroups: int = _entityTargetedGroups[p_id]
	var l_searchedGroups: int = l_priorityGroups | l_normalGroups
	var l_team: int = _entityTeam[p_id]
	
	if (not _has_opponent_on_map(p_id)):
		return C_TargetingServer.NO_TARGET
	
	var l_bestPriorityId: int = C_TargetingServer.NO_TARGET
	var l_bestPriorityScore: float = -INF
	var l_bestNormalId: int = C_TargetingServer.NO_TARGET
	var l_bestNormalScore: float = -INF
	
	for l_chunkId: int in _collect_chunks_in_area(_get_search_area(p_id)):
		if (not _has_opponent_in_chunk(l_chunkId, l_team)):
			continue
		
		for l_candidateId: int in _entitiesInChunk[l_chunkId]:
			if (not _can_target(p_id, l_candidateId, l_searchedGroups)):
				continue
			
			var l_score: float = _score_candidate(p_id, l_candidateId)
			
			if ((_entityGroups[l_candidateId] & l_priorityGroups) != 0):
				if (l_score > l_bestPriorityScore):
					l_bestPriorityScore = l_score
					l_bestPriorityId = l_candidateId
			elif (l_score > l_bestNormalScore):
				l_bestNormalScore = l_score
				l_bestNormalId = l_candidateId
	
	if (l_bestPriorityId != C_TargetingServer.NO_TARGET):
		return l_bestPriorityId
	
	return l_bestNormalId


## Builds the chunk rectangle a search covers around an entity. [br]
## @param p_id The entity that searches [br]
## @return The rectangle as (minColumn, minRow, maxColumn, maxRow)
func _get_search_area(p_id: int) -> Vector4i:
	var l_area: Vector4i = _entityChunkArea[p_id]
	var l_reach: int = _entitySearchChunks[p_id]
	
	return Vector4i(
		maxi(l_area.x - l_reach, 0),
		maxi(l_area.y - l_reach, 0),
		mini(l_area.z + l_reach, C_ChunkingServer.MAP_CHUNK_COLUMNS - 1),
		mini(l_area.w + l_reach, C_ChunkingServer.MAP_CHUNK_ROWS - 1))


## Checks everything about a candidate that does not depend on the score. [br]
## @param p_id The entity that searches [br]
## @param p_candidateId The entity to check [br]
## @param p_groupMask The groups the searcher accepts [br]
## @return true if the candidate is worth scoring
func _can_target(p_id: int, p_candidateId: int, p_groupMask: int) -> bool:
	if (_entityTeam[p_candidateId] == _entityTeam[p_id]):
		return false
	
	if (_entityPreUnregistered[p_candidateId] == 1 or _entityUnregistering[p_candidateId] == 1):
		return false
	
	if ((_entityGroups[p_candidateId] & p_groupMask) == 0):
		return false
	
	return (_entityFlags[p_candidateId] & C_TargetingServer.FLAG_INVISIBLE) == 0 \
		or (_entityFlags[p_id] & C_TargetingServer.FLAG_TARGETS_INVISIBLE) != 0


## Weighs a candidate; every term is a comparison, a bit test or an array size. [br]
## @param p_id The entity that searches [br]
## @param p_candidateId The candidate to weigh [br]
## @return Its score, higher is better
func _score_candidate(p_id: int, p_candidateId: int) -> float:
	var l_distance: float = _get_chunk_distance(p_id, p_candidateId)
	var l_score: float = (_entitySearchChunks[p_id] - l_distance) * C_TargetingServer.WEIGHT_CLOSENESS
	
	if ((_entityFlags[p_candidateId] & C_TargetingServer.FLAG_HAS_FOCUS) != 0 \
			and (_entityFlags[p_id] & C_TargetingServer.FLAG_IGNORES_FOCUS) == 0):
		l_score += C_TargetingServer.WEIGHT_FOCUS
	
	if (_is_behind(p_id, p_candidateId)):
		l_score += C_TargetingServer.WEIGHT_BEHIND
	
	if (_entityTarget[p_candidateId] == p_id):
		l_score += C_TargetingServer.WEIGHT_MUTUAL
	
	return l_score - _targetersOf[p_candidateId].size() * C_TargetingServer.WEIGHT_CROWDING


## Reads the chunk an entity sits in from the rectangle the chunking server already keeps. [br]
## @param p_id The entity to locate [br]
## @return Its chunk as (column, row)
func _get_chunk_coord(p_id: int) -> Vector2i:
	var l_area: Vector4i = _entityChunkArea[p_id]
	return Vector2i(l_area.x, l_area.y)


## Measures the distance between two entities in chunk steps. [br]
## @param p_id The entity to measure from [br]
## @param p_otherId The entity to measure to [br]
## @return The steps, diagonals counted as C_TargetingServer.DIAGONAL_CHUNK_COST
func _get_chunk_distance(p_id: int, p_otherId: int) -> float:
	var l_delta: Vector2i = (_get_chunk_coord(p_otherId) - _get_chunk_coord(p_id)).abs()
	var l_diagonal: int = mini(l_delta.x, l_delta.y)
	var l_straight: int = maxi(l_delta.x, l_delta.y) - l_diagonal
	
	return l_straight + l_diagonal * C_TargetingServer.DIAGONAL_CHUNK_COST


## Checks whether an entity sits behind another one, against its march direction. [br]
## @param p_id The entity that looks [br]
## @param p_otherId The entity to place [br]
## @return true if the other one is further back
func _is_behind(p_id: int, p_otherId: int) -> bool:
	var l_columnDelta: int = _get_chunk_coord(p_otherId).x - _get_chunk_coord(p_id).x
	return l_columnDelta * _get_forward_sign(_entityTeam[p_id]) < 0


## Gives the direction a team marches in along x. [br]
## @param p_team The team to read [br]
## @return 1 towards a larger x, -1 towards a smaller one
func _get_forward_sign(p_team: int) -> int:
	return 1 if C_TargetingServer.TEAM_MARCH_X[p_team] > C_TargetingServer.TEAM_BASE_X[p_team] else -1


## Checks the columns behind an entity for opponents, counting invisible ones too. [br]
## Column counts hold every entity, which is what makes a sneaked past enemy show up. [br]
## @param p_id The entity to check [br]
## @return true if anything hostile got past it
func _has_enemy_behind(p_id: int) -> bool:
	var l_team: int = _entityTeam[p_id]
	var l_step: int = -_get_forward_sign(l_team)
	var l_column: int = _get_chunk_coord(p_id).x + l_step
	
	while (l_column >= 0 and l_column < C_ChunkingServer.MAP_CHUNK_COLUMNS):
		if (_has_opponent_in_column(l_column, l_team)):
			return true
		
		l_column += l_step
	
	return false


## Checks whether any other team holds entities in a column. [br]
## @param p_columnIndex The column to check [br]
## @param p_team The team that asks [br]
## @return true if an opponent stands there
func _has_opponent_in_column(p_columnIndex: int, p_team: int) -> bool:
	for l_team: int in C_ChunkingServer.TEAM_COUNT:
		if (l_team != p_team and _columnCounts[_get_team_column_index(l_team, p_columnIndex)] > 0):
			return true
	
	return false


## Checks whether any other team holds entities in a chunk. [br]
## @param p_chunkId The chunk to check [br]
## @param p_team The team that asks [br]
## @return true if an opponent stands there
func _has_opponent_in_chunk(p_chunkId: int, p_team: int) -> bool:
	for l_team: int in C_ChunkingServer.TEAM_COUNT:
		if (l_team != p_team and _chunkCounts[_get_team_chunk_index(l_team, p_chunkId)] > 0):
			return true
	
	return false


## Checks whether anything the entity may go after exists anywhere on the map. [br]
## @param p_id The entity that asks [br]
## @return true if a search could find something
func _has_opponent_on_map(p_id: int) -> bool:
	var l_team: int = _entityTeam[p_id]
	var l_searchedGroups: int = _entityPriorityTargetedGroups[p_id] | _entityTargetedGroups[p_id]
	
	for l_otherTeam: int in C_ChunkingServer.TEAM_COUNT:
		if (l_otherTeam != l_team and map_has_group(l_otherTeam, l_searchedGroups)):
			return true
	
	return false


## Links an entity to a target and records its slot in the targeter list. [br]
## @param p_id The entity that targets [br]
## @param p_targetId The entity it targets
func _assign_target(p_id: int, p_targetId: int) -> void:
	_drop_target(p_id)
	
	var l_targeters: PackedInt32Array = _targetersOf[p_targetId]
	_entityTargeterIndex[p_id] = l_targeters.size()
	l_targeters.append(p_id)
	_targetersOf[p_targetId] = l_targeters
	_entityTarget[p_id] = p_targetId


## Unlinks an entity from its target by swap-and-pop and sends it back to searching. [br]
## @param p_id The entity that gives up its target
func _drop_target(p_id: int) -> void:
	var l_targetId: int = _entityTarget[p_id]
	
	if (l_targetId == C_TargetingServer.NO_TARGET):
		return
	
	var l_targeters: PackedInt32Array = _targetersOf[l_targetId]
	var l_slot: int = _entityTargeterIndex[p_id]
	var l_lastSlot: int = l_targeters.size() - 1
	var l_movedId: int = l_targeters[l_lastSlot]
	
	l_targeters[l_slot] = l_movedId
	l_targeters.resize(l_lastSlot)
	_targetersOf[l_targetId] = l_targeters
	_entityTargeterIndex[l_movedId] = l_slot
	
	_entityTarget[p_id] = C_TargetingServer.NO_TARGET
	_entityState[p_id] = C_TargetingServer.STATE.SEARCH

#endregion
