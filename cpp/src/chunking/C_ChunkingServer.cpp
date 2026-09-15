#include "chunking/C_ChunkingServer.h"

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

void C_ChunkingServer::_bind_methods() {
	ClassDB::bind_static_method("C_ChunkingServer", D_METHOD("get_chunk_size"), &C_ChunkingServer::get_chunk_size);
	ClassDB::bind_static_method("C_ChunkingServer", D_METHOD("get_map_size"), &C_ChunkingServer::get_map_size);

	BIND_ENUM_CONSTANT(TEAM_ATTACKER);
	BIND_ENUM_CONSTANT(TEAM_DEFENDER);

	BIND_CONSTANT(CONFIGURED_CHUNK_COLUMNS);
	BIND_CONSTANT(CONFIGURED_CHUNK_ROWS);
	BIND_CONSTANT(NO_COLUMN);
	BIND_CONSTANT(NO_SLOT);
	BIND_CONSTANT(NO_ENTITY);
	BIND_CONSTANT(MAP_CHUNK_COLUMNS);
	BIND_CONSTANT(MAP_CHUNK_ROWS);
	BIND_CONSTANT(CHUNK_COUNT);
	BIND_CONSTANT(TEAM_COUNT);
}
