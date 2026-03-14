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

    local brainrotName = _G.Display.Brainrot
    local luckyLevels = _G.Display.LuckyBox

    local brainrotCount = 0
    local luckyCount = 0
    local luckyName = ""

    -- ถ้า config ว่าง ไม่แสดงอะไรเลย
    if (not brainrotName or brainrotName == "") and (not luckyLevels or #luckyLevels == 0 or (luckyLevels[1] == "")) then
        return "", ""
    end

    for _,item in ipairs(backpack:GetChildren()) do
        local brainrot = item:GetAttribute("BrainrotName")
        if brainrotName and brainrotName ~= "" and brainrot and brainrot == brainrotName then
            brainrotCount = brainrotCount + 1
        end

        local displayName = item:GetAttribute("DisplayName")
        if displayName and luckyLevels and #luckyLevels > 0 and luckyLevels[1] ~= "" then
            for _,level in ipairs(luckyLevels) do
                if level ~= "" and displayName:find(level) then
                    luckyCount = luckyCount + 1
                    -- ตัด lv ออกจากชื่อ luckybox
                    local cleanName = displayName:gsub("%s*%b()","")
                    luckyName = cleanName
                    break
                end
            end
        end
    end

    local brainrotSummary =
        (brainrotName and brainrotName ~= "" and brainrotCount > 0) and (brainrotName .. " x"..brainrotCount) or ""

    local luckySummary =
        (luckyLevels and #luckyLevels > 0 and luckyLevels[1] ~= "" and luckyCount > 0) and (luckyName .. " x"..luckyCount) or ""

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
        return "null"
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