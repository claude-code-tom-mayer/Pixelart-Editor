#include "targeting/TargetingServer.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <algorithm>
#include <cmath>

using namespace godot;

namespace {
constexpr int COLUMNS = C_ChunkingServer::MAP_CHUNK_COLUMNS;
constexpr int ROWS = C_ChunkingServer::MAP_CHUNK_ROWS;
constexpr int NO_TARGET = C_TargetingServer::NO_TARGET;
constexpr int NO_ENTITY = C_ChunkingServer::NO_ENTITY;
} // namespace

void TargetingServer::_bind_methods() {
	ClassDB::bind_method(D_METHOD("register_entity", "id", "targetingData"), &TargetingServer::register_entity);
	ClassDB::bind_method(D_METHOD("update_entity", "id"), &TargetingServer::update_entity);
	ClassDB::bind_method(D_METHOD("search_target", "id"), &TargetingServer::search_target);
	ClassDB::bind_method(D_METHOD("drop_targeters", "id"), &TargetingServer::drop_targeters);
	ClassDB::bind_method(D_METHOD("set_invisible", "id", "invisible"), &TargetingServer::set_invisible);
	ClassDB::bind_method(D_METHOD("set_targets_invisible", "id", "enabled"), &TargetingServer::set_targets_invisible);
	ClassDB::bind_method(D_METHOD("set_focused", "id", "enabled"), &TargetingServer::set_focused);
	ClassDB::bind_method(D_METHOD("set_ignores_focus", "id", "enabled"), &TargetingServer::set_ignores_focus);
	ClassDB::bind_method(D_METHOD("set_search_chunks", "id", "searchChunks"), &TargetingServer::set_search_chunks);
	ClassDB::bind_method(D_METHOD("set_flee_chunks", "id", "fleeChunks"), &TargetingServer::set_flee_chunks);
	ClassDB::bind_method(D_METHOD("set_hit_range", "id", "hitRange"), &TargetingServer::set_hit_range);
	ClassDB::bind_method(D_METHOD("set_priority_targeted_groups", "id", "priorityTargetedGroups"), &TargetingServer::set_priority_targeted_groups);
	ClassDB::bind_method(D_METHOD("get_target_position", "id"), &TargetingServer::get_target_position);
	ClassDB::bind_method(D_METHOD("get_state", "id"), &TargetingServer::get_state);
	ClassDB::bind_method(D_METHOD("get_target", "id"), &TargetingServer::get_target);
	ClassDB::bind_method(D_METHOD("get_targeters", "id"), &TargetingServer::get_targeters);
}

// ===== PRIVATE_SLOTS =====

void TargetingServer::_append_slot() {
	_entityTargetedGroups.push_back(0);
	_entityState.push_back(C_TargetingServer::STATE_SEARCH);
	_entitySearchChunks.push_back(0);
	_entityFleeChunks.push_back(0);
	_entityHitRange.push_back(0.0);
	_entityPriorityTargetedGroups.push_back(0);
	_entityFlags.push_back(0);
	_entityTarget.push_back(NO_TARGET);
	_entityTargeterIndex.push_back(0);
	_targetersOf.push_back(std::vector<int32_t>());
}

void TargetingServer::_reset_slot(int p_id) {
	_entityTargetedGroups[p_id] = 0;
	_entityState[p_id] = C_TargetingServer::STATE_SEARCH;
	_entitySearchChunks[p_id] = 0;
	_entityFleeChunks[p_id] = 0;
	_entityHitRange[p_id] = 0.0;
	_entityPriorityTargetedGroups[p_id] = 0;
	_entityFlags[p_id] = 0;
	_entityTarget[p_id] = NO_TARGET;
	_entityTargeterIndex[p_id] = 0;
	_targetersOf[p_id].clear();
}

// ===== PUBLIC_METHODS =====

