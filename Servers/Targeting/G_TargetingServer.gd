extends A_CoreServers
## Autoload that picks and holds a target per entity and reports where it should move. [br]
## Searches are chunk counted and event driven: a target is only ever lost, never re-checked.

#region CACHED_VARS

## Cached C_TargetingServer.FLAG_INVISIBLE.
var FLAG_INVISIBLE: int

## Cached C_TargetingServer.FLAG_TARGETS_INVISIBLE.
var FLAG_TARGETS_INVISIBLE: int

## Cached C_TargetingServer.FLAG_HAS_FOCUS.
var FLAG_HAS_FOCUS: int

## Cached C_TargetingServer.FLAG_IGNORES_FOCUS.
var FLAG_IGNORES_FOCUS: int

## Cached C_TargetingServer.BASE_REACHED_EPSILON.
var BASE_REACHED_EPSILON: float

## Cached C_TargetingServer.DIAGONAL_CHUNK_COST.
var DIAGONAL_CHUNK_COST: float

## Cached C_TargetingServer.TEAM_BASE_X.
var TEAM_BASE_X: PackedFloat32Array

## Cached C_TargetingServer.TEAM_MARCH_X.
var TEAM_MARCH_X: PackedFloat32Array

## Cached C_TargetingServer.TEAM_FORWARD_SIGN.
var TEAM_FORWARD_SIGN: PackedInt32Array

## Cached C_TargetingServer.WEIGHT_CLOSENESS.
var WEIGHT_CLOSENESS: float

## Cached C_TargetingServer.WEIGHT_FOCUS.
var WEIGHT_FOCUS: float

## Cached C_TargetingServer.WEIGHT_BEHIND.
var WEIGHT_BEHIND: float

## Cached C_TargetingServer.WEIGHT_CROWDING.
var WEIGHT_CROWDING: float

## Cached C_TargetingServer.WEIGHT_MUTUAL.
var WEIGHT_MUTUAL: float

#endregion

#region LIFECYCLE_AND_METHODS

## Caches the constants only targeting queries need; MAP_CHUNK_COLUMNS, MAP_CHUNK_ROWS and NO_ID are already inherited.
func _init() -> void:
	super._init()

	FLAG_INVISIBLE = C_TargetingServer.FLAG_INVISIBLE
	FLAG_TARGETS_INVISIBLE = C_TargetingServer.FLAG_TARGETS_INVISIBLE
	FLAG_HAS_FOCUS = C_TargetingServer.FLAG_HAS_FOCUS
	FLAG_IGNORES_FOCUS = C_TargetingServer.FLAG_IGNORES_FOCUS
	BASE_REACHED_EPSILON = C_TargetingServer.BASE_REACHED_EPSILON
	DIAGONAL_CHUNK_COST = C_TargetingServer.DIAGONAL_CHUNK_COST
	TEAM_BASE_X = C_TargetingServer.TEAM_BASE_X
	TEAM_MARCH_X = C_TargetingServer.TEAM_MARCH_X
	TEAM_FORWARD_SIGN = C_TargetingServer.TEAM_FORWARD_SIGN
	WEIGHT_CLOSENESS = C_TargetingServer.WEIGHT_CLOSENESS
	WEIGHT_FOCUS = C_TargetingServer.WEIGHT_FOCUS
	WEIGHT_BEHIND = C_TargetingServer.WEIGHT_BEHIND
	WEIGHT_CROWDING = C_TargetingServer.WEIGHT_CROWDING
	WEIGHT_MUTUAL = C_TargetingServer.WEIGHT_MUTUAL


## Advances the state of one entity; cheap enough to run every tick. [br]
## Never searches — the entity asks for that itself through search_target(). [br]
## @param p_id The entity to advance [br]
## @return Its new C_TargetingServer.STATE
func update_entity(p_id: int) -> int:
	if (_can_still_flee(p_id) and _is_threatened(p_id)):
		_drop_target(p_id)
		_targetingEntityState[p_id] = C_TargetingServer.STATE.FLEE

		return C_TargetingServer.STATE.FLEE

	var l_state: int = _evaluate_state(p_id)
	_targetingEntityState[p_id] = l_state

	return l_state


