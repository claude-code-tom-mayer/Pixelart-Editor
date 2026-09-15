#pragma once

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/core/binder_common.hpp>
#include <godot_cpp/variant/vector2.hpp>

namespace godot {

/// Rounds a positive value up at compile time, so the chunk grid can be constexpr.
/// @param p_value The value to round up
/// @return The smallest whole number not below it
constexpr int ceil_positive(double p_value) {
	const int l_truncated = static_cast<int>(p_value);
	return (p_value > static_cast<double>(l_truncated)) ? l_truncated + 1 : l_truncated;
}

/// Grid, map and team constants of the chunking system.
/// Derives the square chunk grid from the configuration at compile time.
class C_ChunkingServer : public Object {
	GDCLASS(C_ChunkingServer, Object)

protected:
	static void _bind_methods();

public:
	// ===== CONFIGURATION =====

	/// Teams an entity can fight for; the values index every per team container.
	enum TEAM {
		TEAM_ATTACKER,
		TEAM_DEFENDER,
		TEAM_MAX
	};

	/// World size the chunk grid has to cover, in world units.
	static constexpr double CONFIGURED_MAP_SIZE_X = 4096.0;
	static constexpr double CONFIGURED_MAP_SIZE_Y = 4096.0;

	/// Wanted chunks per row; only kept exactly if it already yields square chunks.
	static constexpr int CONFIGURED_CHUNK_COLUMNS = 32;

	/// Wanted chunk rows; only kept exactly if it already yields square chunks.
	static constexpr int CONFIGURED_CHUNK_ROWS = 32;

	/// Tolerance against float error when deriving the chunk counts from the map size.
	static constexpr double COVERAGE_EPSILON = 0.0001;

	/// Stored as the outermost occupied column of a team that holds no entity at all.
	static constexpr int NO_COLUMN = -1;

	/// Stored as a membership link that points nowhere, in every chunk and entity chain.
	static constexpr int NO_SLOT = -1;

	/// Stored as a center link that points nowhere, in every center chain.
	static constexpr int NO_ENTITY = -1;

	// ===== DERIVED_CONSTANTS =====

	/// Edge length of one chunk; identical on both axes, so chunks are square.
	static constexpr double CHUNK_SIZE =
			(CONFIGURED_MAP_SIZE_X / CONFIGURED_CHUNK_COLUMNS +
			 CONFIGURED_MAP_SIZE_Y / CONFIGURED_CHUNK_ROWS) * 0.5;

	/// Chunks per row after the square chunk recalculation.
	static constexpr int MAP_CHUNK_COLUMNS =
			ceil_positive(CONFIGURED_MAP_SIZE_X / CHUNK_SIZE - COVERAGE_EPSILON) > 1
			? ceil_positive(CONFIGURED_MAP_SIZE_X / CHUNK_SIZE - COVERAGE_EPSILON) : 1;

	/// Chunk rows after the square chunk recalculation.
	static constexpr int MAP_CHUNK_ROWS =
			ceil_positive(CONFIGURED_MAP_SIZE_Y / CHUNK_SIZE - COVERAGE_EPSILON) > 1
			? ceil_positive(CONFIGURED_MAP_SIZE_Y / CHUNK_SIZE - COVERAGE_EPSILON) : 1;

	/// Total number of chunks on the map.
	static constexpr int CHUNK_COUNT = MAP_CHUNK_COLUMNS * MAP_CHUNK_ROWS;

	/// Number of teams; size of every per team container.
	static constexpr int TEAM_COUNT = TEAM_MAX;

	/// Size the chunk grid really covers; never smaller than the configured map size.
	static constexpr double MAP_SIZE_X = MAP_CHUNK_COLUMNS * CHUNK_SIZE;
	static constexpr double MAP_SIZE_Y = MAP_CHUNK_ROWS * CHUNK_SIZE;

	// ===== PUBLIC_METHODS =====

	/// Reads the chunk edge length; a method because floats cannot be bound as constants.
	/// @return The edge length of one chunk
	static double get_chunk_size() { return CHUNK_SIZE; }

	/// Reads the size the chunk grid really covers.
	/// @return The covered size as (width, height)
	static Vector2 get_map_size() { return Vector2(MAP_SIZE_X, MAP_SIZE_Y); }
};

} // namespace godot

VARIANT_ENUM_CAST(C_ChunkingServer::TEAM);
