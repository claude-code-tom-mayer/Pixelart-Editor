extends A_CoreServer
## Autoload that picks and holds a target per entity and reports where it should move. [br]
## Searches are chunk counted and event driven: a target is only ever lost, never re-checked.

#region CACHED_VARS

## Cached C_TargetingServer.FLAG_IS_INVISIBLE.
var FLAG_IS_INVISIBLE: int

## Cached C_TargetingServer.FLAG_CAN_TARGET_INVISIBLE.
var FLAG_CAN_TARGET_INVISIBLE: int

## Cached C_TargetingServer.FLAG_HAS_FOCUS.
var FLAG_HAS_FOCUS: int

## Cached C_TargetingServer.FLAG_IS_IGNORING_FOCUS.
var FLAG_IS_IGNORING_FOCUS: int

## Cached C_TargetingServer.NEVER_FLEE.
var NEVER_FLEE: int

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

#region EXPORTS_AND_VARS

## The entity the running search belongs to.
var _searcherId: int = C_CoreServer.NO_ID

## Team of the searcher, a C_CoreServer.TEAM value.
var _searcherTeam: int = 0

## Column of the center chunk of the searcher.
var _searcherColumn: int = 0

## Row of the center chunk of the searcher.
var _searcherRow: int = 0

## Flags of the searcher, as C_TargetingServer.FLAG_ bits.
var _searcherFlags: int = 0

## Direction the searcher marches in along x; decides what counts as behind it.
var _searcherForwardSign: int = 1

## How many chunk rings the running search covers.
var _searchRadiusChunks: int = 0

## Every entity group the running search accepts, priority ones included.
var _searchedGroups: int = 0

## Entity groups the running search prefers over the normal ones.
var _searchedPriorityGroups: int = 0

## Best priority candidate so far, or NO_ID.
var _bestPriorityId: int = C_CoreServer.NO_ID

## Score of the best priority candidate so far.
var _bestPriorityScore: float = 0.0

## Best normal candidate so far, or NO_ID.
var _bestNormalId: int = C_CoreServer.NO_ID

## Score of the best normal candidate so far.
var _bestNormalScore: float = 0.0

#endregion

#region LIFECYCLE_AND_METHODS

## Caches the constants only targeting queries need; the shared ones are inherited from A_CoreServer.
func _init() -> void:
	FLAG_IS_INVISIBLE = C_TargetingServer.FLAG_IS_INVISIBLE
	FLAG_CAN_TARGET_INVISIBLE = C_TargetingServer.FLAG_CAN_TARGET_INVISIBLE
	FLAG_HAS_FOCUS = C_TargetingServer.FLAG_HAS_FOCUS
	FLAG_IS_IGNORING_FOCUS = C_TargetingServer.FLAG_IS_IGNORING_FOCUS
	NEVER_FLEE = C_TargetingServer.NEVER_FLEE
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
## Never searches — the entity asks for that itself through acquire_target(). [br]
## @param p_id The entity to advance [br]
## @return Its new state
func update_state(p_id: int) -> C_TargetingServer.STATE:
	if (_is_away_from_base(p_id) and _is_threatened(p_id)):
		_clear_target(p_id)
		_entityTargetingState[p_id] = C_TargetingServer.STATE.FLEE

		return C_TargetingServer.STATE.FLEE

	var l_state: C_TargetingServer.STATE = _evaluate_state(p_id)
	_entityTargetingState[p_id] = l_state

	return l_state


## Searches the surroundings of an entity and makes the best scoring candidate its target. [br]
## A removed entity is ignored with a warning, so it cannot be linked into a targeter chain again. [br]
## @param p_id The entity that searches [br]
## @return The target it got, or C_CoreServer.NO_ID
func acquire_target(p_id: int) -> int:
	if (_reject_removed_id(p_id, "G_TargetingServer.acquire_target")):
		return NO_ID

	var l_targetId: int = _find_best_target(p_id)

	if (l_targetId != NO_ID):
		_assign_target(p_id, l_targetId)

	return l_targetId