void TargetingServer::register_entity(int p_id, const Ref<Resource> &p_targetingData) {
	ensure_slot(p_id);

	if (p_targetingData.is_null()) {
		UtilityFunctions::push_error("TargetingServer: entity ", p_id,
				" was registered without targeting data, using the defaults.");
		_entityTargetedGroups[p_id] = 0;
		_entitySearchChunks[p_id] = 4;
		_entityFleeChunks[p_id] = 2;
		_entityHitRange[p_id] = 64.0;
		_entityPriorityTargetedGroups[p_id] = 0;
		_entityFlags[p_id] = 0;
		return;
	}

	_entityTargetedGroups[p_id] = p_targetingData->get("targetedGroups");
	_entitySearchChunks[p_id] = p_targetingData->get("searchChunks");
	_entityFleeChunks[p_id] = p_targetingData->get("fleeChunks");
	_entityHitRange[p_id] = p_targetingData->get("hitRange");
	_entityPriorityTargetedGroups[p_id] = p_targetingData->get("priorityTargetedGroups");
	_entityFlags[p_id] = static_cast<uint8_t>(_build_flags(p_targetingData));
}

int TargetingServer::update_entity(int p_id) {
	if (_can_still_flee(p_id) && _is_threatened(p_id)) {
		_drop_target(p_id);
		_entityState[p_id] = C_TargetingServer::STATE_FLEE;

		return C_TargetingServer::STATE_FLEE;
	}

	const int l_state = _evaluate_state(p_id);
	_entityState[p_id] = static_cast<uint8_t>(l_state);

	return l_state;
}

int TargetingServer::search_target(int p_id) {
	const int l_targetId = _find_best_target(p_id);

	if (l_targetId != NO_TARGET) {
		_assign_target(p_id, l_targetId);
	}

	return l_targetId;
}

void TargetingServer::drop_targeters(int p_id) {
	const std::vector<int32_t> l_targeters = _targetersOf[p_id];

	for (const int32_t l_targeterId : l_targeters) {
		_drop_target(l_targeterId);
	}
}

void TargetingServer::set_invisible(int p_id, bool p_invisible) {
	_set_flag(p_id, C_TargetingServer::FLAG_INVISIBLE, p_invisible);

	if (!p_invisible) {
		return;
	}

	const std::vector<int32_t> l_targeters = _targetersOf[p_id];
	for (const int32_t l_targeterId : l_targeters) {
		if ((_entityFlags[l_targeterId] & C_TargetingServer::FLAG_TARGETS_INVISIBLE) == 0) {
			_drop_target(l_targeterId);
		}
	}
}

// ===== PUBLIC_QUERIES =====

Vector2 TargetingServer::get_target_position(int p_id) {
	const int l_team = _chunking->entityTeam[p_id];
	const double l_ownY = _chunking->entityPosition[p_id].y;

	if (_entityState[p_id] == C_TargetingServer::STATE_FLEE) {
		return Vector2(C_TargetingServer::TEAM_BASE_X[l_team], l_ownY);
	}

	const int l_targetId = _entityTarget[p_id];
	if (l_targetId != NO_TARGET) {
		return _chunking->entityPosition[l_targetId];
	}

	if (_has_enemy_behind(p_id) || !_has_opponent_on_map(p_id)) {
		return Vector2(C_TargetingServer::TEAM_BASE_X[l_team], l_ownY);
	}

	return Vector2(C_TargetingServer::TEAM_MARCH_X[l_team], l_ownY);
}

PackedInt32Array TargetingServer::get_targeters(int p_id) const {
	const std::vector<int32_t> &l_targeters = _targetersOf[p_id];
	PackedInt32Array l_result;
	l_result.resize(static_cast<int64_t>(l_targeters.size()));

	for (size_t l_index = 0; l_index < l_targeters.size(); ++l_index) {
		l_result[static_cast<int64_t>(l_index)] = l_targeters[l_index];
	}

	return l_result;
}

void TargetingServer::on_unregister(int p_id) {
	_drop_target(p_id);
	drop_targeters(p_id);
}

// ===== PRIVATE_METHODS =====

