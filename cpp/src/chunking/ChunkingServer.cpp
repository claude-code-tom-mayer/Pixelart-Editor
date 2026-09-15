#include "chunking/ChunkingServer.h"

#include <godot_cpp/core/class_db.hpp>

#include <algorithm>
#include <cmath>

using namespace godot;

// ===== CONSTANTS_CACHED_LOCALLY =====

namespace {
constexpr int COLUMNS = C_ChunkingServer::MAP_CHUNK_COLUMNS;
constexpr int ROWS = C_ChunkingServer::MAP_CHUNK_ROWS;
constexpr int CHUNKS = C_ChunkingServer::CHUNK_COUNT;
constexpr int TEAMS = C_ChunkingServer::TEAM_COUNT;
constexpr double CHUNK_SIZE = C_ChunkingServer::CHUNK_SIZE;
constexpr int NO_SLOT = C_ChunkingServer::NO_SLOT;
constexpr int NO_ENTITY = C_ChunkingServer::NO_ENTITY;
constexpr int NO_COLUMN = C_ChunkingServer::NO_COLUMN;
} // namespace

void ChunkingServer::_bind_methods() {
	ClassDB::bind_method(D_METHOD("register_entity", "position", "radius", "team", "groups"), &ChunkingServer::register_entity);
	ClassDB::bind_method(D_METHOD("pre_unregister_entity", "id"), &ChunkingServer::pre_unregister_entity);
	ClassDB::bind_method(D_METHOD("unregister_entity", "id"), &ChunkingServer::unregister_entity);
	ClassDB::bind_method(D_METHOD("set_position", "id", "position"), &ChunkingServer::set_position);
	ClassDB::bind_method(D_METHOD("set_radius", "id", "radius"), &ChunkingServer::set_radius);
	ClassDB::bind_method(D_METHOD("release_removed_ids"), &ChunkingServer::release_removed_ids);
	ClassDB::bind_method(D_METHOD("is_unregistering", "id"), &ChunkingServer::is_unregistering);
	ClassDB::bind_method(D_METHOD("get_pending_free_ids"), &ChunkingServer::get_pending_free_ids);
	ClassDB::bind_method(D_METHOD("has_opponent_in_chunk", "chunkId", "team"), &ChunkingServer::has_opponent_in_chunk);
	ClassDB::bind_method(D_METHOD("has_opponent_in_column", "columnIndex", "team"), &ChunkingServer::has_opponent_in_column);
	ClassDB::bind_method(D_METHOD("has_opponent_before_column", "columnIndex", "team"), &ChunkingServer::has_opponent_before_column);
	ClassDB::bind_method(D_METHOD("has_opponent_after_column", "columnIndex", "team"), &ChunkingServer::has_opponent_after_column);
	ClassDB::bind_method(D_METHOD("chunk_has_group", "chunkId", "team", "groupMask"), &ChunkingServer::chunk_has_group);
	ClassDB::bind_method(D_METHOD("column_has_group", "columnIndex", "team", "groupMask"), &ChunkingServer::column_has_group);
	ClassDB::bind_method(D_METHOD("map_has_group", "team", "groupMask"), &ChunkingServer::map_has_group);
	ClassDB::bind_method(D_METHOD("chunk_has_opponent_group", "chunkId", "team", "groupMask"), &ChunkingServer::chunk_has_opponent_group);
	ClassDB::bind_method(D_METHOD("column_has_opponent_group", "columnIndex", "team", "groupMask"), &ChunkingServer::column_has_opponent_group);
	ClassDB::bind_method(D_METHOD("map_has_opponent_group", "team", "groupMask"), &ChunkingServer::map_has_opponent_group);
	ClassDB::bind_method(D_METHOD("compute_chunk_area_from_bounds", "minCorner", "maxCorner"), &ChunkingServer::compute_chunk_area_from_bounds);
	ClassDB::bind_method(D_METHOD("collect_chunks_in_area", "area"), &ChunkingServer::collect_chunks_in_area);
}

// ===== LIFECYCLE =====

