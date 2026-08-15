local addonName, addonTable = ...

local HEALER_SPECS = addonTable.HEALER_SPEC_IDS
local SP = addonTable.SPATIAL_PARADOX
local INN = addonTable.INNERVATE

local isHealer = false
local auraContainers = {}
local auraSoundHandles = {}

local CAUSESE_SOUND_PATHS = {
    paradox = "Interface\\AddOns\\SharedMedia_Causese\\sound\\Paradox.ogg",
    innervate = "Interface\\AddOns\\SharedMedia_Causese\\sound\\Innervate.ogg",
}

local function IsCauseseInstalled()
    return C_AddOns.GetAddOnInfo("SharedMedia_Causese") ~= nil
end

local function DefaultSound(alert)
    return IsCauseseInstalled() and CAUSESE_SOUND_PATHS[alert] or ""
end

function addonTable.ResolveSound(sound)
    if not sound or sound == "" then return nil end
    return sound
end

function addonTable.PlaySoundPreview(sound)
    local path = addonTable.ResolveSound(sound)
    if path then
        PlaySoundFile(path, "Master")
    end
end

local function ClearAuraSounds()
    for index = #auraSoundHandles, 1, -1 do
        C_UnitAuras.RemoveAuraSound(auraSoundHandles[index])
        auraSoundHandles[index] = nil
    end
end

function addonTable.RefreshAuraSounds()
    ClearAuraSounds()
    if not isHealer then return end

    local db = ParadoxicalDB or {}
    local alerts = {
        { spellID = SP.SPELL_ID, sound = db.paradoxSound },
        { spellID = INN.SPELL_ID, sound = db.innervateSound },
    }

    for _, alert in ipairs(alerts) do
        local path = addonTable.ResolveSound(alert.sound)
        if path then
            local handle = C_UnitAuras.AddAuraSound(Enum.UnitAuraSoundTrigger.Added, {
                unitToken = "player",
                spellID = alert.spellID,
                soundFileName = path,
                outputChannel = "Master",
            })
            if handle then
                auraSoundHandles[#auraSoundHandles + 1] = handle
            end
        end
    end
end

------------------------------------------------------------
-- Healer Spec Gate
------------------------------------------------------------

local function UpdateHealerState()
    local specIndex = GetSpecialization()
    local specID = specIndex and GetSpecializationInfo(specIndex)
    isHealer = specID ~= nil and HEALER_SPECS[specID] == true

    for _, container in ipairs(auraContainers) do
        container:SetEnabled(isHealer)
    end

    addonTable.RefreshAuraSounds()
end

------------------------------------------------------------
-- Spatial Paradox
------------------------------------------------------------
--
-- Aura data is secret in 12.1, so addons must not inspect UNIT_AURA
-- payloads or enumerate aura slots. AuraContainer hands this exact spell-ID
-- filter to Blizzard's aura engine, which owns the matching and show/hide
-- state even while the aura is secret.

local function InitializeAuraGlowButton(container, color)
    return function(button)
        -- The button itself remains invisible. Blizzard controls its shown state
        -- from the secret aura, while this child texture inherits that state and
        -- recreates the old full-screen alert without Lua inspecting the aura.
        button:SetSize(1, 1)
        button:ClearAllPoints()
        button:SetPoint("CENTER", container, "CENTER")
        button:SetMouseMotionEnabled(false)

        for layer = 1, 2 do
            local glow = button:CreateTexture(nil, layer == 1 and "BACKGROUND" or "ARTWORK")
            glow:SetAllPoints(UIParent)
            glow:SetTexture("Interface\\FullScreenTextures\\LowHealth")
            glow:SetDesaturated(true)
            glow:SetBlendMode("ADD")
            glow:SetVertexColor(color[1], color[2], color[3], 1.0)
        end
    end
end

local function CreateAuraGlow(alert, spellID, color)
    if not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then
        local loaded, reason = C_AddOns.LoadAddOn("Blizzard_AuraContainer")
        if not loaded then
            print(("|cff55c0a8[Paradoxical]|r Unable to load Blizzard_AuraContainer: %s"):format(tostring(reason)))
            return
        end
    end

    local container = CreateFrame(
        "AuraContainer",
        "Paradoxical" .. alert .. "AuraContainer",
        UIParent,
        "CustomAuraContainerTemplate"
    )
    container:Hide()
    container:SetSize(1, 1)
    -- The managed button only supplies visibility. Keep it off-screen; its
    -- child glow textures are explicitly anchored to UIParent instead.
    container:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", -10, -10)
    container:SetUnit("player")
    container:AddAuraGroup(alert, "HELPFUL", {
        maxFrameCount = 1,
        candidateFilters = {
            includeSpellIDs = {
                [spellID] = true,
            },
        },
        sortMethod = AuraContainerSortMethod.AuraInstanceIDOnly,
        sortDirection = AuraContainerSortDirection.Normal,
        initializeFrame = InitializeAuraGlowButton(container, color),
        layout = {
            elementWidth = 1,
            elementHeight = 1,
        },
    })
    container:SetEnabled(isHealer)
    container:Show()
    auraContainers[#auraContainers + 1] = container
end

------------------------------------------------------------
-- Initialization
------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        if ... ~= addonName then return end

        ParadoxicalDB = ParadoxicalDB or {}
        if ParadoxicalDB.paradoxSound == nil then
            ParadoxicalDB.paradoxSound = DefaultSound("paradox")
        end
        if ParadoxicalDB.innervateSound == nil then
            ParadoxicalDB.innervateSound = DefaultSound("innervate")
        end
        UpdateHealerState()
        CreateAuraGlow("SpatialParadox", SP.SPELL_ID, { 1.0, 0.82, 0.0 })
        CreateAuraGlow("Innervate", INN.SPELL_ID, { 0.0, 0.82, 1.0 })
        addonTable.InitSettings()
        self:UnregisterEvent("ADDON_LOADED")

    elseif event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_SPECIALIZATION_CHANGED" then
        UpdateHealerState()
    end
end)
