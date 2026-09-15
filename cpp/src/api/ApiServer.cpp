#include "api/ApiServer.h"

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

void ApiServer::_bind_methods() {
	ClassDB::bind_method(D_METHOD("create_entity", "position", "team", "module", "entityData"), &ApiServer::create_entity);
	ClassDB::bind_method(D_METHOD("pre_unregister_entity", "id"), &ApiServer::pre_unregister_entity);
	ClassDB::bind_method(D_METHOD("unregister_entity", "id"), &ApiServer::unregister_entity);
	ClassDB::bind_method(D_METHOD("release_removed_ids"), &ApiServer::release_removed_ids);
	ClassDB::bind_method(D_METHOD("set_position", "id", "position"), &ApiServer::set_position);
	ClassDB::bind_method(D_METHOD("set_radius", "id", "radius"), &ApiServer::set_radius);

	ClassDB::bind_method(D_METHOD("hit_circle", "emitterId", "origin", "radius", "hitYBand", "maxHits", "preferredId", "hitData"), &ApiServer::hit_circle);
	ClassDB::bind_method(D_METHOD("hit_circle_ordered", "emitterId", "origin", "radius", "hitYBand", "maxHits", "preferredId", "hitData"), &ApiServer::hit_circle_ordered);
	ClassDB::bind_method(D_METHOD("hit_directional_rect", "emitterId", "origin", "direction", "length", "width", "hitYBand", "maxHits", "preferredId", "hitData"), &ApiServer::hit_directional_rect);
	ClassDB::bind_method(D_METHOD("hit_directional_rect_ordered", "emitterId", "origin", "direction", "length", "width", "hitYBand", "maxHits", "preferredId", "hitData", "startEdge"), &ApiServer::hit_directional_rect_ordered);
	ClassDB::bind_method(D_METHOD("hit_cake_slice", "emitterId", "origin", "direction", "radius", "angle", "hitYBand", "maxHits", "preferredId", "hitData"), &ApiServer::hit_cake_slice);
	ClassDB::bind_method(D_METHOD("hit_cake_slice_ordered", "emitterId", "origin", "direction", "radius", "angle", "hitYBand", "maxHits", "preferredId", "hitData", "reversed"), &ApiServer::hit_cake_slice_ordered);

	ClassDB::bind_method(D_METHOD("update_entity", "id"), &ApiServer::update_entity);
	ClassDB::bind_method(D_METHOD("search_target", "id"), &ApiServer::search_target);
	ClassDB::bind_method(D_METHOD("get_target_position", "id"), &ApiServer::get_target_position);
	ClassDB::bind_method(D_METHOD("get_state", "id"), &ApiServer::get_state);
	ClassDB::bind_method(D_METHOD("get_target", "id"), &ApiServer::get_target);
	ClassDB::bind_method(D_METHOD("get_targeters", "id"), &ApiServer::get_targeters);
	ClassDB::bind_method(D_METHOD("drop_targeters", "id"), &ApiServer::drop_targeters);

	ClassDB::bind_method(D_METHOD("set_invisible", "id", "invisible"), &ApiServer::set_invisible);
	ClassDB::bind_method(D_METHOD("set_targets_invisible", "id", "enabled"), &ApiServer::set_targets_invisible);
	ClassDB::bind_method(D_METHOD("set_focused", "id", "enabled"), &ApiServer::set_focused);
	ClassDB::bind_method(D_METHOD("set_ignores_focus", "id", "enabled"), &ApiServer::set_ignores_focus);
	ClassDB::bind_method(D_METHOD("set_search_chunks", "id", "searchChunks"), &ApiServer::set_search_chunks);
	ClassDB::bind_method(D_METHOD("set_flee_chunks", "id", "fleeChunks"), &ApiServer::set_flee_chunks);
	ClassDB::bind_method(D_METHOD("set_hit_range", "id", "hitRange"), &ApiServer::set_hit_range);
	ClassDB::bind_method(D_METHOD("set_priority_targeted_groups", "id", "groups"), &ApiServer::set_priority_targeted_groups);
	ClassDB::bind_method(D_METHOD("set_y_band", "id", "yBand"), &ApiServer::set_y_band);
	ClassDB::bind_method(D_METHOD("set_hurt_groups", "id", "hurtGroups"), &ApiServer::set_hurt_groups);
	ClassDB::bind_method(D_METHOD("set_hit_groups", "id", "hitGroups"), &ApiServer::set_hit_groups);
	ClassDB::bind_method(D_METHOD("set_stop_groups", "id", "stopGroups"), &ApiServer::set_stop_groups);
	ClassDB::bind_method(D_METHOD("set_radius_curve", "id", "curve"), &ApiServer::set_radius_curve);
}

// ===== LIFECYCLE =====

ApiServer::ApiServer() {
	_chunking.instantiate();
	_hits.instantiate();
	_targeting.instantiate();

	_hits->setup(_chunking.ptr());
	_targeting->setup(_chunking.ptr());

	_servers.push_back(_hits.ptr());
	_servers.push_back(_targeting.ptr());
}

// ===== PUBLIC_LIFECYCLE =====

int ApiServer::create_entity(const Vector2 &p_position, int p_team, const Ref<RefCounted> &p_module,
		const Ref<Resource> &p_entityData) {
	ERR_FAIL_COND_V_MSG(p_entityData.is_null(), -1, "ApiServer: create_entity() needs an R_EntityData.");

	const double l_radius = p_entityData->get("radius");
	const int64_t l_groups = p_entityData->get("groups");

	const int l_id = _chunking->register_entity(p_position, l_radius, p_team, l_groups);

	_hits->register_entity(l_id, p_module, p_entityData->get("hitProfile"));
	_targeting->register_entity(l_id, p_entityData->get("targetingData"));

	return l_id;
}

void ApiServer::pre_unregister_entity(int p_id) {
	_chunking->pre_unregister_entity(p_id);

	for (A_EntityServer *l_server : _servers) {
		l_server->on_pre_unregister(p_id);
	}
}

void ApiServer::unregister_entity(int p_id) {
	if (_chunking->is_unregistering(p_id)) {
		return;
	}

	for (A_EntityServer *l_server : _servers) {
		l_server->on_unregister(p_id);
	}

	_chunking->unregister_entity(p_id);
}

void ApiServer::release_removed_ids() {
	const PackedInt32Array l_pending = _chunking->get_pending_free_ids();

	for (int64_t l_index = 0; l_index < l_pending.size(); ++l_index) {
		for (A_EntityServer *l_server : _servers) {
			l_server->release_entity(l_pending[l_index]);
		}
	}

	_chunking->release_removed_ids();
}
