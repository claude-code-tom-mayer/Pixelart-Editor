#pragma once

#include "chunking/C_ChunkingServer.h"

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector4i.hpp>

#include <cstdint>
#include <vector>

namespace godot {

/// Sorts entities into square chunks, columns and one map aggregate for fast group queries.
/// Counts are always written through, group masks only cascade upwards when they really change.
class ChunkingServer : public RefCounted {
	GDCLASS(ChunkingServer, RefCounted)

protected:
	static void _bind_methods();

public:
	// ===== SHARED_VARIABLES =====
	// Private to the chunking system, but read directly by the servers built on top of it.
	// They are plain C++ vectors, so a sibling server reads them without touching a Variant.

	/// Team per entity id, as a C_ChunkingServer::TEAM value.
	std::vector<uint8_t> entityTeam;

	/// Bitmask of the groups an entity belongs to.
	std::vector<int64_t> entityGroups;

	/// Current position per entity id.
	std::vector<Vector2> entityPosition;

	/// Effect radius per entity id; decides in how many chunks the entity stands.
	std::vector<double> entityRadius;

	/// 1 while an entity is announced for removal but still fully active.
	std::vector<uint8_t> entityPreUnregistered;

	/// 1 while an entity is removed but its id stays locked until it is released.
	std::vector<uint8_t> entityUnregistering;

	/// Chunk the center of an entity sits in; the whole entity is listed there exactly once.
	std::vector<int32_t> entityCenterChunk;

	/// Column of the center chunk of an entity; flat mirror for the targeting hot loop.
	std::vector<int32_t> entityCenterColumn;

	/// Row of the center chunk of an entity; flat mirror for the targeting hot loop.
	std::vector<int32_t> entityCenterRow;

	/// First membership slot of every chunk, or C_ChunkingServer::NO_SLOT while it is empty.
	std::vector<int32_t> chunkHead;

	/// Entity every membership slot belongs to; the id a chunk walk reads out.
	std::vector<int32_t> slotEntity;

	/// Next membership slot inside the chain of the same chunk.
	std::vector<int32_t> slotChunkNext;

	/// First entity whose center sits in a chunk, or C_ChunkingServer::NO_ENTITY while none does.
	std::vector<int32_t> centerHead;

	/// Next entity inside the center chain of its chunk.
	std::vector<int32_t> centerNext;

	// ===== LIFECYCLE =====

	/// Allocates the chunk, column and map containers for the configured grid.
	ChunkingServer();

	// ===== PUBLIC_METHODS =====

	/// Registers a new entity and adds it to every chunk its radius covers.
	/// @param p_position Start position of the entity
	/// @param p_radius Effect radius of the entity
	/// @param p_team Team of the entity, a C_ChunkingServer::TEAM value
	/// @param p_groups Bitmask of the groups the entity belongs to
	/// @return The assigned entity id
	int register_entity(const Vector2 &p_position, double p_radius, int p_team, int64_t p_groups);

	/// Marks an entity for removal; it stays fully active and queryable.
	/// @param p_id The entity id to mark
	void pre_unregister_entity(int p_id);

	/// Removes an entity from all its chunks and locks its id until it is released.
	/// Does nothing for an id that is already removed, so a double removal cannot free it twice.
	/// @param p_id The entity id to remove
	void unregister_entity(int p_id);

	/// Moves an entity and updates only the chunks it entered or left.
	/// @param p_id The entity id to move
	/// @param p_position The new position
	void set_position(int p_id, const Vector2 &p_position);

	/// Resizes an entity and updates only the chunks it entered or left.
	/// @param p_id The entity id to resize
	/// @param p_radius The new effect radius
	void set_radius(int p_id, double p_radius);

	/// Hands the ids of removed entities back for reuse and clears their state.
	void release_removed_ids();

	// ===== PUBLIC_QUERIES =====

	/// Checks whether an entity is already removed and only waiting for its id to be released.
	/// @param p_id The entity to check
	/// @return true if it is gone from the index
	bool is_unregistering(int p_id) const { return entityUnregistering[p_id] == 1; }

	/// Reads the ids that were removed since the last release.
	/// @return A snapshot of the ids waiting to be freed
	PackedInt32Array get_pending_free_ids() const;

	/// Checks whether any team other than the asking one holds entities in a chunk.
	/// @param p_chunkId The chunk to check
	/// @param p_team The team that asks
	/// @return true if an opponent stands there
	bool has_opponent_in_chunk(int p_chunkId, int p_team) const;

	/// Checks whether any team other than the asking one holds entities in a column.
	/// @param p_columnIndex The column to check
	/// @param p_team The team that asks
	/// @return true if an opponent stands there
	bool has_opponent_in_column(int p_columnIndex, int p_team) const;

	/// Checks whether any team other than the asking one stands left of a column.
	/// @param p_columnIndex The column to look out from
	/// @param p_team The team that asks
	/// @return true if an opponent stands further left
	bool has_opponent_before_column(int p_columnIndex, int p_team) const;

