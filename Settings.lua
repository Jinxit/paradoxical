local _, addonTable = ...

------------------------------------------------------------
-- Settings Panel (Interface > AddOns > Paradoxical)
------------------------------------------------------------
function addonTable.InitSettings()
    local db = ParadoxicalDB

    local category, layout = Settings.RegisterVerticalLayoutCategory("Paradoxical")

    -- Voice dropdown options
    local function GetVoiceOptions()
        local container = Settings.CreateControlTextContainer()
        local voices = C_VoiceChat.GetTtsVoices()
        if voices then
            for _, v in ipairs(voices) do
                container:Add(v.voiceID, v.name)
            end
        end
        return container:GetData()
    end

    local defaultVoice = C_TTSSettings.GetVoiceOptionID(0) or 0

    ----------------------------------------------------------------
    -- Spatial Paradox
    ----------------------------------------------------------------
    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Spatial Paradox"))

    do
        local setting = Settings.RegisterAddOnSetting(category,
            "ParadoxVoice", "paradoxVoice", db,
            "number", "Voice", defaultVoice)
        Settings.CreateDropdown(category, setting, GetVoiceOptions,
            "TTS voice used when Spatial Paradox is detected.")
    end

    do
        local setting = Settings.RegisterAddOnSetting(category,
            "ParadoxRate", "paradoxRate", db,
            "number", "Speech Rate", 0)
        local options = Settings.CreateSliderOptions(-2, 6, 1)
        options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
        Settings.CreateSlider(category, setting, options,
            "Speech rate for Spatial Paradox TTS. Negative = slower, positive = faster.")
    end

    do
        local init = CreateSettingsButtonInitializer(
            "Test Paradox", "Play",
            function()
                local voice = db.paradoxVoice or defaultVoice
                local rate = db.paradoxRate or 0
                C_VoiceChat.SpeakText(voice, "paradox", rate, 100, true)
            end,
            "Plays a test of the Spatial Paradox TTS alert.",
            true)
        layout:AddInitializer(init)
    end

    ----------------------------------------------------------------
    -- Innervate
    ----------------------------------------------------------------
    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Innervate"))

    do
        local setting = Settings.RegisterAddOnSetting(category,
            "InnervateVoice", "innervateVoice", db,
            "number", "Voice", defaultVoice)
        Settings.CreateDropdown(category, setting, GetVoiceOptions,
            "TTS voice used when Innervate is cast.")
    end

    do
        local setting = Settings.RegisterAddOnSetting(category,
            "InnervateRate", "innervateRate", db,
            "number", "Speech Rate", 0)
        local options = Settings.CreateSliderOptions(-2, 6, 1)
        options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
        Settings.CreateSlider(category, setting, options,
            "Speech rate for Innervate TTS. Negative = slower, positive = faster.")
    end

    do
        local init = CreateSettingsButtonInitializer(
            "Test Innervate", "Play",
            function()
                local voice = db.innervateVoice or defaultVoice
                local rate = db.innervateRate or 0
                C_VoiceChat.SpeakText(voice, "innervate", rate, 100, true)
            end,
            "Plays a test of the Innervate TTS alert.",
            true)
        layout:AddInitializer(init)
    end

    Settings.RegisterAddOnCategory(category)
end
