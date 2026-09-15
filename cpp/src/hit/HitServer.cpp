#include "hit/HitServer.h"

#include <godot_cpp/classes/geometry2d.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <algorithm>
#include <cmath>

using namespace godot;

namespace {
constexpr int COLUMNS = C_ChunkingServer::MAP_CHUNK_COLUMNS;
constexpr int NO_SLOT = C_ChunkingServer::NO_SLOT;
constexpr int NO_CURVE = C_HitServer::NO_CURVE;
constexpr int SAMPLES = C_HitServer::CURVE_SAMPLE_COUNT;
} // namespace

void HitServer::_bind_methods() {
	ClassDB::bind_method(D_METHOD("register_entity", "id", "module", "hitProfile"), &HitServer::register_entity);
	ClassDB::bind_method(D_METHOD("set_y_band", "id", "yBand"), &HitServer::set_y_band);
	ClassDB::bind_method(D_METHOD("set_hurt_groups", "id", "hurtGroups"), &HitServer::set_hurt_groups);
	ClassDB::bind_method(D_METHOD("set_hit_groups", "id", "hitGroups"), &HitServer::set_hit_groups);
	ClassDB::bind_method(D_METHOD("set_stop_groups", "id", "stopGroups"), &HitServer::set_stop_groups);
	ClassDB::bind_method(D_METHOD("set_radius_curve", "id", "curve"), &HitServer::set_radius_curve);
	ClassDB::bind_method(D_METHOD("hit_circle", "emitterId", "origin", "radius", "hitYBand", "maxHits", "preferredId", "hitData"), &HitServer::hit_circle);
	ClassDB::bind_method(D_METHOD("hit_circle_ordered", "emitterId", "origin", "radius", "hitYBand", "maxHits", "preferredId", "hitData"), &HitServer::hit_circle_ordered);
	ClassDB::bind_method(D_METHOD("hit_directional_rect", "emitterId", "origin", "direction", "length", "width", "hitYBand", "maxHits", "preferredId", "hitData"), &HitServer::hit_directional_rect);
	ClassDB::bind_method(D_METHOD("hit_directional_rect_ordered", "emitterId", "origin", "direction", "length", "width", "hitYBand", "maxHits", "preferredId", "hitData", "startEdge"), &HitServer::hit_directional_rect_ordered);
	ClassDB::bind_method(D_METHOD("hit_cake_slice", "emitterId", "origin", "direction", "radius", "angle", "hitYBand", "maxHits", "preferredId", "hitData"), &HitServer::hit_cake_slice);
	ClassDB::bind_method(D_METHOD("hit_cake_slice_ordered", "emitterId", "origin", "direction", "radius", "angle", "hitYBand", "maxHits", "preferredId", "hitData", "reversed"), &HitServer::hit_cake_slice_ordered);
}

// ===== PRIVATE_SLOTS =====

void HitServer::_append_slot() {
	_entityModules.push_back(Ref<RefCounted>());
	_entityYBand.push_back(Vector2());
	_entityHurtGroups.push_back(0);
	_entityHitGroups.push_back(0);
	_entityStopGroups.push_back(0);
	_entityCurveIndex.push_back(NO_CURVE);
	_entityVisitStamp.push_back(0);
}

void HitServer::_reset_slot(int p_id) {
	_entityModules[p_id] = Ref<RefCounted>();
	_entityYBand[p_id] = Vector2();
	_entityHurtGroups[p_id] = 0;
	_entityHitGroups[p_id] = 0;
	_entityStopGroups[p_id] = 0;
	_entityVisitStamp[p_id] = 0;
	_release_curve(p_id);
}

// ===== PUBLIC_METHODS =====

