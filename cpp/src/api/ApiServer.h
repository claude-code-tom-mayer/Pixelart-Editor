#pragma once

#include "chunking/ChunkingServer.h"
#include "hit/HitServer.h"
#include "targeting/TargetingServer.h"

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/resource.hpp>

#include <vector>

namespace godot {

/// The one path entities talk to; owns the chunk index and the servers built on it.
/// Registration happens here once and hands every server only the part it needs.
class ApiServer : public RefCounted {
	GDCLASS(ApiServer, RefCounted)

protected:
	static void _bind_methods();

public:
	// ===== LIFECYCLE =====

	/// Builds the chunk index and the servers that read it.
	/// The servers only ever know the index, never this one, so nothing here keeps itself alive.
	ApiServer();

	// ===== PUBLIC_LIFECYCLE =====

	/// Registers an entity across every server under the one id they all share.
	/// @param p_position Start position of the entity
	/// @param p_team Team of the entity, a C_ChunkingServer::TEAM value
	/// @param p_module Module management of the entity, an M_ModuleManager
	/// @param p_entityData Radius, groups and the setup of every server, an R_EntityData
	/// @return The assigned entity id
	int create_entity(const Vector2 &p_position, int p_team, const Ref<RefCounted> &p_module,
			const Ref<Resource> &p_entityData);

	/// Announces an entity for removal and lets every server react to it.
	/// @param p_id The entity id to mark
	void pre_unregister_entity(int p_id);

	/// Removes an entity from the index and from every server on top of it.
	/// @param p_id The entity id to remove
	void unregister_entity(int p_id);

	/// Lets every server drop what it holds for the removed ids, then releases them.
	void release_removed_ids();

	/// Moves an entity and updates only the chunks it entered or left.
	/// @param p_id The entity id to move
	/// @param p_position The new position
	void set_position(int p_id, const Vector2 &p_position) { _chunking->set_position(p_id, p_position); }

	/// Resizes an entity and updates only the chunks it entered or left.
	/// @param p_id The entity id to resize
	/// @param p_radius The new effect radius
	void set_radius(int p_id, double p_radius) { _chunking->set_radius(p_id, p_radius); }

	// ===== PUBLIC_HITS =====

	/// Hits every reachable target inside a circle, in no particular order.
	/// @return The impact positions as (x, y, height)
	PackedVector3Array hit_circle(int p_emitterId, const Vector2 &p_origin, double p_radius,
			const Vector2 &p_hitYBand, int p_maxHits, int p_preferredId, const Ref<Resource> &p_hitData) {
		return _hits->hit_circle(p_emitterId, p_origin, p_radius, p_hitYBand, p_maxHits, p_preferredId, p_hitData);
	}

	/// Hits every reachable target inside a circle, from the center outwards.
	/// @return The impact positions as (x, y, height), nearest first
	PackedVector3Array hit_circle_ordered(int p_emitterId, const Vector2 &p_origin, double p_radius,
			const Vector2 &p_hitYBand, int p_maxHits, int p_preferredId, const Ref<Resource> &p_hitData) {
		return _hits->hit_circle_ordered(p_emitterId, p_origin, p_radius, p_hitYBand, p_maxHits, p_preferredId, p_hitData);
	}

	/// Hits every reachable target inside a directional rect, in no particular order.
	/// @return The impact positions as (x, y, height)
	PackedVector3Array hit_directional_rect(int p_emitterId, const Vector2 &p_origin, const Vector2 &p_direction,
			double p_length, double p_width, const Vector2 &p_hitYBand, int p_maxHits, int p_preferredId,
			const Ref<Resource> &p_hitData) {
		return _hits->hit_directional_rect(p_emitterId, p_origin, p_direction, p_length, p_width,
				p_hitYBand, p_maxHits, p_preferredId, p_hitData);
	}

	/// Hits every reachable target inside a directional rect, starting from one of its edges.
	/// @return The impact positions as (x, y, height), ordered from that edge
	PackedVector3Array hit_directional_rect_ordered(int p_emitterId, const Vector2 &p_origin, const Vector2 &p_direction,
			double p_length, double p_width, const Vector2 &p_hitYBand, int p_maxHits, int p_preferredId,
			const Ref<Resource> &p_hitData, int p_startEdge) {
		return _hits->hit_directional_rect_ordered(p_emitterId, p_origin, p_direction, p_length, p_width,
				p_hitYBand, p_maxHits, p_preferredId, p_hitData, p_startEdge);
	}

	/// Hits every reachable target inside a cake slice, in no particular order.
	/// @return The impact positions as (x, y, height)
	PackedVector3Array hit_cake_slice(int p_emitterId, const Vector2 &p_origin, const Vector2 &p_direction,
			double p_radius, double p_angle, const Vector2 &p_hitYBand, int p_maxHits, int p_preferredId,
			const Ref<Resource> &p_hitData) {
		return _hits->hit_cake_slice(p_emitterId, p_origin, p_direction, p_radius, p_angle,
				p_hitYBand, p_maxHits, p_preferredId, p_hitData);
	}

