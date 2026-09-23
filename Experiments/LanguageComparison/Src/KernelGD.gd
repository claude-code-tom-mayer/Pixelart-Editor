extends RefCounted
class_name KernelGD
## GDScript reference implementation of the search kernel benchmark. [br]
## Written naively, with one helper call per group check, as the baseline of SPEC.md.

#region ENUMS_AND_CONSTANTS

## Chunks per row.
const COLS: int = 32

## Chunk rows.
const ROWS: int = 32

## How many chunks in each direction a search covers.
const REACH: int = 4

## Bitmask of the groups every searcher goes after.
const SEARCH_GROUPS: int = 7

## Score per chunk a candidate is closer than the edge of the search area.
const W_CLOSE: float = 1.0

## Score added for a focus target.
const W_FOCUS: float = 6.0

## Score added for a candidate behind the searcher.
const W_BEHIND: float = 3.0

## Score lost per entity already targeting the candidate.
const W_CROWD: float = 1.5

## Score added when the candidate already targets the searcher.
const W_MUTUAL: float = 4.0

## Cost of a diagonal chunk step against a straight one.
const DIAG: float = 1.45

#endregion

#region EXPORTS_AND_VARS

## State of the xorshift generator every port seeds identically.
var _randomState: int = 12345

## Team per entity.
var _entityTeam: PackedByteArray = PackedByteArray()

## Group bitmask per entity.
var _entityGroups: PackedInt64Array = PackedInt64Array()

## Invisibility and focus flags per entity.
var _entityFlags: PackedByteArray = PackedByteArray()

## Column of the center chunk per entity.
var _entityCenterColumn: PackedInt32Array = PackedInt32Array()

## Row of the center chunk per entity.
var _entityCenterRow: PackedInt32Array = PackedInt32Array()

## Target per entity, or -1.
var _entityTarget: PackedInt32Array = PackedInt32Array()

## How many entities target each entity; the crowding count.
var _entityTargeterCount: PackedInt32Array = PackedInt32Array()

## First entity whose center sits in a chunk, or -1.
var _centerHead: PackedInt32Array = PackedInt32Array()

## Next entity inside the center chain of its chunk, or -1.
var _centerNext: PackedInt32Array = PackedInt32Array()

## Group bitmask per team and chunk.
var _chunkGroups: PackedInt64Array = PackedInt64Array()

## Group bitmask per team and column.
var _columnGroups: PackedInt64Array = PackedInt64Array()

## Group bitmask per team over the whole map.
var _mapGroups: PackedInt64Array = PackedInt64Array()

## Number of entities in the built world.
var _entityCount: int = 0

#endregion

#region LIFECYCLE_AND_METHODS

## Advances the xorshift generator shared by every port. [br]
## @return The next value in [0, 1)
func _rand01() -> float:
	_randomState ^= (_randomState << 13) & 0xFFFFFFFF
	_randomState ^= (_randomState >> 17)
	_randomState ^= (_randomState << 5) & 0xFFFFFFFF
	_randomState &= 0xFFFFFFFF
	return float(_randomState >> 8) / 16777216.0


## Builds the world of SPEC.md: two fronts, one center chain per chunk and the group masks. [br]
## @param p_entityCount How many entities to place
func build(p_entityCount: int) -> void:
	_entityCount = p_entityCount
	_randomState = 12345
	_entityTeam.resize(p_entityCount)
	_entityGroups.resize(p_entityCount)
	_entityFlags.resize(p_entityCount)
	_entityCenterColumn.resize(p_entityCount)
	_entityCenterRow.resize(p_entityCount)
	_entityTarget.resize(p_entityCount)
	_entityTargeterCount.resize(p_entityCount)
	_centerNext.resize(p_entityCount)
	_centerHead.resize(COLS * ROWS)
	_centerHead.fill(-1)
	_chunkGroups.resize(2 * COLS * ROWS)
	_chunkGroups.fill(0)
	_columnGroups.resize(2 * COLS)
	_columnGroups.fill(0)
	_mapGroups.resize(2)
	_mapGroups.fill(0)

	for l_index: int in p_entityCount:
		var l_team: int = l_index % 2
		var l_frontX: float = 4096.0 * (0.35 if l_team == 0 else 0.65)
		var l_x: float = clampf(l_frontX + (_rand01() - 0.5) * 2.0 * 655.36, 0.0, 4095.0)
		var l_y: float = clampf(_rand01() * 4096.0, 0.0, 4095.0)
		var l_groups: int = 1 << (l_index % 3)

		_entityTeam[l_index] = l_team
		_entityGroups[l_index] = l_groups
		_entityFlags[l_index] = 0
		_entityTarget[l_index] = -1
		_entityTargeterCount[l_index] = 0

		var l_column: int = clampi(int(floor(l_x / 128.0)), 0, COLS - 1)
		var l_row: int = clampi(int(floor(l_y / 128.0)), 0, ROWS - 1)
		_entityCenterColumn[l_index] = l_column
		_entityCenterRow[l_index] = l_row

		var l_chunkId: int = l_row * COLS + l_column
		_centerNext[l_index] = _centerHead[l_chunkId]
		_centerHead[l_chunkId] = l_index
		_chunkGroups[l_team * COLS * ROWS + l_chunkId] |= l_groups
		_columnGroups[l_team * COLS + l_column] |= l_groups
		_mapGroups[l_team] |= l_groups