void HitServer::register_entity(int p_id, const Ref<RefCounted> &p_module, const Ref<Resource> &p_hitProfile) {
	ensure_slot(p_id);

	_entityModules[p_id] = p_module;

	if (p_hitProfile.is_null()) {
		UtilityFunctions::push_error("HitServer: entity ", p_id,
				" was registered without a hit profile, using the default one.");
		_entityYBand[p_id] = Vector2(0.0, 64.0);
		_entityHurtGroups[p_id] = 0;
		_entityHitGroups[p_id] = 0;
		_entityStopGroups[p_id] = 0;
		_release_curve(p_id);
		return;
	}

	_entityYBand[p_id] = p_hitProfile->get("yBand");
	_entityHurtGroups[p_id] = p_hitProfile->get("hurtGroups");
	_entityHitGroups[p_id] = p_hitProfile->get("hitGroups");
	_entityStopGroups[p_id] = p_hitProfile->get("stopGroups");

	set_radius_curve(p_id, p_hitProfile->get("radiusCurve"));
}

void HitServer::release_entity(int p_id) {
	_entityModules[p_id] = Ref<RefCounted>();
	_release_curve(p_id);
}

void HitServer::set_radius_curve(int p_id, const Ref<Curve> &p_curve) {
	if (p_curve.is_null()) {
		_release_curve(p_id);
		return;
	}

	const uint64_t l_key = p_curve->get_instance_id();
	const auto l_found = _curveSlotOf.find(l_key);
	int l_curveIndex = (l_found == _curveSlotOf.end()) ? NO_CURVE : l_found->second;

	if (l_curveIndex != NO_CURVE && l_curveIndex == _entityCurveIndex[p_id]) {
		return;
	}

	_release_curve(p_id);

	if (l_curveIndex == NO_CURVE) {
		l_curveIndex = _acquire_curve_slot(p_curve);
	}

	_curveUsers[l_curveIndex] += 1;
	_entityCurveIndex[p_id] = l_curveIndex;
}

// ===== PUBLIC_HITS =====

PackedVector3Array HitServer::hit_circle(int p_emitterId, const Vector2 &p_origin, double p_radius,
		const Vector2 &p_hitYBand, int p_maxHits, int p_preferredId, const Ref<Resource> &p_hitData) {
	return _resolve_circle(p_emitterId, p_origin, p_radius, p_hitYBand, p_maxHits, p_preferredId, p_hitData, false);
}

PackedVector3Array HitServer::hit_circle_ordered(int p_emitterId, const Vector2 &p_origin, double p_radius,
		const Vector2 &p_hitYBand, int p_maxHits, int p_preferredId, const Ref<Resource> &p_hitData) {
	return _resolve_circle(p_emitterId, p_origin, p_radius, p_hitYBand, p_maxHits, p_preferredId, p_hitData, true);
}

PackedVector3Array HitServer::hit_directional_rect(int p_emitterId, const Vector2 &p_origin, const Vector2 &p_direction,
		double p_length, double p_width, const Vector2 &p_hitYBand, int p_maxHits, int p_preferredId,
		const Ref<Resource> &p_hitData) {
	return _resolve_directional_rect(p_emitterId, p_origin, p_direction, p_length, p_width, p_hitYBand,
			p_maxHits, p_preferredId, p_hitData, false, C_HitServer::RECT_EDGE_BACK);
}

PackedVector3Array HitServer::hit_directional_rect_ordered(int p_emitterId, const Vector2 &p_origin, const Vector2 &p_direction,
		double p_length, double p_width, const Vector2 &p_hitYBand, int p_maxHits, int p_preferredId,
		const Ref<Resource> &p_hitData, int p_startEdge) {
	return _resolve_directional_rect(p_emitterId, p_origin, p_direction, p_length, p_width, p_hitYBand,
			p_maxHits, p_preferredId, p_hitData, true, p_startEdge);
}

PackedVector3Array HitServer::hit_cake_slice(int p_emitterId, const Vector2 &p_origin, const Vector2 &p_direction,
		double p_radius, double p_angle, const Vector2 &p_hitYBand, int p_maxHits, int p_preferredId,
		const Ref<Resource> &p_hitData) {
	return _resolve_cake_slice(p_emitterId, p_origin, p_direction, p_radius, p_angle, p_hitYBand,
			p_maxHits, p_preferredId, p_hitData, false, false);
}

