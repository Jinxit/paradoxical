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
-- Spatial Paradox
------------------------------------------------------------
addonTable.SPATIAL_PARADOX = {
    -- 406732 is the Evoker's cast spell. 406789 is the 10-second aura
    -- applied to the healer, which is the one AuraContainer must track.
    SPELL_ID = 406789,
}

------------------------------------------------------------
-- Innervate Tracking
------------------------------------------------------------
addonTable.INNERVATE = {
    SPELL_ID = 29166,
}

------------------------------------------------------------
-- Defaults
------------------------------------------------------------
addonTable.defaults = {}
