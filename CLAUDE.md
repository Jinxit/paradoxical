# Paradoxical

WoW addon for Midnight (12.0.5) that detects Spatial Paradox (Augmentation Evoker) and Innervate on healers, providing a full-screen edge glow indicator.

## Architecture

- **Constants.lua** — Healer spec IDs, Spatial Paradox heuristic parameters, Innervate config
- **Paradoxical.lua** — All runtime logic: detection, tracking, glow display, slash commands
- **embeds.xml** — Library embedding (LibStub, CallbackHandler, LibEQOL, LibSharedMedia)
- **Libs/** — Vendored dependencies (gitignored)

## Midnight Restrictions

Under 12.0.5 instanced content, addon API returns SECRET values for spell IDs, names, durations, icons, and source units. The following still work:

- `C_UnitAuras.IsAuraFilteredOutByInstanceID(unit, id, filter)` — AllowedWhenTainted, returns real booleans for aura classification
- `C_UnitAuras.GetAuraDuration(unit, id)` — Returns a DurationObject (opaque, engine-driven)
- `UNIT_SPELLCAST_SUCCEEDED` — Fires with real spell IDs for the local player's own casts

## Spatial Paradox Detection

Heuristic pipeline with zero false positives as the hard constraint:

1. **Profile matching** — Aura must be: HELPFUL, NOT PLAYER (self-cast), NOT RAID, NOT IMPORTANT, NOT EXTERNAL_DEFENSIVE, NOT BIG_DEFENSIVE, has a DurationObject
2. **Spell ID gate** — If spellId is readable (non-SECRET), must equal 406732. Rejects known non-SP buffs like Prescience. Under restrictions, SP's ID is SECRET so this check is skipped.
3. **Multi-buff rejection** — Multiple matching buffs in one event = group-wide (Ebon Might), not SP
4. **Split-event detection** — Second single buff arriving within correlation window of a pending candidate rejects both
5. **Deferred confirmation** — Candidate stored, evaluated after 0.5s correlation window:
   - Must correlate with Evoker receiving a matching buff (within 0.5s)
   - Must NOT correlate with other party members receiving matching buffs (group-wide rejection)
6. **Duration safety cap** — If tracking outlives MAX_DURATION (12s), cancelled as false positive

Note: Also detects Rescue (same Evoker-targeted fingerprint, ~3s duration). This is intentional.

## Innervate Detection

Simple: `UNIT_SPELLCAST_SUCCEEDED` on player for spell ID 29166. Fixed 8-second timer. No heuristic needed since the player's own cast events are always readable.

## Visual Feedback

Full-screen edge glow using `Interface\FullScreenTextures\LowHealth` (desaturated, ADD blend, double-layered):
- **Yellow** (1.0, 0.82, 0.0) — Spatial Paradox
- **Blue** (0.0, 0.82, 1.0) — Innervate
- Both can be active simultaneously

## Slash Commands

- `/paradox debug` — Toggle debug mode (forces restrictions via CVars, bypasses healer gate, logs all auras)
- `/paradox test paradox` — Toggle yellow glow
- `/paradox test innervate` — Toggle blue glow

## Key Decisions

- **Zero false positives over detection speed.** The 0.5s deferred confirmation window is acceptable; false alerts are not.
- **No OnUpdate polling.** SP glow is driven by aura add/remove events. Innervate uses a one-shot C_Timer.
- **PLAYER filter is the strongest discriminator.** Self-cast buffs are tagged PLAYER under restrictions. External buffs (SP from Evoker) are not. This single check eliminates most false positive sources.
- **isFromPlayerOrPlayerPet is unreliable.** Always returns true under restrictions for all party-sourced buffs. Not used for filtering.
