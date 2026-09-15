extends A_EntityServer
## Picks and holds a target per entity and reports where it should move. [br]
## Searches are chunk counted and event driven: a target is only ever lost, never re-checked.
class_name TargetingServer

#region PRIVATE_VARIABLES

## Bitmask of the groups an entity may go after.
var _entityTargetedGroups: PackedInt64Array = PackedInt64Array()

## Current C_TargetingServer.STATE per entity.
var _entityState: PackedByteArray = PackedByteArray()

## How many chunks in each direction a search of this entity covers.
var _entitySearchChunks: PackedInt32Array = PackedInt32Array()

## A targeter closer than this many chunks makes the entity flee.
var _entityFleeChunks: PackedInt32Array = PackedInt32Array()

## Real distance at which approaching turns into combat, measured to the edge of the target.
var _entityHitRange: PackedFloat32Array = PackedFloat32Array()

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

#region SEARCH_VARIABLES

# State of the running search, hoisted out of the candidate loop because none of it changes there.
# Only meaningful while _find_best_target() runs.

## The entity the running search belongs to.
var _searchId: int = C_TargetingServer.NO_TARGET

## Team of the searcher, a C_ChunkingServer.TEAM value.
var _searchTeam: int = 0

## Column of the center chunk of the searcher.
var _searchColumn: int = 0

## Row of the center chunk of the searcher.
var _searchRow: int = 0

## Flags of the searcher, as C_TargetingServer.FLAG bits.
var _searchFlags: int = 0

## How many chunks in each direction the running search covers.
var _searchReach: int = 0

## Direction the searcher marches in along x; decides what counts as behind it.
var _searchForwardSign: int = 1

## Every group the searcher accepts, priority ones included.
var _searchGroups: int = 0

## Groups the searcher goes after before it considers the normal ones.
var _searchPriorityGroups: int = 0

## Best priority candidate so far, or C_TargetingServer.NO_TARGET.
var _searchBestPriorityId: int = C_TargetingServer.NO_TARGET

## Score of the best priority candidate so far.
var _searchBestPriorityScore: float = 0.0

## Best normal candidate so far, or C_TargetingServer.NO_TARGET.
var _searchBestNormalId: int = C_TargetingServer.NO_TARGET

## Score of the best normal candidate so far.
var _searchBestNormalScore: float = 0.0

#endregion

#region PUBLIC_METHODS

## Gives an entity its targeting side; the api server calls this while it registers. [br]
## @param p_id The entity to set up [br]
## @param p_targetingData Groups, ranges and flags of the entity
func register(p_id: int, p_targetingData: R_TargetingData) -> void:
	ensure_slot(p_id)
	
	var l_targetingData: R_TargetingData = p_targetingData
	
	if (l_targetingData == null):
		push_error("TargetingServer: entity %d was registered without targeting data, using the defaults." % p_id)
		l_targetingData = R_TargetingData.new()
	
	_entityTargetedGroups[p_id] = l_targetingData.targetedGroups
	_entitySearchChunks[p_id] = l_targetingData.searchChunks
	_entityFleeChunks[p_id] = l_targetingData.fleeChunks
	_entityHitRange[p_id] = l_targetingData.hitRange
	_entityPriorityTargetedGroups[p_id] = l_targetingData.priorityTargetedGroups
	_entityFlags[p_id] = _build_flags(l_targetingData)