PackedVector3Array HitServer::hit_cake_slice_ordered(int p_emitterId, const Vector2 &p_origin, const Vector2 &p_direction,
		double p_radius, double p_angle, const Vector2 &p_hitYBand, int p_maxHits, int p_preferredId,
		const Ref<Resource> &p_hitData, bool p_reversed) {
	return _resolve_cake_slice(p_emitterId, p_origin, p_direction, p_radius, p_angle, p_hitYBand,
			p_maxHits, p_preferredId, p_hitData, true, p_reversed);
}

// ===== PRIVATE_SHAPES =====

PackedVector3Array HitServer::_resolve_circle(int p_emitterId, const Vector2 &p_origin, double p_radius,
		const Vector2 &p_hitYBand, int p_maxHits, int p_preferredId, const Ref<Resource> &p_hitData, bool p_ordered) {
	if (_gather_preferred_candidate(p_emitterId, p_preferredId, p_maxHits, p_hitYBand)) {
		const PackedVector3Array l_preferredResult = _test_circle(p_emitterId, p_origin, p_radius,
				p_hitYBand, p_maxHits, p_hitData, p_ordered);

		if (!l_preferredResult.is_empty()) {
			return l_preferredResult;
		}
	}

	const Vector2 l_extent(p_radius, p_radius);
	_gather_chunk_candidates(p_emitterId, p_origin - l_extent, p_origin + l_extent, p_hitYBand);

	return _test_circle(p_emitterId, p_origin, p_radius, p_hitYBand, p_maxHits, p_hitData, p_ordered);
}

PackedVector3Array HitServer::_test_circle(int p_emitterId, const Vector2 &p_origin, double p_radius,
		const Vector2 &p_hitYBand, int p_maxHits, const Ref<Resource> &p_hitData, bool p_ordered) {
	_hitCount = 0;

	const std::vector<Vector2> &l_positions = _chunking->entityPosition;

	for (int l_slot = 0; l_slot < _candidateCount; ++l_slot) {
		const int l_id = _candidateIds[l_slot];
		const double l_height = _get_sample_height(l_id, p_hitYBand);
		const double l_radius = _get_effective_radius(l_id, l_height);
		const double l_distanceSquared = l_positions[l_id].distance_squared_to(p_origin);
		const double l_reach = p_radius + l_radius;

		if (l_distanceSquared > l_reach * l_reach) {
			continue;
		}

		_push_hit(l_id, l_distanceSquared, _get_impact_position(l_id, l_radius, l_height, p_origin));
	}

	return _apply_hits(p_emitterId, p_maxHits, p_hitData, p_ordered);
}

PackedVector3Array HitServer::_resolve_directional_rect(int p_emitterId, const Vector2 &p_origin, const Vector2 &p_direction,
		double p_length, double p_width, const Vector2 &p_hitYBand, int p_maxHits, int p_preferredId,
		const Ref<Resource> &p_hitData, bool p_ordered, int p_startEdge) {
	if (_gather_preferred_candidate(p_emitterId, p_preferredId, p_maxHits, p_hitYBand)) {
		const PackedVector3Array l_preferredResult = _test_directional_rect(p_emitterId, p_origin, p_direction,
				p_length, p_width, p_hitYBand, p_maxHits, p_hitData, p_ordered, p_startEdge);

		if (!l_preferredResult.is_empty()) {
			return l_preferredResult;
		}
	}

	const Vector2 l_forward = p_direction.normalized();
	const Vector2 l_sideStep = l_forward.orthogonal() * p_width * 0.5;
	const Vector2 l_cornerA = p_origin + l_sideStep;
	const Vector2 l_cornerB = p_origin - l_sideStep;
	const Vector2 l_cornerC = l_cornerA + l_forward * p_length;
	const Vector2 l_cornerD = l_cornerB + l_forward * p_length;

	_gather_chunk_candidates(p_emitterId,
			l_cornerA.min(l_cornerB).min(l_cornerC).min(l_cornerD),
			l_cornerA.max(l_cornerB).max(l_cornerC).max(l_cornerD),
			p_hitYBand);

	return _test_directional_rect(p_emitterId, p_origin, p_direction, p_length, p_width,
			p_hitYBand, p_maxHits, p_hitData, p_ordered, p_startEdge);
}

