print("PawSHOP - Auto Class Buyer")

local Players = game:GetService("Players")
local player = Players.LocalPlayer
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ======================================================
-- CONFIG (taken from getgenv())
-- ======================================================
local Config = getgenv().ConfigsSettings or {
    AUTO_BUY_ENABLED = true,          -- default: enable auto buy
    AUTO_REROLL_ENABLED = true,       -- default: enable auto reroll
    MIN_DIAMONDS_TO_REROLL = 600,     -- minimum Diamonds required to reroll
    CLASS_CHECK_INTERVAL = 5,         -- check every 5s
    REROLL_INTERVAL = 15,             -- reroll interval
    AutoBuyClass = {"Cyborg"},        -- default class list
}
-- ======================================================

-- Simple GUI
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

-- Discord webhook
local WEBHOOK_URL = "https://discord.com/api/webhooks/XXXX/XXXX"

local function sendWebhook(className, currentdiamond, totalClasses)
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
            author = {
                name = "PawSHOP",
                icon_url = "https://media.discordapp.net/attachments/.../noFilter.png"
            },
            footer = { text = "PawSHOP" }
        } }
    }

    local jsonData = HttpService:JSONEncode(payload)
    local req = request or http_request or (syn and syn.request)
    if req then
        req({
            Url = WEBHOOK_URL,
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = jsonData
        })
    end
end

-- Helper: get owned classes
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

-- Try buy
local function tryBuy(className)
    local ownedBefore = getOwnedClassesSet()
    if ownedBefore[className] then
        print("[Skip]", player.Name, "already has", className)
        return false
    end

    ReplicatedStorage.RemoteEvents.RequestPurchaseClass:FireServer(className)
    print("[Run]", player.Name, "-> RequestPurchaseClass("..className..")")

    task.wait(1.5)

    local ownedAfter = getOwnedClassesSet()
    if ownedAfter[className] then
        local DiamondsValue = player:GetAttribute("Diamonds") or 0
        local all = {}
        for k in pairs(ownedAfter) do
            table.insert(all, k)
        end
        table.sort(all)
        local totalClassStr = (#all > 0) and table.concat(all, ", ") or "None"
        sendWebhook(className, DiamondsValue, totalClassStr)
        return true
    else
        print("[Skip] Failed to verify purchase for", className)
        return false
    end
end

-- Check auto buy
local function checkPlayerClasses()
    local list = Config.AutoBuyClass or {}
    if #list == 0 then
        warn("[Config] AutoBuyClass is empty. Nothing to buy.")
        return
    end

    for _, className in ipairs(list) do
        local success = tryBuy(className)
        if success then
            break
        end
    end
end

-- Auto reroll
local function rerollShop()
    local DiamondsValue = player:GetAttribute("Diamonds") or 0
    if DiamondsValue >= Config.MIN_DIAMONDS_TO_REROLL then
        local rerollPrice = player:GetAttribute("RerollPrice") or 0
        if rerollPrice == 0 then
            ReplicatedStorage.RemoteEvents.RequestRerollShop:FireServer()
            print("[Run] Successfully rerolled the shop.")
        else
            print("[Skip] Already rerolled.")
        end
    else
        print("[Skip] Not enough Diamonds to reroll ("..DiamondsValue..")")
    end
end

-- Main loop
task.spawn(function()
    while true do
        if Config.AUTO_BUY_ENABLED then
            checkPlayerClasses()
        end

        if Config.AUTO_REROLL_ENABLED then
            rerollShop()
        end

        task.wait(Config.CLASS_CHECK_INTERVAL)
    end
end)
