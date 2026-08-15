local _, addonTable = ...

local function GetSoundOptions()
    local container = Settings.CreateControlTextContainer()
    container:Add("", "None")

    local seen = {}
    local function Add(path, label)
        if path and not seen[path] then
            seen[path] = true
            container:Add(path, label)
        end
    end

    if C_AddOns.GetAddOnInfo("SharedMedia_Causese") then
        Add("Interface\\AddOns\\SharedMedia_Causese\\sound\\Paradox.ogg", "Causese: Paradox")
        Add("Interface\\AddOns\\SharedMedia_Causese\\sound\\Innervate.ogg", "Causese: Innervate")
    end

    local LSM = LibStub("LibSharedMedia-3.0", true)
    if LSM then
        for name, path in pairs(LSM:HashTable("sound")) do
            if path ~= 1 then
                Add(path, name)
            end
        end
    end

    return container:GetData()
end

local function AddSoundSetting(category, layout, db, key, label, tooltip)
    local setting = Settings.RegisterAddOnSetting(category, key, key, db, "string", label, "")
    setting:SetValueChangedCallback(function()
        addonTable.RefreshAuraSounds()
    end)
    Settings.CreateDropdown(category, setting, GetSoundOptions, tooltip)

    local initializer = CreateSettingsButtonInitializer(
        "Preview " .. label,
        "Play",
        function()
            addonTable.PlaySoundPreview(db[key])
        end,
        "Plays the selected sound.",
        true
    )
    layout:AddInitializer(initializer)
end

function addonTable.InitSettings()
    local db = ParadoxicalDB
    local category, layout = Settings.RegisterVerticalLayoutCategory("Paradoxical")

    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Spatial Paradox"))
    AddSoundSetting(category, layout, db, "paradoxSound", "Sound", "Sound played when Spatial Paradox is applied to you.")

    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Innervate"))
    AddSoundSetting(category, layout, db, "innervateSound", "Sound", "Sound played when Innervate is applied to you.")

    Settings.RegisterAddOnCategory(category)
end
