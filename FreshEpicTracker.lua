-- FreshEpicTracker v2.3 — Retail Safe, Tracks Ongoing & Fresh Epic BGs
-- Tracks epic battlegrounds for fresh vs in-progress matches

local addonName = "FreshEpicTracker"
local FET = CreateFrame("Frame", "FET_Frame", UIParent)

-- Default cycle estimates (seconds)
local DEFAULTS = {
    ["Alterac Valley"] = 50 * 60,
    ["Isle of Conquest"] = 35 * 60,
    ["Ashran"] = 75 * 60,
    ["Wintergrasp"] = 120 * 60
}

-- Saved vars
FETSaved = FETSaved or {}
FETSettings = FETSettings or {
    cycles = {},
    alertThreshold = 300, -- 5 minutes
    playSound = true,
    soundKit = 8959,
    minimap = true,
    showPopupOnQueue = true,
    notifyWhenGoodToQueue = true,
    showGUI = true
}

-- Ensure cycle defaults exist
for k,v in pairs(DEFAULTS) do
    if not FETSettings.cycles[k] then FETSettings.cycles[k] = v end
end

-- Helpers
local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[FET]|r "..msg)
end

local function FormatTime(sec)
    if sec <= 0 then return "0s" end
    local h = math.floor(sec / 3600)
    local m = math.floor((sec % 3600) / 60)
    local s = sec % 60
    if h > 0 then return string.format("%dh %dm", h, m) end
    if m > 0 then return string.format("%dm %ds", m, s) end
    return string.format("%ds", s)
end

-- Data recording
local function EnsureData(name)
    FETSaved[name] = FETSaved[name] or {starts = {}, durations = {}, lastStart = nil, wins = 0, losses = 0}
    return FETSaved[name]
end

local function RecordStart(name, ts)
    local d = EnsureData(name)
    table.insert(d.starts, ts)
    d.lastStart = ts
    Print(name.." match recorded at "..date("%H:%M:%S", ts))
end

local function RecordMatchEnd(name, endTime)
    local d = FETSaved[name]
    if not d or not d.lastStart then return nil end
    local dur = endTime - d.lastStart
    if dur > 5 then
        table.insert(d.durations, dur)
    end
    d.lastStart = nil
    return dur
end

local function AverageDuration(name)
    local d = FETSaved[name]
    if not d or #d.durations == 0 then return nil end
    local sum = 0
    for _,v in ipairs(d.durations) do sum = sum + v end
    return math.floor(sum / #d.durations)
end

-- Predict next fresh spawn
local function PredictBG(name)
    local data = FETSaved[name]
    local cycle = FETSettings.cycles[name] or DEFAULTS[name]
    if not data or #data.starts == 0 then
        return nil, "No data yet for "..name
    end
    local last = data.starts[#data.starts]
    local elapsed = time() - last
    local remaining = cycle - elapsed
    return remaining, nil
end

-- Alerts
local function DoAlert(msg)
    if RaidWarningFrame then
        RaidNotice_AddMessage(RaidWarningFrame, msg, ChatTypeInfo["RAID_WARNING"])
    end
    Print(msg)
    if FETSettings.playSound and FETSettings.soundKit and PlaySound then
        pcall(PlaySound, FETSettings.soundKit, "Master")
    end
end

-- GUI
local function CreateMainGUI()
    if FET.MainFrame then return FET.MainFrame end

    local f = CreateFrame("Frame", "FET_MainFrame", UIParent, "BackdropTemplate")
    f:SetSize(360, 220)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    f:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 8, right = 8, top = 8, bottom = 8 }
    })
    f:SetBackdropColor(0,0,0,0.75)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("TOPLEFT", 12, -8)
    f.title:SetText("FreshEpicTracker")

    f.toggleBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.toggleBtn:SetSize(80, 22)
    f.toggleBtn:SetPoint("TOPRIGHT", -12, -8)
    f.toggleBtn:SetText("Close")
    f.toggleBtn:SetScript("OnClick", function() f:Hide() FETSettings.showGUI = false end)

    f.rows = {}
    local y = -40
    for mapName, _ in pairs(DEFAULTS) do
        local row = {}
        row.label = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.label:SetPoint("TOPLEFT", 12, y)
        row.label:SetText(mapName..":")

        row.pred = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.pred:SetPoint("TOPLEFT", 140, y)
        row.pred:SetText("no data")

        row.avg = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.avg:SetPoint("TOPRIGHT", -12, y)
        row.avg:SetText("avg -")

        f.rows[mapName] = row
        y = y - 26
    end

    f.update = function()
        for mapName, row in pairs(f.rows) do
            local remaining, err = PredictBG(mapName)
            if err then
                row.pred:SetText("no data")
            else
                if remaining <= 0 then
                    row.pred:SetText("Likely fresh NOW")
                else
                    row.pred:SetText("in "..FormatTime(remaining))
                end
            end
            local avg = AverageDuration(mapName)
            if avg then row.avg:SetText("avg "..FormatTime(avg)) else row.avg:SetText("avg -") end
        end
    end

    f.ticker = C_Timer.NewTicker(5, function() if f:IsShown() then f.update() end end)
    f:SetScript("OnShow", function() f.update() end)

    FET.MainFrame = f
    if FETSettings.showGUI then f:Show() else f:Hide() end
    return f
