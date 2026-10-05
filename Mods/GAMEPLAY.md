# Gameplay data mods

OpenSC imports gameplay data from the player's selected original game folder. It does not need a bundled copy of those tables. Imported data is cached in memory for the current session, with file hashes detecting changes; enabling or reordering mods applies fresh patches to the original base.

This provides the data foundation for economy, equipment, weapons and missions. Those gameplay systems are not implemented by this importer. New systems should consume `gameplay_catalogue.tables`, rather than introduce a second set of hardcoded original values. Unknown original fields remain available without claiming that their runtime meaning has been established.

Create a normal mod folder with a `mod.json` manifest:

```json
{
  "schema_version": 1,
  "id": "my-gameplay-mod",
  "name": "My gameplay mod",
  "version": "1.0",
  "assets": { "data.gameplay": "gameplay.json" }
}
```

In `gameplay.json`, supply only the records and fields you want to change:

```json
{
  "schema_version": 1,
  "tables": {
    "equipment": {
      "records": {
        "lights": { "Maximum": 2 }
      }
    },
    "equipment_prices.1": {
      "records": {
        "lights": { "Touka buy": 999 }
      }
    }
  }
}
```

These are example changes, not a recommended balance preset. Field names retain original spelling and case; record IDs are lowercase. Unspecified fields keep their original values. A new record ID adds a record; a `null` record removes it. Later enabled mods override fields changed by earlier mods. Arrays and nested field values are replaced as a whole. Invalid patch structure is rejected without partially applying it, and a warning appears in the existing mod diagnostics.

## Catalogue

The catalogue has `schema_version`, `provenance`, `tables` and `warnings`. Each table has a `source` and a `records` object, with stable record IDs. Duplicate original names use `~2`, `~3`, etc. Mission database IDs combine mission ID and story ID. Placement IDs use their original row index. Runtime pointers and unused matrix lanes are excluded.

| Table | Content |
|---|---|
| `objects` | Original object definitions and physical/combat values |
| `equipment`, `equipment_text` | Equipment/weapon catalogue and descriptions |
| `equipment_prices.1`, `.3`, `.4` | Available original city price tables; no missing stage table is invented |
| `economy_cities`, `economy_commodities`, `economy_timing` | City budgets, stock, production, price ranges, priorities and timing values |
| `commodity_text` | Commodity names, descriptions and illustration references |
| `mission_availability`, `mission_rewards` | Mission availability/bulletin records and reward values |
| `mission_requirements`, `mission_routes` | Equipment requirements and route lists (`items` arrays) |
| `campaign_stages` | Stage parameters, core and optional mission lists, preserving city-column order |
| `mission_text` | English mission sections, including responses and markup (`text` fields) |
| `database.*` | All original scenery database tables, including missions, story rules and city missions |
| `source_texts` | Decoded archive documents for inspection; changing these does not reparse derived tables |
| `weapon_tuning` | OpenSC weapon settings; `zapper` supports `range`, `damage_per_second`, `beam_width`, `animation_speed`, `volume_db` |
| `creature_stats` | Per-model `health`; original object shield values supply provisional starting health |

`database.objects` contains placements; `database.object_types` preserves the separate lowercase `objects` table. Database mission records include named callbacks and callback type numbers. These identify original code entry points; they do not contain the code implementing mission behaviour. Equipment `Default` quantities are retained as written and are not assumed to be the player's starting loadout.

The exact economy formulas, weapon behaviour and mission completion logic still require reconstruction. The English archive may differ from other language releases; missing input files produce explicit warnings rather than fabricated content.

The basic zapper now consumes `weapon_tuning/zapper`, and wildlife consumes `creature_stats/<model name>`. These defaults are provisional, not a recovered original damage formula. Local F1 weapon sliders override mod tuning when explicitly changed and are included in Export All. Lightning replacements use `texture.zapper1` through `texture.zapper3` (PNG replacements supply alpha), the model uses `model.electric`, and audio replacements use `audio.weapon.zapper` and `audio.creature.death`. The equipment record's optional `HUD Pic` field selects the cockpit icon (default `ELECTRIC.RAS`), independently of its original shop `Sq Pic`.

## Local extraction

Run the exporter with Godot (replace paths as appropriate):

```text
Godot --headless --path godot --script res://tools/export_original_data.gd -- "Original Sub Culture" "Extracted Original Data/catalogue.json"
```

Use absolute input/output paths for predictable results. Create the output directory first. Without arguments, the exporter uses the configured original game folder and writes to `user://original_gameplay_catalogue.json`. It exports the original base, without enabled mods.

Extracted files belong to the player's local installation. The project's `Extracted Original Data` directory is ignored by Git and sits outside the Godot resource directory. Do not include these generated files or copied original content in a release or a mod intended for distribution. Distribute the importer, schemas and independently authored mod patches instead. This data layer does not provide arbitrary executable scripting for mods yet.
