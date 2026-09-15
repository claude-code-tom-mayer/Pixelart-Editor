#pragma once

#include "hit/C_HitServer.h"
#include "servers/A_EntityServer.h"

#include <godot_cpp/classes/curve.hpp>
#include <godot_cpp/classes/resource.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <cstdint>
#include <unordered_map>
#include <vector>

namespace godot {

/// Resolves area hits through the chunk index, so only entities near the shape are tested.
/// Hit and hurt groups decide whether a hit connects at all, stop groups end it at the first blocker.
class HitServer : public A_EntityServer {
	GDCLASS(HitServer, A_EntityServer)

protected:
	static void _bind_methods();

	void _append_slot() override;
	void _reset_slot(int p_id) override;
	int _get_slot_count() const override { return static_cast<int>(_entityYBand.size()); }

public:
	// ===== PUBLIC_METHODS =====

	/// Gives an entity its hit side; the api server calls this while it registers.
	/// @param p_id The entity to arm
	/// @param p_module Module management that receives its hits, an M_ModuleManager
	/// @param p_hitProfile Band, groups and radius profile of the entity, an R_HitProfile
	void register_entity(int p_id, const Ref<RefCounted> &p_module, const Ref<Resource> &p_hitProfile);

	/// Drops everything an entity holds once its id is handed back for reuse.
	/// @param p_id The entity whose slot is released
	void release_entity(int p_id) override;

	/// Sets the vertical extent an entity occupies.
	/// @param p_id The entity to change
	/// @param p_yBand The extent as (bottom, top)
	void set_y_band(int p_id, const Vector2 &p_yBand) { _entityYBand[p_id] = p_yBand; }

	/// Sets the hit groups an entity can be harmed by.
	/// @param p_id The entity to change
	/// @param p_hurtGroups Bitmask of the hit groups that may connect with it
	void set_hurt_groups(int p_id, int64_t p_hurtGroups) { _entityHurtGroups[p_id] = p_hurtGroups; }

	/// Sets the hit groups the hits of an entity carry.
	/// @param p_id The entity to change
	/// @param p_hitGroups Bitmask matched against the hurt groups of every target
	void set_hit_groups(int p_id, int64_t p_hitGroups) { _entityHitGroups[p_id] = p_hitGroups; }

	/// Sets the hurt groups that end a hit of this entity on the target they match.
	/// @param p_id The entity to change
	/// @param p_stopGroups Bitmask of the hurt groups that block its hits
	void set_stop_groups(int p_id, int64_t p_stopGroups) { _entityStopGroups[p_id] = p_stopGroups; }

	/// Sets the radius profile of an entity; null gives it a constant radius again.
	/// Entities sharing one curve share its slot, so profiles cost per archetype, not per entity.
	/// @param p_id The entity to change
	/// @param p_curve The profile to sample, or null
	void set_radius_curve(int p_id, const Ref<Curve> &p_curve);

	// ===== PUBLIC_HITS =====

	/// Hits every reachable target inside a circle, in no particular order.
	/// Stop groups need an order to be meaningful and are therefore not evaluated here.
	/// @return The impact positions as (x, y, height)
	PackedVector3Array hit_circle(int p_emitterId, const Vector2 &p_origin, double p_radius,
			const Vector2 &p_hitYBand, int p_maxHits, int p_preferredId, const Ref<Resource> &p_hitData);

	/// Hits every reachable target inside a circle, from the center outwards.
	/// @return The impact positions as (x, y, height), nearest first
	PackedVector3Array hit_circle_ordered(int p_emitterId, const Vector2 &p_origin, double p_radius,
			const Vector2 &p_hitYBand, int p_maxHits, int p_preferredId, const Ref<Resource> &p_hitData);

	/// Hits every reachable target inside a directional rect, in no particular order.
	/// @return The impact positions as (x, y, height)
	PackedVector3Array hit_directional_rect(int p_emitterId, const Vector2 &p_origin, const Vector2 &p_direction,
			double p_length, double p_width, const Vector2 &p_hitYBand, int p_maxHits, int p_preferredId,
			const Ref<Resource> &p_hitData);

	/// Hits every reachable target inside a directional rect, starting from one of its edges.
	/// @return The impact positions as (x, y, height), ordered from that edge
	PackedVector3Array hit_directional_rect_ordered(int p_emitterId, const Vector2 &p_origin, const Vector2 &p_direction,
			double p_length, double p_width, const Vector2 &p_hitYBand, int p_maxHits, int p_preferredId,
			const Ref<Resource> &p_hitData, int p_startEdge);

	/// Hits every reachable target inside a cake slice, in no particular order.
	/// @return The impact positions as (x, y, height)
	PackedVector3Array hit_cake_slice(int p_emitterId, const Vector2 &p_origin, const Vector2 &p_direction,
			double p_radius, double p_angle, const Vector2 &p_hitYBand, int p_maxHits, int p_preferredId,
			const Ref<Resource> &p_hitData);