## Hides an entity from searchers, or reveals it again. [br]
## Hiding drops every targeter that cannot see invisible entities. [br]
## @param p_id The entity to change [br]
## @param p_isInvisible Whether it becomes invisible
func set_is_invisible(p_id: int, p_isInvisible: bool) -> void:
	_set_flag(p_id, FLAG_IS_INVISIBLE, p_isInvisible)

	if (p_isInvisible):
		_release_targeters(p_id, FLAG_CAN_TARGET_INVISIBLE)


## Sets whether an entity can see invisible opponents. [br]
## @param p_id The entity to change [br]
## @param p_canTargetInvisible Whether it sees them
func set_can_target_invisible(p_id: int, p_canTargetInvisible: bool) -> void:
	_set_flag(p_id, FLAG_CAN_TARGET_INVISIBLE, p_canTargetInvisible)


## Sets whether an entity is a focus target that searchers prefer. [br]
## @param p_id The entity to change [br]
## @param p_hasFocus Whether it carries focus
func set_has_focus(p_id: int, p_hasFocus: bool) -> void:
	_set_flag(p_id, FLAG_HAS_FOCUS, p_hasFocus)


## Sets whether an entity scores candidates without the focus bonus. [br]
## @param p_id The entity to change [br]
## @param p_isIgnoringFocus Whether it ignores focus
func set_is_ignoring_focus(p_id: int, p_isIgnoringFocus: bool) -> void:
	_set_flag(p_id, FLAG_IS_IGNORING_FOCUS, p_isIgnoringFocus)


## Sets how many chunk rings a search of this entity covers. [br]
## @param p_id The entity to change [br]
## @param p_searchRadiusChunks Search radius in chunk rings
func set_search_radius_chunks(p_id: int, p_searchRadiusChunks: int) -> void:
	_entitySearchRadiusChunks[p_id] = p_searchRadiusChunks


## Sets how close a targeter has to come before the entity flees. [br]
## @param p_id The entity to change [br]
## @param p_fleeRadiusChunks Threat distance in chunk steps, or C_TargetingServer.NEVER_FLEE
func set_flee_radius_chunks(p_id: int, p_fleeRadiusChunks: int) -> void:
	_entityFleeRadiusChunks[p_id] = p_fleeRadiusChunks


## Sets the real distance at which the entity enters combat. [br]
## Measured to the silhouette of the target, so the radius of the target is added on top. [br]
## @param p_id The entity to change [br]
## @param p_combatRange The distance to the silhouette of the target
func set_combat_range(p_id: int, p_combatRange: float) -> void:
	_entityCombatRange[p_id] = p_combatRange


## Sets the entity groups the entity may go after. [br]
## @param p_id The entity to change [br]
## @param p_targetedGroups Bitmask of the targeted entity groups
func set_targeted_groups(p_id: int, p_targetedGroups: int) -> void:
	_entityTargetedGroups[p_id] = p_targetedGroups


## Sets the entity groups the entity goes after before it considers the normal ones. [br]
## @param p_id The entity to change [br]
## @param p_priorityTargetedGroups Bitmask of the preferred entity groups
func set_priority_targeted_groups(p_id: int, p_priorityTargetedGroups: int) -> void:
	_entityPriorityTargetedGroups[p_id] = p_priorityTargetedGroups


## Returns where the entity should move this tick. [br]
## Fleeing and marching aim at a fixed x of the map, approaching and combat aim at the target itself. [br]
## @param p_id The entity to move [br]
## @return The position the movement should head for
func get_move_destination(p_id: int) -> Vector2:
	var l_targetId: int = _entityTarget[p_id]
	var l_isFleeing: bool = _entityTargetingState[p_id] == C_TargetingServer.STATE.FLEE

	if (l_targetId != NO_ID and not l_isFleeing):
		return _entityPosition[l_targetId]

	var l_team: int = _entityTeam[p_id]
	var l_ownY: float = _entityPosition[p_id].y

	if (l_isFleeing or _has_opponent_behind(p_id) or not _has_targetable_opponent_on_map(p_id)):
		return Vector2(TEAM_BASE_X[l_team], l_ownY)

	return Vector2(TEAM_MARCH_X[l_team], l_ownY)