ChunkingServer::ChunkingServer() {
	_chunkGroups.assign(TEAMS * CHUNKS, 0);
	_chunkCounts.assign(TEAMS * CHUNKS, 0);
	_columnGroups.assign(TEAMS * COLUMNS, 0);
	_columnCounts.assign(TEAMS * COLUMNS, 0);
	_mapGroups.assign(TEAMS, 0);
	_mapCounts.assign(TEAMS, 0);

	_teamMinColumn.assign(TEAMS, NO_COLUMN);
	_teamMaxColumn.assign(TEAMS, NO_COLUMN);

	chunkHead.assign(CHUNKS, NO_SLOT);
	centerHead.assign(CHUNKS, NO_ENTITY);
}

// ===== PUBLIC_METHODS =====

int ChunkingServer::register_entity(const Vector2 &p_position, double p_radius, int p_team, int64_t p_groups) {
	ERR_FAIL_INDEX_V_MSG(p_team, TEAMS, -1, "ChunkingServer: register_entity() got an unknown team.");

	const int l_id = _acquire_id();

	entityTeam[l_id] = static_cast<uint8_t>(p_team);
	entityGroups[l_id] = p_groups;
	entityPosition[l_id] = p_position;
	entityRadius[l_id] = p_radius;

	const Vector4i l_area = _compute_chunk_area(p_position, p_radius);
	_entityChunkArea[l_id] = l_area;

	for (int l_row = l_area.y; l_row <= l_area.w; ++l_row) {
		const int l_rowOffset = l_row * COLUMNS;

		for (int l_column = l_area.x; l_column <= l_area.z; ++l_column) {
			_add_entity_to_chunk(l_id, l_rowOffset + l_column);
		}
	}

	entityCenterChunk[l_id] = NO_COLUMN;
	_apply_center_chunk(l_id, p_position);

	return l_id;
}

void ChunkingServer::pre_unregister_entity(int p_id) {
	entityPreUnregistered[p_id] = 1;
}

void ChunkingServer::unregister_entity(int p_id) {
	if (entityUnregistering[p_id] == 1) {
		return;
	}

	entityUnregistering[p_id] = 1;

	int l_slot = _entitySlotHead[p_id];
	while (l_slot != NO_SLOT) {
		const int l_nextSlot = _slotEntityNext[l_slot];
		_remove_slot_from_chunk(l_slot);
		l_slot = l_nextSlot;
	}

	_remove_center_from_chunk(p_id);
	_pendingFreeIds.push_back(p_id);
}

void ChunkingServer::set_position(int p_id, const Vector2 &p_position) {
	entityPosition[p_id] = p_position;
	_apply_chunk_area(p_id, _compute_chunk_area(p_position, entityRadius[p_id]));
	_apply_center_chunk(p_id, p_position);
}

void ChunkingServer::set_radius(int p_id, double p_radius) {
	entityRadius[p_id] = p_radius;
	_apply_chunk_area(p_id, _compute_chunk_area(entityPosition[p_id], p_radius));
}

void ChunkingServer::release_removed_ids() {
	for (const int32_t l_id : _pendingFreeIds) {
		entityUnregistering[l_id] = 0;
		entityPreUnregistered[l_id] = 0;
		_freeIds.push_back(l_id);
	}

	_pendingFreeIds.clear();
}

// ===== PUBLIC_QUERIES =====

PackedInt32Array ChunkingServer::get_pending_free_ids() const {
	PackedInt32Array l_ids;
	l_ids.resize(static_cast<int64_t>(_pendingFreeIds.size()));

	for (size_t l_index = 0; l_index < _pendingFreeIds.size(); ++l_index) {
		l_ids[static_cast<int64_t>(l_index)] = _pendingFreeIds[l_index];
	}

	return l_ids;
}

bool ChunkingServer::has_opponent_in_chunk(int p_chunkId, int p_team) const {
	for (int l_team = 0; l_team < TEAMS; ++l_team) {
		if (l_team != p_team && _chunkCounts[l_team * CHUNKS + p_chunkId] > 0) {
			return true;
		}
	}

	return false;
}

