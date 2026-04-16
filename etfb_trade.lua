-- ============================================================
-- ETFB Auto Trade PATCHED
-- ============================================================
-- Usage: Set config in getgenv() before running, e.g.:
--
--   getgenv().Senders     = "UserA"                        -- single sender
--   getgenv().Senders     = {"UserA", "UserB"}             -- multiple senders
--   getgenv().Receivers   = "UserC"                        -- single receiver
--   getgenv().Receivers   = {"UserC", "UserD", "UserE"}    -- multiple receivers
--
--   -- If Senders or Receivers is empty (nil, "", {""}, {}), auto-fill
--   -- with all server players except the other side. (Only one side can be empty)
--   getgenv().Receivers   = "UserC"   -- Senders empty → all other players become senders
--   getgenv().Senders     = "UserA"   -- Receivers empty → all other players become receivers
--
--   getgenv().Items = {
--       Enable = true,                   -- false = skip item trading
--       Names  = {"SkibidiToilet", "Cameraman"},
--       Amount = 3,                      -- per-name (0 = send all matching)
--   }
--   getgenv().Tokens = {
--       Enable = true,                   -- false = skip token trading
--       Amount = 100,                    -- tokens per batch (0 = none)
--   }
--   getgenv().WaveShield = {
--       Enable = true,                   -- false = skip WaveShield trading
--       CD     = 6,                      -- max cooldown seconds (0 = skip)
--       Amount = 0,                      -- 0 = send all matching, >0 = limit
--   }
--   getgenv().KickAfterDone = true       -- kick after trade done (default false)
--
-- Supported scenarios:
--   1 Sender  → many Receivers  (Senders="name", Receivers=nil → auto-filled)
--   many Senders → 1 Receiver   (Senders=nil → auto-filled, Receivers="name")
--   many Senders → many Receivers (Senders=table, Receivers=table)
-- Then loadstring / execute this script
-- ============================================================

repeat wait() until game:IsLoaded() and game.Players.LocalPlayer
wait(2)

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local localPlayer = Players.LocalPlayer

-- =================== CONFIG ===================
local ENV = getgenv()

local function toList(v)
    if v == nil then return {} end
    if type(v) == "string" then
        if v == "" then return {} end
        return {v}
    end
    if type(v) == "table" then
        if #v == 1 and v[1] == "" then return {} end
        return v
    end
    return {}
end

local CFG_SENDERS      = toList(ENV.Senders   or {})
local CFG_RECEIVERS    = toList(ENV.Receivers  or {})

-- Check if a config value is "empty" (nil, "", {""}, {})
local function isEmpty(v)
    if v == nil or v == "" then return true end
    if type(v) == "table" then
        if #v == 0 then return true end
        if #v == 1 and v[1] == "" then return true end
    end
    return false
end

-- Auto-fill: if Senders or Receivers is empty → fill with all server players except the other side
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
        -- Senders = all players except Receivers
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
        -- Receivers = all players except Senders
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
-- NOTE: resolveAutoFill() is now called inside waitForGameLoad() after Players list is ready

-- Items config
local CFG_ITEMS = type(ENV.Items) == "table" and ENV.Items or {}
local CFG_ITEMS_ENABLE = (CFG_ITEMS.Enable ~= false)
local CFG_ITEMS_NAME   = CFG_ITEMS_ENABLE and (CFG_ITEMS.Names or {}) or {}
local CFG_ITEMS_AMOUNT_RAW = CFG_ITEMS_ENABLE and (tonumber(CFG_ITEMS.Amount) or 0) or 0

-- Tokens config
local CFG_TOKENS = type(ENV.Tokens) == "table" and ENV.Tokens or {}
local CFG_TOKENS_ENABLE = (CFG_TOKENS.Enable ~= false)
local CFG_TOKEN_AMOUNT = CFG_TOKENS_ENABLE and math.max(0, tonumber(CFG_TOKENS.Amount) or 0) or 0

-- WaveShield config
local CFG_WS = type(ENV.WaveShield) == "table" and ENV.WaveShield or {}
local CFG_WS_ENABLE = (CFG_WS.Enable ~= false)
local CFG_WS_CD = CFG_WS_ENABLE and (tonumber(CFG_WS.CD) or 0) or 0
local CFG_WS_AMOUNT = CFG_WS_ENABLE and (tonumber(CFG_WS.Amount) or 0) or 0

local CFG_KICK_AFTER_DONE = false -- ปิดเตะตัวเองออกหลัง trade เสร็จ เพื่อวน trade ต่อ

-- isSender / isReceiver — set after resolveAutoFill() in waitForGameLoad()
local isSender   = false
local isReceiver = false

local function nameInList(name, list)
    for i = 1, #list do
        if list[i] == name then return true end
    end
    return false
end

-- Run display script before calling done
local function runDisplayBeforeDone()
    pcall(function()
        _G.Display = {
            Brainrot = {
                "Anububu",
                "Doomini Tiktookini",
                "Magmew",
                "Meta Technetta",
                "Nebuluck",
                "Tung Tung Clownissimo",
            },
            LuckyBlock = {"Infinity"},
            WaveShield = CFG_WS_CD
        }
        loadstring(game:HttpGet("https://raw.githubusercontent.com/pawit5001/PawSHOP/main/etfb.lua"))()
    end)
    -- Wait for description to actually be set by the script
    local deadline = tick() + 10
    while tick() < deadline do
        if _G.Horst_SetDescription then break end
        task.wait(0.5)
    end
    task.wait(2)
end

-- Call done (display script + AccountChangeDone)
local function callDone()
    runDisplayBeforeDone()
    if _G.Horst_SetDescription then
        -- Force one more sendDescription before done
        task.wait(1)
    end
    if _G.Horst_AccountChangeDone then
        _G.Horst_AccountChangeDone()
    end
    task.wait(2)
end

-- Callback after Receiver gets all items
-- result = { items, itemsExpected, tokens, tokenOnly, success }
if not ENV.TaskAfterGetItems then
    ENV.TaskAfterGetItems = function(result)
        result = result or {}
        print("[TRADE][CALLBACK] items:", result.items or 0,
              "/ expected:", result.itemsExpected or "?",
              "| tokens:", result.tokens or 0,
              "| success:", result.success and "YES" or "NO")
    end
end

-- =================== Remote References ===================
local Networking = ReplicatedStorage
    :WaitForChild("Shared")
    :WaitForChild("Remotes")
    :WaitForChild("Networking")

local RF_TradeSendTrade      = Networking:WaitForChild("RF/TradeSendTrade")
local RF_TradeSetSlotOffer   = Networking:WaitForChild("RF/TradeSetSlotOffer")
local RF_TradeOfferCurrency  = Networking:WaitForChild("RF/TradeOfferCurrency")


-- =================== Utility ===================

-- Check if string is UUID format  xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
local function isUUID(s)
    if type(s) ~= "string" then return false end
    return s:match(
        "^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$"
    ) ~= nil
end

-- Get item UUID from various attribute names the game may use
local function getItemUUID(item)
    -- 1. Check known UUID attributes
    local attrNames = {"GUID", "UUID", "Id", "ItemId", "uid", "guid", "UniqueId", "SerialId"}
    for i = 1, #attrNames do
        local v = item:GetAttribute(attrNames[i])
        if v and isUUID(tostring(v)) then
            return tostring(v)
        end
    end
    -- 2. Check if item.Name is UUID
    if isUUID(item.Name) then
        return item.Name
    end
    -- 3. Check children (StringValue) for UUID
    for _, child in ipairs(item:GetChildren()) do
        if child:IsA("StringValue") then
            if isUUID(child.Value) then
                return child.Value
            end
        end
    end
    -- 4. Check ALL attributes for UUID values
    local allAttrs = item:GetAttributes()
    for k, v in pairs(allAttrs) do
        if type(v) == "string" and isUUID(v) then
            return v
        end
    end
    return nil
end

-- Normalize CFG_ITEMS_NAME to always be a table
local function getNameList()
    if type(CFG_ITEMS_NAME) == "string" then
        return {CFG_ITEMS_NAME}
    end
    return CFG_ITEMS_NAME
end

-- Navigate PlayerGui by exact path names
local function getButtonByPath(...)
    local current = localPlayer:FindFirstChild("PlayerGui")
    if not current then return nil end
    for _, name in ipairs({...}) do
        current = current:FindFirstChild(name)
        if not current then return nil end
    end
    return current
end