## Scans the search area of an entity and gives it the best scoring target. [br]
## @param p_id The entity that searches [br]
## @return The target it got, or C_CoreServers.NO_ID
func search_target(p_id: int) -> int:
	var l_targetId: int = _find_best_target(p_id)

	if (l_targetId != NO_ID):
		_assign_target(p_id, l_targetId)

	return l_targetId


## Hides an entity from searchers, or reveals it again. [br]
## Hiding drops every targeter that cannot see invisible entities. [br]
## @param p_id The entity to change [br]
## @param p_isInvisible Whether it becomes invisible
func set_invisible(p_id: int, p_isInvisible: bool) -> void:
	_set_flag(p_id, FLAG_INVISIBLE, p_isInvisible)

	if (not p_isInvisible):
		return

	var l_targeters: PackedInt32Array = _targetersOf[p_id].duplicate()
	for l_targeterId: int in l_targeters:
		if ((_targetingEntityFlags[l_targeterId] & FLAG_TARGETS_INVISIBLE) == 0):
			_drop_target(l_targeterId)


## Sets whether an entity can see invisible enemies. [br]
## @param p_id The entity to change [br]
## @param p_isEnabled Whether it sees them
func set_targets_invisible(p_id: int, p_isEnabled: bool) -> void:
	_set_flag(p_id, FLAG_TARGETS_INVISIBLE, p_isEnabled)


## Sets whether an entity is a focus target other entities prefer. [br]
## @param p_id The entity to change [br]
## @param p_isEnabled Whether it carries focus
func set_focused(p_id: int, p_isEnabled: bool) -> void:
	_set_flag(p_id, FLAG_HAS_FOCUS, p_isEnabled)


## Sets whether an entity scores candidates without the focus bonus. [br]
## @param p_id The entity to change [br]
## @param p_isEnabled Whether it ignores focus
func set_ignores_focus(p_id: int, p_isEnabled: bool) -> void:
	_set_flag(p_id, FLAG_IGNORES_FOCUS, p_isEnabled)


## Sets how far a search of this entity reaches. [br]
## @param p_id The entity to change [br]
## @param p_searchChunks Reach in chunks per direction
func set_search_chunks(p_id: int, p_searchChunks: int) -> void:
	_targetingEntitySearchChunks[p_id] = p_searchChunks


## Sets how close a targeter has to come before the entity flees. [br]
## @param p_id The entity to change [br]
## @param p_fleeChunks Threat distance in chunks
func set_flee_chunks(p_id: int, p_fleeChunks: int) -> void:
	_targetingEntityFleeChunks[p_id] = p_fleeChunks


## Sets the real distance at which the entity enters combat. [br]
## Measured to the edge of the target, so the radius of the target is added on top. [br]
## @param p_id The entity to change [br]
## @param p_hitRange The distance to the silhouette of the target
func set_hit_range(p_id: int, p_hitRange: float) -> void:
	_targetingEntityHitRange[p_id] = p_hitRange


## Sets the groups the entity goes after before it considers the normal ones. [br]
## @param p_id The entity to change [br]
## @param p_priorityTargetedGroups Bitmask of the preferred groups
func set_priority_targeted_groups(p_id: int, p_priorityTargetedGroups: int) -> void:
	_targetingEntityPriorityTargetedGroups[p_id] = p_priorityTargetedGroups


## Returns where the entity should move this tick. [br]
## Fleeing and marching aim at a fixed x of the map, fighting aims at the target itself. [br]
## @param p_id The entity to move [br]
## @return The position the movement should head for
func get_target_position(p_id: int) -> Vector2:
	var l_team: int = _chunkEntityTeam[p_id]
	var l_ownY: float = _chunkEntityPosition[p_id].y

	if (_targetingEntityState[p_id] == C_TargetingServer.STATE.FLEE):
		return Vector2(TEAM_BASE_X[l_team], l_ownY)

	var l_targetId: int = _targetingEntityTarget[p_id]
	if (l_targetId != NO_ID):
		return _chunkEntityPosition[l_targetId]

	if (_has_enemy_behind(p_id) or not _has_opponent_on_map(p_id)):
		return Vector2(TEAM_BASE_X[l_team], l_ownY)

	return Vector2(TEAM_MARCH_X[l_team], l_ownY)


## Returns the current state of an entity. [br]
## @param p_id The entity to read [br]
## @return Its C_TargetingServer.STATE
func get_state(p_id: int) -> int:
	return _targetingEntityState[p_id]