bool ChunkingServer::has_opponent_in_column(int p_columnIndex, int p_team) const {
	for (int l_team = 0; l_team < TEAMS; ++l_team) {
		if (l_team != p_team && _columnCounts[l_team * COLUMNS + p_columnIndex] > 0) {
			return true;
		}
	}

	return false;
}

bool ChunkingServer::has_opponent_before_column(int p_columnIndex, int p_team) const {
	for (int l_team = 0; l_team < TEAMS; ++l_team) {
		const int l_minColumn = _teamMinColumn[l_team];

		if (l_team != p_team && l_minColumn != NO_COLUMN && l_minColumn < p_columnIndex) {
			return true;
		}
	}

	return false;
}

bool ChunkingServer::has_opponent_after_column(int p_columnIndex, int p_team) const {
	for (int l_team = 0; l_team < TEAMS; ++l_team) {
		const int l_maxColumn = _teamMaxColumn[l_team];

		if (l_team != p_team && l_maxColumn != NO_COLUMN && l_maxColumn > p_columnIndex) {
			return true;
		}
	}

	return false;
}

bool ChunkingServer::chunk_has_opponent_group(int p_chunkId, int p_team, int64_t p_groupMask) const {
	for (int l_team = 0; l_team < TEAMS; ++l_team) {
		if (l_team != p_team && (_chunkGroups[l_team * CHUNKS + p_chunkId] & p_groupMask) != 0) {
			return true;
		}
	}

	return false;
}

bool ChunkingServer::column_has_opponent_group(int p_columnIndex, int p_team, int64_t p_groupMask) const {
	for (int l_team = 0; l_team < TEAMS; ++l_team) {
		if (l_team != p_team && (_columnGroups[l_team * COLUMNS + p_columnIndex] & p_groupMask) != 0) {
			return true;
		}
	}

	return false;
}

bool ChunkingServer::map_has_opponent_group(int p_team, int64_t p_groupMask) const {
	for (int l_team = 0; l_team < TEAMS; ++l_team) {
		if (l_team != p_team && (_mapGroups[l_team] & p_groupMask) != 0) {
			return true;
		}
	}

	return false;
}

// ===== PUBLIC_INDEX =====

Vector4i ChunkingServer::compute_chunk_area_from_bounds(const Vector2 &p_minCorner, const Vector2 &p_maxCorner) const {
	constexpr int l_lastColumn = COLUMNS - 1;
	constexpr int l_lastRow = ROWS - 1;

	return Vector4i(
			std::clamp(static_cast<int>(std::floor(p_minCorner.x / CHUNK_SIZE)), 0, l_lastColumn),
			std::clamp(static_cast<int>(std::floor(p_minCorner.y / CHUNK_SIZE)), 0, l_lastRow),
			std::clamp(static_cast<int>(std::floor(p_maxCorner.x / CHUNK_SIZE)), 0, l_lastColumn),
			std::clamp(static_cast<int>(std::floor(p_maxCorner.y / CHUNK_SIZE)), 0, l_lastRow));
}

PackedInt32Array ChunkingServer::collect_chunks_in_area(const Vector4i &p_area) const {
	PackedInt32Array l_chunkIds;
	l_chunkIds.resize((p_area.z - p_area.x + 1) * (p_area.w - p_area.y + 1));

	int64_t l_writeIndex = 0;
	for (int l_row = p_area.y; l_row <= p_area.w; ++l_row) {
		const int l_rowOffset = l_row * COLUMNS;

		for (int l_column = p_area.x; l_column <= p_area.z; ++l_column) {
			l_chunkIds[l_writeIndex] = l_rowOffset + l_column;
			++l_writeIndex;
		}
	}

	return l_chunkIds;
}

// ===== PRIVATE_METHODS =====