## Checks whether the other team holds a searched group anywhere. [br]
## @param p_team The team that asks [br]
## @return true if a search could find anything
func _map_has(p_team: int) -> bool:
	for l_team: int in 2:
		if (l_team != p_team and (_mapGroups[l_team] & SEARCH_GROUPS) != 0):
			return true
	return false


## Checks whether the other team holds a searched group in a column. [br]
## @param p_team The team that asks [br]
## @param p_column The column to check [br]
## @return true if the column is worth opening
func _col_has(p_team: int, p_column: int) -> bool:
	for l_team: int in 2:
		if (l_team != p_team and (_columnGroups[l_team * COLS + p_column] & SEARCH_GROUPS) != 0):
			return true
	return false


## Checks whether the other team holds a searched group in a chunk. [br]
## @param p_team The team that asks [br]
## @param p_chunkId The chunk to check [br]
## @return true if the chunk is worth opening
func _chunk_has(p_team: int, p_chunkId: int) -> bool:
	for l_team: int in 2:
		if (l_team != p_team and (_chunkGroups[l_team * COLS * ROWS + p_chunkId] & SEARCH_GROUPS) != 0):
			return true
	return false


## Runs one ring search per entity and assigns the best target, as SPEC.md defines it. [br]
## @return The checksum every port has to reproduce
func run() -> int:
	for l_searcher: int in _entityCount:
		var l_team: int = _entityTeam[l_searcher]
		if (not _map_has(l_team)):
			_entityTarget[l_searcher] = -1
			continue

		var l_searchColumn: int = _entityCenterColumn[l_searcher]
		var l_searchRow: int = _entityCenterRow[l_searcher]
		var l_searcherFlags: int = _entityFlags[l_searcher]
		var l_forwardSign: int = 1 if l_team == 0 else -1
		var l_bestId: int = -1
		var l_bestScore: float = 0.0
		var l_maxBonus: float = W_BEHIND + W_MUTUAL + W_FOCUS

		for l_ring: int in REACH + 1:
			var l_bound: float = (REACH - l_ring) * W_CLOSE + l_maxBonus
			if (l_bestId != -1 and l_bestScore >= l_bound):
				break

			var l_leftColumn: int = l_searchColumn - l_ring
			var l_rightColumn: int = l_searchColumn + l_ring
			var l_topRow: int = l_searchRow - l_ring
			var l_bottomRow: int = l_searchRow + l_ring

			for l_column: int in range(maxi(l_leftColumn, 0), mini(l_rightColumn, COLS - 1) + 1):
				if (not _col_has(l_team, l_column)):
					continue

				var l_isEdgeColumn: bool = l_column == l_leftColumn or l_column == l_rightColumn
				var l_firstRow: int = maxi(l_topRow, 0) if l_isEdgeColumn else l_topRow
				var l_lastRow: int = mini(l_bottomRow, ROWS - 1) if l_isEdgeColumn else l_bottomRow
				var l_rowStep: int = 1 if l_isEdgeColumn else maxi(l_bottomRow - l_topRow, 1)
				var l_row: int = l_firstRow

				while (l_row <= l_lastRow):
					if (l_row < 0 or l_row >= ROWS):
						l_row += l_rowStep
						continue

					var l_chunkId: int = l_row * COLS + l_column
					if (not _chunk_has(l_team, l_chunkId)):
						l_row += l_rowStep
						continue

					var l_candidate: int = _centerHead[l_chunkId]
					while (l_candidate != -1):
						if (_entityTeam[l_candidate] == l_team):
							l_candidate = _centerNext[l_candidate]
							continue
						if ((_entityGroups[l_candidate] & SEARCH_GROUPS) == 0):
							l_candidate = _centerNext[l_candidate]
							continue
						if ((_entityFlags[l_candidate] & 1) != 0 and (l_searcherFlags & 2) == 0):
							l_candidate = _centerNext[l_candidate]
							continue

						var l_columnDelta: int = absi(_entityCenterColumn[l_candidate] - l_searchColumn)
						var l_rowDelta: int = absi(_entityCenterRow[l_candidate] - l_searchRow)
						var l_diagonal: int = mini(l_columnDelta, l_rowDelta)
						var l_distance: float = (maxi(l_columnDelta, l_rowDelta) - l_diagonal) + l_diagonal * DIAG
						var l_score: float = (REACH - l_distance) * W_CLOSE

						if ((_entityFlags[l_candidate] & 4) != 0 and (l_searcherFlags & 8) == 0):
							l_score += W_FOCUS
						if ((_entityCenterColumn[l_candidate] - l_searchColumn) * l_forwardSign < 0):
							l_score += W_BEHIND
						if (_entityTarget[l_candidate] == l_searcher):
							l_score += W_MUTUAL
						l_score -= _entityTargeterCount[l_candidate] * W_CROWD

						if (l_bestId == -1 or l_score > l_bestScore or (l_score == l_bestScore and l_candidate < l_bestId)):
							l_bestScore = l_score
							l_bestId = l_candidate
						l_candidate = _centerNext[l_candidate]

					l_row += l_rowStep

		if (_entityTarget[l_searcher] != -1):
			_entityTargeterCount[_entityTarget[l_searcher]] -= 1
		_entityTarget[l_searcher] = l_bestId
		if (l_bestId != -1):
			_entityTargeterCount[l_bestId] += 1

	var l_checksum: int = 0
	for l_searcher: int in _entityCount:
		l_checksum += _entityTarget[l_searcher] + 1
	return l_checksum

#endregion