## Advances the state of one entity; cheap enough to run every tick. [br]
## Never searches — the entity asks for that itself through search_target(). [br]
## @param p_id The entity to advance [br]
## @return Its new C_TargetingServer.STATE
func update_entity(p_id: int) -> int:
	if (_can_still_flee(p_id) and _is_threatened(p_id)):
		_drop_target(p_id)
		_entityState[p_id] = C_TargetingServer.STATE.FLEE
		
		return C_TargetingServer.STATE.FLEE
	
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
## Measured to the edge of the target, so the radius of the target is added on top. [br]
## @param p_id The entity to change [br]
## @param p_hitRange The distance to the silhouette of the target
func set_hit_range(p_id: int, p_hitRange: float) -> void:
	_entityHitRange[p_id] = p_hitRange


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
	var l_team: int = _chunking._entityTeam[p_id]
	var l_ownY: float = _chunking._entityPosition[p_id].y
	
	if (_entityState[p_id] == C_TargetingServer.STATE.FLEE):
		return Vector2(C_TargetingServer.TEAM_BASE_X[l_team], l_ownY)
	
	var l_targetId: int = _entityTarget[p_id]
	if (l_targetId != C_TargetingServer.NO_TARGET):
		return _chunking._entityPosition[l_targetId]
	
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


## Returns everyone targeting an entity as a snapshot of the moment it is asked. [br]
## Packed arrays copy on write, so the result never follows later changes and editing it changes nothing. [br]
## @param p_id The entity to read [br]
## @return The ids currently targeting it
func get_targeters(p_id: int) -> PackedInt32Array:
	return _targetersOf[p_id]

#endregion

#region PUBLIC_LIFECYCLE

## Sends everyone targeting an announced entity back to searching. [br]
## Overrides A_EntityServer. [br]
## @param p_id The entity that was announced for removal
func on_pre_unregister(p_id: int) -> void:
	drop_targeters(p_id)


## Unlinks a removed entity from both sides of the targeting graph. [br]
## Overrides A_EntityServer. [br]
## @param p_id The entity that was removed
func on_unregister(p_id: int) -> void:
	_drop_target(p_id)
	drop_targeters(p_id)

#endregion

#region PRIVATE_SLOTS

## Appends one fresh slot to every column of this server. [br]
## Overrides A_EntityServer.
func _append_slot() -> void:
	_entityTargetedGroups.append(0)
	_entityState.append(C_TargetingServer.STATE.SEARCH)
	_entitySearchChunks.append(0)
	_entityFleeChunks.append(0)
	_entityHitRange.append(0.0)
	_entityPriorityTargetedGroups.append(0)
	_entityFlags.append(0)
	_entityTarget.append(C_TargetingServer.NO_TARGET)
	_entityTargeterIndex.append(0)
	_targetersOf.append(PackedInt32Array())


## Resets one slot so a reused id inherits neither the target nor the flags of its predecessor. [br]
## Overrides A_EntityServer. [br]
## @param p_id The entity slot to reset
func _reset_slot(p_id: int) -> void:
	_entityTargetedGroups[p_id] = 0
	_entityState[p_id] = C_TargetingServer.STATE.SEARCH
	_entitySearchChunks[p_id] = 0
	_entityFleeChunks[p_id] = 0
	_entityHitRange[p_id] = 0.0
	_entityPriorityTargetedGroups[p_id] = 0
	_entityFlags[p_id] = 0
	_entityTarget[p_id] = C_TargetingServer.NO_TARGET
	_entityTargeterIndex[p_id] = 0
	_targetersOf[p_id] = PackedInt32Array()


## Reads how many slots this server currently holds. [br]
## Overrides A_EntityServer. [br]
## @return The number of slots
func _get_slot_count() -> int:
	return _entityState.size()

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


## Decides what an entity is doing right now, without changing anything about it. [br]
## Fleeing is decided by the caller, because it has to drop the target first. [br]
## @param p_id The entity to judge [br]
## @return Its C_TargetingServer.STATE
func _evaluate_state(p_id: int) -> int:
	var l_targetId: int = _entityTarget[p_id]
	
	if (l_targetId == C_TargetingServer.NO_TARGET):
		return C_TargetingServer.STATE.SEARCH
	
	var l_squaredDistance: float = _chunking._entityPosition[p_id].distance_squared_to(_chunking._entityPosition[l_targetId])
	var l_reach: float = _entityHitRange[p_id] + _chunking._entityRadius[l_targetId]
	
	if (l_squaredDistance <= l_reach * l_reach):
		return C_TargetingServer.STATE.COMBAT
	
	return C_TargetingServer.STATE.APPROACH