int ChunkingServer::_acquire_id() {
	if (!_freeIds.empty()) {
		const int l_reusedId = _freeIds.back();
		_freeIds.pop_back();
		return l_reusedId;
	}

	entityTeam.push_back(0);
	entityGroups.push_back(0);
	entityPosition.push_back(Vector2());
	entityRadius.push_back(0.0);
	entityPreUnregistered.push_back(0);
	entityUnregistering.push_back(0);
	_entityChunkArea.push_back(Vector4i());
	_entitySlotHead.push_back(NO_SLOT);
	entityCenterChunk.push_back(NO_COLUMN);
	entityCenterColumn.push_back(0);
	entityCenterRow.push_back(0);
	centerNext.push_back(NO_ENTITY);
	_centerPrev.push_back(NO_ENTITY);

	return static_cast<int>(entityTeam.size()) - 1;
}

Vector4i ChunkingServer::_compute_chunk_area(const Vector2 &p_position, double p_radius) const {
	const Vector2 l_extent(p_radius, p_radius);
	return compute_chunk_area_from_bounds(p_position - l_extent, p_position + l_extent);
}

void ChunkingServer::_apply_chunk_area(int p_id, const Vector4i &p_area) {
	const Vector4i l_oldArea = _entityChunkArea[p_id];

	if (p_area == l_oldArea) {
		return;
	}

	_entityChunkArea[p_id] = p_area;

	int l_slot = _entitySlotHead[p_id];
	while (l_slot != NO_SLOT) {
		const int l_nextSlot = _slotEntityNext[l_slot];

		if (!_is_chunk_in_area(_slotChunk[l_slot], p_area)) {
			_remove_slot_from_chunk(l_slot);
		}

		l_slot = l_nextSlot;
	}

	for (int l_row = p_area.y; l_row <= p_area.w; ++l_row) {
		const int l_rowOffset = l_row * COLUMNS;
		const bool l_rowIsNew = l_row < l_oldArea.y || l_row > l_oldArea.w;

		for (int l_column = p_area.x; l_column <= p_area.z; ++l_column) {
			if (l_rowIsNew || l_column < l_oldArea.x || l_column > l_oldArea.z) {
				_add_entity_to_chunk(p_id, l_rowOffset + l_column);
			}
		}
	}
}

bool ChunkingServer::_is_chunk_in_area(int p_chunkId, const Vector4i &p_area) const {
	const int l_column = p_chunkId % COLUMNS;

	if (l_column < p_area.x || l_column > p_area.z) {
		return false;
	}

	const int l_row = p_chunkId / COLUMNS;

	return l_row >= p_area.y && l_row <= p_area.w;
}

void ChunkingServer::_apply_center_chunk(int p_id, const Vector2 &p_position) {
	const int l_column = std::clamp(static_cast<int>(std::floor(p_position.x / CHUNK_SIZE)), 0, COLUMNS - 1);
	const int l_row = std::clamp(static_cast<int>(std::floor(p_position.y / CHUNK_SIZE)), 0, ROWS - 1);
	const int l_chunkId = l_row * COLUMNS + l_column;

	if (l_chunkId == entityCenterChunk[p_id]) {
		return;
	}

	_remove_center_from_chunk(p_id);

	const int l_head = centerHead[l_chunkId];
	_centerPrev[p_id] = NO_ENTITY;
	centerNext[p_id] = l_head;

	if (l_head != NO_ENTITY) {
		_centerPrev[l_head] = p_id;
	}

	centerHead[l_chunkId] = p_id;
	entityCenterChunk[p_id] = l_chunkId;
	entityCenterColumn[p_id] = l_column;
	entityCenterRow[p_id] = l_row;
}

void ChunkingServer::_remove_center_from_chunk(int p_id) {
	const int l_chunkId = entityCenterChunk[p_id];

	if (l_chunkId == NO_COLUMN) {
		return;
	}

	const int l_next = centerNext[p_id];
	const int l_prev = _centerPrev[p_id];

	if (l_prev == NO_ENTITY) {
		centerHead[l_chunkId] = l_next;
	} else {
		centerNext[l_prev] = l_next;
	}

	if (l_next != NO_ENTITY) {
		_centerPrev[l_next] = l_prev;
	}

	entityCenterChunk[p_id] = NO_COLUMN;
}