PackedVector3Array HitServer::_test_directional_rect(int p_emitterId, const Vector2 &p_origin, const Vector2 &p_direction,
		double p_length, double p_width, const Vector2 &p_hitYBand, int p_maxHits,
		const Ref<Resource> &p_hitData, bool p_ordered, int p_startEdge) {
	_hitCount = 0;

	const std::vector<Vector2> &l_positions = _chunking->entityPosition;
	const Vector2 l_forward = p_direction.normalized();
	const Vector2 l_side = -l_forward.orthogonal();
	const double l_halfWidth = p_width * 0.5;

	for (int l_slot = 0; l_slot < _candidateCount; ++l_slot) {
		const int l_id = _candidateIds[l_slot];
		const double l_height = _get_sample_height(l_id, p_hitYBand);
		const double l_radius = _get_effective_radius(l_id, l_height);
		const Vector2 l_toTarget = l_positions[l_id] - p_origin;
		const double l_along = l_toTarget.dot(l_forward);
		const double l_across = l_toTarget.dot(l_side);
		const double l_gapAlong = l_along - std::clamp(l_along, 0.0, p_length);
		const double l_gapAcross = l_across - std::clamp(l_across, -l_halfWidth, l_halfWidth);

		if (l_gapAlong * l_gapAlong + l_gapAcross * l_gapAcross > l_radius * l_radius) {
			continue;
		}

		_push_hit(l_id, _get_rect_key(p_startEdge, l_along, l_across, p_length),
				_get_impact_position(l_id, l_radius, l_height, p_origin));
	}

	return _apply_hits(p_emitterId, p_maxHits, p_hitData, p_ordered);
}

PackedVector3Array HitServer::_resolve_cake_slice(int p_emitterId, const Vector2 &p_origin, const Vector2 &p_direction,
		double p_radius, double p_angle, const Vector2 &p_hitYBand, int p_maxHits, int p_preferredId,
		const Ref<Resource> &p_hitData, bool p_ordered, bool p_reversed) {
	if (_gather_preferred_candidate(p_emitterId, p_preferredId, p_maxHits, p_hitYBand)) {
		const PackedVector3Array l_preferredResult = _test_cake_slice(p_emitterId, p_origin, p_direction,
				p_radius, p_angle, p_hitYBand, p_maxHits, p_hitData, p_ordered, p_reversed);

		if (!l_preferredResult.is_empty()) {
			return l_preferredResult;
		}
	}

	const Vector2 l_extent(p_radius, p_radius);
	_gather_chunk_candidates(p_emitterId, p_origin - l_extent, p_origin + l_extent, p_hitYBand);

	return _test_cake_slice(p_emitterId, p_origin, p_direction, p_radius, p_angle,
			p_hitYBand, p_maxHits, p_hitData, p_ordered, p_reversed);
}

PackedVector3Array HitServer::_test_cake_slice(int p_emitterId, const Vector2 &p_origin, const Vector2 &p_direction,
		double p_radius, double p_angle, const Vector2 &p_hitYBand, int p_maxHits,
		const Ref<Resource> &p_hitData, bool p_ordered, bool p_reversed) {
	_hitCount = 0;

	const std::vector<Vector2> &l_positions = _chunking->entityPosition;
	const Vector2 l_forward = p_direction.normalized();
	const double l_halfAngle = p_angle * 0.5;
	const Vector2 l_rightEdge = p_origin + l_forward.rotated(l_halfAngle) * p_radius;
	const Vector2 l_leftEdge = p_origin + l_forward.rotated(-l_halfAngle) * p_radius;

	for (int l_slot = 0; l_slot < _candidateCount; ++l_slot) {
		const int l_id = _candidateIds[l_slot];
		const double l_height = _get_sample_height(l_id, p_hitYBand);
		const double l_radius = _get_effective_radius(l_id, l_height);
		const Vector2 l_position = l_positions[l_id];
		const Vector2 l_toTarget = l_position - p_origin;
		const double l_reach = p_radius + l_radius;

		if (l_toTarget.length_squared() > l_reach * l_reach) {
			continue;
		}

		const double l_signedAngle = l_forward.angle_to(l_toTarget);
		if (!_touches_slice(l_position, l_radius, l_signedAngle, l_halfAngle, p_origin, l_rightEdge, l_leftEdge)) {
			continue;
		}

		_push_hit(l_id, p_reversed ? l_signedAngle : -l_signedAngle,
				_get_impact_position(l_id, l_radius, l_height, p_origin));
	}

	return _apply_hits(p_emitterId, p_maxHits, p_hitData, p_ordered);
}

