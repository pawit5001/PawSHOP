local Players = game:GetService("Players")
local player = Players.LocalPlayer

-- ฟังก์ชันดึงค่า Text ถ้าไม่มีให้เป็น "null"
local function safeText(obj)
    if obj and obj.Text and obj.Text ~= "" then
        return obj.Text
    else
        return "null"
    end
end

-- Clean race → "~ Human ~" → "Human"
local function cleanRace(str)
    if not str or str == "" then return "null" end
    return str:gsub("~", ""):gsub("^%s*(.-)%s*$", "%1")
end

-- ⭐ ฟอร์แมตทอง แบบย่อ มีทศนิยม 2 ตำแหน่ง เช่น 4186 -> $4.18K
local function formatGold(num)
    if not num then return "null" end

    -- ถ้า num เป็น string เอา $ และ , ออก
    if type(num) == "string" then
        num = num:gsub("[%$,]", "")
    end

    num = tonumber(num)
    if not num then return "null" end

    local formatted
    if num >= 1e9 then
        formatted = string.format("%.2fB", num / 1e9)
    elseif num >= 1e6 then
        formatted = string.format("%.2fM", num / 1e6)
    elseif num >= 1e3 then
        formatted = string.format("%.2fK", num / 1e3)
    else
        formatted = tostring(num)
    end

    return "$" .. formatted
end

-- Pickaxe ที่ต้องตรวจสอบ
local PICKAXE_REQUIRE = {
    ["Arcane Pickaxe"] = true,
    ["Demonic Pickaxe"] = true,
}

-- ฟังก์ชันเช็คว่า pickaxe ตาม whitelist มีไหม
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

-- ฟังก์ชันส่ง Description
local function sendDescription()
    -- gold (safeText → formatGold)
    local rawGold = safeText(player.PlayerGui.Main.Screen.Hud:FindFirstChild("Gold"))
    local gold = formatGold(rawGold)

    -- level
    local level = safeText(player.PlayerGui.Main.Screen.Hud:FindFirstChild("Level"))

    -- race
    local raceSlot = player.PlayerGui.Sell.RaceUI.StatMain.Slots:FindFirstChild("SlotTemplate")
    local race
    if raceSlot then
        local firstChild = raceSlot:FindFirstChildWhichIsA("TextLabel", true)
        race = firstChild and cleanRace(firstChild.Text) or "null"
    else
        race = "null"
    end

    -- pickaxe ✔️ / ❌
    local pickaxeStatus = getPickaxeStatus()
    local pickaxeText = ""

    for name, has in pairs(pickaxeStatus) do
        local mark = has and "✔️" or "❌"
        pickaxeText = pickaxeText .. name .. " " .. mark .. ", "
    end
    pickaxeText = pickaxeText:sub(1, #pickaxeText - 2)

    -- ⭐ รูปแบบ Final ที่ต้องการ
    local description =
        "⚔️: " .. level .. ", " ..
	    "💰: " .. gold .. ", " ..
        "⛏️: " .. pickaxeText .. ", " ..
        "🧬: " .. race

    -- ส่งไปให้ Horst
    _G.Horst_SetDescription(description)
end

-- ส่งครั้งแรก
sendDescription()

-- ส่งทุก 40 วินาที
task.spawn(function()
    while task.wait(40) do
        sendDescription()
    end
end)