## Checks whether the entity is still away from its own base and may keep fleeing. [br]
## @param p_id The entity to check [br]
## @return true while it has not reached its own side
func _can_still_flee(p_id: int) -> bool:
	var l_baseX: float = C_TargetingServer.TEAM_BASE_X[_chunking._entityTeam[p_id]]
	return absf(_chunking._entityPosition[p_id].x - l_baseX) > C_TargetingServer.BASE_REACHED_EPSILON


## Checks whether any entity targeting this one is inside its flee distance. [br]
## @param p_id The entity to check [br]
## @return true if it should run
func _is_threatened(p_id: int) -> bool:
	var l_fleeChunks: int = _entityFleeChunks[p_id]
	var l_column: int = _chunking._entityCenterColumn[p_id]
	var l_row: int = _chunking._entityCenterRow[p_id]
	
	for l_targeterId: int in _targetersOf[p_id]:
		if (_get_chunk_distance(l_column, l_row, l_targeterId) <= l_fleeChunks):
			return true
	
	return false


## Scans the search area ring by ring and keeps the best priority and the best normal candidate. [br]
## Stops as soon as no further ring can beat what was already found. [br]
## @param p_id The entity that searches [br]
## @return The best target, or C_TargetingServer.NO_TARGET
func _find_best_target(p_id: int) -> int:
	var l_priorityGroups: int = _entityPriorityTargetedGroups[p_id]
	var l_searchedGroups: int = l_priorityGroups | _entityTargetedGroups[p_id]
	var l_team: int = _chunking._entityTeam[p_id]
	
	if (not _chunking.map_has_opponent_group(l_team, l_searchedGroups)):
		return C_TargetingServer.NO_TARGET
	
	_searchId = p_id
	_searchTeam = l_team
	_searchColumn = _chunking._entityCenterColumn[p_id]
	_searchRow = _chunking._entityCenterRow[p_id]
	_searchFlags = _entityFlags[p_id]
	_searchReach = _entitySearchChunks[p_id]
	_searchForwardSign = C_TargetingServer.TEAM_FORWARD_SIGN[l_team]
	_searchGroups = l_searchedGroups
	_searchPriorityGroups = l_priorityGroups
	_searchBestPriorityId = C_TargetingServer.NO_TARGET
	_searchBestPriorityScore = 0.0
	_searchBestNormalId = C_TargetingServer.NO_TARGET
	_searchBestNormalScore = 0.0
	
	var l_priorityPossible: bool = l_priorityGroups != 0 \
		and _chunking.map_has_opponent_group(l_team, l_priorityGroups)
	var l_maxBonus: float = _get_max_score_bonus()
	
	for l_ring: int in range(0, _searchReach + 1):
		if (_is_search_settled(l_ring, l_maxBonus, l_priorityPossible)):
			break
		
		_scan_ring(l_ring)
	
	if (_searchBestPriorityId != C_TargetingServer.NO_TARGET):
		return _searchBestPriorityId
	
	return _searchBestNormalId


## Sums up every bonus a candidate of the running search could possibly score. [br]
## Crowding only ever subtracts, so leaving it out keeps the sum an upper bound. [br]
## @return The largest bonus any candidate can add on top of its closeness
func _get_max_score_bonus() -> float:
	var l_bonus: float = C_TargetingServer.WEIGHT_BEHIND + C_TargetingServer.WEIGHT_MUTUAL
	
	if ((_searchFlags & C_TargetingServer.FLAG_IGNORES_FOCUS) == 0):
		l_bonus += C_TargetingServer.WEIGHT_FOCUS
	
	return l_bonus