// ===== PRIVATE_METHODS =====

int HitServer::_acquire_curve_slot(const Ref<Curve> &p_curve) {
	p_curve->bake();

	int l_curveIndex = 0;

	if (!_freeCurveIndices.empty()) {
		l_curveIndex = _freeCurveIndices.back();
		_freeCurveIndices.pop_back();
		_radiiCurves[l_curveIndex] = p_curve;
	} else {
		l_curveIndex = static_cast<int>(_radiiCurves.size());
		_radiiCurves.push_back(p_curve);
		_curveUsers.push_back(0);
		_curveSamples.resize(_radiiCurves.size() * SAMPLES);
	}

	_curveUsers[l_curveIndex] = 0;
	_curveSlotOf[p_curve->get_instance_id()] = l_curveIndex;
	_bake_curve_samples(l_curveIndex, p_curve);

	return l_curveIndex;
}

void HitServer::_bake_curve_samples(int p_curveIndex, const Ref<Curve> &p_curve) {
	const int l_base = p_curveIndex * SAMPLES;
	const double l_lastSample = SAMPLES - 1;

	for (int l_sample = 0; l_sample < SAMPLES; ++l_sample) {
		const double l_percent = l_sample / l_lastSample * C_HitServer::CURVE_PERCENT_MAX;
		_curveSamples[l_base + l_sample] = p_curve->sample_baked(l_percent);
	}
}

void HitServer::_release_curve(int p_id) {
	const int l_curveIndex = _entityCurveIndex[p_id];

	if (l_curveIndex == NO_CURVE) {
		return;
	}

	_entityCurveIndex[p_id] = NO_CURVE;
	_curveUsers[l_curveIndex] -= 1;

	if (_curveUsers[l_curveIndex] > 0) {
		return;
	}

	if (_radiiCurves[l_curveIndex].is_valid()) {
		_curveSlotOf.erase(_radiiCurves[l_curveIndex]->get_instance_id());
	}

	_radiiCurves[l_curveIndex] = Ref<Curve>();
	_freeCurveIndices.push_back(l_curveIndex);
}

void HitServer::_push_candidate(int p_id) {
	if (_candidateCount == static_cast<int>(_candidateIds.size())) {
		_candidateIds.resize(std::max(_candidateCount * 2, C_HitServer::BUFFER_MIN_CAPACITY));
	}

	_candidateIds[_candidateCount] = p_id;
	++_candidateCount;
}

void HitServer::_push_hit(int p_id, double p_key, const Vector3 &p_position) {
	if (_hitCount == static_cast<int>(_hitIds.size())) {
		const size_t l_capacity = static_cast<size_t>(std::max(_hitCount * 2, C_HitServer::BUFFER_MIN_CAPACITY));
		_hitIds.resize(l_capacity);
		_hitKeys.resize(l_capacity);
		_hitPositions.resize(l_capacity);
	}

	_hitIds[_hitCount] = p_id;
	_hitKeys[_hitCount] = p_key;
	_hitPositions[_hitCount] = p_position;
	++_hitCount;
}