void ChunkingServer::_add_entity_to_chunk(int p_id, int p_chunkId) {
	const int l_slot = _acquire_slot();

	slotEntity[l_slot] = p_id;
	_slotChunk[l_slot] = p_chunkId;

	const int l_chunkHead = chunkHead[p_chunkId];
	_slotChunkPrev[l_slot] = NO_SLOT;
	slotChunkNext[l_slot] = l_chunkHead;

	if (l_chunkHead != NO_SLOT) {
		_slotChunkPrev[l_chunkHead] = l_slot;
	}

	chunkHead[p_chunkId] = l_slot;

	const int l_entityHead = _entitySlotHead[p_id];
	_slotEntityPrev[l_slot] = NO_SLOT;
	_slotEntityNext[l_slot] = l_entityHead;

	if (l_entityHead != NO_SLOT) {
		_slotEntityPrev[l_entityHead] = l_slot;
	}

	_entitySlotHead[p_id] = l_slot;

	const int l_team = entityTeam[p_id];
	const int64_t l_groups = entityGroups[p_id];
	const int l_chunkIndex = l_team * CHUNKS + p_chunkId;
	const int64_t l_mergedGroups = _chunkGroups[l_chunkIndex] | l_groups;

	_apply_count_delta(p_chunkId, l_team, 1);

	if (l_mergedGroups == _chunkGroups[l_chunkIndex]) {
		return;
	}

	_chunkGroups[l_chunkIndex] = l_mergedGroups;

	if (_apply_group_to_column(p_chunkId % COLUMNS, l_team, l_groups)) {
		_mapGroups[l_team] |= l_groups;
	}
}

void ChunkingServer::_remove_slot_from_chunk(int p_slot) {
	const int l_id = slotEntity[p_slot];
	const int l_chunkId = _slotChunk[p_slot];

	int l_next = slotChunkNext[p_slot];
	int l_prev = _slotChunkPrev[p_slot];

	if (l_prev == NO_SLOT) {
		chunkHead[l_chunkId] = l_next;
	} else {
		slotChunkNext[l_prev] = l_next;
	}

	if (l_next != NO_SLOT) {
		_slotChunkPrev[l_next] = l_prev;
	}

	l_next = _slotEntityNext[p_slot];
	l_prev = _slotEntityPrev[p_slot];

	if (l_prev == NO_SLOT) {
		_entitySlotHead[l_id] = l_next;
	} else {
		_slotEntityNext[l_prev] = l_next;
	}

	if (l_next != NO_SLOT) {
		_slotEntityPrev[l_next] = l_prev;
	}

	_freeSlots.push_back(p_slot);

	const int l_team = entityTeam[l_id];
	_apply_count_delta(l_chunkId, l_team, -1);

	if (_rebuild_chunk_groups(l_chunkId, l_team)) {
		if (_rebuild_column_groups(l_chunkId % COLUMNS, l_team)) {
			_rebuild_map_groups(l_team);
		}
	}
}

int ChunkingServer::_acquire_slot() {
	if (!_freeSlots.empty()) {
		const int l_reusedSlot = _freeSlots.back();
		_freeSlots.pop_back();
		return l_reusedSlot;
	}

	slotEntity.push_back(0);
	_slotChunk.push_back(0);
	slotChunkNext.push_back(NO_SLOT);
	_slotChunkPrev.push_back(NO_SLOT);
	_slotEntityNext.push_back(NO_SLOT);
	_slotEntityPrev.push_back(NO_SLOT);

	return static_cast<int>(slotEntity.size()) - 1;
}

void ChunkingServer::_apply_count_delta(int p_chunkId, int p_team, int p_delta) {
	const int l_column = p_chunkId % COLUMNS;
	const int l_columnIndex = p_team * COLUMNS + l_column;
	const int l_columnCountBefore = _columnCounts[l_columnIndex];

	_chunkCounts[p_team * CHUNKS + p_chunkId] += p_delta;
	_columnCounts[l_columnIndex] = l_columnCountBefore + p_delta;
	_mapCounts[p_team] += p_delta;

	if (p_delta > 0 && l_columnCountBefore == 0) {
		_extend_team_columns(p_team, l_column);
	} else if (p_delta < 0 && l_columnCountBefore + p_delta == 0) {
		_shrink_team_columns(p_team, l_column);
	}
}

