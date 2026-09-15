#include "targeting/C_TargetingServer.h"

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

void C_TargetingServer::_bind_methods() {
	ClassDB::bind_static_method("C_TargetingServer", D_METHOD("get_team_base_x", "team"), &C_TargetingServer::get_team_base_x);
	ClassDB::bind_static_method("C_TargetingServer", D_METHOD("get_team_march_x", "team"), &C_TargetingServer::get_team_march_x);

	BIND_ENUM_CONSTANT(STATE_SEARCH);
	BIND_ENUM_CONSTANT(STATE_APPROACH);
	BIND_ENUM_CONSTANT(STATE_COMBAT);
	BIND_ENUM_CONSTANT(STATE_FLEE);

	BIND_CONSTANT(FLAG_INVISIBLE);
	BIND_CONSTANT(FLAG_TARGETS_INVISIBLE);
	BIND_CONSTANT(FLAG_HAS_FOCUS);
	BIND_CONSTANT(FLAG_IGNORES_FOCUS);
	BIND_CONSTANT(NO_TARGET);
}