int TargetingServer::_build_flags(const Ref<Resource> &p_targetingData) {
	int l_flags = 0;

	if (static_cast<bool>(p_targetingData->get("invisible"))) {
		l_flags |= C_TargetingServer::FLAG_INVISIBLE;
	}

	if (static_cast<bool>(p_targetingData->get("targetsInvisible"))) {
		l_flags |= C_TargetingServer::FLAG_TARGETS_INVISIBLE;
	}

	if (static_cast<bool>(p_targetingData->get("hasFocus"))) {
		l_flags |= C_TargetingServer::FLAG_HAS_FOCUS;
	}

	if (static_cast<bool>(p_targetingData->get("ignoresFocus"))) {
		l_flags |= C_TargetingServer::FLAG_IGNORES_FOCUS;
	}

	return l_flags;
}

void TargetingServer::_set_flag(int p_id, int p_flag, bool p_enabled) {
	if (p_enabled) {
		_entityFlags[p_id] |= static_cast<uint8_t>(p_flag);
	} else {
		_entityFlags[p_id] &= static_cast<uint8_t>(~p_flag);
	}
}

int TargetingServer::_evaluate_state(int p_id) const {
	const int l_targetId = _entityTarget[p_id];

	if (l_targetId == NO_TARGET) {
		return C_TargetingServer::STATE_SEARCH;
	}

	const double l_squaredDistance = _chunking->entityPosition[p_id].distance_squared_to(_chunking->entityPosition[l_targetId]);
	const double l_reach = _entityHitRange[p_id] + _chunking->entityRadius[l_targetId];

	if (l_squaredDistance <= l_reach * l_reach) {
		return C_TargetingServer::STATE_COMBAT;
	}

	return C_TargetingServer::STATE_APPROACH;
}

bool TargetingServer::_can_still_flee(int p_id) const {
	const double l_baseX = C_TargetingServer::TEAM_BASE_X[_chunking->entityTeam[p_id]];
	return std::abs(_chunking->entityPosition[p_id].x - l_baseX) > C_TargetingServer::BASE_REACHED_EPSILON;
}

bool TargetingServer::_is_threatened(int p_id) const {
	const int l_fleeChunks = _entityFleeChunks[p_id];
	const int l_column = _chunking->entityCenterColumn[p_id];
	const int l_row = _chunking->entityCenterRow[p_id];

	for (const int32_t l_targeterId : _targetersOf[p_id]) {
		if (_get_chunk_distance(l_column, l_row, l_targeterId) <= l_fleeChunks) {
			return true;
		}
	}

	return false;
}

int TargetingServer::_find_best_target(int p_id) {
	const int64_t l_priorityGroups = _entityPriorityTargetedGroups[p_id];
	const int64_t l_searchedGroups = l_priorityGroups | _entityTargetedGroups[p_id];
	const int l_team = _chunking->entityTeam[p_id];

	if (!_chunking->map_has_opponent_group(l_team, l_searchedGroups)) {
		return NO_TARGET;
	}

	_searchId = p_id;
	_searchTeam = l_team;
	_searchColumn = _chunking->entityCenterColumn[p_id];
	_searchRow = _chunking->entityCenterRow[p_id];
	_searchFlags = _entityFlags[p_id];
	_searchReach = _entitySearchChunks[p_id];
	_searchForwardSign = C_TargetingServer::TEAM_FORWARD_SIGN[l_team];
	_searchGroups = l_searchedGroups;
	_searchPriorityGroups = l_priorityGroups;
	_searchBestPriorityId = NO_TARGET;
	_searchBestPriorityScore = 0.0;
	_searchBestNormalId = NO_TARGET;
	_searchBestNormalScore = 0.0;

	const bool l_priorityPossible = l_priorityGroups != 0 && _chunking->map_has_opponent_group(l_team, l_priorityGroups);
	const double l_maxBonus = _get_max_score_bonus();

	for (int l_ring = 0; l_ring <= _searchReach; ++l_ring) {
		if (_is_search_settled(l_ring, l_maxBonus, l_priorityPossible)) {
			break;
		}

		_scan_ring(l_ring);
	}

	if (_searchBestPriorityId != NO_TARGET) {
		return _searchBestPriorityId;
	}

	return _searchBestNormalId;
}

