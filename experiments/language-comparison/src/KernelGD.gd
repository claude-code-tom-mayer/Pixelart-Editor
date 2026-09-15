extends RefCounted
## GDScript reference implementation of the search kernel benchmark.
class_name KernelGD

const COLS: int = 32
const ROWS: int = 32
const REACH: int = 4
const SEARCH_GROUPS: int = 7
const W_CLOSE: float = 1.0
const W_FOCUS: float = 6.0
const W_BEHIND: float = 3.0
const W_CROWD: float = 1.5
const W_MUTUAL: float = 4.0
const DIAG: float = 1.45

var _state: int = 12345
var _team: PackedByteArray = PackedByteArray()
var _groups: PackedInt64Array = PackedInt64Array()
var _flags: PackedByteArray = PackedByteArray()
var _ccol: PackedInt32Array = PackedInt32Array()
var _crow: PackedInt32Array = PackedInt32Array()
var _target: PackedInt32Array = PackedInt32Array()
var _crowd: PackedInt32Array = PackedInt32Array()
var _centerHead: PackedInt32Array = PackedInt32Array()
var _centerNext: PackedInt32Array = PackedInt32Array()
var _chunkGroups: PackedInt64Array = PackedInt64Array()
var _colGroups: PackedInt64Array = PackedInt64Array()
var _mapGroups: PackedInt64Array = PackedInt64Array()
var _n: int = 0

func _rand01() -> float:
	_state ^= (_state << 13) & 0xFFFFFFFF
	_state ^= (_state >> 17)
	_state ^= (_state << 5) & 0xFFFFFFFF
	_state &= 0xFFFFFFFF
	return float(_state >> 8) / 16777216.0

func build(p_n: int) -> void:
	_n = p_n
	_state = 12345
	_team.resize(p_n); _groups.resize(p_n); _flags.resize(p_n)
	_ccol.resize(p_n); _crow.resize(p_n); _target.resize(p_n); _crowd.resize(p_n)
	_centerNext.resize(p_n)
	_centerHead.resize(COLS * ROWS); _centerHead.fill(-1)
	_chunkGroups.resize(2 * COLS * ROWS); _chunkGroups.fill(0)
	_colGroups.resize(2 * COLS); _colGroups.fill(0)
	_mapGroups.resize(2); _mapGroups.fill(0)
	for i: int in p_n:
		var l_team: int = i % 2
		var l_front: float = 4096.0 * (0.35 if l_team == 0 else 0.65)
		var l_x: float = clampf(l_front + (_rand01() - 0.5) * 2.0 * 655.36, 0.0, 4095.0)
		var l_y: float = clampf(_rand01() * 4096.0, 0.0, 4095.0)
		var l_g: int = 1 << (i % 3)
		_team[i] = l_team; _groups[i] = l_g; _flags[i] = 0
		_target[i] = -1; _crowd[i] = 0
		var l_c: int = clampi(int(floor(l_x / 128.0)), 0, COLS - 1)
		var l_r: int = clampi(int(floor(l_y / 128.0)), 0, ROWS - 1)
		_ccol[i] = l_c; _crow[i] = l_r
		var l_cid: int = l_r * COLS + l_c
		_centerNext[i] = _centerHead[l_cid]; _centerHead[l_cid] = i
		_chunkGroups[l_team * COLS * ROWS + l_cid] |= l_g
		_colGroups[l_team * COLS + l_c] |= l_g
		_mapGroups[l_team] |= l_g

func _map_has(p_team: int) -> bool:
	for t: int in 2:
		if t != p_team and (_mapGroups[t] & SEARCH_GROUPS) != 0: return true
	return false

func _col_has(p_team: int, p_col: int) -> bool:
	for t: int in 2:
		if t != p_team and (_colGroups[t * COLS + p_col] & SEARCH_GROUPS) != 0: return true
	return false

func _chunk_has(p_team: int, p_cid: int) -> bool:
	for t: int in 2:
		if t != p_team and (_chunkGroups[t * COLS * ROWS + p_cid] & SEARCH_GROUPS) != 0: return true
	return false

func run() -> int:
	for s: int in _n:
		var l_team: int = _team[s]
		if not _map_has(l_team):
			_target[s] = -1
			continue
		var l_col: int = _ccol[s]
		var l_row: int = _crow[s]
		var l_sf: int = _flags[s]
		var l_fwd: int = 1 if l_team == 0 else -1
		var l_bestId: int = -1
		var l_bestScore: float = 0.0
		var l_maxBonus: float = W_BEHIND + W_MUTUAL + W_FOCUS
		for ring: int in REACH + 1:
			var l_bound: float = (REACH - ring) * W_CLOSE + l_maxBonus
			if l_bestId != -1 and l_bestScore >= l_bound: break
			var L: int = l_col - ring
			var R: int = l_col + ring
			var T: int = l_row - ring
			var B: int = l_row + ring
			for c: int in range(maxi(L, 0), mini(R, COLS - 1) + 1):
				if not _col_has(l_team, c): continue
				var l_edge: bool = c == L or c == R
				var l_r0: int = maxi(T, 0) if l_edge else T
				var l_r1: int = mini(B, ROWS - 1) if l_edge else B
				var l_step: int = 1 if l_edge else maxi(B - T, 1)
				var r: int = l_r0
				while r <= l_r1:
					if r < 0 or r >= ROWS:
						r += l_step
						continue
					var l_cid: int = r * COLS + c
					if not _chunk_has(l_team, l_cid):
						r += l_step
						continue
					var k: int = _centerHead[l_cid]
					while k != -1:
						if _team[k] == l_team: k = _centerNext[k]; continue
						if (_groups[k] & SEARCH_GROUPS) == 0: k = _centerNext[k]; continue
						if (_flags[k] & 1) != 0 and (l_sf & 2) == 0: k = _centerNext[k]; continue
						var dc: int = absi(_ccol[k] - l_col)
						var dr: int = absi(_crow[k] - l_row)
						var d: int = mini(dc, dr)
						var dist: float = (maxi(dc, dr) - d) + d * DIAG
						var sc: float = (REACH - dist) * W_CLOSE
						if (_flags[k] & 4) != 0 and (l_sf & 8) == 0: sc += W_FOCUS
						if (_ccol[k] - l_col) * l_fwd < 0: sc += W_BEHIND
						if _target[k] == s: sc += W_MUTUAL
						sc -= _crowd[k] * W_CROWD
						if l_bestId == -1 or sc > l_bestScore or (sc == l_bestScore and k < l_bestId):
							l_bestScore = sc; l_bestId = k
						k = _centerNext[k]
					r += l_step
		if _target[s] != -1: _crowd[_target[s]] -= 1
		_target[s] = l_bestId
		if l_bestId != -1: _crowd[l_bestId] += 1
	var l_sum: int = 0
	for s: int in _n: l_sum += _target[s] + 1
	return l_sum