## Returns the target of an entity. [br]
## @param p_id The entity to read [br]
## @return Its target, or C_CoreServers.NO_ID
func get_target(p_id: int) -> int:
	return _targetingEntityTarget[p_id]


## Returns everyone targeting an entity as a snapshot of the moment it is asked. [br]
## Packed arrays copy on write, so the result never follows later changes and editing it changes nothing. [br]
## @param p_id The entity to read [br]
## @return The ids currently targeting it
func get_targeters(p_id: int) -> PackedInt32Array:
	return _targetersOf[p_id]


## Switches one flag of an entity on or off. [br]
## @param p_id The entity to change [br]
## @param p_flag The C_TargetingServer.FLAG bit [br]
## @param p_isEnabled Whether the bit is set
func _set_flag(p_id: int, p_flag: int, p_isEnabled: bool) -> void:
	if (p_isEnabled):
		_targetingEntityFlags[p_id] |= p_flag
	else:
		_targetingEntityFlags[p_id] &= ~p_flag


## Decides what an entity is doing right now, without changing anything about it. [br]
## Fleeing is decided by the caller, because it has to drop the target first. [br]
## @param p_id The entity to judge [br]
## @return Its C_TargetingServer.STATE
func _evaluate_state(p_id: int) -> int:
	var l_targetId: int = _targetingEntityTarget[p_id]

	if (l_targetId == NO_ID):
		return C_TargetingServer.STATE.SEARCH

	var l_squaredDistance: float = _chunkEntityPosition[p_id].distance_squared_to(_chunkEntityPosition[l_targetId])
	var l_reach: float = _targetingEntityHitRange[p_id] + _chunkEntityRadius[l_targetId]

	if (l_squaredDistance <= l_reach * l_reach):
		return C_TargetingServer.STATE.COMBAT

	return C_TargetingServer.STATE.APPROACH


## Checks whether the entity is still away from its own base and may keep fleeing. [br]
## @param p_id The entity to check [br]
## @return true while it has not reached its own side
func _can_still_flee(p_id: int) -> bool:
	var l_baseX: float = TEAM_BASE_X[_chunkEntityTeam[p_id]]
	return absf(_chunkEntityPosition[p_id].x - l_baseX) > BASE_REACHED_EPSILON


## Checks whether any entity targeting this one is inside its flee distance. [br]
## @param p_id The entity to check [br]
## @return true if it should run
func _is_threatened(p_id: int) -> bool:
	var l_fleeChunks: int = _targetingEntityFleeChunks[p_id]
	var l_column: int = _chunkEntityCenterColumn[p_id]
	var l_row: int = _chunkEntityCenterRow[p_id]

	for l_targeterId: int in _targetersOf[p_id]:
		if (_get_chunk_distance(l_column, l_row, l_targeterId) <= l_fleeChunks):
			return true

	return false


## Scans the search area ring by ring and keeps the best priority and the best normal candidate. [br]
## Stops as soon as no further ring can beat what was already found. [br]
## @param p_id The entity that searches [br]
## @return The best target, or C_CoreServers.NO_ID
func _find_best_target(p_id: int) -> int:
	var l_priorityGroups: int = _targetingEntityPriorityTargetedGroups[p_id]
	var l_searchedGroups: int = l_priorityGroups | _targetingEntityTargetedGroups[p_id]
	var l_team: int = _chunkEntityTeam[p_id]

	if (not G_ChunkingServer.map_has_opponent_group(l_team, l_searchedGroups)):
		return NO_ID

	_searchId = p_id
	_searchTeam = l_team
	_searchColumn = _chunkEntityCenterColumn[p_id]
	_searchRow = _chunkEntityCenterRow[p_id]
	_searchFlags = _targetingEntityFlags[p_id]
	_searchReach = _targetingEntitySearchChunks[p_id]
	_searchForwardSign = TEAM_FORWARD_SIGN[l_team]
	_searchGroups = l_searchedGroups
	_searchPriorityGroups = l_priorityGroups
	_searchBestPriorityId = NO_ID
	_searchBestPriorityScore = 0.0
	_searchBestNormalId = NO_ID
	_searchBestNormalScore = 0.0

	var l_isPriorityPossible: bool = l_priorityGroups != 0 \
		and G_ChunkingServer.map_has_opponent_group(l_team, l_priorityGroups)
	var l_maxBonus: float = _get_max_score_bonus()

	for l_ring: int in range(0, _searchReach + 1):
		if (_is_search_settled(l_ring, l_maxBonus, l_isPriorityPossible)):
			break

		_scan_ring(l_ring)

	if (_searchBestPriorityId != NO_ID):
		return _searchBestPriorityId

	return _searchBestNormalId