double TargetingServer::_get_max_score_bonus() const {
	double l_bonus = C_TargetingServer::WEIGHT_BEHIND + C_TargetingServer::WEIGHT_MUTUAL;

	if ((_searchFlags & C_TargetingServer::FLAG_IGNORES_FOCUS) == 0) {
		l_bonus += C_TargetingServer::WEIGHT_FOCUS;
	}

	return l_bonus;
}

bool TargetingServer::_is_search_settled(int p_ring, double p_maxBonus, bool p_priorityPossible) const {
	const double l_bound = (_searchReach - p_ring) * C_TargetingServer::WEIGHT_CLOSENESS + p_maxBonus;

	if (_searchBestPriorityId != NO_TARGET) {
		return _searchBestPriorityScore >= l_bound;
	}

	if (p_priorityPossible) {
		return false;
	}

	return _searchBestNormalId != NO_TARGET && _searchBestNormalScore >= l_bound;
}

void TargetingServer::_scan_ring(int p_ring) {
	const int l_leftColumn = _searchColumn - p_ring;
	const int l_rightColumn = _searchColumn + p_ring;
	const int l_topRow = _searchRow - p_ring;
	const int l_bottomRow = _searchRow + p_ring;
	const int l_firstRow = std::max(l_topRow, 0);
	const int l_lastRow = std::min(l_bottomRow, ROWS - 1);

	const int l_fromColumn = std::max(l_leftColumn, 0);
	const int l_toColumn = std::min(l_rightColumn, COLUMNS - 1);

	for (int l_column = l_fromColumn; l_column <= l_toColumn; ++l_column) {
		if (!_chunking->column_has_opponent_group(l_column, _searchTeam, _searchGroups)) {
			continue;
		}

		if (l_column == l_leftColumn || l_column == l_rightColumn) {
			for (int l_row = l_firstRow; l_row <= l_lastRow; ++l_row) {
				_scan_chunk(l_row * COLUMNS + l_column);
			}

			continue;
		}

		if (l_topRow >= 0) {
			_scan_chunk(l_topRow * COLUMNS + l_column);
		}

		if (l_bottomRow < ROWS) {
			_scan_chunk(l_bottomRow * COLUMNS + l_column);
		}
	}
}

void TargetingServer::_scan_chunk(int p_chunkId) {
	if (!_chunking->chunk_has_opponent_group(p_chunkId, _searchTeam, _searchGroups)) {
		return;
	}

	int l_candidateId = _chunking->centerHead[p_chunkId];
	while (l_candidateId != NO_ENTITY) {
		const int l_nextId = _chunking->centerNext[l_candidateId];

		if (!_can_target(l_candidateId)) {
			l_candidateId = l_nextId;
			continue;
		}

		const double l_score = _score_candidate(l_candidateId);

		if ((_chunking->entityGroups[l_candidateId] & _searchPriorityGroups) != 0) {
			if (_is_better(l_score, l_candidateId, _searchBestPriorityScore, _searchBestPriorityId)) {
				_searchBestPriorityScore = l_score;
				_searchBestPriorityId = l_candidateId;
			}
		} else if (_is_better(l_score, l_candidateId, _searchBestNormalScore, _searchBestNormalId)) {
			_searchBestNormalScore = l_score;
			_searchBestNormalId = l_candidateId;
		}

		l_candidateId = l_nextId;
	}
}

bool TargetingServer::_is_better(double p_score, int p_candidateId, double p_bestScore, int p_bestId) {
	if (p_bestId == NO_TARGET || p_score > p_bestScore) {
		return true;
	}

	return p_score == p_bestScore && p_candidateId < p_bestId;
}

