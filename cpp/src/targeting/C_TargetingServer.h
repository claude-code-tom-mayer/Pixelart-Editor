#pragma once

#include "chunking/C_ChunkingServer.h"

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/core/binder_common.hpp>

namespace godot {

/// Constants, states and scoring weights of the targeting system.
/// Ranges are counted in chunks here, only the combat range is a real distance.
class C_TargetingServer : public Object {
	GDCLASS(C_TargetingServer, Object)

protected:
	static void _bind_methods();

public:
	// ===== CONFIGURATION =====

	/// What an entity is currently doing.
	enum STATE {
		STATE_SEARCH,
		STATE_APPROACH,
		STATE_COMBAT,
		STATE_FLEE
	};

	/// Set while the entity cannot be seen by searchers without FLAG_TARGETS_INVISIBLE.
	static constexpr int FLAG_INVISIBLE = 1 << 0;

	/// Set while the entity can see invisible enemies.
	static constexpr int FLAG_TARGETS_INVISIBLE = 1 << 1;

	/// Set while the entity is a focus target and scores the focus bonus.
	static constexpr int FLAG_HAS_FOCUS = 1 << 2;

	/// Set while the entity scores every candidate without the focus bonus.
	static constexpr int FLAG_IGNORES_FOCUS = 1 << 3;

	/// Stored as the target of an entity that has none.
	static constexpr int NO_TARGET = -1;

	/// How close to its own base x an entity has to be before it stops fleeing.
	static constexpr double BASE_REACHED_EPSILON = 32.0;

	/// What a diagonal chunk step costs against a straight one.
	static constexpr double DIAGONAL_CHUNK_COST = 1.45;

	// ===== DERIVED_CONSTANTS =====

	/// The x every team retreats towards; attackers hold the left side, defenders the right one.
	static constexpr double TEAM_BASE_X[C_ChunkingServer::TEAM_COUNT] = { 0.0, C_ChunkingServer::MAP_SIZE_X };

	/// The x every team marches towards while it has no target, the opposing base.
	static constexpr double TEAM_MARCH_X[C_ChunkingServer::TEAM_COUNT] = { C_ChunkingServer::MAP_SIZE_X, 0.0 };

	/// The direction a team marches in along x; 1 towards a larger x, -1 towards a smaller one.
	static constexpr int TEAM_FORWARD_SIGN[C_ChunkingServer::TEAM_COUNT] = { 1, -1 };

	// ===== SCORING_WEIGHTS =====

	/// Score per chunk the candidate is closer than the edge of the search area.
	static constexpr double WEIGHT_CLOSENESS = 1.0;

	/// Score added when the candidate is a focus target.
	static constexpr double WEIGHT_FOCUS = 6.0;

	/// Score added when the candidate stands behind the searcher.
	static constexpr double WEIGHT_BEHIND = 3.0;

	/// Score lost per entity that already targets the candidate.
	static constexpr double WEIGHT_CROWDING = 1.5;

	/// Score added when the candidate already targets the searcher.
	static constexpr double WEIGHT_MUTUAL = 4.0;

	// ===== PUBLIC_METHODS =====

	/// Reads the x a team retreats towards.
	/// @param p_team The team to read
	/// @return Its own base x
	static double get_team_base_x(int p_team) { return TEAM_BASE_X[p_team]; }

	/// Reads the x a team marches towards while it has no target.
	/// @param p_team The team to read
	/// @return The opposing base x
	static double get_team_march_x(int p_team) { return TEAM_MARCH_X[p_team]; }
};

} // namespace godot

VARIANT_ENUM_CAST(C_TargetingServer::STATE);
