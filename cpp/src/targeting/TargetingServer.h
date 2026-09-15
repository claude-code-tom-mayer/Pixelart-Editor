#pragma once

#include "servers/A_EntityServer.h"
#include "targeting/C_TargetingServer.h"

#include <godot_cpp/classes/resource.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/vector2.hpp>

#include <cstdint>
#include <vector>

namespace godot {

/// Picks and holds a target per entity and reports where it should move.
/// Searches are chunk counted and event driven: a target is only ever lost, never re-checked.
class TargetingServer : public A_EntityServer {
	GDCLASS(TargetingServer, A_EntityServer)

protected:
	static void _bind_methods();

	void _append_slot() override;
	void _reset_slot(int p_id) override;
	int _get_slot_count() const override { return static_cast<int>(_entityState.size()); }

public:
	// ===== PUBLIC_METHODS =====

	/// Gives an entity its targeting side; the api server calls this while it registers.
	/// @param p_id The entity to set up
	/// @param p_targetingData Groups, ranges and flags of the entity, an R_TargetingData
	void register_entity(int p_id, const Ref<Resource> &p_targetingData);

	/// Advances the state of one entity; cheap enough to run every tick.
	/// Never searches, the entity asks for that itself through search_target().
	/// @param p_id The entity to advance
	/// @return Its new C_TargetingServer::STATE
	int update_entity(int p_id);

	/// Scans the search area of an entity and gives it the best scoring target.
	/// @param p_id The entity that searches
	/// @return The target it got, or C_TargetingServer::NO_TARGET
	int search_target(int p_id);

	/// Makes every entity that targets this one drop it and look for something else.
	/// @param p_id The entity that is no longer worth targeting
	void drop_targeters(int p_id);

	/// Hides an entity from searchers, or reveals it again.
	/// Hiding drops every targeter that cannot see invisible entities.
	/// @param p_id The entity to change
	/// @param p_invisible Whether it becomes invisible
	void set_invisible(int p_id, bool p_invisible);

	/// Sets whether an entity can see invisible enemies.
	/// @param p_id The entity to change
	/// @param p_enabled Whether it sees them
	void set_targets_invisible(int p_id, bool p_enabled) {
		_set_flag(p_id, C_TargetingServer::FLAG_TARGETS_INVISIBLE, p_enabled);
	}

	/// Sets whether an entity is a focus target other entities prefer.
	/// @param p_id The entity to change
	/// @param p_enabled Whether it carries focus
	void set_focused(int p_id, bool p_enabled) {
		_set_flag(p_id, C_TargetingServer::FLAG_HAS_FOCUS, p_enabled);
	}

	/// Sets whether an entity scores candidates without the focus bonus.
	/// @param p_id The entity to change
	/// @param p_enabled Whether it ignores focus
	void set_ignores_focus(int p_id, bool p_enabled) {
		_set_flag(p_id, C_TargetingServer::FLAG_IGNORES_FOCUS, p_enabled);
	}

	/// Sets how far a search of this entity reaches.
	/// @param p_id The entity to change
	/// @param p_searchChunks Reach in chunks per direction
	void set_search_chunks(int p_id, int p_searchChunks) { _entitySearchChunks[p_id] = p_searchChunks; }

	/// Sets how close a targeter has to come before the entity flees.
	/// @param p_id The entity to change
	/// @param p_fleeChunks Threat distance in chunks
	void set_flee_chunks(int p_id, int p_fleeChunks) { _entityFleeChunks[p_id] = p_fleeChunks; }

	/// Sets the real distance at which the entity enters combat.
	/// Measured to the edge of the target, so the radius of the target is added on top.
	/// @param p_id The entity to change
	/// @param p_hitRange The distance to the silhouette of the target
	void set_hit_range(int p_id, double p_hitRange) { _entityHitRange[p_id] = p_hitRange; }

	/// Sets the groups the entity goes after before it considers the normal ones.
	/// @param p_id The entity to change
	/// @param p_priorityTargetedGroups Bitmask of the preferred groups
	void set_priority_targeted_groups(int p_id, int64_t p_priorityTargetedGroups) {
		_entityPriorityTargetedGroups[p_id] = p_priorityTargetedGroups;
	}