	/// Checks whether any team other than the asking one stands right of a column.
	/// @param p_columnIndex The column to look out from
	/// @param p_team The team that asks
	/// @return true if an opponent stands further right
	bool has_opponent_after_column(int p_columnIndex, int p_team) const;

	/// Checks whether a chunk holds at least one of the searched groups.
	/// @param p_chunkId The chunk to check
	/// @param p_team Team to check, a C_ChunkingServer::TEAM value
	/// @param p_groupMask Bitmask of the searched groups
	/// @return true if at least one searched group bit is present
	bool chunk_has_group(int p_chunkId, int p_team, int64_t p_groupMask) const {
		return (_chunkGroups[p_team * C_ChunkingServer::CHUNK_COUNT + p_chunkId] & p_groupMask) != 0;
	}

	/// Checks whether a column holds at least one of the searched groups.
	/// @param p_columnIndex The column to check
	/// @param p_team Team to check, a C_ChunkingServer::TEAM value
	/// @param p_groupMask Bitmask of the searched groups
	/// @return true if at least one searched group bit is present
	bool column_has_group(int p_columnIndex, int p_team, int64_t p_groupMask) const {
		return (_columnGroups[p_team * C_ChunkingServer::MAP_CHUNK_COLUMNS + p_columnIndex] & p_groupMask) != 0;
	}

	/// Checks whether the map holds at least one of the searched groups.
	/// @param p_team Team to check, a C_ChunkingServer::TEAM value
	/// @param p_groupMask Bitmask of the searched groups
	/// @return true if at least one searched group bit is present
	bool map_has_group(int p_team, int64_t p_groupMask) const {
		return (_mapGroups[p_team] & p_groupMask) != 0;
	}

	/// Checks whether any opposing team holds one of the searched groups in a chunk.
	/// Smallest step of the map to column to chunk filter a search walks down.
	/// @param p_chunkId The chunk to check
	/// @param p_team The team that asks
	/// @param p_groupMask Bitmask of the searched groups
	/// @return true if the chunk is worth opening
	bool chunk_has_opponent_group(int p_chunkId, int p_team, int64_t p_groupMask) const;

	/// Checks whether any opposing team holds one of the searched groups in a column.
	/// Skipping here skips every chunk of that column at once.
	/// @param p_columnIndex The column to check
	/// @param p_team The team that asks
	/// @param p_groupMask Bitmask of the searched groups
	/// @return true if the column is worth opening
	bool column_has_opponent_group(int p_columnIndex, int p_team, int64_t p_groupMask) const;

	/// Checks whether any opposing team holds one of the searched groups anywhere.
	/// Widest step of the filter; a search that fails here never touches a chunk.
	/// @param p_team The team that asks
	/// @param p_groupMask Bitmask of the searched groups
	/// @return true if a search could find anything at all
	bool map_has_opponent_group(int p_team, int64_t p_groupMask) const;

	// ===== PUBLIC_INDEX =====

	/// Calculates the chunk rectangle an axis aligned box covers, clamped to the map.
	/// @param p_minCorner Upper left corner of the box
	/// @param p_maxCorner Lower right corner of the box
	/// @return The rectangle as (minColumn, minRow, maxColumn, maxRow)
	Vector4i compute_chunk_area_from_bounds(const Vector2 &p_minCorner, const Vector2 &p_maxCorner) const;

	/// Lists every chunk inside a chunk rectangle.
	/// Only for callers that need the list itself; walking an area is done with two loops.
	/// @param p_area The rectangle as (minColumn, minRow, maxColumn, maxRow)
	/// @return The chunk ids inside the rectangle, in ascending order
	PackedInt32Array collect_chunks_in_area(const Vector4i &p_area) const;

private:
	// ===== PRIVATE_VARIABLES =====

	/// Chunk rectangle an entity covers as (minColumn, minRow, maxColumn, maxRow).
	std::vector<Vector4i> _entityChunkArea;

	/// Entity ids that may be reused; only filled by release_removed_ids().
	std::vector<int32_t> _freeIds;

	/// Ids removed since the last release; moved into the free list by release_removed_ids().
	std::vector<int32_t> _pendingFreeIds;

	/// First membership slot of every entity, or C_ChunkingServer::NO_SLOT while it stands nowhere.
	std::vector<int32_t> _entitySlotHead;

	/// Chunk every membership slot belongs to.
	std::vector<int32_t> _slotChunk;

	/// Previous membership slot inside the chain of the same chunk; makes unlinking O(1).
	std::vector<int32_t> _slotChunkPrev;

	/// Next membership slot inside the chain of the same entity.
	std::vector<int32_t> _slotEntityNext;

	/// Previous membership slot inside the chain of the same entity; makes unlinking O(1).
	std::vector<int32_t> _slotEntityPrev;

	/// Membership slots that may be handed out again.
	std::vector<int32_t> _freeSlots;

	/// Previous entity inside the center chain of its chunk; makes unlinking O(1).
	std::vector<int32_t> _centerPrev;

