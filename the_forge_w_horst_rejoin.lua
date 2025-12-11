task.wait(10)
print("PawSHOP loading...")
task.wait(5)
print("Log The Forge is now ready")

local Players = game:GetService("Players")
local player = Players.LocalPlayer

-- Waiting PlayerGui path safely
local function waitForPath(path)
    local current = player:WaitForChild("PlayerGui", 10)
    for child in string.gmatch(path, "[^%.]+") do
        current = current:WaitForChild(child, 10)
        if not current then return nil end
    end
    return current
end

-- ดึง Text ปลอดภัย
local function safeText(obj)
    if obj and obj.Text and obj.Text ~= "" then
        return obj.Text
    else
        return "null"
    end
end

-- clean race
local function cleanRace(str)
    if not str or str == "" then return "null" end
    return str:gsub("~", ""):gsub("^%s*(.-)%s*$", "%1")
end

-- format gold
local function formatGold(num)
    if not num then return "null" end
    if type(num) == "string" then
        num = num:gsub("[%$,]", "")
    end
    num = tonumber(num)
    if not num then return "null" end

    local f
    if num >= 1e9 then
        f = string.format("%.2fB", num / 1e9)
    elseif num >= 1e6 then
        f = string.format("%.2fM", num / 1e6)
    elseif num >= 1e3 then
        f = string.format("%.2fK", num / 1e3)
    else
        f = tostring(num)
    end
    
    return "$" .. f
end

-- pickaxe whitelist
local PICKAXE_REQUIRE = {
    ["Arcane Pickaxe"] = true,
    ["Demonic Pickaxe"] = true,
}

local function getPickaxeStatus()
    local path = player.PlayerGui:FindFirstChild("Menu")
        and player.PlayerGui.Menu.Frame.Frame.Menus.Tools.Frame

    local result = {}
    for name in pairs(PICKAXE_REQUIRE) do
        result[name] = false
    end

    if not path then return result end

    for _, item in ipairs(path:GetChildren()) do
        if item:IsA("Frame") and PICKAXE_REQUIRE[item.Name] then
            result[item.Name] = true
        end
    end

    return result
end

--------------------------------------------------------
-- ⭐ รอ Race โหลดจนไม่เป็น "X"
--------------------------------------------------------
local function waitRaceLoaded()
    local race = "X"

    while race == "X" or race == "" or race == nil do
        task.wait(0.5)

        local slot = waitForPath("Sell.RaceUI.StatMain.Slots.SlotTemplate")
        if slot then
            local label = slot:FindFirstChildWhichIsA("TextLabel", true)
            if label then
                race = label.Text
            end
        end
    end

    return race
end

--------------------------------------------------------
-- ส่ง Description
--------------------------------------------------------
local function sendDescription()
    local goldObj = waitForPath("Main.Screen.Hud.Gold")
    local levelObj = waitForPath("Main.Screen.Hud.Level")

    if not goldObj or not levelObj then
        warn("Waiting for GUI… (HUD not ready)")
        return
    end

    local rawGold = safeText(goldObj)
    local gold = formatGold(rawGold)
    local level = safeText(levelObj)

    -- ⭐ Race ถูกต้องแน่นอน (ไม่ X)
    local raceRaw = waitRaceLoaded()
    local race = cleanRace(raceRaw)

    local pickaxeStatus = getPickaxeStatus()
    local pickaxeText = ""
    for name, has in pairs(pickaxeStatus) do
        pickaxeText = pickaxeText .. name .. (has and " ✔️" or " ❌") .. ", "
    end
    pickaxeText = pickaxeText:sub(1, -3)

    local description =
        "⚔️: " .. level .. ", " ..
        "💰: " .. gold .. ", " ..
        "⛏️: " .. pickaxeText .. ", " ..
        "🧬: " .. race

    warn("===== Description Log =====")
    warn("Gold Raw:", rawGold)
    warn("Gold Formatted:", gold)
    warn("Level:", level)
    warn("Race:", race)
    warn("Pickaxe:", pickaxeText)
    warn("Final Description:", description)
    warn("===========================")

    _G.Horst_SetDescription(description)
end

--------------------------------------------------------
-- ส่งครั้งแรก
--------------------------------------------------------
task.spawn(function()
    repeat task.wait(1) until player:FindFirstChild("PlayerGui") and player.PlayerGui:FindFirstChild("Main")
    sendDescription()
end)

--------------------------------------------------------
-- ส่งทุก 40 วิ
--------------------------------------------------------
task.spawn(function()
    while task.wait(40) do
        sendDescription()
    end
end)
