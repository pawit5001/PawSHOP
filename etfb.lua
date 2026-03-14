-- full open source, ETFB log description only works with horst rejoin

task.wait(5)
print("PawSHOP loading...")
task.wait(5)
print("Log ETFB is now ready")

local Players = game:GetService("Players")
local player = Players.LocalPlayer

-- CONFIG
_G.Display = _G.Display or {
    Brainrot = {""},
    LuckyBlock = {""}
}

-- Waiting PlayerGui path safely
local function waitForPath(path)
    local current = player:WaitForChild("PlayerGui",10)
    for child in string.gmatch(path,"[^%.]+") do
        current = current:WaitForChild(child,10)
        local backpack = player:FindFirstChild("Backpack")
        if not current then return nil end
    end
    return current
end

-- Backpack summary
local function getBackpackSummary()

    local backpack = player:FindFirstChild("Backpack")
    if not backpack then return "","" end

    local brainrotNames = _G.Display.Brainrot or {}
    local luckyLevels = _G.Display.LuckyBlock or {}

    local brainrotCounts = {}
    local luckyCounts = {}

    for _,item in ipairs(backpack:GetChildren()) do
        -- ...existing code...
        local brainrot = item and item:GetAttribute("BrainrotName") or nil
        local displayName = item and item:GetAttribute("DisplayName") or nil
        -- ...existing code...
        -- เช็ค brainrotName หรือ displayName สำหรับ brainrot
        if #brainrotNames > 0 then
            for _,name in ipairs(brainrotNames) do
                -- ...existing code...
                if name ~= "" then
                    local matched = false
                    if brainrot and brainrot:find(name) then
                        matched = true
                        -- Always use config name as key
                        brainrotCounts[name] = (brainrotCounts[name] or 0) + 1
                    elseif displayName and displayName:find(name) then
                        matched = true
                        brainrotCounts[name] = (brainrotCounts[name] or 0) + 1
                    end
                    if matched then break end
                end
            end
        end
        -- lucky box logic เหมือนเดิม
        if displayName and #luckyLevels > 0 then
            for _,level in ipairs(luckyLevels) do
                if level ~= "" and displayName:find(level) then
                    -- Clean name to just the level (Infinity, Divine, etc.)
                    local cleanName = level
                    luckyCounts[cleanName] = (luckyCounts[cleanName] or 0) + 1
                    break
                end
            end
        end
    end


    local brainrotSummary = ""
    for _,name in ipairs(brainrotNames) do
        local found = false
        for k,v in pairs(brainrotCounts) do
            -- strict match: config name must be contained in cleaned name, but not partial/duplicate
            if k == name and v > 0 then
                if brainrotSummary ~= "" then brainrotSummary = brainrotSummary .. ", " end
                brainrotSummary = brainrotSummary .. k .. " x" .. v
                found = true
                break
            end
        end
        -- fallback: allow contains if strict not found
        if not found then
            for k,v in pairs(brainrotCounts) do
                if k:find(name) and v > 0 then
                    if brainrotSummary ~= "" then brainrotSummary = brainrotSummary .. ", " end
                    brainrotSummary = brainrotSummary .. k .. " x" .. v
                    break
                end
            end
        end
    end

    local luckySummary = ""
    for _,level in ipairs(luckyLevels) do
        local found = false
        for k,v in pairs(luckyCounts) do
            -- strict match: config level must be contained in cleaned name, but not partial/duplicate
            if k == level and v > 0 then
                if luckySummary ~= "" then luckySummary = luckySummary .. ", " end
                luckySummary = luckySummary .. k .. " x" .. v
                found = true
                break
            end
        end
        -- fallback: allow contains if strict not found
        if not found then
            for k,v in pairs(luckyCounts) do
                if k:find(level) and v > 0 then
                    if luckySummary ~= "" then luckySummary = luckySummary .. ", " end
                    luckySummary = luckySummary .. k .. " x" .. v
                    break
                end
            end
        end
    end

    return brainrotSummary,luckySummary
end

-- Main description sender
local function sendDescription()
    local speedObj   = waitForPath("HUD.BottomLeft.JumpAndSpeed.Container.EventCurrency.Value")
    local tokenObj   = waitForPath("HUD.BottomLeft.TradeTokens.Container.TradeTokens.Value")
    local rebirthObj = waitForPath("Menus.Toggles.Rebirth.ImageButton.TextLabel")
    local brainrotSummary,luckySummary = getBackpackSummary()

    local function safeValue(obj, valueField, textField)
        if not obj then return "null" end
        local val = obj[valueField]
        if typeof(val) == "string" or typeof(val) == "number" then return val end
        val = obj[textField]
        if typeof(val) == "string" or typeof(val) == "number" then return val end
    end

    local speed   = safeValue(speedObj, "Text", "Value")
    local token   = safeValue(tokenObj, "Text", "Value")
    local rebirth = "null"
    if rebirthObj and rebirthObj.Text then
        -- ดึงตัวเลขจากข้อความที่อยู่ใน [] เช่น Rebirth [24]
        local found = tostring(rebirthObj.Text):match("%[(%d+)%]")
        if found then
            rebirth = found
        else
            -- fallback: ดึงตัวเลขแรกที่เจอ
            rebirth = tostring(rebirthObj.Text):match("%d+") or "null"
        end
    end

    local backpackLog = ""
    if brainrotSummary ~= "" then
        backpackLog = "🤖: "..brainrotSummary
    end
    if luckySummary ~= "" then
        if backpackLog ~= "" then
            backpackLog = backpackLog .. ", "
        end
        backpackLog = backpackLog .. "🎁: "..luckySummary
    end

    local description =
        "⚡: "..speed..", ".. 
        "🔁: "..rebirth..", ".. 
        "💰: "..token..
        (backpackLog ~= "" and (", "..backpackLog) or "")

    if _G.Horst_SetDescription then
        _G.Horst_SetDescription(description)
    end
end

sendDescription()

-- wait UI load
player:WaitForChild("PlayerGui",10)

-- run auto update every 30s
task.spawn(function()
    while true do
        sendDescription()
        task.wait(30)
    end
end)