end

-- Minimap
local function CreateMinimapButton()
    if FET.MinimapButton then return FET.MinimapButton end
    if not Minimap then return nil end

    local b = CreateFrame("Button", "FETMinimapButton", Minimap)
    b:SetSize(28,28)
    b:SetFrameStrata("MEDIUM")
    b.icon = b:CreateTexture(nil, "BACKGROUND")
    b.icon:SetAllPoints(true)
    b.icon:SetTexture("Interface\\Icons\\INV_Banner_03")

    b:SetPoint("TOPLEFT", Minimap, "TOPLEFT", 0, 0)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("FreshEpicTracker")
        GameTooltip:AddLine("Left-click: Open main window")
        GameTooltip:AddLine("Right-click: Print predictions to chat")
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnMouseUp", function(self, btn)
        if btn == "LeftButton" then
            local mf = CreateMainGUI()
            mf:SetShown(not mf:IsShown())
        else
            FET_PrintPredictions()
        end
    end)

    FET.MinimapButton = b
    if not FETSettings.minimap then b:Hide() end
    return b
end

-- Print predictions
function FET_PrintPredictions()
    Print("Epic BG Predictions:")
    for mapName, _ in pairs(DEFAULTS) do
        local remaining, err = PredictBG(mapName)
        if err then
            Print(" - "..mapName..": "..err)
        else
            if remaining <= 0 then
                Print(" - "..mapName..": likely fresh RIGHT NOW")
            else
                Print(" - "..mapName..": likely fresh in "..FormatTime(remaining))
            end
        end
        local avg = AverageDuration(mapName)
        if avg then Print("   Avg duration: "..FormatTime(avg)) end
    end
end

-- BG helper
local function FET_IsInsideBG()
    local inInstance, instType = IsInInstance()
    return inInstance and (instType == "pvp" or instType == "arena")
end

-- Runtime tracking
local FET_Data = FET_Data or { total = 0, inProgress = 0 }
local currentBG, currentStartTime

local function FET_Record()
    if not FET_IsInsideBG() then return end

    local name = GetInstanceInfo()
    local elapsed = GetBattlefieldInstanceRunTime() or 0
    local isInProgress = elapsed > 0

    -- Approximate start for ongoing matches
    local startTime = isInProgress and (time() - elapsed) or time()

    -- Record if no previous lastStart
    local data = EnsureData(name)
    if not data.lastStart then
        RecordStart(name, startTime)
    end

    -- Runtime stats
    FET_Data.total = FET_Data.total + 1
    if isInProgress then
        FET_Data.inProgress = FET_Data.inProgress + 1
        Print("MATCH IN PROGRESS: "..name)
    else
        Print("Fresh match: "..name)
    end

    local perc = (FET_Data.inProgress / FET_Data.total) * 100
    Print(string.format("Stats: %d total, %d in-progress (%.1f%%)", FET_Data.total, FET_Data.inProgress, perc))
