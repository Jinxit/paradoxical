local _, addonTable = ...

addonTable.LEM = LibStub("LibEQOLEditMode-1.0", true)

------------------------------------------------------------
-- Healer Spec IDs (addon enable gate)
------------------------------------------------------------
addonTable.HEALER_SPEC_IDS = {
    [256]  = true,  -- Discipline Priest
    [257]  = true,  -- Holy Priest
    [65]   = true,  -- Holy Paladin
    [105]  = true,  -- Restoration Druid
    [264]  = true,  -- Restoration Shaman
    [270]  = true,  -- Mistweaver Monk
    [1468] = true,  -- Preservation Evoker
}

------------------------------------------------------------
-- Spatial Paradox Heuristic Parameters
------------------------------------------------------------
addonTable.SPATIAL_PARADOX = {
    SPELL_ID = 406732,            -- Direct match (works outside instances, may be secret inside)
    BASE_DURATION = 10,           -- Base duration in seconds
    MIN_DURATION = 9.5,           -- Floor: base minus jitter
    MAX_DURATION = 12.0,          -- Ceiling: base + ~15% mastery + jitter
}

------------------------------------------------------------
-- Innervate Tracking
------------------------------------------------------------
addonTable.INNERVATE = {
    SPELL_ID = 29166,
    DURATION = 8,
}

------------------------------------------------------------
-- Defaults
------------------------------------------------------------
addonTable.defaults = {}