## Checks whether no ring from here outwards could still beat what the search already holds. [br]
## A chunk of ring r is at least r steps away, so its closeness can never top the bound. [br]
## @param p_ring The ring that would be scanned next [br]
## @param p_maxBonus The largest bonus a candidate can score on top of its closeness [br]
## @param p_priorityPossible Whether a priority target exists on the map at all [br]
## @return true if the search can stop here
func _is_search_settled(p_ring: int, p_maxBonus: float, p_priorityPossible: bool) -> bool:
	var l_bound: float = (_searchReach - p_ring) * C_TargetingServer.WEIGHT_CLOSENESS + p_maxBonus
	
	if (_searchBestPriorityId != C_TargetingServer.NO_TARGET):
		return _searchBestPriorityScore >= l_bound
	
	if (p_priorityPossible):
		return false
	
	return _searchBestNormalId != C_TargetingServer.NO_TARGET and _searchBestNormalScore >= l_bound


## Scans every chunk at exactly one ring distance around the searcher. [br]
## Walks the ring column by column so one column that holds nothing skips all its chunks at once. [br]
## @param p_ring The ring distance to scan, 0 being the chunk of the searcher itself
func _scan_ring(p_ring: int) -> void:
	var l_leftColumn: int = _searchColumn - p_ring
	var l_rightColumn: int = _searchColumn + p_ring
	var l_topRow: int = _searchRow - p_ring
	var l_bottomRow: int = _searchRow + p_ring
	var l_firstRow: int = maxi(l_topRow, 0)
	var l_lastRow: int = mini(l_bottomRow, _chunkRows - 1)
	
	for l_column: int in range(maxi(l_leftColumn, 0), mini(l_rightColumn, _chunkColumns - 1) + 1):
		if (not _chunking.column_has_opponent_group(l_column, _searchTeam, _searchGroups)):
			continue
		
		if (l_column == l_leftColumn or l_column == l_rightColumn):
			for l_row: int in range(l_firstRow, l_lastRow + 1):
				_scan_chunk(l_row * _chunkColumns + l_column)
			
			continue
		
		if (l_topRow >= 0):
			_scan_chunk(l_topRow * _chunkColumns + l_column)
		
		if (l_bottomRow < _chunkRows):
			_scan_chunk(l_bottomRow * _chunkColumns + l_column)


## Scores every center that sits in one chunk and keeps the best of each category. [br]
## Only centers hang in this chain, so an entity spanning several chunks is still seen exactly once. [br]
## @param p_chunkId The chunk to open
func _scan_chunk(p_chunkId: int) -> void:
	if (not _chunking.chunk_has_opponent_group(p_chunkId, _searchTeam, _searchGroups)):
		return
	
	var l_candidateId: int = _chunking._centerHead[p_chunkId]
	while (l_candidateId != C_ChunkingServer.NO_ENTITY):
		var l_nextId: int = _chunking._centerNext[l_candidateId]
		
		if (not _can_target(l_candidateId)):
			l_candidateId = l_nextId
			continue
		
		var l_score: float = _score_candidate(l_candidateId)
		
		if ((_chunking._entityGroups[l_candidateId] & _searchPriorityGroups) != 0):
			if (_is_better(l_score, l_candidateId, _searchBestPriorityScore, _searchBestPriorityId)):
				_searchBestPriorityScore = l_score
				_searchBestPriorityId = l_candidateId
		elif (_is_better(l_score, l_candidateId, _searchBestNormalScore, _searchBestNormalId)):
			_searchBestNormalScore = l_score
			_searchBestNormalId = l_candidateId
		
		l_candidateId = l_nextId


## Compares a candidate against the best one so far, the lower id winning a tie. [br]
## Without the id the winner of a tie would depend on the order chunks happen to be stored in. [br]
## @param p_score Score of the candidate [br]
## @param p_candidateId The candidate itself [br]
## @param p_bestScore Score of the best candidate so far [br]
## @param p_bestId The best candidate so far, or C_TargetingServer.NO_TARGET [br]
## @return true if the candidate takes the lead
func _is_better(p_score: float, p_candidateId: int, p_bestScore: float, p_bestId: int) -> bool:
	if (p_bestId == C_TargetingServer.NO_TARGET or p_score > p_bestScore):
		return true
	
	return p_score == p_bestScore and p_candidateId < p_bestId