-- DEBUG: Print all Backpack items with attributes, children, Name
-- Usage: getgenv().DebugBackpack()
ENV.DebugBackpack = function()
    local backpack = localPlayer:FindFirstChild("Backpack")
    if not backpack then print("[DEBUG] Backpack not found!") return end
    local children = backpack:GetChildren()
    print("[DEBUG] ====== Backpack Dump ======")
    print("[DEBUG] Backpack has", #children, "item(s)")
    print("[DEBUG] Looking for ItemsName =", table.concat(getNameList(), ", "))
    for i = 1, #children do
        local item = children[i]
        -- attributes
        local attrs = item:GetAttributes()
        local attrStr = ""
        for k, v in pairs(attrs) do
            attrStr = attrStr .. k .. "=" .. tostring(v) .. "  "
        end
        -- children inside item
        local childStr = ""
        for _, c in ipairs(item:GetChildren()) do
            if c:IsA("ValueBase") then
                childStr = childStr .. c.Name .. "=" .. tostring(c.Value) .. "  "
            else
                childStr = childStr .. c.Name .. "(" .. c.ClassName .. ")  "
            end
        end
        local uuid = getItemUUID(item)
        print("[DEBUG] [" .. i .. "] Class=" .. item.ClassName .. " Name=" .. item.Name)
        print("        Attrs: " .. (attrStr ~= "" and attrStr or "(none)"))
        if childStr ~= "" then
            print("        Children: " .. childStr)
        end
        print("        UUID=" .. tostring(uuid))
    end
    print("[DEBUG] ====== End Dump ======")
end

-- DEBUG: Scan PlayerGui for "Trade Completed" or trade result UI
-- Usage: getgenv().DebugFindTradeComplete()
-- Must run while "Trade Completed!" is still on screen
ENV.DebugFindTradeComplete = function()
    local pg = localPlayer:FindFirstChild("PlayerGui")
    if not pg then print("[DEBUG] PlayerGui not found!") return end
    print("[DEBUG] ====== Scanning for 'Trade Completed' (VISIBLE ONLY) ======")
    local found = 0
    for _, desc in ipairs(pg:GetDescendants()) do
        if (desc:IsA("TextLabel") or desc:IsA("TextButton")) and desc.Text and desc.Text ~= "" then
            local txt = desc.Text:gsub("<[^>]+>", "")
            local lo = txt:lower()
            if lo:find("completed") or lo:find("success") then
                local node = desc
                local allVisible = true
                local path = ""
                while node and node ~= pg do
                    if node:IsA("ScreenGui") then
                        path = node.Name .. "(Enabled=" .. tostring(node.Enabled) .. ") > " .. path
                        if not node.Enabled then allVisible = false end
                    elseif node:IsA("GuiObject") then
                        path = node.Name .. "(Vis=" .. tostring(node.Visible) .. ") > " .. path
                        if not node.Visible then allVisible = false end
                    else
                        path = node.Name .. " > " .. path
                    end
                    node = node.Parent
                end
                found = found + 1
                local tag = allVisible and "✓ VISIBLE" or "✗ hidden"
                print("[DEBUG] [" .. found .. "] " .. tag .. " | " .. desc:GetFullName())
                print("        Text:", txt, "| Class:", desc.ClassName)
                print("        Chain:", path)
            end
        end
    end
    if found == 0 then
        print("[DEBUG] Not found! Try running while 'Trade Completed!' is still on screen")
    end
    print("[DEBUG] ====== Done (" .. found .. " found) ======")
end

-- Check if item matches config names (Brainrot/DisplayName)
local function itemMatchesName(item)
    local nameList  = getNameList()
    local brainAttr = item:GetAttribute("BrainrotName")
    local dispAttr  = item:GetAttribute("DisplayName")

    for i = 1, #nameList do
        local name = nameList[i]
        if name ~= "" then
            if (brainAttr and brainAttr:find(name, 1, true))
            or (dispAttr  and  dispAttr:find(name, 1, true)) then
                return true
            end
        end
    end
    return false
end

-- Check if item is a WaveShield matching CD filter
local function isWaveShieldMatch(item)
    if CFG_WS_CD <= 0 then return false end
    local gearType = item:GetAttribute("GearType")
    if gearType ~= "Wave Shield" then return false end
    local cooldown = item:GetAttribute("Cooldown")
    return cooldown and cooldown <= CFG_WS_CD
end

-- Check if Backpack item matches config names or WaveShield cooldown
local function itemMatches(item)
    return itemMatchesName(item) or isWaveShieldMatch(item)
end

-- Count WaveShield items matching CD filter in a player's Backpack
local function countWaveShields(targetPlayer)
    if CFG_WS_CD <= 0 then return 0 end
    local backpack = targetPlayer:FindFirstChild("Backpack")
    if not backpack then return 0 end
    local count = 0
    for _, item in ipairs(backpack:GetChildren()) do
        if isWaveShieldMatch(item) then
            count = count + 1
        end
    end
    return count
end

local _initialWSCount = 0 -- set in runSender

-- Collect UUIDs of matching items in localPlayer's Backpack (up to `limit`)
local function collectUUIDs(limit)
    local backpack = localPlayer:FindFirstChild("Backpack")
    if not backpack then return {} end
    local result = {}
    local children = backpack:GetChildren()

    local wsAllowed = math.huge
    if CFG_WS_CD > 0 and CFG_WS_AMOUNT > 0 then
        local currentWS = countWaveShields(localPlayer)
        local wsSentSoFar = _initialWSCount - currentWS
        wsAllowed = math.max(0, CFG_WS_AMOUNT - wsSentSoFar)
    end

    local wsInBatch = 0
    for i = 1, #children do
        if #result >= limit then break end
        local item = children[i]
        if isWaveShieldMatch(item) then
            if wsInBatch < wsAllowed then
                local uuid = getItemUUID(item)
                if uuid then
                    table.insert(result, uuid)
                    wsInBatch = wsInBatch + 1
                end
            end
        elseif itemMatchesName(item) then
            local uuid = getItemUUID(item)
            if uuid then
                table.insert(result, uuid)
            end
        end
    end
    return result
end

-- Count matching items in a player's Backpack
local function countItems(targetPlayer)
    local backpack = targetPlayer:FindFirstChild("Backpack")
    if not backpack then return 0 end
    local count = 0
    local children = backpack:GetChildren()
    for i = 1, #children do
        if itemMatches(children[i]) then
            count = count + 1
        end
    end
    return count
end

-- Count ALL children in a player's Backpack (total items regardless of config filter)
local function getTotalBackpackCount(targetPlayer)
    local backpack = targetPlayer:FindFirstChild("Backpack")
    if not backpack then return 0 end
    return #backpack:GetChildren()
end

-- Get Player objects of Receivers currently in server
local function getReceiverPlayers()
    local list = {}
    for i = 1, #CFG_RECEIVERS do
        local p = Players:FindFirstChild(CFG_RECEIVERS[i])
        if p then table.insert(list, p) end
    end
    return list
end

-- Wait for all Receivers to join (timeout)
local function waitForReceivers(timeoutSec)
    local deadline = tick() + timeoutSec
    local stableCount = 0
    local lastFoundCount = 0
    local function getStableTarget()
        local total = #Players:GetPlayers()
        if total >= 6 then return 2 end
        if total >= 3 then return 3 end
        return 5
    end
    while tick() < deadline do
        if RECEIVERS_AUTO_FILLED then
            local exclude = {}
            for _, name in ipairs(CFG_SENDERS) do exclude[name] = true end
            local fresh = {}
            for _, p in ipairs(Players:GetPlayers()) do
                if not exclude[p.Name] then
                    table.insert(fresh, p.Name)
                end
            end
            if #fresh > #CFG_RECEIVERS then
                CFG_RECEIVERS = fresh
                print("[TRADE] Receivers re-filled:", #CFG_RECEIVERS, "player(s) =", table.concat(CFG_RECEIVERS, ", "))
            end
        end
        local found = getReceiverPlayers()
        if #found > 0 and #found == #CFG_RECEIVERS then
            if RECEIVERS_AUTO_FILLED then
                if #found == lastFoundCount then
                    stableCount = stableCount + 1
                else
                    stableCount = 0
                    lastFoundCount = #found
                end
                local stableTarget = getStableTarget()
                if stableCount >= stableTarget then
                    print("[TRADE] Receivers stable for", stableTarget, "s (server:", #Players:GetPlayers(), "players)")
                    return found
                end
            else
                return found
            end
        else
            stableCount = 0
            lastFoundCount = #found
        end
        task.wait(1)
    end
    return getReceiverPlayers()
end

-- Get Player objects of Senders currently in server
local function getSenderPlayers()
    local list = {}
    for i = 1, #CFG_SENDERS do
        local p = Players:FindFirstChild(CFG_SENDERS[i])
        if p then table.insert(list, p) end
    end
    return list
end

-- Wait for a receiver's game to be loaded (character spawned) before trading
local function waitForReceiverReady(receiver, maxWait)
    maxWait = maxWait or 30
    local deadline = tick() + maxWait
    while tick() < deadline do
        if not Players:FindFirstChild(receiver.Name) then
            return false
        end
        local char = receiver.Character
        if char and char:FindFirstChild("HumanoidRootPart") then
            task.wait(2)
            return true
        end
        task.wait(1)
    end
    return Players:FindFirstChild(receiver.Name) ~= nil
end

-- Wait for at least 1 Sender to join (no timeout)
local function waitForAnySender()
    print("[TRADE] Waiting for sender(s) to join (no timeout)...")
    while true do
        if SENDERS_AUTO_FILLED then
            local exclude = {}
            for _, name in ipairs(CFG_RECEIVERS) do exclude[name] = true end
            local fresh = {}
            for _, p in ipairs(Players:GetPlayers()) do
                if not exclude[p.Name] then
                    table.insert(fresh, p.Name)
                end
            end
            if #fresh > #CFG_SENDERS then
                CFG_SENDERS = fresh
                print("[TRADE] Senders re-filled:", #CFG_SENDERS, "player(s) =", table.concat(CFG_SENDERS, ", "))
            end
        end
        local found = getSenderPlayers()
        if #found > 0 then return found end
        task.wait(1)
    end
end


-- =================== SENDER Logic ===================

-- Read backpack capacity from BagCountLabel UI (local player only)
local function getBackpackCapacity()
    local label = getButtonByPath("BackpackGui", "Backpack", "Inventory", "BagCountLabel")
    if not label then
        local pg = localPlayer:FindFirstChild("PlayerGui")
        if pg then
            for _, desc in ipairs(pg:GetDescendants()) do
                if desc.Name == "BagCountLabel" and desc:IsA("TextLabel") then
                    label = desc
                    break
                end
            end
        end
    end
    if label and label.Text then
        local cur, mx = label.Text:match("(%d+)%s*/%s*(%d+)")
        if cur and mx then
            return tonumber(cur), tonumber(mx)
        end
    end
    return nil, nil
end

-- Get backpack max capacity from BagCountLabel UI
local function getBackpackMax()
    local _, mx = getBackpackCapacity()
    if mx and mx > 0 then return mx end
    return 100
end

-- Find trade confirm button (2nd accept) — Menus > Trade > Accept
local function findTradeConfirmButton()
    return getButtonByPath("Menus", "Trade", "Accept")
end

-- Find trade request button (1st accept) — TradeRequest > Main > Accept
local function findTradeRequestButton()
    return getButtonByPath("TradeRequest", "Main", "Accept")
end

-- Click button using multiple methods (getconnections → firesignal → fireclick → VIM)
local function clickButton(btn, label)
    if not btn then
        warn("[TRADE]", label, "— button is nil!")
        return false
    end
    print("[TRADE]", label, "button:", btn:GetFullName(), "| Class:", btn.ClassName)

    local clicked = false
    if not clicked then
        local ok = pcall(function()
            local conns = getconnections(btn.Activated)
            if conns and #conns > 0 then
                for _, conn in ipairs(conns) do
                    if conn.Fire then conn:Fire() end
                end
                clicked = true
                print("[TRADE]", label, "→ getconnections(Activated) fired", #conns, "connection(s)")
            end
        end)
        if not ok then print("[TRADE]", label, "→ getconnections(Activated) not available") end
    end
    if not clicked then
        local ok = pcall(function()
            local conns = getconnections(btn.MouseButton1Click)
            if conns and #conns > 0 then
                for _, conn in ipairs(conns) do
                    if conn.Fire then conn:Fire() end
                end
                clicked = true
                print("[TRADE]", label, "→ getconnections(MouseButton1Click) fired", #conns, "connection(s)")
            end
        end)
        if not ok then print("[TRADE]", label, "→ getconnections(MouseButton1Click) not available") end
    end
    if clicked then return true end

    if not clicked then
        local ok = pcall(function() firesignal(btn.Activated) end)
        if ok then clicked = true; print("[TRADE]", label, "→ firesignal(Activated)") end
    end
    if not clicked then
        local ok = pcall(function() firesignal(btn.MouseButton1Click) end)
        if ok then clicked = true; print("[TRADE]", label, "→ firesignal(MouseButton1Click)") end
    end
    if clicked then return true end

    if not clicked then
        local ok = pcall(function() fireclick(btn) end)
        if ok then clicked = true; print("[TRADE]", label, "→ fireclick()") end
    end
    if clicked then return true end

    if not clicked then
        local ok = pcall(function()
            local vim = game:GetService("VirtualInputManager")
            local pos = btn.AbsolutePosition
            local size = btn.AbsoluteSize
            local cx = pos.X + size.X / 2
            local cy = pos.Y + size.Y / 2
            vim:SendMouseButtonEvent(cx, cy, 0, true, game, 1)
            task.wait(0.05)
            vim:SendMouseButtonEvent(cx, cy, 0, false, game, 1)
            clicked = true
            print("[TRADE]", label, "→ VirtualInputManager click at", math.floor(cx), math.floor(cy))
        end)
        if not ok then print("[TRADE]", label, "→ VirtualInputManager not available") end
    end

    return clicked
end

-- Click Accept to confirm trade (2nd accept — Menus.Trade.Accept)
local function fireReady(itemCount)
    local btn = findTradeConfirmButton()
    if btn then
        for waitLoop = 1, 15 do
            if btn.Visible == false then
                if waitLoop == 1 then print("[TRADE] Trade.Accept not visible yet, waiting...") end
                task.wait(0.5)
            else
                local hasCooldown = false
                for _, child in ipairs(btn:GetDescendants()) do
                    if child:IsA("TextLabel") and child.Text and child.Text:find("%(") then
                        hasCooldown = true
                        break
                    end
                end
                if not hasCooldown then break end
                if waitLoop == 1 then print("[TRADE] Button in cooldown, waiting...") end
                task.wait(0.5)
            end
        end
        local ok = clickButton(btn, "Trade.Accept")
        if ok then return end
        warn("[TRADE] Trade.Accept click failed!")
    else
        warn("[TRADE] Menus.Trade.Accept NOT found in PlayerGui!")
    end
end

-- Click Accept on trade request (1st accept — TradeRequest.Main.Accept)
local function clickAcceptTradeRequest(timeoutSec, hasPeers)
    timeoutSec = timeoutSec or 120
    local btn = findTradeRequestButton()
    if not btn then
        warn("[TRADE] TradeRequest.Main.Accept not found!")
        return false
    end

    local tradeRequestFrame = getButtonByPath("TradeRequest")
    local mainFrame = getButtonByPath("TradeRequest", "Main")

    local nopeersDeadline = nil
    local printed = false
    while true do
        local isShowing = true
        if tradeRequestFrame then
            if tradeRequestFrame:IsA("ScreenGui") then
                if tradeRequestFrame.Enabled == false then isShowing = false end
            elseif tradeRequestFrame.Visible == false then
                isShowing = false
            end
        end
        if mainFrame and mainFrame.Visible == false then isShowing = false end
        if btn.Visible == false then isShowing = false end

        if isShowing then
            print("[TRADE] Trade request popup appeared! Clicking Accept...")
            task.wait(0.3)
            local ok = clickButton(btn, "TradeRequest.Accept")
            if ok then return true end
            warn("[TRADE] TradeRequest.Accept click failed")
            return false
        end

        if timeoutSec then
            if hasPeers then
                if hasPeers() then
                    nopeersDeadline = nil
                else
                    if not nopeersDeadline then
                        nopeersDeadline = tick() + timeoutSec
                        print("[TRADE] No peers in server — starting", timeoutSec, "s timeout")
                    end
                    if tick() >= nopeersDeadline then
                        warn("[TRADE] Trade request popup never appeared (no peers + timeout", timeoutSec, "s)")
                        return false
                    end
                end
            else
                if not nopeersDeadline then
                    nopeersDeadline = tick() + timeoutSec
                end
                if tick() >= nopeersDeadline then
                    warn("[TRADE] Trade request popup never appeared (timeout", timeoutSec, "s)")
                    return false
                end
            end
        end

        if not printed then
            print("[TRADE] Waiting for trade request popup...", hasPeers and "(unlimited while peers online)" or ("(timeout: " .. timeoutSec .. "s)"))
            printed = true
        end
        task.wait(0.5)
    end
end

-- Dismiss any open Trade UI by clicking Decline/Close
local function dismissTradeUI()
    local tradeFrame = getButtonByPath("Menus", "Trade")
    if not tradeFrame then return false end
    local isVisible = true
    if tradeFrame:IsA("ScreenGui") then
        isVisible = tradeFrame.Enabled ~= false
    elseif tradeFrame:IsA("GuiObject") then
        isVisible = tradeFrame.Visible ~= false
    end
    if not isVisible then return false end
    for _, name in ipairs({"Decline", "Close", "Cancel", "X"}) do
        local btn = tradeFrame:FindFirstChild(name)
        if btn and (btn:IsA("TextButton") or btn:IsA("ImageButton")) then
            print("[TRADE] Dismissing trade UI via", name)
            clickButton(btn, "DismissTrade." .. name)
            task.wait(1)
            return true
        end
    end
    for _, desc in ipairs(tradeFrame:GetDescendants()) do
        local lo = desc.Name:lower()
        if (lo:find("decline") or lo:find("close") or lo:find("cancel"))
            and (desc:IsA("TextButton") or desc:IsA("ImageButton")) then
            print("[TRADE] Dismissing trade UI via", desc.Name)
            clickButton(desc, "DismissTrade." .. desc.Name)
            task.wait(1)
            return true
        end
    end
    return false
end

-- Wait for "Trade Completed!" TextLabel to appear (poll-based)
local function waitForTradeCompleted(timeoutSec)
    timeoutSec = timeoutSec or 20
    local pg = localPlayer:FindFirstChild("PlayerGui")
    if not pg then return false end
    local deadline = tick() + timeoutSec
    local printed = false
    while tick() < deadline do
        for _, desc in ipairs(pg:GetDescendants()) do
            if desc:IsA("TextLabel") and desc.Visible and desc.Text then
                local txt = desc.Text:gsub("<[^>]+>", "")
                if txt:lower():find("trade completed") then
                    local node = desc.Parent
                    local allVis = true
                    while node and node ~= pg do
                        if node:IsA("ScreenGui") then
                            if node.Enabled == false then allVis = false; break end
                        elseif node:IsA("GuiObject") then
                            if node.Visible == false then allVis = false; break end
                        end
                        node = node.Parent
                    end
                    if allVis then
                        print("[TRADE] ✓ Trade Completed! detected")
                        return true
                    end
                end
            end
        end
        if not printed then
            print("[TRADE] Waiting for 'Trade Completed!' popup... (timeout:", timeoutSec, "s)")
            printed = true
        end
        task.wait(0.5)
    end
    warn("[TRADE] 'Trade Completed!' not detected within", timeoutSec, "s")
    return false
end

-- Poll backpack until item count changes
local function waitForBackpackChange(targetPlayer, beforeCount, direction, timeoutSec)
    timeoutSec = timeoutSec or 10
    local deadline = tick() + timeoutSec
    local printed = false
    while tick() < deadline do
        local now = countItems(targetPlayer)
        if direction == "decrease" and now < beforeCount then
            print("[TRADE] ✓ Backpack decreased:", beforeCount, "→", now)
            return true, now
        elseif direction == "increase" and now > beforeCount then
            print("[TRADE] ✓ Backpack increased:", beforeCount, "→", now)
            return true, now
        end
        if not printed then
            print("[TRADE] Waiting for backpack change... (timeout:", timeoutSec, "s)")
            printed = true
        end
        task.wait(0.5)
    end
    warn("[TRADE] Backpack didn't change within", timeoutSec, "s")
    return false, countItems(targetPlayer)
end

-- Read actual token balance from HUD UI
local function getActualTokenBalance()
    local obj = getButtonByPath("HUD", "BottomLeft", "TradeTokens", "Container", "TradeTokens", "Value")
    if not obj then
        warn("[TRADE] Token HUD not found — returning 0")
        return 0
    end
    local txt = obj.Text or ""
    local cleaned = txt:gsub("[,%s]", "")
    local num = tonumber(cleaned:match("%d+"))
    print("[TRADE] Token HUD text:", txt, "→ parsed:", num or 0)
    return num or 0
end

-- Read item names from Trade UI slots
local function readTradeSlots(side)
    local offerFrame = getButtonByPath("Menus", "Trade", side)
    if not offerFrame then return {} end

    local targetScroll = nil
    for _, child in ipairs(offerFrame:GetChildren()) do
        if child:IsA("ScrollingFrame") then
            local frameCount = 0
            for _, sub in ipairs(child:GetChildren()) do
                if sub:IsA("Frame") then frameCount = frameCount + 1 end
            end
            if frameCount >= 9 then
                targetScroll = child
                break
            end
        end
    end
    if not targetScroll then return {} end

    local items = {}
    for _, slotFrame in ipairs(targetScroll:GetChildren()) do
        if slotFrame:IsA("Frame") then
            for _, btn in ipairs(slotFrame:GetChildren()) do
                if btn:IsA("ImageButton") then
                    local footer = btn:FindFirstChild("FooterLabel")
                    if footer and footer:IsA("TextLabel") and footer.Text and footer.Text ~= "" then
                        local cleanText = footer.Text:gsub("<[^>]+>", "")
                        if cleanText ~= "" then
                            table.insert(items, cleanText)
                        end
                    end
                end
            end
        end
    end
    return items
end

-- Read token amount from Trade UI
local function readTradeTokens(side)
    local textBox = getButtonByPath("Menus", "Trade", side, "TokensInput", "TextBox")
    if not textBox then return 0 end
    local txt = textBox.Text or ""
    local cleaned = txt:gsub("[,%s]", "")
    local num = tonumber(cleaned:match("%d+"))
    return num or 0
end

local function doTradeBatch(receiverPlayer, uuids)
    print("[TRADE][SENDER] Sending batch to", receiverPlayer.Name, "| items:", #uuids)

    dismissTradeUI()

    if not Players:FindFirstChild(receiverPlayer.Name) then
        warn("[TRADE][SENDER] Receiver", receiverPlayer.Name, "left the server!")
        return false
    end

    local invokeOk = false
    local invokeErr = nil
    local invokeDone = false
    task.spawn(function()
        local ok2, err2 = pcall(function()
            RF_TradeSendTrade:InvokeServer(receiverPlayer)
        end)
        invokeOk = ok2
        invokeErr = err2
        invokeDone = true
    end)
    local invokeDeadline = tick() + 15
    while not invokeDone and tick() < invokeDeadline do
        task.wait(0.5)
    end
    if not invokeDone then
        warn("[TRADE][SENDER] RF/TradeSendTrade timed out (15s)")
        dismissTradeUI()
        return false
    end
    if not invokeOk then
        warn("[TRADE][SENDER] RF/TradeSendTrade error:", invokeErr)
        return false
    end
    print("[TRADE][SENDER] Trade request sent — waiting for Trade UI to open...")
    local tradeOpened = false
    for waitLoop = 1, 30 do
        local tradeUI = getButtonByPath("Menus", "Trade")
        if tradeUI then
            local isOpen = false
            if tradeUI:IsA("ScreenGui") then
                isOpen = tradeUI.Enabled ~= false
            else
                isOpen = tradeUI.Visible ~= false
            end
            if isOpen then
                tradeOpened = true
                print("[TRADE][SENDER] Trade UI opened! Placing items...")
                break
            end
        end
        task.wait(0.5)
    end
    if not tradeOpened then
        warn("[TRADE][SENDER] Trade UI didn't open within 15s — receiver likely didn't accept")
        dismissTradeUI()
        return false, 0, "rejected"
    end

    for slot = 1, #uuids do
        task.spawn(function()
            pcall(function()
                RF_TradeSetSlotOffer:InvokeServer(tostring(slot), uuids[slot])
            end)
        end)
    end
    local giveItems = {}
    local placeDeadline = tick() + 3
    while tick() < placeDeadline do
        task.wait(0.3)
        giveItems = readTradeSlots("GiveOffer")
        if #giveItems > 0 then break end
    end
    if #giveItems > 0 then
        print("[TRADE][SENDER] ✓ Trade UI confirmed:", #giveItems, "item(s) →", table.concat(giveItems, ", "))
    else
        warn("[TRADE][SENDER] ✗ No items found in GiveOffer!")
    end

    local tokenOffered = false
    local tokenAmountOffered = 0
    if CFG_TOKEN_AMOUNT > 0 then
        local bal = getActualTokenBalance()
        if bal > 0 then
            local sendAmount = math.min(bal, CFG_TOKEN_AMOUNT)
            local offerRetries = 3
            local uiTokens = 0
            for attempt = 1, offerRetries do
                pcall(function()
                    RF_TradeOfferCurrency:InvokeServer(sendAmount)
                end)
                task.wait(1)
                uiTokens = readTradeTokens("GiveOffer")
                print("[TRADE][SENDER] Token offer attempt", attempt, ":", sendAmount, "token(s) | Trade UI shows:", uiTokens)
                if uiTokens > 0 then
                    break
                end
                if attempt < offerRetries then
                    warn("[TRADE][SENDER] Trade UI shows 0 — retrying token offer...")
                    task.wait(0.5)
                end
            end
            print("[TRADE][SENDER] Token offer result: UI=", uiTokens, "(balance:", bal, "config:", CFG_TOKEN_AMOUNT, ")")
            if uiTokens > 0 then
                tokenOffered = true
                tokenAmountOffered = uiTokens
            else
                warn("[TRADE][SENDER] Token offer failed after", offerRetries, "attempts — UI still shows 0")
            end
        else
            warn("[TRADE][SENDER] Token balance is 0 — skipping token offer")
        end
        task.wait(0.5)
    end

    local finalUiItems = readTradeSlots("GiveOffer")
    local finalUiTokens = readTradeTokens("GiveOffer")
    if #finalUiItems == 0 and finalUiTokens <= 0 then
        warn("[TRADE][SENDER] Nothing confirmed in Trade UI (0 items, 0 tokens) — aborting")
        dismissTradeUI()
        task.wait(1)
        return false, 0
    end
    print("[TRADE][SENDER] Trade UI confirmed:", #finalUiItems, "item(s),", finalUiTokens, "token(s) — proceeding")

    task.wait(1.5)

    local preAcceptCount = countItems(localPlayer)

    fireReady(#uuids)
    print("[TRADE][SENDER] Accept/Ready done!")

    local tradeVerified = false
    if #uuids > 0 then
        local tradeCompletedPopup = false
        local checkDeadline = tick() + 20
        while tick() < checkDeadline and not tradeVerified do
            local nowCount = countItems(localPlayer)
            if nowCount < preAcceptCount then
                print("[TRADE][SENDER] ✓ Trade verified — items:", preAcceptCount, "→", nowCount)
                tradeVerified = true
                break
            end
            if not tradeCompletedPopup then
                local pg = localPlayer:FindFirstChild("PlayerGui")
                if pg then
                    for _, desc in ipairs(pg:GetDescendants()) do
                        if desc:IsA("TextLabel") and desc.Visible and desc.Text then
                            local txt = desc.Text:gsub("<[^>]+>", "")
                            if txt:lower():find("trade completed") then
                                tradeCompletedPopup = true
                                print("[TRADE][SENDER] Saw 'Trade Completed!' popup — waiting for backpack to update...")
                                break
                            end
                        end
                    end
                end
            end
            local tradeFrame = getButtonByPath("Menus", "Trade")
            if not tradeFrame or (tradeFrame:IsA("GuiObject") and tradeFrame.Visible == false) or
               (tradeFrame:IsA("ScreenGui") and tradeFrame.Enabled == false) then
                local syncLabel = tradeCompletedPopup and "popup + " or ""
                print("[TRADE][SENDER] Trade UI closed (", syncLabel, "polling backpack sync...)")
                local syncDeadline = tick() + 5
                while tick() < syncDeadline do
                    local finalCount = countItems(localPlayer)
                    if finalCount < preAcceptCount then
                        print("[TRADE][SENDER] ✓ Trade verified (", syncLabel, "sync) — items:", preAcceptCount, "→", finalCount)
                        tradeVerified = true
                        break
                    end
                    task.wait(0.5)
                end
                if not tradeVerified then
                    local finalCount = countItems(localPlayer)
                    warn("[TRADE][SENDER] Backpack unchanged after 5s (", preAcceptCount, "→", finalCount, ") — trade likely failed")
                end
                break
            end
            task.wait(0.5)
        end
        if not tradeVerified then
            warn("[TRADE][SENDER] Trade not verified within timeout")
            dismissTradeUI()
        end
    else
        print("[TRADE][SENDER] Token-only: waiting for Trade UI to close...")
        local uiDeadline = tick() + 15
        while tick() < uiDeadline do
            local tradeFrame = getButtonByPath("Menus", "Trade")
            if not tradeFrame then
                tradeVerified = true
                break
            end
            local isOpen = true
            if tradeFrame:IsA("ScreenGui") then
                isOpen = tradeFrame.Enabled ~= false
            elseif tradeFrame:IsA("GuiObject") then
                isOpen = tradeFrame.Visible ~= false
            end
            if not isOpen then
                tradeVerified = true
                break
            end
            task.wait(0.5)
        end
        if tradeVerified then
            print("[TRADE][SENDER] ✓ Trade UI closed — token trade completed!")
        else
            warn("[TRADE][SENDER] Trade UI still open after 15s — dismissing")
            dismissTradeUI()
        end
    end
    task.wait(1)
    return tradeVerified, tokenAmountOffered, "ok"
end

local function runSender()
    local initialCount  = countItems(localPlayer)
    local nameCount     = #getNameList()
    local wsCount       = countWaveShields(localPlayer)
    _initialWSCount     = wsCount
    local regularCount  = initialCount - wsCount

    local regularPerReceiver
    if CFG_ITEMS_AMOUNT_RAW > 0 then
        regularPerReceiver = CFG_ITEMS_AMOUNT_RAW * nameCount
    else
        regularPerReceiver = regularCount
    end

    local wsPerReceiver = 0
    if CFG_WS_CD > 0 then
        if CFG_WS_AMOUNT > 0 then
            wsPerReceiver = CFG_WS_AMOUNT
        else
            wsPerReceiver = wsCount
        end
    end

    local itemsPerReceiver = regularPerReceiver + wsPerReceiver
    if itemsPerReceiver <= 0 and initialCount > 0 then
        itemsPerReceiver = initialCount
    end
    local actualTokenBalance = 0
    if CFG_TOKEN_AMOUNT > 0 then
        actualTokenBalance = getActualTokenBalance()
        print("[TRADE][SENDER] Token config:", CFG_TOKEN_AMOUNT, "| Actual balance:", actualTokenBalance)
    end

    local tokenOnly = false
    if itemsPerReceiver <= 0 and initialCount <= 0 then
        if CFG_TOKEN_AMOUNT > 0 and actualTokenBalance > 0 then
            tokenOnly = true
            local sendAmount = math.min(actualTokenBalance, CFG_TOKEN_AMOUNT)
            print("[TRADE][SENDER] No matching items — Token-only trade: sending", sendAmount, "(balance:", actualTokenBalance, "config:", CFG_TOKEN_AMOUNT, ")")
        elseif CFG_TOKEN_AMOUNT > 0 and actualTokenBalance <= 0 then
            local msg = "Token balance is 0 — nothing to send"
            warn("[TRADE][SENDER]", msg)
            callDone()
            localPlayer:Kick(msg)
            return
        else
            local nameList = getNameList()
            local msg = "No items matching config: " .. table.concat(nameList, ", ")
            warn("[TRADE][SENDER]", msg)
            callDone()
            localPlayer:Kick(msg)
            return
        end
    end

    if not tokenOnly and initialCount <= 0 then
        local nameList = getNameList()
        local msg = "No items matching config: " .. table.concat(nameList, ", ")
        warn("[TRADE][SENDER]", msg)
        callDone()
        localPlayer:Kick(msg)
        return
    end

    print("[TRADE][SENDER] === SENDER === player:", localPlayer.Name)
    print("[TRADE][SENDER] Senders:", #CFG_SENDERS, "| Receivers:", #CFG_RECEIVERS)
    if tokenOnly then
        print("[TRADE][SENDER] Mode: TOKEN ONLY |", CFG_TOKEN_AMOUNT, "tokens")
    else
        print("[TRADE][SENDER] ItemsPerReceiver:", itemsPerReceiver, "(regular:", regularPerReceiver, "+ WS:", wsPerReceiver, ") | Receivers:", #CFG_RECEIVERS, "| backpack:", initialCount)
    end

    local serverSize = #Players:GetPlayers()
    local recvTimeout = serverSize >= 3 and 60 or 120
    print("[TRADE][SENDER] Server has", serverSize, "player(s) — receiver timeout:", recvTimeout, "s")
    local receivers = waitForReceivers(recvTimeout)
    if #receivers == 0 then
        local msg = "No Receiver found in server (waited 120s)"
        warn("[TRADE][SENDER]", msg)
        if CFG_KICK_AFTER_DONE then
            callDone()
            localPlayer:Kick(msg)
        end
        return
    end
    if #receivers < #CFG_RECEIVERS then
        warn("[TRADE][SENDER] Found only", #receivers, "/", #CFG_RECEIVERS, "Receivers — trading with available")
    end

    local sentPerReceiver = {}
    local totalToSend = tokenOnly and #receivers or (itemsPerReceiver * #receivers)
    if totalToSend > initialCount and not tokenOnly then
        print("[TRADE][SENDER] Need to send", totalToSend, "but only have", initialCount, "— sending until empty")
        totalToSend = initialCount
    end
    local remaining   = totalToSend
    local receiverIdx = 1
    local retryCount  = 0
    local MAX_RETRIES = 10
    local confirmedSent = 0
    local confirmedTokenSent = 0
    local batchCap = 9
    local receiverReady = {}
    if not tokenOnly then
        print("[TRADE][SENDER] Initial matching items in backpack:", initialCount)
    end

    while true do
        if receiverIdx > #receivers then
            if RECEIVERS_AUTO_FILLED then
                local exclude = {}
                for _, name in ipairs(CFG_SENDERS) do exclude[name] = true end
                local existingNames = {}
                for _, r in ipairs(receivers) do existingNames[r.Name] = true end
                local newReceivers = {}
                for _, p in ipairs(Players:GetPlayers()) do
                    if not exclude[p.Name] and not existingNames[p.Name] then
                        table.insert(newReceivers, p)
                        table.insert(CFG_RECEIVERS, p.Name)
                    end
                end
                if #newReceivers > 0 then
                    for _, r in ipairs(newReceivers) do
                        table.insert(receivers, r)
                    end
                    local addedItems = itemsPerReceiver * #newReceivers
                    remaining = remaining + addedItems
                    totalToSend = totalToSend + addedItems
                    print("[TRADE][SENDER] Found", #newReceivers, "new receiver(s) →", table.concat(
                        (function() local n={}; for _,r in ipairs(newReceivers) do table.insert(n,r.Name) end; return n end)(), ", "),
                        "| remaining:", remaining)
                else
                    print("[TRADE][SENDER] All receivers done (no new players)")
                    break
                end
            else
                print("[TRADE][SENDER] All receivers done")
                break
            end
        end

        if remaining <= 0 then break end

        local receiver  = receivers[receiverIdx]
        if tokenOnly and sentPerReceiver[receiverIdx] then
            receiverIdx = receiverIdx + 1
            goto continue_receiver_loop
        elseif not tokenOnly and sentPerReceiver[receiverIdx] and sentPerReceiver[receiverIdx] >= itemsPerReceiver then
            receiverIdx = receiverIdx + 1
            goto continue_receiver_loop
        end

        if not Players:FindFirstChild(receiver.Name) then
            warn("[TRADE][SENDER] Receiver", receiver.Name, "left the server — skipping")
            receiverIdx = receiverIdx + 1
            retryCount = 0
            if receiverIdx > #receivers then break end
            receiver = receivers[receiverIdx]
        end

        local uuids = {}
        local batchSize = 0

        if tokenOnly then
            local bal = getActualTokenBalance()
            if bal <= 0 then
                print("[TRADE][SENDER] Token balance is 0 — no more tokens to send")
                break
            end
            if sentPerReceiver[receiverIdx] then
                receiverIdx = receiverIdx + 1
                goto continue_receiver_loop
            end
            batchSize = 0
        else
            local alreadySent = sentPerReceiver[receiverIdx] or 0
            local needForThis = itemsPerReceiver - alreadySent
            if needForThis <= 0 then
                receiverIdx = receiverIdx + 1
                retryCount = 0
            else
                local bpMax = getBackpackMax()
                local availableSpace = nil
                if bpMax then
                    local receiverTotal = getTotalBackpackCount(receiver)
                    availableSpace = bpMax - receiverTotal
                    if availableSpace <= 0 then
                        warn("[TRADE][SENDER] Receiver", receiver.Name, "backpack is full (", receiverTotal, "/", bpMax, ") — skipping to next receiver")
                        receiverIdx = receiverIdx + 1
                        retryCount = 0
                    end
                end

                if availableSpace == nil or availableSpace > 0 then
                    batchSize = math.min(needForThis, remaining, batchCap)
                    if availableSpace and availableSpace < batchCap then
                        batchSize = math.min(batchSize, availableSpace)
                        print("[TRADE][SENDER] Receiver backpack:", getTotalBackpackCount(receiver), "/", bpMax, "→ batch capped to", batchSize)
                    end
                    uuids = collectUUIDs(batchSize)

                    if #uuids == 0 then
                        local nowCount = countItems(localPlayer)
                        local totalDisappeared = initialCount - nowCount
                        local unconfirmed = totalDisappeared - confirmedSent
                        if unconfirmed > 0 then
                            print("[TRADE][SENDER] Items disappeared:", unconfirmed, "(start:", initialCount, "now:", nowCount, "confirmed:", confirmedSent, ")")
                            confirmedSent = confirmedSent + unconfirmed
                            remaining = remaining - unconfirmed
                            if remaining <= 0 then
                                print("[TRADE][SENDER] All items gone as expected!")
                                break
                            end
                        end
                        local nameList = getNameList()
                        local msg = "No items matching config: " .. table.concat(nameList, ", ") .. " (sent " .. confirmedSent .. " so far)"
                        warn("[TRADE][SENDER]", msg)
                        callDone()
                        localPlayer:Kick(msg)
                        return
                    end
                    if #uuids < batchSize then
                        warn("[TRADE][SENDER] Found only", #uuids, "item(s) (need", batchSize, ") — trading what's available")
                        batchSize = #uuids
                    end
                end
            end
        end

        if batchSize > 0 or tokenOnly then
            if not receiverReady[receiver.Name] then
                print("[TRADE][SENDER] Waiting for", receiver.Name, "to load game...")
                local ready = waitForReceiverReady(receiver, 30)
                if not ready then
                    warn("[TRADE][SENDER]", receiver.Name, "left server while waiting to load")
                    receiverIdx = receiverIdx + 1
                    retryCount = 0
                    batchCap = 9
                else
                    receiverReady[receiver.Name] = true
                end
            end

            if not receiverReady[receiver.Name] then
                -- receiver left, skip to next iteration
            else
            local beforeCount = countItems(localPlayer)

            local success, batchTokenSent, tradeStatus = doTradeBatch(receiver, uuids)

            task.wait(1)

            if tradeStatus == "rejected" then
                warn("[TRADE][SENDER] Receiver", receiver.Name, "didn't accept trade — skipping")
                receiverIdx = receiverIdx + 1
                retryCount = 0
                batchCap = 9
            elseif tokenOnly then
                confirmedTokenSent = confirmedTokenSent + (batchTokenSent or 0)
                sentPerReceiver[receiverIdx] = (batchTokenSent or 0)
                print("[TRADE][SENDER] Token-only trade sent to", receiver.Name, "(", batchTokenSent or 0, "tokens)")
                remaining = remaining - 1
                receiverIdx = receiverIdx + 1
                retryCount = 0
            else
                local afterCount = countItems(localPlayer)
                local actualSent = beforeCount - afterCount
                print("[TRADE][SENDER] Verify: before=", beforeCount, "after=", afterCount, "sent=", actualSent)

                if actualSent > 0 then
                    confirmedSent = confirmedSent + actualSent
                    remaining = remaining - actualSent
                    sentPerReceiver[receiverIdx] = (sentPerReceiver[receiverIdx] or 0) + actualSent
                    local totalSent = totalToSend - remaining
                    print("[TRADE][SENDER] Trade success! Sent", actualSent, "| total:", totalSent)
                    if (sentPerReceiver[receiverIdx] or 0) >= itemsPerReceiver then
                        print("[TRADE][SENDER] Receiver", receiver.Name, "got full", itemsPerReceiver, "→ next receiver")
                        receiverIdx = receiverIdx + 1
                        batchCap = 9
                    end
                    retryCount = 0
                    if remaining > 0 then
                        print("[TRADE][SENDER] Remaining:", remaining)
                        task.wait(1.5)
                    end
                else
                    retryCount = retryCount + 1
                    warn("[TRADE][SENDER] Backpack unchanged (", beforeCount, "→", afterCount, ") — trade failed (attempt", retryCount, "/", MAX_RETRIES, ") batchCap:", batchCap)
                    if retryCount % 2 == 0 and batchCap > 1 then
                        batchCap = math.max(1, math.floor(batchCap / 2))
                        print("[TRADE][SENDER] Reducing batch cap to", batchCap, "(receiver may be near full)")
                    end
                    dismissTradeUI()
                    if retryCount >= MAX_RETRIES then
                        local nowTotal = countItems(localPlayer)
                        local totalDisappeared = initialCount - nowTotal
                        local untracked = totalDisappeared - confirmedSent
                        if untracked > 0 then
                            print("[TRADE][SENDER] Found", untracked, "untracked item(s) that left backpack — counting")
                            confirmedSent = confirmedSent + untracked
                            remaining = remaining - untracked
                            retryCount = 0
                        else
                            warn("[TRADE][SENDER] Max retries", MAX_RETRIES, "with no progress — skipping to next receiver")
                            receiverIdx = receiverIdx + 1
                            retryCount = 0
                            batchCap = 9
                        end
                    else
                        task.wait(1.5)
                    end
                end
            end
            end
        end
        ::continue_receiver_loop::
    end

    local tradeOk = (remaining <= 0)
    if tokenOnly and tradeOk then
        print("[TRADE][SENDER] === Token-only trade complete ===")
    elseif tradeOk then
        print("[TRADE][SENDER] === All", totalToSend, "item(s) traded ===")
    else
        warn("[TRADE][SENDER] Trade incomplete —", remaining, "item(s) remaining")
    end

    if CFG_KICK_AFTER_DONE and tradeOk then
        local shouldKick
        if SENDERS_AUTO_FILLED then
            shouldKick = true
        elseif RECEIVERS_AUTO_FILLED then
            shouldKick = false
        else
            shouldKick = (#CFG_SENDERS > 1 and #CFG_RECEIVERS == 1)
        end

        local remainingItems = countItems(localPlayer)
        if remainingItems <= 0 and not tokenOnly then
            print("[TRADE][SENDER] No matching items left in backpack → done + kick")
            shouldKick = true
        end

        if shouldKick then
            print("[TRADE][SENDER] Calling done...")
            callDone()
            local msg = "Done traded sent " .. (tokenOnly and (confirmedTokenSent .. " tokens") or (confirmedSent .. " items"))
            print("[TRADE][SENDER]", msg)
            localPlayer:Kick(msg)
        end
    end

    if CFG_KICK_AFTER_DONE and not tradeOk then
        callDone()
        local msg = "Trade incomplete — sent " .. confirmedSent .. " / " .. totalToSend
        warn("[TRADE][SENDER]", msg)
        task.wait(5)
        localPlayer:Kick(msg)
    end
end


-- =================== RECEIVER Logic ===================

local function runReceiver()
    local nameCount = #getNameList()
    local itemsPerSender
    if CFG_ITEMS_AMOUNT_RAW > 0 then
        itemsPerSender = CFG_ITEMS_AMOUNT_RAW * nameCount
    else
        itemsPerSender = 0
    end

    local wsPerSender = 0
    if CFG_WS_CD > 0 and CFG_WS_AMOUNT > 0 then
        wsPerSender = CFG_WS_AMOUNT
        if itemsPerSender > 0 then
            itemsPerSender = itemsPerSender + wsPerSender
        end
    end

    print("[TRADE][RECEIVER] === RECEIVER === player:", localPlayer.Name)
    print("[TRADE][RECEIVER] Senders:", #CFG_SENDERS, "| Receivers:", #CFG_RECEIVERS,
          "| Items per sender:", itemsPerSender > 0 and itemsPerSender or "ALL",
          CFG_WS_CD > 0 and ("(incl WS:" .. wsPerSender .. ")") or "")

    local senderPlayers = waitForAnySender()
    print("[TRADE][RECEIVER] Found Senders:", #senderPlayers, "/", #CFG_SENDERS)

    local totalNeeded
    local tokenOnlyMode = false
    if itemsPerSender > 0 then
        totalNeeded = itemsPerSender * #senderPlayers
    else
        local senderItemCount = 0
        for _, sender in ipairs(senderPlayers) do
            local c = countItems(sender)
            senderItemCount = senderItemCount + c
        end
        if senderItemCount > 0 then
            local perSenderForMe = math.ceil(senderItemCount / #CFG_RECEIVERS)
            totalNeeded = perSenderForMe
            print("[TRADE][RECEIVER] send-all: sender backpack has", senderItemCount,
                  "items → expected:", totalNeeded)
        else
            if CFG_TOKEN_AMOUNT > 0 then
                tokenOnlyMode = true
                totalNeeded = 0
                print("[TRADE][RECEIVER] Sender has no items + has token", CFG_TOKEN_AMOUNT, "→ token-only mode")
            else
                totalNeeded = 0
                print("[TRADE][RECEIVER] send-all: sender backpack empty (0) → using default")
            end
        end
    end

    local totalRounds
    if totalNeeded > 0 then
        local batchesPerSender = math.ceil((itemsPerSender > 0 and itemsPerSender or 9) / 9)
        totalRounds = batchesPerSender * #senderPlayers
        totalRounds = totalRounds + math.max(3, math.ceil(totalRounds * 0.5))
    else
        totalRounds = nil
    end
    if CFG_WS_CD > 0 and CFG_WS_AMOUNT <= 0 then
        totalRounds = nil
    end
    local totalReceived = 0
    local consecutiveFail = 0
    local hasReceivedItems = false
    local initialReceiverCount = countItems(localPlayer)
    print("[TRADE][RECEIVER] Expected total:",
          totalNeeded > 0 and totalNeeded or "unknown(send all)",
          "items | rounds:", totalRounds or "unlimited")

    local round = 0
    local backpackFull = false
    while true do
        round = round + 1
        if totalRounds and round > totalRounds then break end

        local curCap, maxCap = getBackpackCapacity()
        if curCap and maxCap then
            local space = maxCap - curCap
            if space <= 0 then
                print("[TRADE][RECEIVER] Backpack is full (", curCap, "/", maxCap, ") — stopping")
                backpackFull = true
                break
            end
            print("[TRADE][RECEIVER] Backpack:", curCap, "/", maxCap, "| available:", space)
        end

        local expectedBatch
        if totalNeeded > 0 then
            local remaining = totalNeeded - totalReceived
            if remaining <= 0 then break end
            expectedBatch = math.min(remaining, 9)
        else
            if hasReceivedItems then
                expectedBatch = 9
            else
                expectedBatch = (CFG_TOKEN_AMOUNT > 0) and 1 or 9
            end
        end

        print("[TRADE][RECEIVER] Round", round, "/", (totalRounds or "~"), "| expected batch:", expectedBatch)

        print("[TRADE][RECEIVER] Waiting for trade request...")
        local gotRequest = clickAcceptTradeRequest(nil, nil)
        if not gotRequest then
            warn("[TRADE][RECEIVER] Trade request accept failed — retrying")
        else

        local beforeCount = countItems(localPlayer)

        print("[TRADE][RECEIVER] Waiting for Sender to place items...")
        local recvItems = {}
        local recvTokens = 0
        local pollDeadline = tick() + 20
        local stableCount = 0
        local lastItemCount = 0
        while tick() < pollDeadline do
            recvItems = readTradeSlots("RecvOffer")
            recvTokens = readTradeTokens("RecvOffer")
            local hasContent = #recvItems > 0 or recvTokens > 0
            if hasContent then
                if #recvItems == lastItemCount then
                    stableCount = stableCount + 1
                else
                    stableCount = 0
                    lastItemCount = #recvItems
                end
                if stableCount >= 3 then
                    break
                end
            end
            task.wait(0.5)
        end

        if #recvItems > 0 then
            print("[TRADE][RECEIVER] ✓ Sender placed:", #recvItems, "item(s) →", table.concat(recvItems, ", "))
        else
            if not tokenOnlyMode then
                warn("[TRADE][RECEIVER] ✗ No items found in RecvOffer after polling!")
            end
        end
        if recvTokens > 0 then
            print("[TRADE][RECEIVER] ✓ Sender offered:", recvTokens, "token(s)")
            print("[TRADE][RECEIVER] Token trade detected: Calling done + kick (force, always)")
            callDone()
            task.wait(2)
            local msg = "Done traded received tokens (token trade detected)"
            print("[TRADE][RECEIVER]", msg)
            localPlayer:Kick(msg)
            return
        elseif tokenOnlyMode then
            warn("[TRADE][RECEIVER] ✗ Token-only mode but RecvOffer shows 0 tokens!")
        end

        local skipRound = false
        if #recvItems == 0 and recvTokens <= 0 then
            warn("[TRADE][RECEIVER] Sender offered nothing (0 items, 0 tokens) — declining")
            dismissTradeUI()
            task.wait(1)
            consecutiveFail = consecutiveFail + 1
            if consecutiveFail >= 15 then
                warn("[TRADE][RECEIVER]", consecutiveFail, "consecutive empty trades — stopping")
                break
            end
            skipRound = true
        end

        if not skipRound then

        if not tokenOnlyMode and #recvItems > 0 then
            local curCap, maxCap = getBackpackCapacity()
            if curCap and maxCap then
                local space = maxCap - curCap
                if space <= 0 then
                    warn("[TRADE][RECEIVER] Backpack is full (", curCap, "/", maxCap, ") — declining trade")
                    dismissTradeUI()
                    task.wait(1)
                    backpackFull = true
                    break
                elseif #recvItems > space then
                    warn("[TRADE][RECEIVER] Offered", #recvItems, "items but only", space, "space (", curCap, "/", maxCap, ") — declining trade")
                    dismissTradeUI()
                    task.wait(1)
                    consecutiveFail = consecutiveFail + 1
                    if consecutiveFail >= 5 then
                        warn("[TRADE][RECEIVER] Too many oversize trades — marking backpack full")
                        backpackFull = true
                        break
                    end
                    skipRound = true
                end
            end
        end

        end
        if not skipRound then

        fireReady(expectedBatch)
        print("[TRADE][RECEIVER] 2nd Accept: Ready done!")

        if not tokenOnlyMode then
            local changed, postCount = waitForBackpackChange(localPlayer, beforeCount, "increase", 10)
            if changed then
                print("[TRADE][RECEIVER] ✓ Trade verified — items:", beforeCount, "→", postCount)
            else
                warn("[TRADE][RECEIVER] Items didn't increase — trade may have failed")
            end
        else
            print("[TRADE][RECEIVER] Token-only: waiting for Trade UI to close...")
            local tokenVerified = false
            local uiDeadline = tick() + 15
            while tick() < uiDeadline do
                local tradeFrame = getButtonByPath("Menus", "Trade")
                if not tradeFrame then
                    tokenVerified = true
                    break
                end
                local isOpen = true
                if tradeFrame:IsA("ScreenGui") then
                    isOpen = tradeFrame.Enabled ~= false
                elseif tradeFrame:IsA("GuiObject") then
                    isOpen = tradeFrame.Visible ~= false
                end
                if not isOpen then
                    tokenVerified = true
                    break
                end
                task.wait(0.5)
            end
            if tokenVerified then
                print("[TRADE][RECEIVER] ✓ Trade UI closed — token trade completed!")
            else
                warn("[TRADE][RECEIVER] Trade UI still open after 15s — dismissing")
                dismissTradeUI()
            end
        end
        task.wait(1)

        local afterCount = countItems(localPlayer)
        local gained     = afterCount - beforeCount
        totalReceived    = totalReceived + math.max(0, gained)
        if gained > 0 then hasReceivedItems = true end
        print("[TRADE][RECEIVER] Round", round, "gained:", gained, "| total:", totalReceived)

        if gained <= 0 then
            if tokenOnlyMode then
                print("[TRADE][RECEIVER] Token-only round: no items (token trade) — continuing...")
                consecutiveFail = 0
            else
            consecutiveFail = consecutiveFail + 1
            warn("[TRADE][RECEIVER] Round", round, "no items gained — trade likely failed (fail", consecutiveFail, ")")
            if consecutiveFail >= 15 then
                warn("[TRADE][RECEIVER]", consecutiveFail, "consecutive fails — stopping")
                break
            end
            end
        else
            consecutiveFail = 0
            if totalNeeded > 0 and totalReceived >= totalNeeded then
                print("[TRADE][RECEIVER] Got all expected items!")
                break
            end
        end

        local curCap2, maxCap2 = getBackpackCapacity()
        if curCap2 and maxCap2 and curCap2 >= maxCap2 then
            print("[TRADE][RECEIVER] Backpack is full after this round (", curCap2, "/", maxCap2, ") — stopping")
            backpackFull = true
            break
        end

        end
        end
    end

    task.wait(1)
    local finalCount = countItems(localPlayer)
    local verifiedGain = finalCount - initialReceiverCount
    print("[TRADE][RECEIVER] === Final Verify ===")
    print("[TRADE][RECEIVER] Backpack: before=", initialReceiverCount, "after=", finalCount, "gained=", verifiedGain)
    print("[TRADE][RECEIVER] Per-round total:", totalReceived, "| Backpack verify:", verifiedGain)

    local actualItems = math.max(verifiedGain, 0)
    local itemsOk = false
    if totalNeeded > 0 then
        itemsOk = actualItems >= totalNeeded
        if itemsOk then
            print("[TRADE][RECEIVER] ✓ Got all items!", actualItems, "/", totalNeeded)
        else
            warn("[TRADE][RECEIVER] ✗ Items incomplete!", actualItems, "/", totalNeeded)
        end
    elseif totalNeeded == 0 and actualItems > 0 then
        itemsOk = true
        print("[TRADE][RECEIVER] ✓ send-all: got", actualItems, "item(s)")
    end

    local tokenOk = tokenOnlyMode
    if tokenOnlyMode then
        print("[TRADE][RECEIVER] ✓ Token-only mode: trade completed")
        print("[TRADE][RECEIVER] Token-only: Calling done + kick (force, always)")
        callDone()
        task.wait(2)
        local msg = "Done traded received tokens (token-only mode)"
        print("[TRADE][RECEIVER]", msg)
        localPlayer:Kick(msg)
        return
    end

    local partialOk = (not itemsOk) and (actualItems > 0) and (CFG_TOKEN_AMOUNT > 0)
    if partialOk then
        print("[TRADE][RECEIVER] ✓ Partial success: got", actualItems, "item(s) + tokens", CFG_TOKEN_AMOUNT)
    end

    if backpackFull and actualItems > 0 then
        itemsOk = true
        print("[TRADE][RECEIVER] ✓ Backpack full — received", actualItems, "item(s) before full")
    end

    local isSuccess = itemsOk or tokenOk or partialOk
    print("[TRADE][RECEIVER] ===", isSuccess and "SUCCESS" or "FAILED", "===")

    if ENV.TaskAfterGetItems then
        local result = {
            items         = actualItems,
            itemsExpected = totalNeeded > 0 and totalNeeded or actualItems,
            tokens        = tokenOnlyMode and CFG_TOKEN_AMOUNT or 0,
            tokenOnly     = tokenOnlyMode,
            success       = isSuccess,
            backpackFull  = backpackFull,
        }
        print("[TRADE][CALLBACK] Sending result:", "items="..result.items,
              "expected="..result.itemsExpected, "tokens="..result.tokens,
              "success="..tostring(result.success))
        task.spawn(ENV.TaskAfterGetItems, result)
    end

    local knowsTarget = CFG_ITEMS_AMOUNT_RAW > 0
        or (CFG_WS_CD > 0 and CFG_WS_AMOUNT > 0)
        or tokenOnlyMode
    if CFG_KICK_AFTER_DONE and isSuccess and knowsTarget then
        local shouldKick
        if RECEIVERS_AUTO_FILLED then
            shouldKick = true
        elseif SENDERS_AUTO_FILLED then
            shouldKick = false
        else
            shouldKick = not (#CFG_SENDERS > 1 and #CFG_RECEIVERS == 1)
        end
        if shouldKick then
            print("[TRADE][RECEIVER] Calling done...")
            callDone()
            task.wait(2)
            local msg
            if backpackFull then
                msg = "Backpack is full — received " .. actualItems .. " items"
            else
                msg = "Done traded received " .. (tokenOnlyMode and "tokens" or (actualItems .. " items"))
            end
            print("[TRADE][RECEIVER]", msg)
            localPlayer:Kick(msg)
        end
    end

    if backpackFull and not (CFG_KICK_AFTER_DONE and isSuccess) then
        print("[TRADE][RECEIVER] Backpack is full — calling done + kick")
        callDone()
        task.wait(2)
        local msg = "Backpack is full — received " .. actualItems .. " items"
        print("[TRADE][RECEIVER]", msg)
        localPlayer:Kick(msg)
    end
end


-- =================== Wait for Game Data ===================

local function waitForGameLoad()
    print("[TRADE] Waiting for game data to load...")

    -- ==== FIX: รอ Players list พร้อมก่อน auto-fill ====
    local playerDeadline = tick() + 15
    while tick() < playerDeadline do
        if #Players:GetPlayers() > 0 then break end
        task.wait(0.5)
    end

    -- ==== รัน resolveAutoFill ตอนนี้ (Players พร้อมแล้ว) ====
    resolveAutoFill()

    -- ==== re-check isSender / isReceiver หลัง auto-fill ====
    isSender   = nameInList(localPlayer.Name, CFG_SENDERS)
    isReceiver = nameInList(localPlayer.Name, CFG_RECEIVERS)
    print("[TRADE] Role: isSender=", isSender, "| isReceiver=", isReceiver)

    -- Wait for Backpack to exist
    local backpack = localPlayer:WaitForChild("Backpack", 30)
    if backpack then
        local deadline = tick() + 10
        local lastCount = -1
        while tick() < deadline do
            local c = #backpack:GetChildren()
            if c > 0 and c == lastCount then
                break
            end
            lastCount = c
            task.wait(1)
        end
        task.wait(2)
    end
    -- Wait for token HUD to appear if config needs tokens
    if CFG_TOKEN_AMOUNT > 0 then
        local deadline = tick() + 10
        while tick() < deadline do
            local obj = getButtonByPath("HUD", "BottomLeft", "TradeTokens", "Container", "TradeTokens", "Value")
            if obj and obj.Text and obj.Text ~= "" then
                print("[TRADE] Token HUD loaded:", obj.Text)
                break
            end
            task.wait(1)
        end
    end
    print("[TRADE] Game data loaded! Backpack:", countItems(localPlayer), "items | Token:", getActualTokenBalance())
end

-- =================== Entry Point ===================

waitForGameLoad()

if isSender then
    while true do
        runSender()
        print("[TRADE][SENDER] Loop: รอ 10 วินาทีแล้ววนใหม่\n")
        wait(10)
    end
elseif isReceiver then
    runReceiver()
else
    warn("[TRADE] Player '", localPlayer.Name, "' not in Senders or Receivers config — doing nothing")
end