void ChunkingServer::_extend_team_columns(int p_team, int p_columnIndex) {
	if (_teamMinColumn[p_team] == NO_COLUMN || p_columnIndex < _teamMinColumn[p_team]) {
		_teamMinColumn[p_team] = p_columnIndex;
	}

	if (_teamMaxColumn[p_team] == NO_COLUMN || p_columnIndex > _teamMaxColumn[p_team]) {
		_teamMaxColumn[p_team] = p_columnIndex;
	}
}

void ChunkingServer::_shrink_team_columns(int p_team, int p_columnIndex) {
	if (_mapCounts[p_team] == 0) {
		_teamMinColumn[p_team] = NO_COLUMN;
		_teamMaxColumn[p_team] = NO_COLUMN;
		return;
	}

	const int l_firstColumnIndex = p_team * COLUMNS;

	if (p_columnIndex == _teamMinColumn[p_team]) {
		int l_column = p_columnIndex + 1;

		while (_columnCounts[l_firstColumnIndex + l_column] == 0) {
			++l_column;
		}

		_teamMinColumn[p_team] = l_column;
	}

	if (p_columnIndex == _teamMaxColumn[p_team]) {
		int l_column = p_columnIndex - 1;

		while (_columnCounts[l_firstColumnIndex + l_column] == 0) {
			--l_column;
		}

		_teamMaxColumn[p_team] = l_column;
	}
}

bool ChunkingServer::_rebuild_chunk_groups(int p_chunkId, int p_team) {
	const int l_chunkIndex = p_team * CHUNKS + p_chunkId;
	const int64_t l_oldGroups = _chunkGroups[l_chunkIndex];
	int64_t l_groups = 0;

	int l_slot = chunkHead[p_chunkId];
	while (l_slot != NO_SLOT) {
		const int l_id = slotEntity[l_slot];

		if (entityTeam[l_id] == p_team) {
			l_groups |= entityGroups[l_id];

			if (l_groups == l_oldGroups) {
				break;
			}
		}

		l_slot = slotChunkNext[l_slot];
	}

	if (l_groups == l_oldGroups) {
		return false;
	}

	_chunkGroups[l_chunkIndex] = l_groups;
	return true;
}

bool ChunkingServer::_apply_group_to_column(int p_columnIndex, int p_team, int64_t p_groups) {
	const int l_columnIndex = p_team * COLUMNS + p_columnIndex;
	const int64_t l_mergedGroups = _columnGroups[l_columnIndex] | p_groups;

	if (l_mergedGroups == _columnGroups[l_columnIndex]) {
		return false;
	}

	_columnGroups[l_columnIndex] = l_mergedGroups;
	return true;
}

bool ChunkingServer::_rebuild_column_groups(int p_columnIndex, int p_team) {
	const int l_columnIndex = p_team * COLUMNS + p_columnIndex;
	const int64_t l_oldGroups = _columnGroups[l_columnIndex];
	int64_t l_groups = 0;
	const int l_firstChunkIndex = p_team * CHUNKS + p_columnIndex;

	for (int l_rowOffset = 0; l_rowOffset < ROWS; ++l_rowOffset) {
		l_groups |= _chunkGroups[l_firstChunkIndex + l_rowOffset * COLUMNS];

		if (l_groups == l_oldGroups) {
			break;
		}
	}

	if (l_groups == l_oldGroups) {
		return false;
	}

	_columnGroups[l_columnIndex] = l_groups;
	return true;
}

void ChunkingServer::_rebuild_map_groups(int p_team) {
	const int64_t l_oldGroups = _mapGroups[p_team];
	int64_t l_groups = 0;
	const int l_firstColumnIndex = p_team * COLUMNS;

	for (int l_columnOffset = 0; l_columnOffset < COLUMNS; ++l_columnOffset) {
		l_groups |= _columnGroups[l_firstColumnIndex + l_columnOffset];

		if (l_groups == l_oldGroups) {
			return;
		}
	}

	_mapGroups[p_team] = l_groups;
}
