#include "servers/A_EntityServer.h"

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

void A_EntityServer::_bind_methods() {
	ClassDB::bind_method(D_METHOD("ensure_slot", "id"), &A_EntityServer::ensure_slot);
	ClassDB::bind_method(D_METHOD("release_entity", "id"), &A_EntityServer::release_entity);
	ClassDB::bind_method(D_METHOD("on_pre_unregister", "id"), &A_EntityServer::on_pre_unregister);
	ClassDB::bind_method(D_METHOD("on_unregister", "id"), &A_EntityServer::on_unregister);
}

// ===== PUBLIC_LIFECYCLE =====

void A_EntityServer::ensure_slot(int p_id) {
	if (p_id == _get_slot_count()) {
		_append_slot();
		return;
	}

	_reset_slot(p_id);
}