	// ===== PUBLIC_QUERIES =====

	/// Returns where the entity should move this tick.
	/// Fleeing and marching aim at a fixed x of the map, fighting aims at the target itself.
	/// @param p_id The entity to move
	/// @return The position the movement should head for
	Vector2 get_target_position(int p_id);

	/// Returns the current state of an entity.
	/// @param p_id The entity to read
	/// @return Its C_TargetingServer::STATE
	int get_state(int p_id) const { return _entityState[p_id]; }

	/// Returns the target of an entity.
	/// @param p_id The entity to read
	/// @return Its target, or C_TargetingServer::NO_TARGET
	int get_target(int p_id) const { return _entityTarget[p_id]; }

	/// Returns everyone targeting an entity as a snapshot of the moment it is asked.
	/// @param p_id The entity to read
	/// @return The ids currently targeting it
	PackedInt32Array get_targeters(int p_id) const;

	// ===== PUBLIC_LIFECYCLE =====

	/// Sends everyone targeting an announced entity back to searching.
	/// @param p_id The entity that was announced for removal
	void on_pre_unregister(int p_id) override { drop_targeters(p_id); }

	/// Unlinks a removed entity from both sides of the targeting graph.
	/// @param p_id The entity that was removed
	void on_unregister(int p_id) override;

private:
	// ===== PRIVATE_VARIABLES =====

	/// Bitmask of the groups an entity may go after.
	std::vector<int64_t> _entityTargetedGroups;

	/// Current C_TargetingServer::STATE per entity.
	std::vector<uint8_t> _entityState;

	/// How many chunks in each direction a search of this entity covers.
	std::vector<int32_t> _entitySearchChunks;

	/// A targeter closer than this many chunks makes the entity flee.
	std::vector<int32_t> _entityFleeChunks;

	/// Real distance at which approaching turns into combat, measured to the edge of the target.
	std::vector<double> _entityHitRange;

	/// Bitmask of the groups an entity goes after before it considers the normal ones.
	std::vector<int64_t> _entityPriorityTargetedGroups;

	/// Invisibility and focus flags of an entity, as C_TargetingServer::FLAG bits.
	std::vector<uint8_t> _entityFlags;

	/// Target of an entity, or C_TargetingServer::NO_TARGET.
	std::vector<int32_t> _entityTarget;

	/// Own slot inside the targeter list of the target; makes dropping a target O(1).
	std::vector<int32_t> _entityTargeterIndex;

	/// Ids that currently target this entity; its size is the crowding count.
	std::vector<std::vector<int32_t>> _targetersOf;

	// ===== SEARCH_VARIABLES =====
	// State of the running search, hoisted out of the candidate loop because none of it changes there.

	/// The entity the running search belongs to.
	int _searchId = C_TargetingServer::NO_TARGET;

	/// Team of the searcher.
	int _searchTeam = 0;

	/// Column of the center chunk of the searcher.
	int _searchColumn = 0;

	/// Row of the center chunk of the searcher.
	int _searchRow = 0;

	/// Flags of the searcher, as C_TargetingServer::FLAG bits.
	int _searchFlags = 0;

	/// How many chunks in each direction the running search covers.
	int _searchReach = 0;

	/// Direction the searcher marches in along x; decides what counts as behind it.
	int _searchForwardSign = 1;

	/// Every group the searcher accepts, priority ones included.
	int64_t _searchGroups = 0;

	/// Groups the searcher goes after before it considers the normal ones.
	int64_t _searchPriorityGroups = 0;

	/// Best priority candidate so far, or C_TargetingServer::NO_TARGET.
	int _searchBestPriorityId = C_TargetingServer::NO_TARGET;

	/// Score of the best priority candidate so far.
	double _searchBestPriorityScore = 0.0;

	/// Best normal candidate so far, or C_TargetingServer::NO_TARGET.
	int _searchBestNormalId = C_TargetingServer::NO_TARGET;

	/// Score of the best normal candidate so far.
	double _searchBestNormalScore = 0.0;

	// ===== PRIVATE_METHODS =====