## Returns the current state of an entity. [br]
## @param p_id The entity to read [br]
## @return Its state
func get_state(p_id: int) -> C_TargetingServer.STATE:
	return _entityTargetingState[p_id] as C_TargetingServer.STATE


## Returns the target of an entity. [br]
## @param p_id The entity to read [br]
## @return Its target, or C_CoreServer.NO_ID
func get_target(p_id: int) -> int:
	return _entityTarget[p_id]


## Returns everyone targeting an entity, as a snapshot of the moment it is asked. [br]
## @param p_id The entity to read [br]
## @return The ids currently targeting it
func get_targeters(p_id: int) -> PackedInt32Array:
	var l_targeterIds: PackedInt32Array = PackedInt32Array()
	var l_targeterId: int = _entityFirstTargeter[p_id]

	while (l_targeterId != NO_ID):
		l_targeterIds.append(l_targeterId)
		l_targeterId = _entityTargeterNext[l_targeterId]

	return l_targeterIds


## Switches one flag of an entity on or off. [br]
## @param p_id The entity to change [br]
## @param p_flag The C_TargetingServer.FLAG_ bit [br]
## @param p_isSet Whether the bit is set
func _set_flag(p_id: int, p_flag: int, p_isSet: bool) -> void:
	if (p_isSet):
		_entityTargetingFlags[p_id] |= p_flag
	else:
		_entityTargetingFlags[p_id] &= ~p_flag


## Decides what an entity is doing right now, without changing anything about it. [br]
## Fleeing is decided by the caller, because it has to drop the target first. [br]
## @param p_id The entity to judge [br]
## @return Its state
func _evaluate_state(p_id: int) -> C_TargetingServer.STATE:
	var l_targetId: int = _entityTarget[p_id]

	if (l_targetId == NO_ID):
		return C_TargetingServer.STATE.SEARCH

	var l_distanceSquared: float = _entityPosition[p_id].distance_squared_to(_entityPosition[l_targetId])
	var l_reach: float = _entityCombatRange[p_id] + _entityRadius[l_targetId]

	if (l_distanceSquared <= l_reach * l_reach):
		return C_TargetingServer.STATE.COMBAT

	return C_TargetingServer.STATE.APPROACH


## Checks whether the entity is still away from its own base, so fleeing still makes sense. [br]
## @param p_id The entity to check [br]
## @return true while it has not reached its own base
func _is_away_from_base(p_id: int) -> bool:
	var l_baseX: float = TEAM_BASE_X[_entityTeam[p_id]]
	return absf(_entityPosition[p_id].x - l_baseX) > BASE_REACHED_EPSILON


## Checks whether any entity targeting this one is within its flee radius. [br]
## @param p_id The entity to check [br]
## @return true if it should flee
func _is_threatened(p_id: int) -> bool:
	var l_fleeRadiusChunks: int = _entityFleeRadiusChunks[p_id]

	if (l_fleeRadiusChunks == NEVER_FLEE):
		return false

	var l_column: int = _entityCenterColumn[p_id]
	var l_row: int = _entityCenterRow[p_id]
	var l_targeterId: int = _entityFirstTargeter[p_id]

	while (l_targeterId != NO_ID):
		if (_get_chunk_distance(l_column, l_row, l_targeterId) <= l_fleeRadiusChunks):
			return true

		l_targeterId = _entityTargeterNext[l_targeterId]

	return false