	/// Hits every reachable target inside a cake slice, sweeping from its right edge to its left.
	/// @return The impact positions as (x, y, height), in sweep order
	PackedVector3Array hit_cake_slice_ordered(int p_emitterId, const Vector2 &p_origin, const Vector2 &p_direction,
			double p_radius, double p_angle, const Vector2 &p_hitYBand, int p_maxHits, int p_preferredId,
			const Ref<Resource> &p_hitData, bool p_reversed) {
		return _hits->hit_cake_slice_ordered(p_emitterId, p_origin, p_direction, p_radius, p_angle,
				p_hitYBand, p_maxHits, p_preferredId, p_hitData, p_reversed);
	}

	// ===== PUBLIC_TARGETING =====

	/// Advances the state of one entity; cheap enough to run every tick.
	/// @param p_id The entity to advance
	/// @return Its new C_TargetingServer::STATE
	int update_entity(int p_id) { return _targeting->update_entity(p_id); }

	/// Scans the search area of an entity and gives it the best scoring target.
	/// @param p_id The entity that searches
	/// @return The target it got, or C_TargetingServer::NO_TARGET
	int search_target(int p_id) { return _targeting->search_target(p_id); }

	/// Returns where an entity should move this tick.
	/// @param p_id The entity to move
	/// @return The position the movement should head for
	Vector2 get_target_position(int p_id) { return _targeting->get_target_position(p_id); }

	/// Returns the current state of an entity.
	/// @param p_id The entity to read
	/// @return Its C_TargetingServer::STATE
	int get_state(int p_id) const { return _targeting->get_state(p_id); }

	/// Returns the target of an entity.
	/// @param p_id The entity to read
	/// @return Its target, or C_TargetingServer::NO_TARGET
	int get_target(int p_id) const { return _targeting->get_target(p_id); }

	/// Returns everyone targeting an entity as a snapshot of the moment it is asked.
	/// @param p_id The entity to read
	/// @return The ids currently targeting it
	PackedInt32Array get_targeters(int p_id) const { return _targeting->get_targeters(p_id); }

	/// Makes every entity that targets this one drop it and look for something else.
	/// @param p_id The entity that is no longer worth targeting
	void drop_targeters(int p_id) { _targeting->drop_targeters(p_id); }

	// ===== PUBLIC_SETTERS =====

	/// Hides an entity from searchers, or reveals it again.
	void set_invisible(int p_id, bool p_invisible) { _targeting->set_invisible(p_id, p_invisible); }

	/// Sets whether an entity can see invisible enemies.
	void set_targets_invisible(int p_id, bool p_enabled) { _targeting->set_targets_invisible(p_id, p_enabled); }

	/// Sets whether an entity is a focus target other entities prefer.
	void set_focused(int p_id, bool p_enabled) { _targeting->set_focused(p_id, p_enabled); }

	/// Sets whether an entity scores candidates without the focus bonus.
	void set_ignores_focus(int p_id, bool p_enabled) { _targeting->set_ignores_focus(p_id, p_enabled); }

	/// Sets how far a search of this entity reaches.
	void set_search_chunks(int p_id, int p_searchChunks) { _targeting->set_search_chunks(p_id, p_searchChunks); }

	/// Sets how close a targeter has to come before the entity flees.
	void set_flee_chunks(int p_id, int p_fleeChunks) { _targeting->set_flee_chunks(p_id, p_fleeChunks); }

	/// Sets the real distance at which the entity enters combat.
	void set_hit_range(int p_id, double p_hitRange) { _targeting->set_hit_range(p_id, p_hitRange); }

	/// Sets the groups the entity goes after before it considers the normal ones.
	void set_priority_targeted_groups(int p_id, int64_t p_groups) { _targeting->set_priority_targeted_groups(p_id, p_groups); }

	/// Sets the vertical extent an entity occupies.
	void set_y_band(int p_id, const Vector2 &p_yBand) { _hits->set_y_band(p_id, p_yBand); }

	/// Sets the hit groups an entity can be harmed by.
	void set_hurt_groups(int p_id, int64_t p_hurtGroups) { _hits->set_hurt_groups(p_id, p_hurtGroups); }

	/// Sets the hit groups the hits of an entity carry.
	void set_hit_groups(int p_id, int64_t p_hitGroups) { _hits->set_hit_groups(p_id, p_hitGroups); }

	/// Sets the hurt groups that end a hit of this entity on the target they match.
	void set_stop_groups(int p_id, int64_t p_stopGroups) { _hits->set_stop_groups(p_id, p_stopGroups); }

	/// Sets the radius profile of an entity; null gives it a constant radius again.
	void set_radius_curve(int p_id, const Ref<Curve> &p_curve) { _hits->set_radius_curve(p_id, p_curve); }

private:
	// ===== PRIVATE_VARIABLES =====

	/// Chunk index every server reads; owned here and never handed out to the outside.
	Ref<ChunkingServer> _chunking;

	/// Resolves area hits against the shared chunk index.
	Ref<HitServer> _hits;

	/// Picks and holds targets against the shared chunk index.
	Ref<TargetingServer> _targeting;

	/// Every server that keeps a slot per entity id, in the order the lifecycle walks them.
	std::vector<A_EntityServer *> _servers;
};

} // namespace godot