	/// Packs the flag booleans of a targeting setup into one byte.
	/// @param p_targetingData The setup to read, an R_TargetingData
	/// @return The packed flags
	static int _build_flags(const Ref<Resource> &p_targetingData);

	/// Switches one flag of an entity on or off.
	/// @param p_id The entity to change
	/// @param p_flag The C_TargetingServer::FLAG bit
	/// @param p_enabled Whether the bit is set
	void _set_flag(int p_id, int p_flag, bool p_enabled);

	/// Decides what an entity is doing right now, without changing anything about it.
	/// @param p_id The entity to judge
	/// @return Its C_TargetingServer::STATE
	int _evaluate_state(int p_id) const;

	/// Checks whether the entity is still away from its own base and may keep fleeing.
	/// @param p_id The entity to check
	/// @return true while it has not reached its own side
	bool _can_still_flee(int p_id) const;

	/// Checks whether any entity targeting this one is inside its flee distance.
	/// @param p_id The entity to check
	/// @return true if it should run
	bool _is_threatened(int p_id) const;

	/// Scans the search area ring by ring and keeps the best priority and normal candidate.
	/// @param p_id The entity that searches
	/// @return The best target, or C_TargetingServer::NO_TARGET
	int _find_best_target(int p_id);

	/// Sums up every bonus a candidate of the running search could possibly score.
	/// @return The largest bonus any candidate can add on top of its closeness
	double _get_max_score_bonus() const;

	/// Checks whether no ring from here outwards could still beat what the search already holds.
	/// @param p_ring The ring that would be scanned next
	/// @param p_maxBonus The largest bonus a candidate can score on top of its closeness
	/// @param p_priorityPossible Whether a priority target exists on the map at all
	/// @return true if the search can stop here
	bool _is_search_settled(int p_ring, double p_maxBonus, bool p_priorityPossible) const;

	/// Scans every chunk at exactly one ring distance around the searcher.
	/// @param p_ring The ring distance to scan, 0 being the chunk of the searcher itself
	void _scan_ring(int p_ring);

	/// Scores every center that sits in one chunk and keeps the best of each category.
	/// @param p_chunkId The chunk to open
	void _scan_chunk(int p_chunkId);

	/// Compares a candidate against the best one so far, the lower id winning a tie.
	/// @param p_score Score of the candidate
	/// @param p_candidateId The candidate itself
	/// @param p_bestScore Score of the best candidate so far
	/// @param p_bestId The best candidate so far
	/// @return true if the candidate takes the lead
	static bool _is_better(double p_score, int p_candidateId, double p_bestScore, int p_bestId);

	/// Checks everything about a candidate of the running search that does not depend on the score.
	/// @param p_candidateId The entity to check
	/// @return true if the candidate is worth scoring
	bool _can_target(int p_candidateId) const;

	/// Weighs a candidate of the running search.
	/// @param p_candidateId The candidate to weigh
	/// @return Its score, higher is better
	double _score_candidate(int p_candidateId) const;

	/// Measures the distance from a center chunk to the center chunk of an entity, in chunk steps.
	/// @param p_column Column of the chunk to measure from
	/// @param p_row Row of the chunk to measure from
	/// @param p_otherId The entity to measure to
	/// @return The steps, diagonals counted as C_TargetingServer::DIAGONAL_CHUNK_COST
	double _get_chunk_distance(int p_column, int p_row, int p_otherId) const;

	/// Checks whether anything hostile got past an entity, counting invisible ones too.
	/// @param p_id The entity to check
	/// @return true if an opponent stands behind it
	bool _has_enemy_behind(int p_id) const;

	/// Checks whether anything the entity may go after exists anywhere on the map.
	/// @param p_id The entity that asks
	/// @return true if a search could find something
	bool _has_opponent_on_map(int p_id) const;

	/// Links an entity to a target and records its slot in the targeter list.
	/// @param p_id The entity that targets
	/// @param p_targetId The entity it targets
	void _assign_target(int p_id, int p_targetId);

	/// Unlinks an entity from its target by swap-and-pop and sends it back to searching.
	/// @param p_id The entity that gives up its target
	void _drop_target(int p_id);
};

} // namespace godot