## Sums up every bonus a candidate of the running search could possibly score. [br]
## Crowding only ever subtracts, so leaving it out keeps the sum an upper bound. [br]
## @return The largest bonus any candidate can add on top of its closeness
func _get_max_score_bonus() -> float:
	var l_bonus: float = WEIGHT_BEHIND + WEIGHT_MUTUAL

	if ((_searchFlags & FLAG_IGNORES_FOCUS) == 0):
		l_bonus += WEIGHT_FOCUS

	return l_bonus


## Checks whether no ring from here outwards could still beat what the search already holds. [br]
## A chunk of ring r is at least r steps away, so its closeness can never top the bound. [br]
## @param p_ring The ring that would be scanned next [br]
## @param p_maxBonus The largest bonus a candidate can score on top of its closeness [br]
## @param p_isPriorityPossible Whether a priority target exists on the map at all [br]
## @return true if the search can stop here
func _is_search_settled(p_ring: int, p_maxBonus: float, p_isPriorityPossible: bool) -> bool:
	var l_bound: float = (_searchReach - p_ring) * WEIGHT_CLOSENESS + p_maxBonus

	if (_searchBestPriorityId != NO_ID):
		return _searchBestPriorityScore >= l_bound

	if (p_isPriorityPossible):
		return false

	return _searchBestNormalId != NO_ID and _searchBestNormalScore >= l_bound


## Scans every chunk at exactly one ring distance around the searcher. [br]
## Walks the ring column by column so one column that holds nothing skips all its chunks at once. [br]
## @param p_ring The ring distance to scan, 0 being the chunk of the searcher itself
func _scan_ring(p_ring: int) -> void:
	var l_leftColumn: int = _searchColumn - p_ring
	var l_rightColumn: int = _searchColumn + p_ring
	var l_topRow: int = _searchRow - p_ring
	var l_bottomRow: int = _searchRow + p_ring
	var l_firstRow: int = maxi(l_topRow, 0)
	var l_lastRow: int = mini(l_bottomRow, MAP_CHUNK_ROWS - 1)

	for l_column: int in range(maxi(l_leftColumn, 0), mini(l_rightColumn, MAP_CHUNK_COLUMNS - 1) + 1):
		if (not G_ChunkingServer.column_has_opponent_group(l_column, _searchTeam, _searchGroups)):
			continue

		if (l_column == l_leftColumn or l_column == l_rightColumn):
			for l_row: int in range(l_firstRow, l_lastRow + 1):
				_scan_chunk(l_row * MAP_CHUNK_COLUMNS + l_column)

			continue

		if (l_topRow >= 0):
			_scan_chunk(l_topRow * MAP_CHUNK_COLUMNS + l_column)

		if (l_bottomRow < MAP_CHUNK_ROWS):
			_scan_chunk(l_bottomRow * MAP_CHUNK_COLUMNS + l_column)


## Scores every center that sits in one chunk and keeps the best of each category. [br]
## Only centers hang in this chain, so an entity spanning several chunks is still seen exactly once. [br]
## @param p_chunkId The chunk to open
func _scan_chunk(p_chunkId: int) -> void:
	if (not G_ChunkingServer.chunk_has_opponent_group(p_chunkId, _searchTeam, _searchGroups)):
		return

	var l_candidateId: int = _centerHead[p_chunkId]
	while (l_candidateId != NO_ID):
		var l_nextId: int = _centerNext[l_candidateId]

		if (not _can_target(l_candidateId)):
			l_candidateId = l_nextId
			continue

		var l_score: float = _score_candidate(l_candidateId)

		if ((_chunkEntityGroups[l_candidateId] & _searchPriorityGroups) != 0):
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
## @param p_bestId The best candidate so far, or C_CoreServers.NO_ID [br]
## @return true if the candidate takes the lead
func _is_better(p_score: float, p_candidateId: int, p_bestScore: float, p_bestId: int) -> bool:
	if (p_bestId == NO_ID or p_score > p_bestScore):
		return true

	return p_score == p_bestScore and p_candidateId < p_bestId