## Scans the search area ring by ring and keeps the best priority and the best normal candidate. [br]
## Stops as soon as no further ring can beat what was already found. [br]
## @param p_id The entity that searches [br]
## @return The best target, or C_CoreServer.NO_ID
func _find_best_target(p_id: int) -> int:
	var l_team: int = _entityTeam[p_id]
	var l_priorityGroups: int = _entityPriorityTargetedGroups[p_id]
	var l_searchedGroups: int = _get_searched_groups(p_id)

	if (not _map_has_opponent_group(l_team, l_searchedGroups)):
		return NO_ID

	_searcherId = p_id
	_searcherTeam = l_team
	_searcherColumn = _entityCenterColumn[p_id]
	_searcherRow = _entityCenterRow[p_id]
	_searcherFlags = _entityTargetingFlags[p_id]
	_searcherForwardSign = TEAM_FORWARD_SIGN[l_team]
	_searchRadiusChunks = _entitySearchRadiusChunks[p_id]
	_searchedGroups = l_searchedGroups
	_searchedPriorityGroups = l_priorityGroups
	_bestPriorityId = NO_ID
	_bestPriorityScore = 0.0
	_bestNormalId = NO_ID
	_bestNormalScore = 0.0

	var l_isPriorityPossible: bool = l_priorityGroups != 0 and _map_has_opponent_group(l_team, l_priorityGroups)
	var l_maxBonus: float = _get_max_score_bonus()

	for l_ring: int in _searchRadiusChunks + 1:
		if (_is_search_settled(l_ring, l_maxBonus, l_isPriorityPossible)):
			break

		_scan_ring(l_ring)

	if (_bestPriorityId != NO_ID):
		return _bestPriorityId

	return _bestNormalId


## Combines the normal and the priority targeted groups of an entity. [br]
## @param p_id The entity that searches [br]
## @return Every entity group it may go after
func _get_searched_groups(p_id: int) -> int:
	return _entityPriorityTargetedGroups[p_id] | _entityTargetedGroups[p_id]


## Sums up every bonus a candidate of the running search could possibly score. [br]
## Crowding only ever subtracts, so leaving it out keeps the sum an upper bound. [br]
## @return The largest bonus any candidate can add on top of its closeness
func _get_max_score_bonus() -> float:
	var l_bonus: float = WEIGHT_BEHIND + WEIGHT_MUTUAL

	if ((_searcherFlags & FLAG_IS_IGNORING_FOCUS) == 0):
		l_bonus += WEIGHT_FOCUS

	return l_bonus


## Checks whether no ring from here outwards could still beat what the search already holds. [br]
## A chunk of ring r is at least r steps away, so its closeness can never top the bound. [br]
## @param p_ring The ring that would be scanned next [br]
## @param p_maxBonus The largest bonus a candidate can score on top of its closeness [br]
## @param p_isPriorityPossible Whether a priority candidate exists on the map at all [br]
## @return true if the search can stop here
func _is_search_settled(p_ring: int, p_maxBonus: float, p_isPriorityPossible: bool) -> bool:
	var l_bestReachableScore: float = (_searchRadiusChunks - p_ring) * WEIGHT_CLOSENESS + p_maxBonus

	if (_bestPriorityId != NO_ID):
		return _bestPriorityScore >= l_bestReachableScore

	if (p_isPriorityPossible):
		return false

	return _bestNormalId != NO_ID and _bestNormalScore >= l_bestReachableScore


## Scans every chunk at exactly one ring distance around the searcher. [br]
## Walks the ring column by column so a column without candidates skips all its chunks at once. [br]
## @param p_ring The ring to scan, 0 being the center chunk of the searcher itself
func _scan_ring(p_ring: int) -> void:
	var l_leftColumn: int = _searcherColumn - p_ring
	var l_rightColumn: int = _searcherColumn + p_ring
	var l_topRow: int = _searcherRow - p_ring
	var l_bottomRow: int = _searcherRow + p_ring
	var l_firstRow: int = maxi(l_topRow, 0)
	var l_lastRow: int = mini(l_bottomRow, CHUNK_ROWS - 1)

	for l_column: int in range(maxi(l_leftColumn, 0), mini(l_rightColumn, CHUNK_COLUMNS - 1) + 1):
		if (not _column_has_opponent_group(l_column, _searcherTeam, _searchedGroups)):
			continue

		if (l_column == l_leftColumn or l_column == l_rightColumn):
			for l_row: int in range(l_firstRow, l_lastRow + 1):
				_scan_chunk(l_row * CHUNK_COLUMNS + l_column)

			continue

		if (l_topRow >= 0):
			_scan_chunk(l_topRow * CHUNK_COLUMNS + l_column)

		if (l_bottomRow < CHUNK_ROWS):
			_scan_chunk(l_bottomRow * CHUNK_COLUMNS + l_column)


