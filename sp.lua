repeat task.wait() until game:IsLoaded()
repeat task.wait() until game:GetService("Players").LocalPlayer
repeat task.wait() until _G.Horst_SetDescription

task.wait(5)
print("PawSHOP loading...")
task.wait(5)
print("Log SP is now ready")

local players = game:GetService("Players").LocalPlayer

-- ฟังก์ชันแปลงตัวเลขเป็น K/M/B
local function formatNumber(num)
    if num >= 1e9 then
        return string.format("%.1fB", num/1e9)
    elseif num >= 1e6 then
        return string.format("%.1fM", num/1e6)
    elseif num >= 1e3 then
        return string.format("%.1fK", num/1e3)
    else
        return tostring(num)
    end
end

-- ฟังก์ชันแปลงชื่อ item เป็นชื่อที่ต้องการแสดง
local itemNameMap = {
    ["Strongest in History"] = "Sukuna V2"
    -- เพิ่ม mapping อื่น ๆ ได้ที่นี่
}

local function mapItemName(name)
    return itemNameMap[name] or name
end

-- ฟังก์ชันตรวจสอบของใน Backpack + Character สำหรับ Melee/Sword
local function checkItems(itemList)
    local backpack = players.Backpack
    local character = players.Character
    local result = {}
    for _, itemName in ipairs(itemList) do
        local found = false
        local lower = itemName:lower()
        for _, item in ipairs(backpack:GetChildren()) do
            if item.Name:lower() == lower then
                found = true
                break
            end
        end
        if not found and character then
            for _, item in ipairs(character:GetChildren()) do
                if item.Name:lower() == lower then
                    found = true
                    break
                end
            end
        end
        local displayName = mapItemName(itemName)
        table.insert(result, string.format("%s %s", displayName, found and "✔️" or "❌"))
    end
    return table.concat(result, ", ")
end

-- ฟังก์ชัน fire click ที่รองรับทุก executor (ใช้ getconnections)
local function clickButton(btn)
    local fired = false
    -- ลอง getconnections (รองรับเกือบทุก executor)
    if getconnections then
        for _, signal in pairs({"Activated", "MouseButton1Click", "MouseButton1Down"}) do
            pcall(function()
                for _, conn in pairs(getconnections(btn[signal])) do
                    conn:Fire()
                    fired = true
                end
            end)
            if fired then return end
        end
    end
    -- fallback: firesignal
    if not fired and firesignal then
        pcall(function() firesignal(btn.Activated) fired = true end)
    end
    if not fired and firesignal then
        pcall(function() firesignal(btn.MouseButton1Click) fired = true end)
    end
    -- fallback: fireclick
    if not fired and fireclick then
        pcall(function() fireclick(btn) fired = true end)
    end
end

-- ฟังก์ชันเปิด Stats UI แบบซ่อน (fire click ปุ่มจริง + ย้ายออกนอกจอ)
local function refreshStatsUI()
    local playerGui = players.PlayerGui

    -- หา MainFrame ของ StatsPanelUI
    local statsPanel = playerGui:FindFirstChild("StatsPanelUI")
    if not statsPanel then return end
    local mainFrame = statsPanel:FindFirstChild("MainFrame")
    if not mainFrame then return end

    -- เก็บค่าเดิม
    local oldPos = mainFrame.Position

    -- ย้าย MainFrame ออกนอกจอ
    mainFrame.Position = UDim2.new(5, 0, 5, 0)

    -- กดปุ่มเปิด Stats UI
    pcall(function()
        local statsBtn = playerGui.BasicStatsCurrencyAndButtonsUIOld.MainFrame.UIButtons.StatsButtonFrame.StatsButton
        clickButton(statsBtn)
    end)
    task.wait(0.5)

    -- กดปุ่ม Total Stats เพื่อสลับไปหน้า Page3 (Damage/Luck)
    pcall(function()
        local totalStatsBtn = statsPanel.MainFrame.Frame.Content.ToggleTabsFrame.TotalStatsButton
        clickButton(totalStatsBtn)
    end)
    task.wait(0.5)

    -- เรียก remote ด้วย
    pcall(function()
        game:GetService("ReplicatedStorage"):WaitForChild("Remotes"):WaitForChild("GetTotalStats"):InvokeServer()
    end)
    pcall(function()
        game:GetService("ReplicatedStorage"):WaitForChild("RemoteEvents"):WaitForChild("GetPlayerStats"):InvokeServer()
    end)
    task.wait(0.5)

    -- ปิด Stats UI
    pcall(function()
        local closeBtn = statsPanel.MainFrame.Frame.CloseButtonFrame.CloseButton
        clickButton(closeBtn)
    end)
    task.wait(0.1)

    -- คืนตำแหน่งเดิม
    mainFrame.Position = oldPos
end

task.spawn(function()
    while true do task.wait(20) -- loop
        refreshStatsUI()
        local level = players.Data.Level.Value
        local money = players.Data.Money.Value
        local gems = players.Data.Gems.Value
        local race = players:GetAttribute("CurrentRace") or "None"
        local clan = players:GetAttribute("CurrentClan") or "None"
        -- Luck Stat
        local luckStat = players.PlayerGui.StatsPanelUI.MainFrame.Frame.Content.Page3.LeftSideStatsFrame.Stats.StatsUtility.Stat1.Stat.Text:gsub("^%+", "")
        -- Damage Stat
        local damageStat = players.PlayerGui.StatsPanelUI.MainFrame.Frame.Content.Page3.LeftSideStatsFrame.Stats.StatsOffense.Stat1.Stat.Text:gsub("^%+", "")
        -- Trait
        local traitRaw = players.PlayerGui.StatsPanelUI.MainFrame.Frame.Content.SideFrame.UserStats.TraitEquipped.StatName.Text
        local trait = traitRaw:gsub("Trait: ", "")
        -- Melee Item Status (หลายชื่อ)
        local meleeStatus = checkItems(_G.Melee)
        -- Sword Item Status (หลายชื่อ)
        local swordStatus = checkItems(_G.Sword)
        -- แปลง money/gems
        local moneyStr = formatNumber(money)
        local gemsStr = formatNumber(gems)
        local messages = string.format(
            "Lv.%s 👊: %s ⚔️: %s 💵: %s 💠: %s 🧬: %s 👑: %s 🧩: %s 💥: %s 🍀: %s",
            level, meleeStatus, swordStatus, moneyStr, gemsStr, race, clan, trait, damageStat, luckStat
        )
        _G.Horst_SetDescription(messages)
    end
end)