void HitServer::_gather_chunk_candidates(int p_emitterId, const Vector2 &p_minCorner, const Vector2 &p_maxCorner,
		const Vector2 &p_hitYBand) {
	_candidateCount = 0;
	++_visitStamp;

	const Vector4i l_area = _chunking->compute_chunk_area_from_bounds(p_minCorner, p_maxCorner);
	const int l_emitterTeam = _chunking->entityTeam[p_emitterId];
	const int32_t l_stamp = _visitStamp;

	for (int l_column = l_area.x; l_column <= l_area.z; ++l_column) {
		if (!_chunking->has_opponent_in_column(l_column, l_emitterTeam)) {
			continue;
		}

		for (int l_row = l_area.y; l_row <= l_area.w; ++l_row) {
			const int l_chunkId = l_row * COLUMNS + l_column;

			if (!_chunking->has_opponent_in_chunk(l_chunkId, l_emitterTeam)) {
				continue;
			}

			int l_slot = _chunking->chunkHead[l_chunkId];
			while (l_slot != NO_SLOT) {
				const int l_id = _chunking->slotEntity[l_slot];
				l_slot = _chunking->slotChunkNext[l_slot];

				if (_entityVisitStamp[l_id] == l_stamp) {
					continue;
				}

				_entityVisitStamp[l_id] = l_stamp;

				if (_can_be_hit(p_emitterId, l_id, p_hitYBand)) {
					_push_candidate(l_id);
				}
			}
		}
	}
}

bool HitServer::_gather_preferred_candidate(int p_emitterId, int p_preferredId, int p_maxHits, const Vector2 &p_hitYBand) {
	_candidateCount = 0;

	if (p_preferredId == C_HitServer::NO_PREFERRED_TARGET) {
		return false;
	}

	if (p_maxHits != 1) {
		if (!_warnedPreferredMisuse) {
			_warnedPreferredMisuse = true;
			UtilityFunctions::push_warning("HitServer: a preferred target is only used when p_maxHits is 1, ignoring it.");
		}

		return false;
	}

	if (!_can_be_hit(p_emitterId, p_preferredId, p_hitYBand)) {
		return false;
	}

	_push_candidate(p_preferredId);
	return true;
}

bool HitServer::_can_be_hit(int p_emitterId, int p_targetId, const Vector2 &p_hitYBand) const {
	if (_chunking->entityTeam[p_targetId] == _chunking->entityTeam[p_emitterId]) {
		return false;
	}

	if (_chunking->entityPreUnregistered[p_targetId] == 1 || _chunking->entityUnregistering[p_targetId] == 1) {
		return false;
	}

	if ((_entityHitGroups[p_emitterId] & _entityHurtGroups[p_targetId]) == 0) {
		return false;
	}

	const Vector2 l_band = _entityYBand[p_targetId];
	return p_hitYBand.x <= l_band.y && p_hitYBand.y >= l_band.x;
}

double HitServer::_get_sample_height(int p_id, const Vector2 &p_hitYBand) const {
	const Vector2 l_band = _entityYBand[p_id];
	return std::clamp((p_hitYBand.x + p_hitYBand.y) * 0.5, static_cast<double>(l_band.x), static_cast<double>(l_band.y));
}

double HitServer::_get_effective_radius(int p_id, double p_sampleHeight) const {
	const double l_radius = _chunking->entityRadius[p_id];
	const int l_curveIndex = _entityCurveIndex[p_id];

	if (l_curveIndex == NO_CURVE) {
		return l_radius;
	}

	const Vector2 l_band = _entityYBand[p_id];
	const double l_height = l_band.y - l_band.x;

	if (l_height <= 0.0) {
		return l_radius;
	}

	constexpr int l_lastSample = SAMPLES - 1;
	const double l_position = std::clamp((p_sampleHeight - l_band.x) / l_height, 0.0, 1.0) * l_lastSample;
	const int l_sample = std::min(static_cast<int>(l_position), l_lastSample - 1);
	const int l_base = l_curveIndex * SAMPLES + l_sample;
	const double l_low = _curveSamples[l_base];
	const double l_percent = l_low + (_curveSamples[l_base + 1] - l_low) * (l_position - l_sample);

	return l_radius * l_percent / C_HitServer::CURVE_PERCENT_MAX;
}

Vector3 HitServer::_get_impact_position(int p_id, double p_radius, double p_height, const Vector2 &p_origin) const {
	const Vector2 l_position = _chunking->entityPosition[p_id];
	const Vector2 l_toOrigin = p_origin - l_position;
	const double l_distance = l_toOrigin.length();

	if (l_distance == 0.0) {
		return Vector3(l_position.x, l_position.y, p_height);
	}

	const Vector2 l_impact = l_position + l_toOrigin / l_distance * std::min(p_radius, l_distance);
	return Vector3(l_impact.x, l_impact.y, p_height);
}