## Scores every entity whose center sits in one chunk and keeps the best of each category. [br]
## Only centers hang in this chain, so an entity spanning several chunks is still seen exactly once. [br]
## @param p_chunkId The chunk to open
func _scan_chunk(p_chunkId: int) -> void:
	if (not _chunk_has_opponent_group(p_chunkId, _searcherTeam, _searchedGroups)):
		return

	var l_candidateId: int = _chunkFirstCenter[p_chunkId]
	while (l_candidateId != NO_ID):
		var l_nextCandidateId: int = _entityCenterNext[l_candidateId]

		if (not _is_valid_search_candidate(l_candidateId)):
			l_candidateId = l_nextCandidateId
			continue

		var l_score: float = _score_candidate(l_candidateId)

		if ((_entityGroups[l_candidateId] & _searchedPriorityGroups) != 0):
			if (_is_better_candidate(l_score, l_candidateId, _bestPriorityScore, _bestPriorityId)):
				_bestPriorityScore = l_score
				_bestPriorityId = l_candidateId
		elif (_is_better_candidate(l_score, l_candidateId, _bestNormalScore, _bestNormalId)):
			_bestNormalScore = l_score
			_bestNormalId = l_candidateId

		l_candidateId = l_nextCandidateId


## Compares a candidate against the best one so far, the lower id winning a tie. [br]
## Without the id the winner of a tie would depend on the order chunks happen to be stored in. [br]
## @param p_score Score of the candidate [br]
## @param p_candidateId The candidate itself [br]
## @param p_bestScore Score of the best candidate so far [br]
## @param p_bestId The best candidate so far, or C_CoreServer.NO_ID [br]
## @return true if the candidate takes the lead
func _is_better_candidate(p_score: float, p_candidateId: int, p_bestScore: float, p_bestId: int) -> bool:
	if (p_bestId == NO_ID or p_score > p_bestScore):
		return true

	return p_score == p_bestScore and p_candidateId < p_bestId


## Checks everything about a candidate of the running search that does not depend on its score. [br]
## @param p_candidateId The entity to check [br]
## @return true if the candidate is worth scoring
func _is_valid_search_candidate(p_candidateId: int) -> bool:
	if (_entityTeam[p_candidateId] == _searcherTeam):
		return false

	if (_isEntityPendingRemoval[p_candidateId] == 1 or _isEntityRemoved[p_candidateId] == 1):
		return false

	if ((_entityGroups[p_candidateId] & _searchedGroups) == 0):
		return false

	return (_entityTargetingFlags[p_candidateId] & FLAG_IS_INVISIBLE) == 0 \
		or (_searcherFlags & FLAG_CAN_TARGET_INVISIBLE) != 0


## Weighs a candidate of the running search; every term is a comparison, a bit test or a count. [br]
## @param p_candidateId The candidate to weigh [br]
## @return Its score, higher is better
func _score_candidate(p_candidateId: int) -> float:
	var l_chunkDistance: float = _get_chunk_distance(_searcherColumn, _searcherRow, p_candidateId)
	var l_score: float = (_searchRadiusChunks - l_chunkDistance) * WEIGHT_CLOSENESS

	if ((_entityTargetingFlags[p_candidateId] & FLAG_HAS_FOCUS) != 0 \
			and (_searcherFlags & FLAG_IS_IGNORING_FOCUS) == 0):
		l_score += WEIGHT_FOCUS

	if ((_entityCenterColumn[p_candidateId] - _searcherColumn) * _searcherForwardSign < 0):
		l_score += WEIGHT_BEHIND

	if (_entityTarget[p_candidateId] == _searcherId):
		l_score += WEIGHT_MUTUAL

	return l_score - _entityTargeterCount[p_candidateId] * WEIGHT_CROWDING


