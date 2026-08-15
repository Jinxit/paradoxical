# Paradoxical

WoW addon for Midnight 12.1 that alerts healers to Spatial Paradox and Innervate.

## Spatial Paradox

Spatial Paradox is tracked by a Blizzard-managed `AuraContainer`, not Lua aura inspection. The container watches `player` with a `HELPFUL` filter and an engine-side `includeSpellIDs` candidate filter for spell `406732`.

This is required for 12.1: `UNIT_AURA` data and APIs that enumerate or inspect auras by slot, index, or instance ID are secret in restricted content. The AuraContainer owns both matching and visibility, so the tracker stays exact without inferring the spell from unrelated aura metadata.

The AuraContainer button itself is one pixel and off-screen, but owns two full-screen `LowHealth` textures. Because the texture is a child of Blizzard's aura-managed button, it shows and hides exactly with Spatial Paradox without addon Lua receiving or inspecting the secret aura. `C_UnitAuras.AddAuraSound` plays the selected sound from the same engine-side aura application event. The sound selectors default to Causese's Paradox and Innervate clips when `SharedMedia_Causese` is installed; otherwise they default to None.

## Innervate

Innervate uses a second AuraContainer and `AddAuraSound` registration for spell `29166`, so it detects applications from any Druid rather than only the local player's casts. It uses the same blue edge glow.

## Files

| File | Purpose |
|---|---|
| `Constants.lua` | Healer specs and spell IDs |
| `Paradoxical.lua` | AuraContainer displays and engine-side aura-sound registration |
| `Settings.lua` | Sound selectors and preview buttons |