end

-- Event handling
FET:RegisterEvent("PLAYER_LOGIN")
FET:RegisterEvent("PLAYER_ENTERING_BATTLEGROUND")
FET:RegisterEvent("ZONE_CHANGED_NEW_AREA")
FET:RegisterEvent("UPDATE_BATTLEFIELD_STATUS")
FET:RegisterEvent("PVP_MATCH_ACTIVE")
FET:RegisterEvent("PVP_MATCH_INACTIVE")
FET:RegisterEvent("LFG_UPDATE")

FET:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        CreateMainGUI()
        CreateMinimapButton()
        Print("FreshEpicTracker loaded. /fet to print predictions (or right-click minimap).")

    elseif event == "PLAYER_ENTERING_BATTLEGROUND" then
        local _, instanceType = GetInstanceInfo()
        if instanceType ~= "pvp" then return end

        currentBG = select(1, GetInstanceInfo())
        currentStartTime = time()
        FET_Record()

    elseif event == "PVP_MATCH_INACTIVE" then
        if currentBG and currentStartTime then
            local dur = RecordMatchEnd(currentBG, time())
            if dur and dur > 0 then
                Print(currentBG.." ended. Duration: "..FormatTime(dur))
            end
            currentBG, currentStartTime = nil, nil
        end

    elseif event == "ZONE_CHANGED_NEW_AREA" then
        if currentBG and currentStartTime then
            local dur = RecordMatchEnd(currentBG, time())
            if dur and dur > 0 then
                Print(currentBG.." ended (zone change). Duration: "..FormatTime(dur))
            end
            currentBG, currentStartTime = nil, nil
        end

    elseif event == "UPDATE_BATTLEFIELD_STATUS" then
        if not FETSettings.notifyWhenGoodToQueue then return end
        local max = GetMaxBattlefieldID and GetMaxBattlefieldID() or 0
        for i = 1, max do
            local status, mapName = GetBattlefieldStatus(i)
            if status and (status == "queued" or status == "confirm") then
                if mapName and DEFAULTS[mapName] then
                    local remaining, err = PredictBG(mapName)
                    if remaining and remaining <= FETSettings.alertThreshold then
                        if FETSettings.showPopupOnQueue then
                            DoAlert(mapName.." predicted fresh in "..FormatTime(remaining)..". Good time to queue.")
                        else
                            Print(mapName.." predicted fresh in "..FormatTime(remaining)..".")
                        end
                    end
                end
            end
        end
    end
end)

-- Periodic alert
C_Timer.NewTicker(60, function()
    if not FETSettings.notifyWhenGoodToQueue then return end
    for mapName, _ in pairs(DEFAULTS) do
        local remaining, err = PredictBG(mapName)
        if remaining and remaining <= FETSettings.alertThreshold then
            if remaining <= 0 then
                DoAlert(mapName.." likely fresh RIGHT NOW.")
            else
                DoAlert(mapName.." likely fresh in "..FormatTime(remaining).." — good time to queue.")
            end
        end
    end
end)

-- Slash commands
SLASH_FET1 = "/fet"
SlashCmdList["FET"] = function(msg)
    msg = msg:lower():trim()
    if msg == "" or msg == "status" then
        FET_PrintPredictions()
    elseif msg == "open" then
        CreateMainGUI():Show()
    elseif msg == "hide" then
        if FET.MainFrame then FET.MainFrame:Hide() end
    elseif msg == "reset" then
        StaticPopup_Show("FET_RESET_CONFIRM")
    elseif msg == "help" then
        Print("/fet - show predictions")
        Print("/fet open - open GUI")
        Print("/fet hide - hide GUI")
        Print("/fet reset - reset data")
    else
        Print("Unknown arg. Type '/fet help' for commands.")
    end
end

-- Reset popup
StaticPopupDialogs["FET_RESET_CONFIRM"] = {
    text = "Reset all FreshEpicTracker saved data? This cannot be undone.",
    button1 = "Reset",
    button2 = "Cancel",
    OnAccept = function()
        FETSaved = {}
        Print("All data reset.")
    end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1
}