## Measures the chunk distance from a chunk to the center chunk of an entity. [br]
## @param p_column Column of the chunk to measure from [br]
## @param p_row Row of the chunk to measure from [br]
## @param p_otherId The entity to measure to [br]
## @return The steps, diagonal ones counted as C_TargetingServer.DIAGONAL_CHUNK_COST
func _get_chunk_distance(p_column: int, p_row: int, p_otherId: int) -> float:
	var l_columnDelta: int = absi(_entityCenterColumn[p_otherId] - p_column)
	var l_rowDelta: int = absi(_entityCenterRow[p_otherId] - p_row)
	var l_diagonalSteps: int = mini(l_columnDelta, l_rowDelta)
	var l_straightSteps: int = maxi(l_columnDelta, l_rowDelta) - l_diagonalSteps

	return l_straightSteps + l_diagonalSteps * DIAGONAL_CHUNK_COST


## Checks whether any opponent got past an entity, counting invisible ones too. [br]
## Reads the column span of every team, so the width of the map never enters the cost. [br]
## @param p_id The entity to check [br]
## @return true if an opponent stands behind it
func _has_opponent_behind(p_id: int) -> bool:
	var l_team: int = _entityTeam[p_id]
	var l_column: int = _entityCenterColumn[p_id]
	var l_isMarchingRight: bool = TEAM_FORWARD_SIGN[l_team] > 0

	for l_otherTeam: int in TEAM_COUNT:
		if (l_otherTeam == l_team or _teamMinColumn[l_otherTeam] == NO_ID):
			continue

		if (l_isMarchingRight and _teamMinColumn[l_otherTeam] < l_column):
			return true

		if (not l_isMarchingRight and _teamMaxColumn[l_otherTeam] > l_column):
			return true

	return false


## Checks whether anything the entity may go after exists anywhere on the map. [br]
## @param p_id The entity that asks [br]
## @return true if a search could find something
func _has_targetable_opponent_on_map(p_id: int) -> bool:
	return _map_has_opponent_group(_entityTeam[p_id], _get_searched_groups(p_id))


## Checks whether any other team holds one of the searched groups anywhere. [br]
## Widest step of the map, column, chunk filter; a search that fails here never touches a chunk. [br]
## @param p_team The team that asks [br]
## @param p_groups Bitmask of the searched entity groups [br]
## @return true if a search could find anything at all
func _map_has_opponent_group(p_team: int, p_groups: int) -> bool:
	for l_team: int in TEAM_COUNT:
		if (l_team != p_team and (_teamMapGroups[l_team] & p_groups) != 0):
			return true

	return false


## Checks whether any other team holds one of the searched groups in a column. [br]
## Skipping here skips every chunk of that column at once. [br]
## @param p_column The column to check [br]
## @param p_team The team that asks [br]
## @param p_groups Bitmask of the searched entity groups [br]
## @return true if the column is worth opening
func _column_has_opponent_group(p_column: int, p_team: int, p_groups: int) -> bool:
	for l_team: int in TEAM_COUNT:
		if (l_team != p_team and (_teamColumnGroups[l_team * CHUNK_COLUMNS + p_column] & p_groups) != 0):
			return true

	return false


## Checks whether any other team holds one of the searched groups in a chunk. [br]
## Narrowest step of the filter, right before the center chain is walked. [br]
## @param p_chunkId The chunk to check [br]
## @param p_team The team that asks [br]
## @param p_groups Bitmask of the searched entity groups [br]
## @return true if the chunk is worth opening
func _chunk_has_opponent_group(p_chunkId: int, p_team: int, p_groups: int) -> bool:
	for l_team: int in TEAM_COUNT:
		if (l_team != p_team and (_teamChunkGroups[l_team * CHUNK_COUNT + p_chunkId] & p_groups) != 0):
			return true

	return false


## Links an entity into the targeter chain of its new target. [br]
## @param p_id The entity that targets [br]
## @param p_targetId The entity it targets
func _assign_target(p_id: int, p_targetId: int) -> void:
	_clear_target(p_id)

	var l_firstTargeterId: int = _entityFirstTargeter[p_targetId]
	_entityTargeterPrev[p_id] = NO_ID
	_entityTargeterNext[p_id] = l_firstTargeterId

	if (l_firstTargeterId != NO_ID):
		_entityTargeterPrev[l_firstTargeterId] = p_id

	_entityFirstTargeter[p_targetId] = p_id
	_entityTargeterCount[p_targetId] += 1
	_entityTarget[p_id] = p_targetId

#endregion
