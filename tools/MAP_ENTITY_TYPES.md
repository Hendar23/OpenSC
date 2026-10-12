# Editor types and placements

- **Object types** lists shared templates for salvage, mines, clams, rocks, gun turrets and smoke emitters.
- **Objects** lists placed objects and object population groups. The old Object groups category has been renamed.
- **NPC types** lists shared ground vehicle and civilian submarine templates. **NPCs** lists their map instances.
- Lights, scenery and wildlife retain their existing categories.

Types own model/behaviour tuning: durability, turret targeting and rotation, driving speed and stops, respawning, or smoke appearance. Instances own name, placement, faction, turret hostility, vehicle operating area and emitter enablement. Select **Edit shared type** from an instance to change every instance using that template.

Use **New object type** / **New NPC type** to create templates, and **Add object** / **Add NPC** to place one. Duplicating a type creates an independent variant. Duplicating an instance keeps its shared type reference. Referenced types cannot be deleted until their live instances are reassigned or removed.

## Storage and compatibility

Population templates continue to use `object_types` and `object_groups`. Authored machine/emitter templates use `entity_types`; ground vehicles and civilian submarines use `npc_types`. Entity records reference them through `entity_type` or `npc_type`. `map_entity_types.gd` resolves these definitions before validation and world application. Shared tuning on a referenced instance is rejected rather than silently overriding the template. The stored entity model is a compatibility hint; the template model takes precedence.

Old maps migrate when loaded. Identical shared settings are grouped; genuinely different tuning is preserved in named variants. Existing transforms and instance settings are retained. Undo/redo and JSON save/export retain template references. The native map now explicitly records the original turret and ground vehicle placements so editing a shared type affects all of them.

Validation: `verify_entity_types.gd`, `verify_turrets.gd`, `verify_ground_traffic.gd`, `verify_smoke.gd` and `verify_map_editor.gd` cover migration, shared edits, variants, per-instance properties, runtime configuration and save/load.
