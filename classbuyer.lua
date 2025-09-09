print("PawSHOP - Auto class buyer")

local Players = game:GetService("Players")
local player = Players.LocalPlayer
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ======================================================
-- CONFIG (taken from getgenv())
-- ======================================================
local Config = getgenv().ConfigsSettings or {
    AUTO_BUY_ENABLED = true,
    AUTO_REROLL_ENABLED = true,
    MIN_DIAMONDS_TO_REROLL = 600,
    CLASS_CHECK_INTERVAL = 5,
    REROLL_INTERVAL = 15,
    AutoBuyClass = {"Cyborg"},
    WEBHOOK_URL = nil, -- set this in getgenv()
}
-- ======================================================

-- GUI (wrapped in pcall to prevent warnings)
pcall(function()
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "PawSHOPGui"
    screenGui.Parent = player:WaitForChild("PlayerGui")

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 200, 0, 50)
    frame.Position = UDim2.new(1, -220, 0, 20)
    frame.BackgroundColor3 = Color3.fromRGB(54, 57, 63)
    frame.BorderSizePixel = 0
    frame.Parent = screenGui

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.Text = "PawSHOP is here"
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.TextScaled = true
    label.Parent = frame
end)

-- Webhook
local function sendWebhook(className, currentdiamond, totalClasses)
    if not Config.WEBHOOK_URL or Config.WEBHOOK_URL == "" then
        return -- skip if no webhook provided
    end

    local payload = {
        username = "PawSHOP",
        embeds = { {
            title = "🎉 Class Purchased!",
            description = "**Auto Class Buyer**",
            color = 0x00ff00,
            fields = {
                { name = "Player", value = player.Name, inline = true },
                { name = "Current Diamonds", value = tostring(currentdiamond), inline = true },
                { name = "Got Class", value = className, inline = true },
                { name = "Total Classes", value = totalClasses, inline = false },
                { name = "Timestamp", value = os.date("%Y-%m-%d %H:%M:%S"), inline = false }
            },
            author = { name = "PawSHOP" },
            footer = { text = "PawSHOP - Auto Class Buyer" }
        } }
    }

    local jsonData = HttpService:JSONEncode(payload)
    local req = request or http_request or (syn and syn.request)
    if req then
        req({
            Url = Config.WEBHOOK_URL,
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = jsonData
        })
    end
end

-- Helpers
local function getOwnedClassesSet()
    local owned = {}
    local classProgress = player:FindFirstChild("ClassProgress")
    if classProgress then
        for _, c in ipairs(classProgress:GetChildren()) do
            owned[c.Name] = true
        end
    end
    return owned
end

local function tryBuy(className)
    local ownedBefore = getOwnedClassesSet()
    if ownedBefore[className] then return false end

    ReplicatedStorage.RemoteEvents.RequestPurchaseClass:FireServer(className)
    task.wait(1.5)

    local ownedAfter = getOwnedClassesSet()
    if ownedAfter[className] then
        local DiamondsValue = player:GetAttribute("Diamonds") or 0
        local all = {}
        for k in pairs(ownedAfter) do table.insert(all, k) end
        table.sort(all)
        sendWebhook(className, DiamondsValue, table.concat(all, ", "))
        return true
    end
    return false
end

local function checkPlayerClasses()
    for _, className in ipairs(Config.AutoBuyClass) do
        if tryBuy(className) then break end
    end
end

local function rerollShop()
    local DiamondsValue = player:GetAttribute("Diamonds") or 0
    if DiamondsValue >= Config.MIN_DIAMONDS_TO_REROLL then
        local rerollPrice = player:GetAttribute("RerollPrice") or 0
        if rerollPrice == 0 then
            ReplicatedStorage.RemoteEvents.RequestRerollShop:FireServer()
        end
    end
end

-- Main loop
task.spawn(function()
    while true do
        if Config.AUTO_BUY_ENABLED then checkPlayerClasses() end
        if Config.AUTO_REROLL_ENABLED then rerollShop() end
        task.wait(Config.CLASS_CHECK_INTERVAL)
    end
end)
