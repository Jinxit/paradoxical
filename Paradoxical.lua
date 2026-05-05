local addonName, addonTable = ...

local HEALER_SPECS = addonTable.HEALER_SPEC_IDS
local SP = addonTable.SPATIAL_PARADOX
local INN = addonTable.INNERVATE

------------------------------------------------------------
-- State
------------------------------------------------------------
local isHealer = false
local debugMode = false

-- Tracking
local trackedInstanceID = nil
local trackedStartTime = 0
local trackedDuration = SP.BASE_DURATION  -- for text estimate only; bar is DurationObject-driven

-- Evoker cache: updated on roster change
local evokerUnits = {}   -- unit -> true
local hasEvokers = false

-- Cross-reference: bidirectional correlation within a time window.
-- Either the Evoker fires first (player checks backwards) or
-- the player fires first (Evoker checks backwards and confirms).
local CORRELATION_WINDOW = 0.5
local evokerBuffTime = 0   -- most recent Evoker buff timestamp
local othersBuffTime = 0   -- most recent non-Evoker, non-player matching buff

-- Pending candidate: player buff that passed profile matching
-- but had no Evoker correlation yet. Evoker handler will confirm.
local pendingCandidate = nil  -- { instanceID, durationObj, time }

-- Innervate tracking
local innervateActive = false


------------------------------------------------------------
-- Debug Logging
------------------------------------------------------------
local function DebugPrint(...)
    if not debugMode then return end
    print("|cff55c0a8[Paradoxical]|r", ...)
end

local function SecretStr(value)
    if value == nil then return "|cff888888nil|r" end
    if issecretvalue and issecretvalue(value) then return "|cffff4444SECRET|r" end
    return tostring(value)
end