	/// Hits every reachable target inside a cake slice, sweeping from its right edge to its left.
	/// @return The impact positions as (x, y, height), in sweep order
	PackedVector3Array hit_cake_slice_ordered(int p_emitterId, const Vector2 &p_origin, const Vector2 &p_direction,
			double p_radius, double p_angle, const Vector2 &p_hitYBand, int p_maxHits, int p_preferredId,
			const Ref<Resource> &p_hitData, bool p_reversed);

private:
	// ===== PRIVATE_VARIABLES =====

	/// Module management per entity id; receives every hit that connects with it.
	std::vector<Ref<RefCounted>> _entityModules;

	/// Vertical extent per entity as (bottom, top); the third axis next to the 2D position.
	std::vector<Vector2> _entityYBand;

	/// Bitmask of the hit groups an entity can be harmed by.
	std::vector<int64_t> _entityHurtGroups;

	/// Bitmask of the hit groups the hits of an entity carry.
	std::vector<int64_t> _entityHitGroups;

	/// Bitmask of the hurt groups that end a hit of this entity on the target they match.
	std::vector<int64_t> _entityStopGroups;

	/// Curve slot per entity, or C_HitServer::NO_CURVE while its radius is constant.
	std::vector<int32_t> _entityCurveIndex;

	/// Hit query that last looked at an entity; turns the candidate dedup into one compare.
	std::vector<int32_t> _entityVisitStamp;

	/// Curve stored in every slot; kept only to recognise it again and to free the slot.
	std::vector<Ref<Curve>> _radiiCurves;

	/// Every curve slot baked into C_HitServer::CURVE_SAMPLE_COUNT samples, one block per slot.
	std::vector<double> _curveSamples;

	/// Slot every stored curve sits in, so one archetype never fills more than one slot.
	std::unordered_map<uint64_t, int32_t> _curveSlotOf;

	/// Entities using each curve slot; the slot returns to the free list when it drops to zero.
	std::vector<int32_t> _curveUsers;

	/// Curve slots of dropped profiles, ready to be handed out again.
	std::vector<int32_t> _freeCurveIndices;

	/// Set once a preferred target was passed with a hit limit other than one.
	bool _warnedPreferredMisuse = false;

	// ===== BUFFER_VARIABLES =====
	// Reused across hits and only ever grown, so a hit allocates nothing once the buffers are warm.

	/// Candidates of the running hit, live up to _candidateCount.
	std::vector<int32_t> _candidateIds;

	/// How many candidates of _candidateIds belong to the running hit.
	int _candidateCount = 0;

	/// Targets the shape accepted, live up to _hitCount.
	std::vector<int32_t> _hitIds;

	/// Sort key of every accepted target, parallel to _hitIds.
	std::vector<double> _hitKeys;

	/// Impact position of every accepted target, parallel to _hitIds.
	std::vector<Vector3> _hitPositions;

	/// How many targets of the hit buffers belong to the running hit.
	int _hitCount = 0;

	/// Indices into the hit buffers in the order an ordered hit applies them.
	std::vector<int32_t> _hitOrder;

	/// Counter handed to every gather, so stamps of earlier hits can never collide.
	int32_t _visitStamp = 0;

	// ===== PRIVATE_SHAPES =====

	/// Runs a circle hit against the preferred target first and the chunks of its area second.
	PackedVector3Array _resolve_circle(int p_emitterId, const Vector2 &p_origin, double p_radius,
			const Vector2 &p_hitYBand, int p_maxHits, int p_preferredId, const Ref<Resource> &p_hitData, bool p_ordered);

	/// Keeps the gathered candidates whose silhouette reaches into the circle.
	PackedVector3Array _test_circle(int p_emitterId, const Vector2 &p_origin, double p_radius,
			const Vector2 &p_hitYBand, int p_maxHits, const Ref<Resource> &p_hitData, bool p_ordered);

	/// Runs a rect hit against the preferred target first and the chunks of its area second.
	PackedVector3Array _resolve_directional_rect(int p_emitterId, const Vector2 &p_origin, const Vector2 &p_direction,
			double p_length, double p_width, const Vector2 &p_hitYBand, int p_maxHits, int p_preferredId,
			const Ref<Resource> &p_hitData, bool p_ordered, int p_startEdge);

	/// Keeps the gathered candidates whose silhouette reaches into the rect.
	PackedVector3Array _test_directional_rect(int p_emitterId, const Vector2 &p_origin, const Vector2 &p_direction,
			double p_length, double p_width, const Vector2 &p_hitYBand, int p_maxHits,
			const Ref<Resource> &p_hitData, bool p_ordered, int p_startEdge);