## Checks everything about a candidate of the running search that does not depend on the score. [br]
## @param p_candidateId The entity to check [br]
## @return true if the candidate is worth scoring
func _can_target(p_candidateId: int) -> bool:
	if (_chunkEntityTeam[p_candidateId] == _searchTeam):
		return false

	if (_chunkEntityPreUnregistered[p_candidateId] == 1 or _chunkEntityUnregistering[p_candidateId] == 1):
		return false

	if ((_chunkEntityGroups[p_candidateId] & _searchGroups) == 0):
		return false

	return (_targetingEntityFlags[p_candidateId] & FLAG_INVISIBLE) == 0 \
		or (_searchFlags & FLAG_TARGETS_INVISIBLE) != 0


## Weighs a candidate of the running search; every term is a comparison, a bit test or an array size. [br]
## @param p_candidateId The candidate to weigh [br]
## @return Its score, higher is better
func _score_candidate(p_candidateId: int) -> float:
	var l_distance: float = _get_chunk_distance(_searchColumn, _searchRow, p_candidateId)
	var l_score: float = (_searchReach - l_distance) * WEIGHT_CLOSENESS

	if ((_targetingEntityFlags[p_candidateId] & FLAG_HAS_FOCUS) != 0 \
			and (_searchFlags & FLAG_IGNORES_FOCUS) == 0):
		l_score += WEIGHT_FOCUS

	if ((_chunkEntityCenterColumn[p_candidateId] - _searchColumn) * _searchForwardSign < 0):
		l_score += WEIGHT_BEHIND

	if (_targetingEntityTarget[p_candidateId] == _searchId):
		l_score += WEIGHT_MUTUAL

	return l_score - _targetersOf[p_candidateId].size() * WEIGHT_CROWDING


## Measures the distance from a center chunk to the center chunk of an entity, in chunk steps. [br]
## @param p_column Column of the chunk to measure from [br]
## @param p_row Row of the chunk to measure from [br]
## @param p_otherId The entity to measure to [br]
## @return The steps, diagonals counted as C_TargetingServer.DIAGONAL_CHUNK_COST
func _get_chunk_distance(p_column: int, p_row: int, p_otherId: int) -> float:
	var l_columnDelta: int = absi(_chunkEntityCenterColumn[p_otherId] - p_column)
	var l_rowDelta: int = absi(_chunkEntityCenterRow[p_otherId] - p_row)
	var l_diagonal: int = mini(l_columnDelta, l_rowDelta)
	var l_straight: int = maxi(l_columnDelta, l_rowDelta) - l_diagonal

	return l_straight + l_diagonal * DIAGONAL_CHUNK_COST


## Checks whether anything hostile got past an entity, counting invisible ones too. [br]
## Reads the outermost column each team occupies, so the width of the map never enters the cost. [br]
## @param p_id The entity to check [br]
## @return true if an opponent stands behind it
func _has_enemy_behind(p_id: int) -> bool:
	var l_team: int = _chunkEntityTeam[p_id]
	var l_column: int = _chunkEntityCenterColumn[p_id]

	if (TEAM_FORWARD_SIGN[l_team] > 0):
		return G_ChunkingServer.has_opponent_before_column(l_column, l_team)

	return G_ChunkingServer.has_opponent_after_column(l_column, l_team)


## Checks whether anything the entity may go after exists anywhere on the map. [br]
## @param p_id The entity that asks [br]
## @return true if a search could find something
func _has_opponent_on_map(p_id: int) -> bool:
	var l_searchedGroups: int = _targetingEntityPriorityTargetedGroups[p_id] | _targetingEntityTargetedGroups[p_id]
	return G_ChunkingServer.map_has_opponent_group(_chunkEntityTeam[p_id], l_searchedGroups)


## Links an entity to a target and records its slot in the targeter list. [br]
## @param p_id The entity that targets [br]
## @param p_targetId The entity it targets
func _assign_target(p_id: int, p_targetId: int) -> void:
	_drop_target(p_id)

	var l_targeters: PackedInt32Array = _targetersOf[p_targetId]
	_targetingEntityTargeterIndex[p_id] = l_targeters.size()
	l_targeters.append(p_id)
	_targetersOf[p_targetId] = l_targeters
	_targetingEntityTarget[p_id] = p_targetId

#endregion
