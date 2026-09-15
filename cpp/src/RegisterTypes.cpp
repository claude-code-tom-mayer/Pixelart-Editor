#include "RegisterTypes.h"

#include "api/ApiServer.h"
#include "chunking/C_ChunkingServer.h"
#include "chunking/ChunkingServer.h"
#include "hit/C_HitServer.h"
#include "hit/HitServer.h"
#include "servers/A_EntityServer.h"
#include "targeting/C_TargetingServer.h"
#include "targeting/TargetingServer.h"

#include <gdextension_interface.h>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

using namespace godot;

void initialize_entity_servers(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}

	// the constants classes are never instantiated, only read
	GDREGISTER_ABSTRACT_CLASS(C_ChunkingServer);
	GDREGISTER_ABSTRACT_CLASS(C_HitServer);
	GDREGISTER_ABSTRACT_CLASS(C_TargetingServer);

	GDREGISTER_CLASS(ChunkingServer);
	GDREGISTER_ABSTRACT_CLASS(A_EntityServer);
	GDREGISTER_CLASS(HitServer);
	GDREGISTER_CLASS(TargetingServer);
	GDREGISTER_CLASS(ApiServer);
}

void uninitialize_entity_servers(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
}

extern "C" {
/// Entry point named by EntityServers.gdextension.
GDExtensionBool GDE_EXPORT entity_servers_library_init(
		GDExtensionInterfaceGetProcAddress p_get_proc_address,
		const GDExtensionClassLibraryPtr p_library,
		GDExtensionInitialization *r_initialization) {
	godot::GDExtensionBinding::InitObject l_initObject(p_get_proc_address, p_library, r_initialization);

	l_initObject.register_initializer(initialize_entity_servers);
	l_initObject.register_terminator(uninitialize_entity_servers);
	l_initObject.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);

	return l_initObject.init();
}
}
