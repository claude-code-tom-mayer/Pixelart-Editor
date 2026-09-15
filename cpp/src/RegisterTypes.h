#pragma once

#include <godot_cpp/core/class_db.hpp>

/// Registers every server class with Godot once the scene level comes up.
/// @param p_level The initialization level Godot is currently at
void initialize_entity_servers(godot::ModuleInitializationLevel p_level);

/// Tears the registration down again.
/// @param p_level The initialization level Godot is currently at
void uninitialize_entity_servers(godot::ModuleInitializationLevel p_level);
