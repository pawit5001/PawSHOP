local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local localPlayer = Players.LocalPlayer
local ENV = getgenv()

-- =================== CONFIG ===================
local function toList(v)
    if type(v) == "string" then return {v} end
    if type(v) == "table"  then return v   end
    return {}
end

local CFG_SENDERS   = toList(ENV.Senders   or {""})
local CFG_RECEIVERS = toList(ENV.Receivers or {""})

local function isEmpty(v)
    if v == nil or v == "" then return true end
    if type(v) == "table" then
        if #v == 0 then return true end
        if #v == 1 and v[1] == "" then return true end
    end
    return false
end

-- Auto-fill
local SENDERS_AUTO_FILLED = false
local RECEIVERS_AUTO_FILLED = false

local function resolveAutoFill()
    local senderEmpty   = isEmpty(ENV.Senders)
    local receiverEmpty = isEmpty(ENV.Receivers)

    if not senderEmpty and not receiverEmpty then return end
    if senderEmpty and receiverEmpty then
        warn("[TRADE] Both Senders and Receivers are empty! Set at least one side.")
        return
    end

    local allPlayers = {}
    for _, p in ipairs(Players:GetPlayers()) do
        table.insert(allPlayers, p.Name)
    end

    if senderEmpty then
        local exclude = {}
        for _, name in ipairs(CFG_RECEIVERS) do exclude[name] = true end
        CFG_SENDERS = {}
        for _, name in ipairs(allPlayers) do
            if not exclude[name] then
                table.insert(CFG_SENDERS, name)
            end
        end
        print("[TRADE] Senders auto-filled:", #CFG_SENDERS, "player(s) =", table.concat(CFG_SENDERS, ", "))
        SENDERS_AUTO_FILLED = true
    else
        local exclude = {}
        for _, name in ipairs(CFG_SENDERS) do exclude[name] = true end
        CFG_RECEIVERS = {}
        for _, name in ipairs(allPlayers) do
            if not exclude[name] then
                table.insert(CFG_RECEIVERS, name)
            end
        end
        print("[TRADE] Receivers auto-filled:", #CFG_RECEIVERS, "player(s) =", table.concat(CFG_RECEIVERS, ", "))
        RECEIVERS_AUTO_FILLED = true
    end
end
resolveAutoFill()

-- Items config
local CFG_ITEMS = type(ENV.Items) == "table" and ENV.Items or {}
local CFG_ITEMS_ENABLE = (CFG_ITEMS.Enable ~= false)
local CFG_ITEMS_NAME   = CFG_ITEMS_ENABLE and (CFG_ITEMS.Names or {""}) or {}
local CFG_ITEMS_AMOUNT = CFG_ITEMS_ENABLE and (tonumber(CFG_ITEMS.Amount) or 0) or 0

local CFG_KICK_AFTER_DONE = (ENV.KickAfterDone == true)

local function getItemNameList()
    if type(CFG_ITEMS_NAME) == "string" then
        return {CFG_ITEMS_NAME}
    end
    return CFG_ITEMS_NAME
end

local function nameInList(name, list)
    for i = 1, #list do
        if list[i] == name then return true end
    end
    return false
end

local MAX_ADD_RETRIES = 5   -- max retry rounds when items fail to appear in trade slots

local isSender   = nameInList(localPlayer.Name, CFG_SENDERS)
local isReceiver = nameInList(localPlayer.Name, CFG_RECEIVERS)

-- =================== TRADE REMOTES ===================
local TradeRemotes = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("TradeRemotes")

local function getUserIdByName(name)
    local plr = Players:FindFirstChild(name)
    return plr and plr.UserId or nil
end

local function sendTradeRequest(targetName)
    local userId = getUserIdByName(targetName)
    if not userId then warn("[TRADE] User not found:", targetName) return false end
    TradeRemotes:WaitForChild("SendTradeRequest"):FireServer(userId)
    return true
end

local function addItemToTrade(itemName, amount)
    TradeRemotes:WaitForChild("AddItemToTrade"):FireServer("Items", itemName, amount)
end

local function setReady()
    TradeRemotes:WaitForChild("SetReady"):FireServer(true)
end

local function confirmTrade()
    TradeRemotes:WaitForChild("ConfirmTrade"):FireServer()
end

-- Check if InTradingUI is open (actual trade panel with items, not just request UI)
local function isTradingUIOpen()
    local gui = localPlayer:FindFirstChild("PlayerGui")
    if not gui then return false end
    local tradingUI = gui:FindFirstChild("InTradingUI")
    if not tradingUI then return false end
    if tradingUI:IsA("ScreenGui") then
        return tradingUI.Enabled
    end
    if tradingUI:IsA("GuiObject") then
        return tradingUI.Visible
    end
    return true
end

-- Wait for TradingUI to appear (up to timeoutSec seconds)
local function waitForTradingUI(timeoutSec)
    for t = 1, timeoutSec do
        if isTradingUIOpen() then
            print("[TRADE] TradingUI detected — trade window is open")
            return true
        end
        task.wait(1)
    end
    return false
end

local function requestInventory()
    pcall(function()
        ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("RequestInventory"):FireServer()
    end)
end

-- Toggle InventoryPanelUI open/close to force the game to refresh item data
local function toggleInventoryUI()
    local gui = localPlayer:FindFirstChild("PlayerGui")
    if not gui then return end
    local invUI = gui:FindFirstChild("InventoryPanelUI")
    if not invUI then return end
    if invUI:IsA("ScreenGui") then
        -- Close then re-open
        invUI.Enabled = false
        task.wait(0.3)
        invUI.Enabled = true
        task.wait(0.5)
        print("[TRADE] InventoryPanelUI toggled (close→open) to refresh")
    end
end

-- Toggle InTradingUI inventory popup to refresh trade inventory data
local function toggleTradeInventoryUI()
    local gui = localPlayer:FindFirstChild("PlayerGui")
    if not gui then return end
    local tradingUI = gui:FindFirstChild("InTradingUI")
    if not tradingUI then return end
    -- Find the InventoryPopup inside trade UI
    local path = tradingUI
    for _, name in ipairs({"MainFrame", "Frame", "Content", "Player1Side", "Player1Holder", "PopupHolder", "InventoryPopup"}) do
        path = path:FindFirstChild(name)
        if not path then return end
    end
    -- Toggle visibility
    if path:IsA("GuiObject") then
        path.Visible = false
        task.wait(0.3)
        path.Visible = true
        task.wait(0.5)
        print("[TRADE] Trade InventoryPopup toggled (close→open) to refresh")
    end
end

-- Scan player inventory from InventoryPanelUI (outside trade)
-- Path: PlayerGui.InventoryPanelUI.MainFrame.Frame.Content.Holder.StorageHolder.Storage
-- Children: Item_Obsidian, Item_BossKey, etc. → strip "Item_" prefix
-- Returns table: { ["Obsidian"] = 2, ["BossKey"] = 1, ... }
local function scanPlayerInventory()
    local gui = localPlayer:FindFirstChild("PlayerGui")
    if not gui then return {} end
    local invUI = gui:FindFirstChild("InventoryPanelUI")
    if not invUI then return {} end
    local mainFrame = invUI:FindFirstChild("MainFrame")
    if not mainFrame then return {} end
    local frame = mainFrame:FindFirstChild("Frame")
    if not frame then return {} end
    local content = frame:FindFirstChild("Content")
    if not content then return {} end
    local holder = content:FindFirstChild("Holder")
    if not holder then return {} end
    local storageHolder = holder:FindFirstChild("StorageHolder")
    if not storageHolder then return {} end
    local storage = storageHolder:FindFirstChild("Storage")
    if not storage then return {} end

    local counts = {}
    for _, child in ipairs(storage:GetChildren()) do
        local name = child.Name
        if string.sub(name, 1, 5) == "Item_" then
            local itemName = string.sub(name, 6)
            counts[itemName] = (counts[itemName] or 0) + 1
        end
    end
    return counts
end

-- Print inventory snapshot
local function printInventory(label, inv)
    local parts = {}
    for name, count in pairs(inv) do
        table.insert(parts, name .. " x" .. count)
    end
    if #parts == 0 then
        print(label, "(empty)")
    else
        table.sort(parts)
        print(label, #parts, "type(s):", table.concat(parts, ", "))
    end
end

-- Compare two inventory snapshots and print diff
local function printInventoryDiff(label, before, after)
    local allNames = {}
    for name in pairs(before) do allNames[name] = true end
    for name in pairs(after) do allNames[name] = true end

    local changes = {}
    for name in pairs(allNames) do
        local b = before[name] or 0
        local a = after[name] or 0
        if a ~= b then
            local diff = a - b
            local sign = diff > 0 and "+" or ""
            table.insert(changes, name .. " " .. sign .. diff .. " (" .. b .. "→" .. a .. ")")
        end
    end

    if #changes == 0 then
        print(label, "No changes")
    else
        table.sort(changes)
        print(label, #changes, "change(s):", table.concat(changes, ", "))
    end
end

-- Scan item names from the trading inventory UI (inside trade)
-- Path: PlayerGui.InTradingUI.MainFrame.Frame.Content.Player1Side.Player1Holder.PopupHolder.InventoryPopup.Content.Inventory
-- Children: Obsidian, BossKey, etc. (no prefix — use directly with addItemToTrade)
-- Returns table: { ["Obsidian"] = 2, ["BossKey"] = 1, ... }
local function scanInventoryUI()
    local gui = localPlayer:FindFirstChild("PlayerGui")
    if not gui then return {} end
    local tradingUI = gui:FindFirstChild("InTradingUI")
    if not tradingUI then return {} end
    local mainFrame = tradingUI:FindFirstChild("MainFrame")
    if not mainFrame then return {} end
    local frame = mainFrame:FindFirstChild("Frame")
    if not frame then return {} end
    local content = frame:FindFirstChild("Content")
    if not content then return {} end
    local p1Side = content:FindFirstChild("Player1Side")
    if not p1Side then return {} end
    local p1Holder = p1Side:FindFirstChild("Player1Holder")
    if not p1Holder then return {} end
    local popupHolder = p1Holder:FindFirstChild("PopupHolder")
    if not popupHolder then return {} end
    local invPopup = popupHolder:FindFirstChild("InventoryPopup")
    if not invPopup then return {} end
    local invContent = invPopup:FindFirstChild("Content")
    if not invContent then return {} end
    local inventory = invContent:FindFirstChild("Inventory")
    if not inventory then return {} end

    local counts = {}
    for _, child in ipairs(inventory:GetChildren()) do
        if child:IsA("ImageButton") or child:IsA("TextButton") then
            local name = child.Name
            if name ~= "" then
                -- Read quantity from Slot.Holder.Quantity
                local qty = 1
                local slot = child:FindFirstChild("Slot")
                if slot then
                    local holder = slot:FindFirstChild("Holder")
                    if holder then
                        local qtyLabel = holder:FindFirstChild("Quantity")
                        if qtyLabel and qtyLabel.Text then
                            qty = tonumber(qtyLabel.Text:match("%d+")) or 1
                        end
                    end
                end
                counts[name] = (counts[name] or 0) + qty
            end
        end
    end
    return counts
end

-- Scan trade slots to verify items actually added to trade
-- Path: InTradingUI.MainFrame.Frame.Content.Player1Side.Player1Holder.Player1Items.TradeSlot_N.Slot.Holder.ItemName / Quantity
-- Returns array: { {name="Obsidian", quantity=9}, {name="Iron", quantity=15}, ... }
local function scanTradeSlots()
    local gui = localPlayer:FindFirstChild("PlayerGui")
    if not gui then return {} end
    local tradingUI = gui:FindFirstChild("InTradingUI")
    if not tradingUI then return {} end
    local mainFrame = tradingUI:FindFirstChild("MainFrame")
    if not mainFrame then return {} end
    local frame = mainFrame:FindFirstChild("Frame")
    if not frame then return {} end
    local content = frame:FindFirstChild("Content")
    if not content then return {} end
    local p1Side = content:FindFirstChild("Player1Side")
    if not p1Side then return {} end
    local p1Holder = p1Side:FindFirstChild("Player1Holder")
    if not p1Holder then return {} end
    local p1Items = p1Holder:FindFirstChild("Player1Items")
    if not p1Items then return {} end

    local slots = {}
    for _, child in ipairs(p1Items:GetChildren()) do
        if string.sub(child.Name, 1, 10) == "TradeSlot_" then
            local slot = child:FindFirstChild("Slot")
            if slot then
                local holder = slot:FindFirstChild("Holder")
                if holder then
                    local nameLabel = holder:FindFirstChild("ItemName")
                    local qtyLabel = holder:FindFirstChild("Quantity")
                    local itemName = nameLabel and nameLabel.Text or "?"
                    local qtyText = qtyLabel and qtyLabel.Text or "1"
                    -- Strip non-numeric chars (e.g. "x15" → 15)
                    local qty = tonumber(qtyText:match("%d+")) or 1
                    table.insert(slots, {name = itemName, quantity = qty})
                end
            end
        end
    end
    return slots
end

-- Scan Player2's trade slots (the other player's offered items)
-- Path: InTradingUI.MainFrame.Frame.Content.Player2Side.Player2Holder.Player2Items.TradeSlot_N.Slot.Holder.ItemName / Quantity
-- Returns array: { {name="Obsidian", quantity=9}, ... }
local function scanPlayer2TradeSlots()
    local gui = localPlayer:FindFirstChild("PlayerGui")
    if not gui then return {} end
    local tradingUI = gui:FindFirstChild("InTradingUI")
    if not tradingUI then return {} end
    local mainFrame = tradingUI:FindFirstChild("MainFrame")
    if not mainFrame then return {} end
    local frame = mainFrame:FindFirstChild("Frame")
    if not frame then return {} end
    local content = frame:FindFirstChild("Content")
    if not content then return {} end
    local p2Side = content:FindFirstChild("Player2Side")
    if not p2Side then return {} end
    local p2Holder = p2Side:FindFirstChild("Player2Holder")
    if not p2Holder then return {} end
    local p2Items = p2Holder:FindFirstChild("Player2Items")
    if not p2Items then return {} end

    local slots = {}
    for _, child in ipairs(p2Items:GetChildren()) do
        if string.sub(child.Name, 1, 10) == "TradeSlot_" then
            local slot = child:FindFirstChild("Slot")
            if slot then
                local holder = slot:FindFirstChild("Holder")
                if holder then
                    local nameLabel = holder:FindFirstChild("ItemName")
                    local qtyLabel = holder:FindFirstChild("Quantity")
                    local itemName = nameLabel and nameLabel.Text or "?"
                    local qtyText = qtyLabel and qtyLabel.Text or "1"
                    local qty = tonumber(qtyText:match("%d+")) or 1
                    if itemName ~= "?" and itemName ~= "" then
                        table.insert(slots, {name = itemName, quantity = qty})
                    end
                end
            end
        end
    end
    return slots
end

-- Click button using multiple methods (getconnections → firesignal → fireclick → VIM)
local function clickButton(btn, label)
    if not btn then return false end
    label = label or "Button"

    local clicked = false
    -- Method 1: getconnections
    if not clicked then
        pcall(function()
            local conns = getconnections(btn.Activated)
            if conns and #conns > 0 then
                for _, conn in ipairs(conns) do
                    if conn.Fire then conn:Fire() end
                end
                clicked = true
            end
        end)
    end
    if not clicked then
        pcall(function()
            local conns = getconnections(btn.MouseButton1Click)
            if conns and #conns > 0 then
                for _, conn in ipairs(conns) do
                    if conn.Fire then conn:Fire() end
                end
                clicked = true
            end
        end)
    end
    if clicked then return true end

    -- Method 2: firesignal
    if not clicked then
        local ok = pcall(function() firesignal(btn.Activated) end)
        if ok then clicked = true end
    end
    if not clicked then
        local ok = pcall(function() firesignal(btn.MouseButton1Click) end)
        if ok then clicked = true end
    end
    if clicked then return true end

    -- Method 3: fireclick
    if not clicked then
        local ok = pcall(function() fireclick(btn) end)
        if ok then clicked = true end
    end
    if clicked then return true end

    -- Method 4: VirtualInputManager
    if not clicked then
        pcall(function()
            local vim = game:GetService("VirtualInputManager")
            local pos = btn.AbsolutePosition
            local size = btn.AbsoluteSize
            local cx = pos.X + size.X / 2
            local cy = pos.Y + size.Y / 2
            vim:SendMouseButtonEvent(cx, cy, 0, true, game, 1)
            task.wait(0.05)
            vim:SendMouseButtonEvent(cx, cy, 0, false, game, 1)
            clicked = true
        end)
    end

    return clicked
end

local function clickAcceptTradeRequest()
    local gui = localPlayer:FindFirstChild("PlayerGui")
    if not gui then return false end
    local reqUI = gui:FindFirstChild("TradeRequestUI")
    if not reqUI then return false end
    -- Check ScreenGui is enabled
    if reqUI:IsA("ScreenGui") and not reqUI.Enabled then return false end
    local tr = reqUI:FindFirstChild("TradeRequest")
    if not tr then return false end
    -- Check TradeRequest frame is visible
    if tr:IsA("GuiObject") and not tr.Visible then return false end
    local holder = tr:FindFirstChild("ButtonsHolder")
    if not holder then return false end
    local yesBtn = holder:FindFirstChild("Yes")
    if not yesBtn then return false end
    -- Check button is visible
    if yesBtn:IsA("GuiObject") and not yesBtn.Visible then return false end
    return clickButton(yesBtn, "AcceptTradeRequest")
end

-- Click READY/CONFIRM button — direct path: [Side].[Holder].Buttons.Ready
-- This button serves as both Ready and Confirm (click once = Ready, click again = Confirm)
local function clickReadyButton(onlySide)
    local gui = localPlayer:FindFirstChild("PlayerGui")
    if not gui then return false end
    local tradingUI = gui:FindFirstChild("InTradingUI")
    if not tradingUI then return false end

    local sides = onlySide and {onlySide} or {"Player1Side", "Player2Side"}
    for _, side in ipairs(sides) do
        local holder = side == "Player1Side" and "Player1Holder" or "Player2Holder"
        local path = tradingUI
        for _, name in ipairs({"MainFrame", "Frame", "Content", side, holder, "Buttons", "Ready"}) do
            path = path:FindFirstChild(name)
            if not path then break end
        end
        if path and (path:IsA("TextButton") or path:IsA("ImageButton")) and path.Visible then
            return clickButton(path, "ReadyButton(" .. side .. ")")
        end
    end

    return false
end

-- Click CONFIRM button — same Ready button, but only when Txt child shows "CONFIRM"
-- Path: [Side].[Holder].Buttons.Ready  (child Txt.Text changes: READY → CONFIRM → CONFIRMED)
local function clickConfirmTrade(onlySide)
    local gui = localPlayer:FindFirstChild("PlayerGui")
    if not gui then return false end
    local tradingUI = gui:FindFirstChild("InTradingUI")
    if not tradingUI then return false end

    local sides = onlySide and {onlySide} or {"Player1Side", "Player2Side"}
    for _, side in ipairs(sides) do
        local holder = side == "Player1Side" and "Player1Holder" or "Player2Holder"
        local path = tradingUI
        for _, name in ipairs({"MainFrame", "Frame", "Content", side, holder, "Buttons", "Ready"}) do
            path = path:FindFirstChild(name)
            if not path then break end
        end
        if path and (path:IsA("TextButton") or path:IsA("ImageButton")) and path.Visible then
            -- Check if Txt child shows "CONFIRM" (not "READY" or "CONFIRMED")
            local txt = path:FindFirstChild("Txt")
            local txtVal = ""
            if txt and txt:IsA("TextLabel") then
                txtVal = (txt.Text or ""):upper()
            elseif path:IsA("TextButton") then
                txtVal = (path.Text or ""):upper()
            end
            if txtVal == "CONFIRM" then
                return clickButton(path, "ConfirmTrade(" .. side .. ")")
            end
        end
    end

    return false
end

-- Check if Ready button's Txt shows we are already in ready/confirmed state
local function isReadyButtonConfirmState(onlySide)
    local gui = localPlayer:FindFirstChild("PlayerGui")
    if not gui then return false end
    local tradingUI = gui:FindFirstChild("InTradingUI")
    if not tradingUI then return false end

    local sides = onlySide and {onlySide} or {"Player1Side", "Player2Side"}
    for _, side in ipairs(sides) do
        local holder = side == "Player1Side" and "Player1Holder" or "Player2Holder"
        local path = tradingUI
        for _, name in ipairs({"MainFrame", "Frame", "Content", side, holder, "Buttons", "Ready"}) do
            path = path:FindFirstChild(name)
            if not path then break end
        end
        if path and path.Visible then
            local txt = path:FindFirstChild("Txt")
            if txt and txt:IsA("TextLabel") then
                local val = (txt.Text or ""):upper()
                -- After clicking Ready: READY → CONFIRM → CONFIRMED / Waiting...
                if val ~= "READY" and val ~= "DECLINE" and val ~= "" then
                    return true
                end
            end
        end
    end
    return false
end

-- Close trade window — try multiple approaches for both TradingUI and InTradingUI
local function closeTrade()
    local gui = localPlayer:FindFirstChild("PlayerGui")
    if not gui then return end
    local closed = false

    -- Method 1: Try CancelTrade remote (most reliable if it exists)
    pcall(function()
        TradeRemotes:WaitForChild("CancelTrade", 1)
        if TradeRemotes:FindFirstChild("CancelTrade") then
            TradeRemotes.CancelTrade:FireServer()
            closed = true
            print("[TRADE] CancelTrade remote fired")
        end
    end)

    -- Method 2: Search for close/cancel buttons in BOTH trade UIs
    for _, uiName in ipairs({"InTradingUI", "TradingUI"}) do
        local tradeUI = gui:FindFirstChild(uiName)
        if tradeUI then
            for _, desc in ipairs(tradeUI:GetDescendants()) do
                if (desc:IsA("TextButton") or desc:IsA("ImageButton")) and desc.Visible then
                    local name = desc.Name:lower()
                    -- Check by name
                    if name == "close" or name == "closebutton" or name == "cancel" or name == "cancelbutton" or name == "close_button" then
                        clickButton(desc, "Close(" .. uiName .. ")")
                        closed = true
                    end
                    -- Check by text content
                    local txt = ""
                    if desc:IsA("TextButton") then txt = (desc.Text or ""):lower() end
                    if txt:find("cancel") or txt:find("close") then
                        clickButton(desc, "Close(" .. uiName .. ")")
                        closed = true
                    end
                    -- Check child TextLabel
                    for _, child in ipairs(desc:GetChildren()) do
                        if child:IsA("TextLabel") then
                            local childTxt = (child.Text or ""):lower()
                            if childTxt:find("cancel") or childTxt:find("close") then
                                clickButton(desc, "Close(" .. uiName .. ")")
                                closed = true
                            end
                        end
                    end
                end
            end
        end
    end

    -- Method 3: Force disable ScreenGuis directly
    if not closed then
        for _, uiName in ipairs({"InTradingUI", "TradingUI"}) do
            local tradeUI = gui:FindFirstChild(uiName)
            if tradeUI and tradeUI:IsA("ScreenGui") and tradeUI.Enabled then
                tradeUI.Enabled = false
                print("[TRADE] Force disabled", uiName)
                closed = true
            end
        end
    end

    if closed then
        print("[TRADE] Trade window closed")
    else
        warn("[TRADE] Could not close trade window")
    end
end

-- =================== DONE + KICK ===================
local function callDone()
    if _G.Horst_AccountChangeDone then
        pcall(function()
            _G.Horst_AccountChangeDone()
        end)
        task.wait(2)
    end
    if CFG_KICK_AFTER_DONE then
        pcall(function()
            localPlayer:Kick("[TRADE] Done!")
        end)
    end
end

-- =================== TRADE STATE CHECKS ===================

-- Check if the other player's ReadyIndicator is visible on a specific side
local function isPlayerReadyOnSide(checkSide)
    local gui = localPlayer:FindFirstChild("PlayerGui")
    if not gui then return false end
    local tradingUI = gui:FindFirstChild("InTradingUI")
    if not tradingUI then return false end

    for _, desc in ipairs(tradingUI:GetDescendants()) do
        if desc.Name == "ReadyIndicator" then
            local fullName = desc:GetFullName()
            if string.find(fullName, checkSide) then
                if desc:IsA("GuiObject") and desc.Visible then
                    return true
                end
            end
        end
    end
    return false
end

-- Sender checks if receiver (Player2) is ready
local function isOtherPlayerReady()
    return isPlayerReadyOnSide("Player2")
end

-- Receiver checks if sender is ready
-- Path: Player2Side.Player2Holder.Player2Holder.ReadyIndicator.Txt  (Text == "READY" means sender pressed Ready)
local function isSenderReadyFromReceiver()
    local gui = localPlayer:FindFirstChild("PlayerGui")
    if not gui then return false end
    local tradingUI = gui:FindFirstChild("InTradingUI")
    if not tradingUI then return false end

    local path = tradingUI
    for _, name in ipairs({"MainFrame", "Frame", "Content", "Player2Side", "Player2Holder", "Player2Holder", "ReadyIndicator"}) do
        path = path:FindFirstChild(name)
        if not path then return false end
    end

    -- Check visibility first
    if path:IsA("GuiObject") and not path.Visible then return false end

    -- Check Txt child text
    local txt = path:FindFirstChild("Txt")
    if txt and txt:IsA("TextLabel") then
        local val = (txt.Text or ""):upper()
        if val == "READY" then return true end
    end

    return false
end

-- Check if items appeared in the trade from the other side (Player2's offer)
local function otherPlayerHasItems()
    local gui = localPlayer:FindFirstChild("PlayerGui")
    if not gui then return false end
    local tradingUI = gui:FindFirstChild("InTradingUI")
    if not tradingUI then return false end

    -- Look for Player2Holder or Player2Side items
    for _, desc in ipairs(tradingUI:GetDescendants()) do
        local fullName = desc:GetFullName()
        if string.find(fullName, "Player2") and string.find(fullName, "Offer") then
            if desc:IsA("Frame") or desc:IsA("ScrollingFrame") then
                local children = desc:GetChildren()
                local itemCount = 0
                for _, child in ipairs(children) do
                    if child:IsA("ImageButton") or child:IsA("TextButton") or child:IsA("ImageLabel") then
                        itemCount = itemCount + 1
                    end
                end
                if itemCount > 0 then
                    return true
                end
            end
        end
    end
    return false
end

-- =================== SENDER LOGIC ===================
local function runSender()
    print("[TRADE] Sender starting...")
    local configNames = getItemNameList()
    local amount = CFG_ITEMS_AMOUNT

    -- Fire RequestInventory + toggle UI to force refresh
    requestInventory()
    task.wait(1)
    toggleInventoryUI()
    task.wait(1)

    -- Pre-trade inventory snapshot (outside trade — InventoryPanelUI)
    local invBefore = scanPlayerInventory()
    printInventory("[TRADE][SENDER] Inventory before:", invBefore)

    for _, receiverName in ipairs(CFG_RECEIVERS) do
        print("[TRADE][SENDER] Trading to receiver:", receiverName)

        -- 1. Send trade request
        local ok = sendTradeRequest(receiverName)
        if not ok then
            warn("[TRADE][SENDER] Failed to send trade request to", receiverName)
        else
            -- 2. Wait for TradingUI to appear (receiver accepted)
            print("[TRADE][SENDER] Waiting for trade window to open...")
            local tradeOpened = waitForTradingUI(15)
            if not tradeOpened then
                warn("[TRADE][SENDER] TradingUI not detected in 15s — skipping", receiverName)
                closeTrade()
                task.wait(1)
            else

            -- 3. Add items (only if enabled)
            if CFG_ITEMS_ENABLE then
                -- Toggle trade inventory popup to refresh, then scan
                task.wait(1)
                toggleTradeInventoryUI()
                local tradeInv = scanInventoryUI()
                printInventory("[TRADE][SENDER] Trade UI inventory:", tradeInv)

                -- Determine which items to send: { [itemName] = sendAmount }
                local itemsToSend = {}
                local itemNames = configNames
                local sendAll = isEmpty(configNames)
                if sendAll then
                    itemNames = {}
                    for itemName in pairs(tradeInv) do
                        table.insert(itemNames, itemName)
                    end
                    if #itemNames == 0 then
                        warn("[TRADE][SENDER] No items found in trade UI inventory!")
                    else
                        print("[TRADE][SENDER] Sending all", #itemNames, "item type(s)")
                    end
                end

                for _, itemName in ipairs(itemNames) do
                    if itemName ~= "" then
                        local have = tradeInv[itemName] or 0
                        local sendAmount
                        if amount > 0 then
                            sendAmount = math.min(amount, have)
                        else
                            sendAmount = have
                        end
                        if sendAmount > 0 then
                            itemsToSend[itemName] = sendAmount
                        end
                    end
                end

                -- Add items with retry — keep trying until all items appear in trade slots
                for attempt = 1, MAX_ADD_RETRIES do
                    -- Fire AddItemToTrade for each pending item
                    local addedCount = 0
                    for itemName, sendAmount in pairs(itemsToSend) do
                        local args = {"Items", itemName, sendAmount}
                        ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("TradeRemotes"):WaitForChild("AddItemToTrade"):FireServer(unpack(args))
                        print("[TRADE][SENDER] Added item:", itemName, "x" .. sendAmount, "(attempt " .. attempt .. ")")
                        addedCount = addedCount + 1
                        task.wait(0.5)
                    end

                    if addedCount == 0 then break end
                    task.wait(1)

                    -- Verify which items actually appeared in trade slots
                    local tradeSlots = scanTradeSlots()
                    local slotsMap = {}  -- { [itemName] = quantity }
                    for _, slot in ipairs(tradeSlots) do
                        slotsMap[slot.name] = (slotsMap[slot.name] or 0) + slot.quantity
                    end

                    print("[TRADE][SENDER] Trade slots after attempt", attempt, ":", #tradeSlots, "slot(s)")
                    for _, slot in ipairs(tradeSlots) do
                        print("[TRADE][SENDER]   ", slot.name, "x" .. slot.quantity)
                    end

                    -- Check which items are still missing or have wrong quantity
                    local missing = {}
                    for itemName, sendAmount in pairs(itemsToSend) do
                        local inSlot = slotsMap[itemName] or 0
                        if inSlot < sendAmount then
                            missing[itemName] = sendAmount -- re-send full amount (server replaces)
                        end
                    end

                    if next(missing) == nil then
                        print("[TRADE][SENDER] All items verified in trade slots!")
                        break
                    else
                        local missingList = {}
                        for name, qty in pairs(missing) do
                            table.insert(missingList, name .. " x" .. qty)
                        end
                        warn("[TRADE][SENDER] Missing items after attempt " .. attempt .. ": " .. table.concat(missingList, ", "))
                        if attempt < MAX_ADD_RETRIES then
                            itemsToSend = missing  -- only retry missing items
                            task.wait(1)
                        else
                            warn("[TRADE][SENDER] Giving up after " .. MAX_ADD_RETRIES .. " attempts — proceeding with what's in slots")
                        end
                    end
                end
            end

            -- 4. Set ready (fire remote + click UI button)
            setReady()
            task.wait(0.5)
            clickReadyButton("Player1Side")
            print("[TRADE][SENDER] Ready!")

            -- 5. Wait for receiver to be ready (poll up to 30s)
            print("[TRADE][SENDER] Waiting for receiver to be ready...")
            local otherReady = false
            for t = 1, 30 do
                if isOtherPlayerReady() then
                    otherReady = true
                    print("[TRADE][SENDER] Receiver is ready!")
                    break
                end
                task.wait(1)
            end
            if not otherReady then
                warn("[TRADE][SENDER] Receiver not ready in 30s — confirming anyway")
            end

            -- 6. Wait 5s cooldown then confirm (fire remote + click UI button)
            print("[TRADE][SENDER] Waiting 5s before confirm...")
            task.wait(5)
            confirmTrade()
            task.wait(0.5)
            clickConfirmTrade("Player1Side")
            print("[TRADE][SENDER] Confirmed!")

            -- 7. Wait for trade to complete — spam confirm + check inventory
            print("[TRADE][SENDER] Waiting for trade to complete...")
            local tradeDone = false
            for t = 1, 30 do
                if not isTradingUIOpen() then
                    print("[TRADE][SENDER] Trade UI closed!")
                    tradeDone = true
                    break
                end
                -- Keep spamming confirm in case it didn't go through
                pcall(function() confirmTrade() end)
                pcall(function() clickConfirmTrade("Player1Side") end)
                -- After 1s, refresh inventory to detect trade completion
                if t >= 1 and t % 2 == 0 then
                    requestInventory()
                    task.wait(0.3)
                    toggleInventoryUI()
                    task.wait(0.5)
                    local invCheck = scanPlayerInventory()
                    local changed = false
                    for name in pairs(invBefore) do
                        if (invCheck[name] or 0) ~= invBefore[name] then changed = true break end
                    end
                    if not changed then
                        for name in pairs(invCheck) do
                            if (invBefore[name] or 0) ~= invCheck[name] then changed = true break end
                        end
                    end
                    if changed then
                        print("[TRADE][SENDER] Inventory changed — trade completed!")
                        tradeDone = true
                        break
                    end
                end
                task.wait(1)
            end
            if not tradeDone and isTradingUIOpen() then
                warn("[TRADE][SENDER] Trade UI still open after 30s — force closing")
                closeTrade()
                task.wait(1)
            end

            -- Post-trade inventory check — toggle UI to refresh counts
            task.wait(1)
            requestInventory()
            task.wait(1)
            toggleInventoryUI()
            task.wait(1)
            local invAfterTrade = scanPlayerInventory()
            printInventoryDiff("[TRADE][SENDER] After trade with " .. receiverName .. ":", invBefore, invAfterTrade)
            invBefore = invAfterTrade

            end -- end tradeOpened
        end
    end

    -- Final inventory (refresh UI first)
    requestInventory()
    task.wait(1)
    toggleInventoryUI()
    task.wait(1)
    local invFinal = scanPlayerInventory()
    printInventory("[TRADE][SENDER] Final inventory:", invFinal)

    callDone()
end

-- =================== RECEIVER LOGIC ===================
local function runReceiver()
    print("[TRADE] Receiver starting...")

    -- Fire RequestInventory + toggle UI to force refresh
    requestInventory()
    task.wait(1)
    toggleInventoryUI()
    task.wait(1)

    -- Pre-trade inventory snapshot (outside trade — InventoryPanelUI)
    local invBefore = scanPlayerInventory()
    printInventory("[TRADE][RECEIVER] Inventory before:", invBefore)

    for i = 1, #CFG_SENDERS do
        print("[TRADE][RECEIVER] Waiting for sender:", CFG_SENDERS[i])

        -- 1. Wait for trade request and accept (30s to give sender time to send)
        local accepted = false
        for t = 1, 30 do
            if clickAcceptTradeRequest() then
                accepted = true
                print("[TRADE][RECEIVER] Accepted trade request!")
                break
            end
            task.wait(1)
        end

        if not accepted then
            warn("[TRADE][RECEIVER] No trade request from", CFG_SENDERS[i])
        else
            -- 2. Wait for TradingUI to appear (trade window opened)
            print("[TRADE][RECEIVER] Waiting for trade window to open...")
            local tradeOpened = waitForTradingUI(10)
            if tradeOpened then
                print("[TRADE][RECEIVER] Trade window is open!")
            else
                warn("[TRADE][RECEIVER] TradingUI not detected — continuing anyway")
            end

            -- 3. Wait for sender to press Ready, then receiver presses Ready, then Confirm
            local tradeCompleted = false

            -- Phase 1: Wait for sender to add items + press Ready
            -- Minimum 5s wait to let UI settle, then check sender's ReadyIndicator
            print("[TRADE][RECEIVER] Waiting for sender to press Ready...")
            local senderReadyDetected = false
            for t = 1, 45 do
                if not isTradingUIOpen() then
                    print("[TRADE][RECEIVER] Trade UI closed!")
                    tradeCompleted = true
                    break
                end
                -- Only start checking after 5s to avoid false positives during UI load
                if t >= 5 and isSenderReadyFromReceiver() then
                    senderReadyDetected = true
                    print("[TRADE][RECEIVER] Sender pressed Ready! (detected at " .. t .. "s)")
                    break
                end
                task.wait(1)
            end
            if not tradeCompleted and not senderReadyDetected then
                print("[TRADE][RECEIVER] Sender Ready not detected in 45s — pressing Ready anyway")
            end

            -- Phase 2: Spam Ready until button text changes from "READY"
            if not tradeCompleted then
                print("[TRADE][RECEIVER] Pressing Ready...")
                for t = 1, 15 do
                    if not isTradingUIOpen() then
                        tradeCompleted = true
                        break
                    end
                    pcall(function() setReady() end)
                    pcall(function() clickReadyButton("Player2Side") end)
                    task.wait(0.5)
                    -- Check if button changed to confirm state
                    if isReadyButtonConfirmState("Player2Side") then
                        print("[TRADE][RECEIVER] Ready accepted — button in confirm state")
                        break
                    end
                end
            end

            -- Phase 3: Spam Confirm + check inventory to detect trade completion
            if not tradeCompleted then
                print("[TRADE][RECEIVER] Pressing Confirm...")
                for t = 1, 30 do
                    if not isTradingUIOpen() then
                        print("[TRADE][RECEIVER] Trade UI closed — trade completed!")
                        tradeCompleted = true
                        break
                    end
                    pcall(function() confirmTrade() end)
                    pcall(function() clickConfirmTrade("Player2Side") end)
                    -- After 1s, refresh inventory to detect trade completion
                    if t >= 1 and t % 2 == 0 then
                        requestInventory()
                        task.wait(0.3)
                        toggleInventoryUI()
                        task.wait(0.5)
                        local invCheck = scanPlayerInventory()
                        local changed = false
                        for name in pairs(invCheck) do
                            if (invBefore[name] or 0) ~= invCheck[name] then changed = true break end
                        end
                        if not changed then
                            for name in pairs(invBefore) do
                                if (invCheck[name] or 0) ~= invBefore[name] then changed = true break end
                            end
                        end
                        if changed then
                            print("[TRADE][RECEIVER] Inventory changed — trade completed!")
                            tradeCompleted = true
                            break
                        end
                    end
                    task.wait(1)
                end
            end

            if not tradeCompleted then
                if not isTradingUIOpen() then
                    print("[TRADE][RECEIVER] Trade UI closed!")
                else
                    warn("[TRADE][RECEIVER] Trade UI still open after 60s — force closing")
                    closeTrade()
                    task.wait(1)
                end
            end

            -- Post-trade inventory check — toggle UI to refresh counts
            task.wait(1)
            requestInventory()
            task.wait(1)
            toggleInventoryUI()
            task.wait(1)
            local invAfterTrade = scanPlayerInventory()
            printInventoryDiff("[TRADE][RECEIVER] After trade with " .. CFG_SENDERS[i] .. ":", invBefore, invAfterTrade)
            invBefore = invAfterTrade
        end
    end

    -- Final inventory (refresh UI first)
    requestInventory()
    task.wait(1)
    toggleInventoryUI()
    task.wait(1)
    local invFinal = scanPlayerInventory()
    printInventory("[TRADE][RECEIVER] Final inventory:", invFinal)

    callDone()
end

-- =================== ENTRY POINT ===================
if isSender then
    runSender()
elseif isReceiver then
    runReceiver()
else
    warn("[TRADE] Player '" .. localPlayer.Name .. "' not in Senders or Receivers config — doing nothing")
end