	/// Runs a slice hit against the preferred target first and the chunks of its area second.
	PackedVector3Array _resolve_cake_slice(int p_emitterId, const Vector2 &p_origin, const Vector2 &p_direction,
			double p_radius, double p_angle, const Vector2 &p_hitYBand, int p_maxHits, int p_preferredId,
			const Ref<Resource> &p_hitData, bool p_ordered, bool p_reversed);

	/// Keeps the gathered candidates whose silhouette reaches into the slice.
	PackedVector3Array _test_cake_slice(int p_emitterId, const Vector2 &p_origin, const Vector2 &p_direction,
			double p_radius, double p_angle, const Vector2 &p_hitYBand, int p_maxHits,
			const Ref<Resource> &p_hitData, bool p_ordered, bool p_reversed);

	// ===== PRIVATE_METHODS =====

	/// Takes a free curve slot or appends one, and remembers which curve sits in it.
	/// @param p_curve The profile to store
	/// @return The slot the curve was stored in
	int _acquire_curve_slot(const Ref<Curve> &p_curve);

	/// Reads a curve into the flat sample block of its slot, once when the slot is taken.
	/// @param p_curveIndex The slot to fill
	/// @param p_curve The profile to read
	void _bake_curve_samples(int p_curveIndex, const Ref<Curve> &p_curve);

	/// Gives the curve slot of an entity back, and frees the slot once nobody uses it.
	/// @param p_id The entity whose profile is dropped
	void _release_curve(int p_id);

	/// Records one candidate in the reused buffer, growing it only when it is full.
	/// @param p_id The entity worth testing against the shape
	void _push_candidate(int p_id);

	/// Records one accepted target in the reused hit buffers.
	/// @param p_id The target the shape accepted
	/// @param p_key Its sort key
	/// @param p_position Its impact position as (x, y, height)
	void _push_hit(int p_id, double p_key, const Vector3 &p_position);

	/// Collects every entity of another team that a hit in this area could reach.
	/// Skips empty columns and chunks, and stamps every entity so one is gathered exactly once.
	void _gather_chunk_candidates(int p_emitterId, const Vector2 &p_minCorner, const Vector2 &p_maxCorner,
			const Vector2 &p_hitYBand);

	/// Puts the preferred target into the candidate buffer as the only entry.
	/// @return true if the preferred target is worth testing on its own
	bool _gather_preferred_candidate(int p_emitterId, int p_preferredId, int p_maxHits, const Vector2 &p_hitYBand);

	/// Checks everything about a target that does not depend on the hit shape.
	/// @return true if only the geometry is left to decide
	bool _can_be_hit(int p_emitterId, int p_targetId, const Vector2 &p_hitYBand) const;

	/// Picks the height a hit is measured at: the middle of the hit band, held inside the target.
	/// @return The height on the target the hit lands at
	double _get_sample_height(int p_id, const Vector2 &p_hitYBand) const;

	/// Reads the radius a target offers at one height from the baked samples of its profile.
	/// @return The radius that counts for this hit
	double _get_effective_radius(int p_id, double p_sampleHeight) const;

	/// Places the impact on the silhouette of the target, facing the origin of the hit.
	/// @return The impact as (x, y, height)
	Vector3 _get_impact_position(int p_id, double p_radius, double p_height, const Vector2 &p_origin) const;

	/// Checks a target against the opening angle and the two straight edges of a slice.
	/// @return true if the target reaches into the slice
	static bool _touches_slice(const Vector2 &p_position, double p_radius, double p_signedAngle, double p_halfAngle,
			const Vector2 &p_origin, const Vector2 &p_rightEdge, const Vector2 &p_leftEdge);

	/// Turns the position inside a rect into the sort key of the chosen start edge.
	/// @return The key to sort ascending by
	static double _get_rect_key(int p_startEdge, double p_along, double p_across, double p_length);

	/// Orders the hits, cuts them at the stop group and the hit limit, and hands them to their modules.
	/// Dispatching after the walk keeps a module free to remove its entity while it takes the hit.
	/// @return The impact positions of the hits that landed
	PackedVector3Array _apply_hits(int p_emitterId, int p_maxHits, const Ref<Resource> &p_hitData, bool p_ordered);

	/// Hands one hit to the module management of its target, if the target has one.
	/// @param p_id The entity that was hit
	/// @param p_hitData The payload of the hit
	void _dispatch_hit(int p_id, const Ref<Resource> &p_hitData);

	/// Finds the hit with the smallest key, for ordered hits that land exactly once.
	/// @return The index of the first hit in key order
	int _get_nearest_hit() const;

	/// Fills _hitOrder with the hit indices sorted ascending by key.
	void _build_hit_order();
};

} // namespace godot