## Checks everything about a candidate of the running search that does not depend on the score. [br]
## @param p_candidateId The entity to check [br]
## @return true if the candidate is worth scoring
func _can_target(p_candidateId: int) -> bool:
	if (_chunking._entityTeam[p_candidateId] == _searchTeam):
		return false
	
	if (_chunking._entityPreUnregistered[p_candidateId] == 1 or _chunking._entityUnregistering[p_candidateId] == 1):
		return false
	
	if ((_chunking._entityGroups[p_candidateId] & _searchGroups) == 0):
		return false
	
	return (_entityFlags[p_candidateId] & C_TargetingServer.FLAG_INVISIBLE) == 0 \
		or (_searchFlags & C_TargetingServer.FLAG_TARGETS_INVISIBLE) != 0


## Weighs a candidate of the running search; every term is a comparison, a bit test or an array size. [br]
## @param p_candidateId The candidate to weigh [br]
## @return Its score, higher is better
func _score_candidate(p_candidateId: int) -> float:
	var l_distance: float = _get_chunk_distance(_searchColumn, _searchRow, p_candidateId)
	var l_score: float = (_searchReach - l_distance) * C_TargetingServer.WEIGHT_CLOSENESS
	
	if ((_entityFlags[p_candidateId] & C_TargetingServer.FLAG_HAS_FOCUS) != 0 \
			and (_searchFlags & C_TargetingServer.FLAG_IGNORES_FOCUS) == 0):
		l_score += C_TargetingServer.WEIGHT_FOCUS
	
	if ((_chunking._entityCenterColumn[p_candidateId] - _searchColumn) * _searchForwardSign < 0):
		l_score += C_TargetingServer.WEIGHT_BEHIND
	
	if (_entityTarget[p_candidateId] == _searchId):
		l_score += C_TargetingServer.WEIGHT_MUTUAL
	
	return l_score - _targetersOf[p_candidateId].size() * C_TargetingServer.WEIGHT_CROWDING


## Measures the distance from a center chunk to the center chunk of an entity, in chunk steps. [br]
## @param p_column Column of the chunk to measure from [br]
## @param p_row Row of the chunk to measure from [br]
## @param p_otherId The entity to measure to [br]
## @return The steps, diagonals counted as C_TargetingServer.DIAGONAL_CHUNK_COST
func _get_chunk_distance(p_column: int, p_row: int, p_otherId: int) -> float:
	var l_columnDelta: int = absi(_chunking._entityCenterColumn[p_otherId] - p_column)
	var l_rowDelta: int = absi(_chunking._entityCenterRow[p_otherId] - p_row)
	var l_diagonal: int = mini(l_columnDelta, l_rowDelta)
	var l_straight: int = maxi(l_columnDelta, l_rowDelta) - l_diagonal
	
	return l_straight + l_diagonal * C_TargetingServer.DIAGONAL_CHUNK_COST


## Checks whether anything hostile got past an entity, counting invisible ones too. [br]
## Reads the outermost column each team occupies, so the width of the map never enters the cost. [br]
## @param p_id The entity to check [br]
## @return true if an opponent stands behind it
func _has_enemy_behind(p_id: int) -> bool:
	var l_team: int = _chunking._entityTeam[p_id]
	var l_column: int = _chunking._entityCenterColumn[p_id]
	
	if (C_TargetingServer.TEAM_FORWARD_SIGN[l_team] > 0):
		return _chunking.has_opponent_before_column(l_column, l_team)
	
	return _chunking.has_opponent_after_column(l_column, l_team)


## Checks whether anything the entity may go after exists anywhere on the map. [br]
## @param p_id The entity that asks [br]
## @return true if a search could find something
func _has_opponent_on_map(p_id: int) -> bool:
	var l_searchedGroups: int = _entityPriorityTargetedGroups[p_id] | _entityTargetedGroups[p_id]
	return _chunking.map_has_opponent_group(_chunking._entityTeam[p_id], l_searchedGroups)


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