local function DebugDumpAura(unit, auraInstanceID)
    if not debugMode then return end

    local filters = {
        { "HELPFUL",                    "HELPFUL" },
        { "HARMFUL",                    "HARMFUL" },
        { "HELPFUL|PLAYER",             "PLAYER" },
        { "HELPFUL|RAID",               "RAID" },
        { "HELPFUL|CANCELABLE",         "CANCEL" },
        { "HELPFUL|NOT_CANCELABLE",     "NO_CANCEL" },
        { "HELPFUL|IMPORTANT",          "IMPORTANT" },
        { "HELPFUL|EXTERNAL_DEFENSIVE", "EXT_DEF" },
        { "HELPFUL|BIG_DEFENSIVE",      "BIG_DEF" },
        { "HELPFUL|SMALL_DEFENSIVE",    "SMALL_DEF" },
        { "HELPFUL|CROWD_CONTROL",      "CC" },
        { "HELPFUL|INCLUDE_NAME_PLATE_ONLY", "NAMEPLATE" },
    }

    local tags = {}
    for _, f in ipairs(filters) do
        local filtered = C_UnitAuras.IsAuraFilteredOutByInstanceID(unit, auraInstanceID, f[1])
        if not filtered then
            tags[#tags + 1] = "|cff00ff00" .. f[2] .. "|r"
        end
    end

    local tagStr = #tags > 0 and table.concat(tags, " ") or "|cff888888(none)|r"
    DebugPrint(string.format("  [%s] Aura ID %s — %s", unit, tostring(auraInstanceID), tagStr))

    local data = C_UnitAuras.GetAuraDataByAuraInstanceID(unit, auraInstanceID)
    if data then
        DebugPrint(string.format("  spellId=%s  name=%s  icon=%s",
            SecretStr(data.spellId), SecretStr(data.name), SecretStr(data.icon)))
        DebugPrint(string.format("  duration=%s  expirationTime=%s  sourceUnit=%s",
            SecretStr(data.duration), SecretStr(data.expirationTime), SecretStr(data.sourceUnit)))
        DebugPrint(string.format("  isFromPlayerOrPlayerPet=%s",
            SecretStr(data.isFromPlayerOrPlayerPet)))
    end

    local durationObj = C_UnitAuras.GetAuraDuration(unit, auraInstanceID)
    DebugPrint(string.format("  GetAuraDuration=%s", durationObj and "|cff00ff00exists|r" or "|cff888888nil|r"))
end

------------------------------------------------------------
-- Healer Spec Gate
------------------------------------------------------------
local function UpdateHealerState()
    local specIndex = GetSpecialization()
    if not specIndex then
        isHealer = false
        return
    end
    local specId = GetSpecializationInfo(specIndex)
    isHealer = specId ~= nil and HEALER_SPECS[specId] == true
end

------------------------------------------------------------
-- Evoker Cache
-- Rebuilt on GROUP_ROSTER_UPDATE. Stores unit IDs of Evokers
-- in the current group so we can watch their auras.
------------------------------------------------------------
local function RebuildEvokerCache()
    wipe(evokerUnits)
    hasEvokers = false

    local numMembers = GetNumGroupMembers()
    if numMembers == 0 then return end

    local prefix = IsInRaid() and "raid" or "party"
    local count = IsInRaid() and numMembers or (numMembers - 1)

    for i = 1, count do
        local unit = prefix .. i
        if UnitExists(unit) and not UnitIsUnit(unit, "player") then
            local _, classToken = UnitClass(unit)
            if classToken == "EVOKER" then
                evokerUnits[unit] = true
                hasEvokers = true
            end
        end
    end

    DebugPrint(string.format("Evoker cache rebuilt: %s",
        hasEvokers and table.concat((function()
            local t = {}
            for u in pairs(evokerUnits) do t[#t+1] = u end
            return t
        end)(), ", ") or "none"))
end

------------------------------------------------------------
-- Aura Profile Matching
-- Returns true if the aura matches the Spatial Paradox
-- fingerprint: HELPFUL, NOT defensive, NOT important, NOT CC,
-- has a DurationObject (temporary buff).
------------------------------------------------------------
local function MatchesSpatialParadoxProfile(unit, auraInstanceID)
    -- Must pass HELPFUL filter
    if C_UnitAuras.IsAuraFilteredOutByInstanceID(unit, auraInstanceID, "HELPFUL") then
        return false
    end
    -- Must NOT be from the local player (rejects self-cast healer buffs AND
    -- healer buffs on the Evoker — PLAYER filter is AllowedWhenTainted)
    if not C_UnitAuras.IsAuraFilteredOutByInstanceID(unit, auraInstanceID, "HELPFUL|PLAYER") then
        return false
    end
    -- Must NOT be a RAID-frame buff (SP is targeted, not group-wide)
    if not C_UnitAuras.IsAuraFilteredOutByInstanceID(unit, auraInstanceID, "HELPFUL|RAID") then
        return false
    end
    -- Must NOT be IMPORTANT
    if not C_UnitAuras.IsAuraFilteredOutByInstanceID(unit, auraInstanceID, "HELPFUL|IMPORTANT") then
        return false
    end
    -- Must NOT be EXTERNAL_DEFENSIVE
    if not C_UnitAuras.IsAuraFilteredOutByInstanceID(unit, auraInstanceID, "HELPFUL|EXTERNAL_DEFENSIVE") then
        return false
    end
    -- Must NOT be BIG_DEFENSIVE
    if not C_UnitAuras.IsAuraFilteredOutByInstanceID(unit, auraInstanceID, "HELPFUL|BIG_DEFENSIVE") then
        return false
    end
    -- Must have a DurationObject (is a temporary buff)
    local durationObj = C_UnitAuras.GetAuraDuration(unit, auraInstanceID)
    if not durationObj then return false end

    -- Spell ID gate: if readable, must be SP. Under restrictions SP is SECRET
    -- (falls through to heuristic). Non-secret buffs like Prescience are rejected here.
    local data = C_UnitAuras.GetAuraDataByAuraInstanceID(unit, auraInstanceID)
    if data and data.spellId ~= nil then
        if not (issecretvalue and issecretvalue(data.spellId)) then
            if data.spellId ~= SP.SPELL_ID then
                return false
            end
        end
    end

    return true, durationObj
end

------------------------------------------------------------
-- TTS Helper
-- Reads voice + rate from ParadoxicalDB per alert type.
------------------------------------------------------------
local function SpeakAlert(alertType)
    local db = ParadoxicalDB or {}
    local defaultVoice = C_TTSSettings.GetVoiceOptionID(0) or 0
    if alertType == "paradox" then
        local voice = db.paradoxVoice or defaultVoice
        local rate = db.paradoxRate or 0
        C_VoiceChat.SpeakText(voice, "paradox", rate, 100, true)
    elseif alertType == "innervate" then
        local voice = db.innervateVoice or defaultVoice
        local rate = db.innervateRate or 0
        C_VoiceChat.SpeakText(voice, "innervate", rate, 100, true)
    end
end

------------------------------------------------------------
-- Screen Edge Glow
-- Full-screen vignette using the LowHealth texture, tinted yellow.
-- Constant while active — no timer or animation changes.
------------------------------------------------------------
local glow = CreateFrame("Frame", "ParadoxicalGlow", UIParent)
glow:SetAllPoints()
glow:SetFrameStrata("BACKGROUND")
glow:SetFrameLevel(0)
glow:EnableMouse(false)
glow:Hide()

local glowTexture = glow:CreateTexture(nil, "BACKGROUND")
glowTexture:SetAllPoints()
glowTexture:SetTexture("Interface\\FullScreenTextures\\LowHealth")
glowTexture:SetDesaturated(true)
glowTexture:SetBlendMode("ADD")
glowTexture:SetVertexColor(1.0, 0.82, 0.0, 1.0)

local glowTexture2 = glow:CreateTexture(nil, "ARTWORK")
glowTexture2:SetAllPoints()
glowTexture2:SetTexture("Interface\\FullScreenTextures\\LowHealth")
glowTexture2:SetDesaturated(true)
glowTexture2:SetBlendMode("ADD")
glowTexture2:SetVertexColor(1.0, 0.82, 0.0, 1.0)

------------------------------------------------------------
-- Screen Edge Glow — Innervate (blue)
------------------------------------------------------------
local innervateGlow = CreateFrame("Frame", "ParadoxicalInnervateGlow", UIParent)
innervateGlow:SetAllPoints()
innervateGlow:SetFrameStrata("BACKGROUND")
innervateGlow:SetFrameLevel(0)
innervateGlow:EnableMouse(false)
innervateGlow:Hide()

local innGlowTex1 = innervateGlow:CreateTexture(nil, "BACKGROUND")
innGlowTex1:SetAllPoints()
innGlowTex1:SetTexture("Interface\\FullScreenTextures\\LowHealth")
innGlowTex1:SetDesaturated(true)
innGlowTex1:SetBlendMode("ADD")
innGlowTex1:SetVertexColor(0.0, 0.82, 1.0, 1.0)

local innGlowTex2 = innervateGlow:CreateTexture(nil, "ARTWORK")
innGlowTex2:SetAllPoints()
innGlowTex2:SetTexture("Interface\\FullScreenTextures\\LowHealth")
innGlowTex2:SetDesaturated(true)
innGlowTex2:SetBlendMode("ADD")
innGlowTex2:SetVertexColor(0.0, 0.82, 1.0, 1.0)


------------------------------------------------------------
-- Track / Untrack — Spatial Paradox
------------------------------------------------------------
local function StartTracking(instanceID, durationObj)
    trackedInstanceID = instanceID
    trackedStartTime = GetTime()
    trackedDuration = SP.BASE_DURATION
    pendingCandidate = nil

    glow:Show()
    SpeakAlert("paradox")
    DebugPrint("Tracking started!")

    -- Safety cap: if tracking outlives MAX_DURATION, it's not Spatial Paradox.
    -- Catches false positives from longer buffs that slip through heuristics.
    C_Timer.After(SP.MAX_DURATION, function()
        if trackedInstanceID == instanceID then
            DebugPrint(string.format("Duration exceeded MAX (%.1fs) — not Spatial Paradox, cancelling", SP.MAX_DURATION))
            StopTracking()
        end
    end)
end

local function StopTracking()
    if trackedInstanceID and debugMode then
        local measured = GetTime() - trackedStartTime
        DebugPrint(string.format("Tracking stopped — measured: %.3fs", measured))
    end
    trackedInstanceID = nil
    glow:Hide()
end

------------------------------------------------------------
-- Track / Untrack — Innervate
------------------------------------------------------------
local function StopInnervateTracking()
    if innervateActive then
        DebugPrint("Innervate tracking stopped")
    end
    innervateActive = false
    innervateGlow:Hide()
end

local function StartInnervateTracking()
    innervateActive = true
    innervateGlow:Show()
    SpeakAlert("innervate")
    DebugPrint(string.format("Innervate tracking started! (%ds timer)", INN.DURATION))
    C_Timer.After(INN.DURATION, function()
        if innervateActive then
            StopInnervateTracking()
        end
    end)
end

------------------------------------------------------------
-- Deferred Confirmation
-- All event handlers just record timestamps. After the
-- correlation window expires, the timer callback decides.
-- This eliminates all event-ordering race conditions.
------------------------------------------------------------
local function ConfirmPendingCandidate()
    -- Timer fired — evaluate the evidence
    if not pendingCandidate then return end
    if trackedInstanceID then
        pendingCandidate = nil
        return
    end

    local pending = pendingCandidate
    pendingCandidate = nil

    local evokerCorrelated = math.abs(pending.time - evokerBuffTime) <= CORRELATION_WINDOW
    local othersCorrelated = math.abs(pending.time - othersBuffTime) <= CORRELATION_WINDOW

    if not evokerCorrelated then
        DebugPrint("Deferred check: NO Evoker correlation — rejected")
        return
    end

    if othersCorrelated then
        DebugPrint("Deferred check: others also received buff — rejected (group-wide)")
        return
    end

    -- Confirmed! Re-fetch DurationObject in case the original went stale
    local freshDurationObj = C_UnitAuras.GetAuraDuration("player", pending.instanceID)
    if not freshDurationObj then
        DebugPrint("Deferred check: aura already expired before confirmation")
        return
    end

    DebugPrint("Deferred check: CONFIRMED — Evoker correlated, no others")
    StartTracking(pending.instanceID, freshDurationObj)
end

------------------------------------------------------------
-- Cross-Reference: Evoker Buff Detection
-- Just record timestamp. The deferred timer handles logic.
------------------------------------------------------------
local function OnEvokerAura(unit, updateInfo)
    if not updateInfo or updateInfo.isFullUpdate then return end
    if not updateInfo.addedAuras then return end

    for _, aura in ipairs(updateInfo.addedAuras) do
        if aura.auraInstanceID then
            local matches = MatchesSpatialParadoxProfile(unit, aura.auraInstanceID)
            if matches then
                evokerBuffTime = GetTime()
                DebugPrint(string.format("Evoker [%s] received matching buff — timestamp recorded", unit))
                return
            end
        end
    end
end

------------------------------------------------------------
-- Other Party Member Aura Detection
-- Just record timestamp. The deferred timer handles logic.
------------------------------------------------------------
local function OnOtherAura(unit, updateInfo)
    if not updateInfo or updateInfo.isFullUpdate then return end
    if not updateInfo.addedAuras then return end

    for _, aura in ipairs(updateInfo.addedAuras) do
        if aura.auraInstanceID then
            local matches = MatchesSpatialParadoxProfile(unit, aura.auraInstanceID)
            if matches then
                othersBuffTime = GetTime()
                DebugPrint(string.format("Other [%s] received matching buff — group-wide indicator", unit))
                return
            end
        end
    end
end

------------------------------------------------------------
-- Player Aura Detection
------------------------------------------------------------
local function OnPlayerAura(updateInfo)
    -- Full update: can't do incremental detection, scan not feasible
    -- without readable spell IDs. Just clear tracking if our buff dropped.
    if not updateInfo or updateInfo.isFullUpdate then
        if trackedInstanceID then
            local durationObj = C_UnitAuras.GetAuraDuration("player", trackedInstanceID)
            if not durationObj then
                StopTracking()
            end
        end
        return
    end

    -- SP: check removal of tracked aura
    if trackedInstanceID and updateInfo.removedAuraInstanceIDs then
        for _, id in ipairs(updateInfo.removedAuraInstanceIDs) do
            if id == trackedInstanceID then
                StopTracking()
                break
            end
        end
    end

    -- Already tracking? Don't look for new candidates
    if trackedInstanceID then return end
    if not updateInfo.addedAuras then return end

    -- Debug: dump all new auras
    if debugMode then
        for _, aura in ipairs(updateInfo.addedAuras) do
            if aura.auraInstanceID then
                DebugPrint("--- New aura on PLAYER ---")
                DebugDumpAura("player", aura.auraInstanceID)
            end
        end
    end

    -- Collect ALL matching auras in this event.
    -- Spatial Paradox applies exactly 1 buff. If multiple match, it's group-wide (Ebon Might).
    local candidates = {}
    for _, aura in ipairs(updateInfo.addedAuras) do
        if aura.auraInstanceID then
            local matches, durationObj = MatchesSpatialParadoxProfile("player", aura.auraInstanceID)
            if matches then
                local data = C_UnitAuras.GetAuraDataByAuraInstanceID("player", aura.auraInstanceID)
                if data and data.isFromPlayerOrPlayerPet == true then
                    candidates[#candidates + 1] = {
                        instanceID = aura.auraInstanceID,
                        durationObj = durationObj,
                    }
                end
            end
        end
    end

    if #candidates == 0 then return end

    local now = GetTime()

    if #candidates > 1 then
        DebugPrint(string.format("Multiple matching buffs (%d) in same event — rejected (group-wide)", #candidates))
        -- Also clear any pending from a prior event in this window (split multi-buff)
        if pendingCandidate then
            DebugPrint("Clearing prior pending — same cast split across events")
            pendingCandidate = nil
        end
        return
    end

    -- Exactly 1 matching buff — possible Spatial Paradox
    -- But if we already have a pending from this window, a second single buff
    -- means the first was part of a multi-buff cast that split across events.
    if pendingCandidate and (now - pendingCandidate.time) <= CORRELATION_WINDOW then
        DebugPrint("Another matching buff within window — original pending was multi-buff, rejecting both")
        pendingCandidate = nil
        return
    end

    local candidate = candidates[1]

    if debugMode and not hasEvokers then
        DebugPrint("Debug mode, no Evokers — tracking without correlation")
        StartTracking(candidate.instanceID, candidate.durationObj)
    else
        pendingCandidate = {
            instanceID = candidate.instanceID,
            durationObj = candidate.durationObj,
            time = now,
        }
        C_Timer.After(CORRELATION_WINDOW, ConfirmPendingCandidate)
        DebugPrint(string.format("Candidate stored — deferred check in %.1fs", CORRELATION_WINDOW))
    end
end

------------------------------------------------------------
-- UNIT_AURA Handler
------------------------------------------------------------
local function OnUnitAura(unit, updateInfo)
    if unit == "player" then
        if not debugMode and not isHealer then return end
        OnPlayerAura(updateInfo)
    elseif evokerUnits[unit] then
        OnEvokerAura(unit, updateInfo)
    else
        -- Any other party/raid member — watch for group-wide buff rejection
        local prefix = unit:sub(1, 4)
        if prefix == "part" or prefix == "raid" then
            OnOtherAura(unit, updateInfo)
        end
    end
end

------------------------------------------------------------
-- Core Event Frame
------------------------------------------------------------
local eventFrame = CreateFrame("Frame")

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon ~= addonName then return end

        if not ParadoxicalDB then
            ParadoxicalDB = {}
        end

        UpdateHealerState()
        RebuildEvokerCache()
        if isHealer then
            self:RegisterEvent("UNIT_AURA")
            self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
        end

        addonTable.InitSettings()
        self:UnregisterEvent("ADDON_LOADED")

    elseif event == "PLAYER_ENTERING_WORLD" then
        UpdateHealerState()
        RebuildEvokerCache()
        if isHealer then
            self:RegisterEvent("UNIT_AURA")
            self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
        end

    elseif event == "GROUP_ROSTER_UPDATE" then
        RebuildEvokerCache()

    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        local wasHealer = isHealer
        UpdateHealerState()

        if isHealer and not wasHealer then
            self:RegisterEvent("UNIT_AURA")
            self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
        elseif not isHealer and wasHealer then
            self:UnregisterEvent("UNIT_AURA")
            self:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
            StopTracking()
            StopInnervateTracking()
        end

    elseif event == "UNIT_AURA" then
        OnUnitAura(...)

    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, _, spellID = ...
        if unit == "player" and spellID == INN.SPELL_ID then
            DebugPrint(string.format("Innervate cast detected (spellID %d)", spellID))
            StartInnervateTracking()
        end
    end
end)

------------------------------------------------------------
-- Slash Command
------------------------------------------------------------
SLASH_PARADOXICAL1 = "/paradox"
SLASH_PARADOXICAL2 = "/paradoxical"
SlashCmdList["PARADOXICAL"] = function(msg)
    msg = strtrim(msg):lower()

    if msg == "test paradox" or msg == "test sp" then
        if glow:IsShown() then
            glow:Hide()
            print("|cff55c0a8[Paradoxical]|r Paradox glow |cffff4444hidden|r")
        else
            glow:Show()
            SpeakAlert("paradox")
            print("|cff55c0a8[Paradoxical]|r Paradox glow |cffffcc00shown|r")
        end
        return
    elseif msg == "test innervate" or msg == "test inn" then
        if innervateGlow:IsShown() then
            innervateGlow:Hide()
            print("|cff55c0a8[Paradoxical]|r Innervate glow |cffff4444hidden|r")
        else
            innervateGlow:Show()
            SpeakAlert("innervate")
            print("|cff55c0a8[Paradoxical]|r Innervate glow |cff00ccffshown|r")
        end
        return
    elseif msg == "test" then
        print("|cff55c0a8[Paradoxical]|r Test commands:")
        print("  /paradox test paradox — Toggle Spatial Paradox glow (yellow)")
        print("  /paradox test innervate — Toggle Innervate glow (blue)")
        return
    elseif msg == "debug" then
        debugMode = not debugMode
        local restrictionCVars = {
            "addonChallengeModeRestrictionsForced",
            "addonCombatRestrictionsForced",
            "addonEncounterRestrictionsForced",
            "addonMapRestrictionsForced",
        }
        if debugMode then
            for _, cvar in ipairs(restrictionCVars) do
                C_CVar.SetCVar(cvar, "1")
            end
            eventFrame:RegisterEvent("UNIT_AURA")
            eventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
            RebuildEvokerCache()
            print("|cff55c0a8[Paradoxical]|r Debug mode |cff00ff00ON|r")
            print("|cff55c0a8[Paradoxical]|r Gates BYPASSED | Restrictions FORCED | Logging all auras")
        else
            for _, cvar in ipairs(restrictionCVars) do
                C_CVar.SetCVar(cvar, "0")
            end
            print("|cff55c0a8[Paradoxical]|r Debug mode |cffff4444OFF|r")
            print("|cff55c0a8[Paradoxical]|r Restrictions CLEARED")
            if not isHealer then
                eventFrame:UnregisterEvent("UNIT_AURA")
                eventFrame:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
                StopTracking()
                StopInnervateTracking()
            end
        end
    else
        print("|cff55c0a8[Paradoxical]|r Commands:")
        print("  /paradox test [paradox|innervate] — Toggle glow display")
        print("  /paradox debug — Toggle debug (logging + forced restrictions)")
    end
end