	/// Entity count per team and chunk.
	std::vector<int32_t> _chunkCounts;

	/// Entity count per team and column.
	std::vector<int32_t> _columnCounts;

	/// Group bitmask per team and chunk.
	std::vector<int64_t> _chunkGroups;

	/// Group bitmask per team and column, the OR of the chunk masks of that column.
	std::vector<int64_t> _columnGroups;

	/// Group bitmask per team over the whole map, the OR of all column masks.
	std::vector<int64_t> _mapGroups;

	/// Entity count per team over the whole map.
	std::vector<int32_t> _mapCounts;

	/// Lowest column a team occupies, or C_ChunkingServer::NO_COLUMN while it holds nothing.
	std::vector<int32_t> _teamMinColumn;

	/// Highest column a team occupies, or C_ChunkingServer::NO_COLUMN while it holds nothing.
	std::vector<int32_t> _teamMaxColumn;

	// ===== PRIVATE_METHODS =====

	/// Takes a free entity id or appends a fresh slot to every entity container.
	/// @return The id the next entity is stored under
	int _acquire_id();

	/// Calculates the chunk rectangle a position and radius cover, clamped to the map.
	/// @param p_position Center of the covered area
	/// @param p_radius Radius of the covered area
	/// @return The rectangle as (minColumn, minRow, maxColumn, maxRow)
	Vector4i _compute_chunk_area(const Vector2 &p_position, double p_radius) const;

	/// Moves an entity onto a new chunk rectangle, touching only the chunks it entered or left.
	/// Both sides are rectangles, so telling them apart is a bounds test per chunk, never a search.
	/// @param p_id The entity id to update
	/// @param p_area The new rectangle as (minColumn, minRow, maxColumn, maxRow)
	void _apply_chunk_area(int p_id, const Vector4i &p_area);

	/// Checks whether a chunk lies inside a chunk rectangle.
	/// @param p_chunkId The chunk to place
	/// @param p_area The rectangle as (minColumn, minRow, maxColumn, maxRow)
	/// @return true if the chunk is part of the rectangle
	bool _is_chunk_in_area(int p_chunkId, const Vector4i &p_area) const;

	/// Moves the center of an entity into the chunk its position falls into.
	/// @param p_id The entity id to update
	/// @param p_position The position the center is taken from
	void _apply_center_chunk(int p_id, const Vector2 &p_position);

	/// Unlinks the center of an entity from the chain of its chunk.
	/// @param p_id The entity whose center is removed
	void _remove_center_from_chunk(int p_id);

	/// Adds an entity to a chunk and cascades its groups upwards while they change.
	/// @param p_id The entity id to add
	/// @param p_chunkId The target chunk
	void _add_entity_to_chunk(int p_id, int p_chunkId);

	/// Unlinks one membership slot and rebuilds the masks upwards while they change.
	/// @param p_slot The membership slot to drop
	void _remove_slot_from_chunk(int p_slot);

	/// Takes a free membership slot or appends a fresh one to every slot column.
	/// @return The slot the next membership is stored under
	int _acquire_slot();

	/// Writes a count change through to chunk, column and map and keeps the column span current.
	/// @param p_chunkId The chunk the entity was added to or removed from
	/// @param p_team Team whose counts change
	/// @param p_delta The change to apply, 1 when adding and -1 when removing
	void _apply_count_delta(int p_chunkId, int p_team, int p_delta);

	/// Widens the occupied column span of a team by a column that just filled up.
	/// @param p_team The team whose span grows
	/// @param p_columnIndex The column that now holds entities
	void _extend_team_columns(int p_team, int p_columnIndex);

	/// Pulls the occupied column span of a team in after a column ran empty.
	/// @param p_team The team whose span shrinks
	/// @param p_columnIndex The column that ran empty
	void _shrink_team_columns(int p_team, int p_columnIndex);

	/// Rebuilds the group mask of a chunk from the entities still standing in it.
	/// @param p_chunkId The chunk to rebuild
	/// @param p_team Team whose mask is rebuilt
	/// @return true if the mask value changed
	bool _rebuild_chunk_groups(int p_chunkId, int p_team);

	/// Merges a group mask into a column mask, counterpart of the add path.
	/// @param p_columnIndex The column to extend
	/// @param p_team Team whose mask is extended
	/// @param p_groups The group bits to merge in
	/// @return true if the mask value changed
	bool _apply_group_to_column(int p_columnIndex, int p_team, int64_t p_groups);

	/// Rebuilds a column mask from the chunk masks of that column.
	/// @param p_columnIndex The column to rebuild
	/// @param p_team Team whose mask is rebuilt
	/// @return true if the mask value changed
	bool _rebuild_column_groups(int p_columnIndex, int p_team);

	/// Rebuilds the map mask from all column masks, never from chunks directly.
	/// @param p_team Team whose mask is rebuilt
	void _rebuild_map_groups(int p_team);
};

} // namespace godot