bool HitServer::_touches_slice(const Vector2 &p_position, double p_radius, double p_signedAngle, double p_halfAngle,
		const Vector2 &p_origin, const Vector2 &p_rightEdge, const Vector2 &p_leftEdge) {
	if (std::abs(p_signedAngle) <= p_halfAngle) {
		return true;
	}

	const double l_radiusSquared = p_radius * p_radius;
	Geometry2D *l_geometry = Geometry2D::get_singleton();

	if (p_position.distance_squared_to(l_geometry->get_closest_point_to_segment(p_position, p_origin, p_rightEdge)) <= l_radiusSquared) {
		return true;
	}

	return p_position.distance_squared_to(l_geometry->get_closest_point_to_segment(p_position, p_origin, p_leftEdge)) <= l_radiusSquared;
}

double HitServer::_get_rect_key(int p_startEdge, double p_along, double p_across, double p_length) {
	switch (p_startEdge) {
		case C_HitServer::RECT_EDGE_FRONT:
			return p_length - p_along;
		case C_HitServer::RECT_EDGE_RIGHT:
			return -p_across;
		case C_HitServer::RECT_EDGE_LEFT:
			return p_across;
		default:
			return p_along;
	}
}

PackedVector3Array HitServer::_apply_hits(int p_emitterId, int p_maxHits, const Ref<Resource> &p_hitData, bool p_ordered) {
	PackedVector3Array l_result;
	int l_limit = _hitCount;

	if (p_maxHits != C_HitServer::UNLIMITED_HITS) {
		l_limit = std::min(p_maxHits, _hitCount);
	}

	if (l_limit <= 0) {
		return l_result;
	}

	if (p_ordered && l_limit == 1) {
		const int l_nearest = _get_nearest_hit();
		l_result.push_back(_hitPositions[l_nearest]);
		_dispatch_hit(_hitIds[l_nearest], p_hitData);

		return l_result;
	}

	if (!p_ordered) {
		for (int l_index = 0; l_index < l_limit; ++l_index) {
			l_result.push_back(_hitPositions[l_index]);
		}

		for (int l_index = 0; l_index < l_limit; ++l_index) {
			_dispatch_hit(_hitIds[l_index], p_hitData);
		}

		return l_result;
	}

	_build_hit_order();

	const int64_t l_stopGroups = _entityStopGroups[p_emitterId];
	int l_appliedCount = 0;

	while (l_appliedCount < l_limit) {
		const int l_index = _hitOrder[l_appliedCount];
		l_result.push_back(_hitPositions[l_index]);
		++l_appliedCount;

		if ((l_stopGroups & _entityHurtGroups[_hitIds[l_index]]) != 0) {
			break;
		}
	}

	for (int l_slot = 0; l_slot < l_appliedCount; ++l_slot) {
		_dispatch_hit(_hitIds[_hitOrder[l_slot]], p_hitData);
	}

	return l_result;
}

void HitServer::_dispatch_hit(int p_id, const Ref<Resource> &p_hitData) {
	const Ref<RefCounted> &l_module = _entityModules[p_id];

	if (l_module.is_valid()) {
		l_module->call("hit", p_hitData);
	}
}

int HitServer::_get_nearest_hit() const {
	int l_nearest = 0;

	for (int l_index = 1; l_index < _hitCount; ++l_index) {
		if (_hitKeys[l_index] < _hitKeys[l_nearest]) {
			l_nearest = l_index;
		}
	}

	return l_nearest;
}

void HitServer::_build_hit_order() {
	if (static_cast<int>(_hitOrder.size()) < _hitCount) {
		_hitOrder.resize(_hitCount);
	}

	for (int l_index = 0; l_index < _hitCount; ++l_index) {
		const double l_key = _hitKeys[l_index];
		int l_insertAt = l_index;

		while (l_insertAt > 0 && _hitKeys[_hitOrder[l_insertAt - 1]] > l_key) {
			_hitOrder[l_insertAt] = _hitOrder[l_insertAt - 1];
			--l_insertAt;
		}

		_hitOrder[l_insertAt] = l_index;
	}
}