bool TargetingServer::_can_target(int p_candidateId) const {
	if (_chunking->entityTeam[p_candidateId] == _searchTeam) {
		return false;
	}

	if (_chunking->entityPreUnregistered[p_candidateId] == 1 || _chunking->entityUnregistering[p_candidateId] == 1) {
		return false;
	}

	if ((_chunking->entityGroups[p_candidateId] & _searchGroups) == 0) {
		return false;
	}

	return (_entityFlags[p_candidateId] & C_TargetingServer::FLAG_INVISIBLE) == 0 ||
			(_searchFlags & C_TargetingServer::FLAG_TARGETS_INVISIBLE) != 0;
}

double TargetingServer::_score_candidate(int p_candidateId) const {
	const double l_distance = _get_chunk_distance(_searchColumn, _searchRow, p_candidateId);
	double l_score = (_searchReach - l_distance) * C_TargetingServer::WEIGHT_CLOSENESS;

	if ((_entityFlags[p_candidateId] & C_TargetingServer::FLAG_HAS_FOCUS) != 0 &&
			(_searchFlags & C_TargetingServer::FLAG_IGNORES_FOCUS) == 0) {
		l_score += C_TargetingServer::WEIGHT_FOCUS;
	}

	if ((_chunking->entityCenterColumn[p_candidateId] - _searchColumn) * _searchForwardSign < 0) {
		l_score += C_TargetingServer::WEIGHT_BEHIND;
	}

	if (_entityTarget[p_candidateId] == _searchId) {
		l_score += C_TargetingServer::WEIGHT_MUTUAL;
	}

	return l_score - static_cast<double>(_targetersOf[p_candidateId].size()) * C_TargetingServer::WEIGHT_CROWDING;
}

double TargetingServer::_get_chunk_distance(int p_column, int p_row, int p_otherId) const {
	const int l_columnDelta = std::abs(_chunking->entityCenterColumn[p_otherId] - p_column);
	const int l_rowDelta = std::abs(_chunking->entityCenterRow[p_otherId] - p_row);
	const int l_diagonal = std::min(l_columnDelta, l_rowDelta);
	const int l_straight = std::max(l_columnDelta, l_rowDelta) - l_diagonal;

	return l_straight + l_diagonal * C_TargetingServer::DIAGONAL_CHUNK_COST;
}

bool TargetingServer::_has_enemy_behind(int p_id) const {
	const int l_team = _chunking->entityTeam[p_id];
	const int l_column = _chunking->entityCenterColumn[p_id];

	if (C_TargetingServer::TEAM_FORWARD_SIGN[l_team] > 0) {
		return _chunking->has_opponent_before_column(l_column, l_team);
	}

	return _chunking->has_opponent_after_column(l_column, l_team);
}

bool TargetingServer::_has_opponent_on_map(int p_id) const {
	const int64_t l_searchedGroups = _entityPriorityTargetedGroups[p_id] | _entityTargetedGroups[p_id];
	return _chunking->map_has_opponent_group(_chunking->entityTeam[p_id], l_searchedGroups);
}

void TargetingServer::_assign_target(int p_id, int p_targetId) {
	_drop_target(p_id);

	std::vector<int32_t> &l_targeters = _targetersOf[p_targetId];
	_entityTargeterIndex[p_id] = static_cast<int32_t>(l_targeters.size());
	l_targeters.push_back(p_id);
	_entityTarget[p_id] = p_targetId;
}

void TargetingServer::_drop_target(int p_id) {
	const int l_targetId = _entityTarget[p_id];

	if (l_targetId == NO_TARGET) {
		return;
	}

	std::vector<int32_t> &l_targeters = _targetersOf[l_targetId];
	const int l_slot = _entityTargeterIndex[p_id];
	const int32_t l_movedId = l_targeters.back();

	l_targeters[l_slot] = l_movedId;
	l_targeters.pop_back();
	_entityTargeterIndex[l_movedId] = l_slot;

	_entityTarget[p_id] = NO_TARGET;
	_entityState[p_id] = C_TargetingServer::STATE_SEARCH;
}
