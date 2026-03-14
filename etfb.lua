-- full open source, ETFB log description only works with horst rejoin

task.wait(5)
print("PawSHOP loading...")
task.wait(5)
print("Log ETFB is now ready")

local Players = game:GetService("Players")
local player = Players.LocalPlayer

-- CONFIG
_G.Display = _G.Display or {
    Brainrot = {"",},
    LuckyBox = {"",}
}

-- Waiting PlayerGui path safely
local function waitForPath(path)
    local current = player:WaitForChild("PlayerGui",10)
    for child in string.gmatch(path,"[^%.]+") do
        current = current:WaitForChild(child,10)
        if not current then return nil end
    end
    return current
end

-- Backpack summary
local function getBackpackSummary()

    local backpack = player:FindFirstChild("Backpack")
    if not backpack then return "","" end

    local brainrotNames = _G.Display.Brainrot or {}
    local luckyLevels = _G.Display.LuckyBox or {}

    local brainrotCounts = {}
    local luckyCounts = {}

    for _,item in ipairs(backpack:GetChildren()) do
        local brainrot = item:GetAttribute("BrainrotName")
        if brainrot and #brainrotNames > 0 then
            for _,name in ipairs(brainrotNames) do
                if name ~= "" and brainrot:find(name) then
                    local cleanName = brainrot:gsub("^%w+%s+","")
                    cleanName = cleanName:gsub("%s*%b()","")
                    brainrotCounts[cleanName] = (brainrotCounts[cleanName] or 0) + 1
                    break
                end
            end
        end

        local displayName = item:GetAttribute("DisplayName")
        if displayName and #luckyLevels > 0 then
            for _,level in ipairs(luckyLevels) do
                if level ~= "" and displayName:find(level) then
                    local cleanName = displayName:gsub("^%w+%s+","")
                    cleanName = cleanName:gsub("%s*%b()","")
                    luckyCounts[cleanName] = (luckyCounts[cleanName] or 0) + 1
                    break
                end
            end
        end
    end

    local brainrotSummary = ""
    for name,count in pairs(brainrotCounts) do
        if brainrotSummary ~= "" then brainrotSummary = brainrotSummary .. ", " end
        brainrotSummary = brainrotSummary .. name .. " x"..count
    end

    local luckySummary = ""
    for name,count in pairs(luckyCounts) do
        if luckySummary ~= "" then luckySummary = luckySummary .. ", " end
        luckySummary = luckySummary .. name .. " x"..count
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
            print("[DEBUG] Backpack summary start")
            print("[DEBUG] Config Brainrot:", table.concat(_G.Display.Brainrot or {}, ", "))
            print("[DEBUG] Config LuckyBox:", table.concat(_G.Display.LuckyBox or {}, ", "))
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
                print("[DEBUG] Item:", item.Name)
            -- fallback: ดึงตัวเลขแรกที่เจอ
                print("[DEBUG] brainrotName:", brainrot)
            rebirth = tostring(rebirthObj.Text):match("%d+") or "null"
        end
                        print("[DEBUG] Check brainrot config:", name)
    end
                            print("[DEBUG] Matched brainrot:", brainrot, "with", name)

    local backpackLog = ""
    if brainrotSummary ~= "" then
        backpackLog = "🤖: "..brainrotSummary
    end
    if luckySummary ~= "" then
        if backpackLog ~= "" then
            backpackLog = backpackLog .. ", "
        end
                print("[DEBUG] displayName:", displayName)
        backpackLog = backpackLog .. "🎁: "..luckySummary
    end
                        print("[DEBUG] Check lucky config:", level)

                            print("[DEBUG] Matched lucky:", displayName, "with", level)
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
            print("[DEBUG] brainrotSummary:", brainrotSummary)
            print("[DEBUG] luckySummary:", luckySummary)
    end
end)