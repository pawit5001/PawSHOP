-- ============================================================
-- ETFB Auto Trade
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
--   getgenv().ItemsName   = {"SkibidiToilet", "Cameraman"}
--   getgenv().ItemsAmount = 3            -- per-name amount (e.g. 3 names x 3 = 9 total, 0 = send all matching)
--   getgenv().TokenAmount = 0            -- tokens to send per batch (0 = none)
--   getgenv().KickAfterDone = true       -- kick after trade done (default false)
--
-- Supported scenarios:
--   1 Sender  → many Receivers  (Senders="name", Receivers=nil → auto-filled)
--   many Senders → 1 Receiver   (Senders=nil → auto-filled, Receivers="name")
--   many Senders → many Receivers (Senders=table, Receivers=table)
-- Then loadstring / execute this script
-- ============================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local localPlayer = Players.LocalPlayer

-- =================== CONFIG ===================
local ENV = getgenv()

local function toList(v)
    if type(v) == "string" then return {v} end
    if type(v) == "table"  then return v   end
    return {}
end

local CFG_SENDERS      = toList(ENV.Senders   or {""})
local CFG_RECEIVERS    = toList(ENV.Receivers  or {""})

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
resolveAutoFill()

local CFG_ITEMS_NAME   = ENV.ItemsName   or {""}
local CFG_ITEMS_AMOUNT_RAW = tonumber(ENV.ItemsAmount) or 0 -- per-name (0 = send all), total = ItemsAmount * #ItemsName
local CFG_TOKEN_AMOUNT = math.max(0,  tonumber(ENV.TokenAmount) or 100)
local CFG_KICK_AFTER_DONE = (ENV.KickAfterDone == true) -- kick player after trade done (default false)

-- Callback after Receiver gets all items
-- result = { items, itemsExpected, tokens, tokenOnly, success }
if not ENV.TaskAfterGetItems then
    ENV.TaskAfterGetItems = function(result)
        result = result or {}
        print("[TRADE][CALLBACK] items:", result.items or 0,
              "/ expected:", result.itemsExpected or "?",
              "| tokens:", result.tokens or 0,
              "| success:", result.success and "YES" or "NO")
        task.wait(5)
        if ENV.Horst_AccountChangeDone then
            ENV.Horst_AccountChangeDone()
        end
    end
end

local function nameInList(name, list)
    for i = 1, #list do
        if list[i] == name then return true end
    end
    return false
end

local isSender   = nameInList(localPlayer.Name, CFG_SENDERS)
local isReceiver = nameInList(localPlayer.Name, CFG_RECEIVERS)

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
        -- check if matches config
        local matched = itemMatches(item)
        local uuid    = getItemUUID(item)
        print("[DEBUG] [" .. i .. "] Class=" .. item.ClassName .. " Name=" .. item.Name)
        print("        Attrs: " .. (attrStr ~= "" and attrStr or "(none)"))
        if childStr ~= "" then
            print("        Children: " .. childStr)
        end
        print("        Match=" .. tostring(matched) .. " UUID=" .. tostring(uuid))
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
            -- Only match text containing "completed" or "success"
            local lo = txt:lower()
            if lo:find("completed") or lo:find("success") then
                -- Check visibility chain
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

-- Check if Backpack item matches config names
local function itemMatches(item)
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

-- Collect UUIDs of matching items in localPlayer's Backpack (up to `limit`)
local function collectUUIDs(limit)
    local backpack = localPlayer:FindFirstChild("Backpack")
    if not backpack then return {} end
    local result = {}
    local children = backpack:GetChildren()
    for i = 1, #children do
        if #result >= limit then break end
        local item = children[i]
        if itemMatches(item) then
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
    while tick() < deadline do
        local found = getReceiverPlayers()
        if #found == #CFG_RECEIVERS then return found end
        task.wait(1)
    end
    -- Return whatever was found
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

-- Wait for at least 1 Sender to join (timeout)
local function waitForAnySender(timeoutSec)
    local deadline = tick() + timeoutSec
    while tick() < deadline do
        local found = getSenderPlayers()
        if #found > 0 then return found end
        task.wait(1)
    end
    return {}
end


-- =================== SENDER Logic ===================

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

    -- Method 1: getconnections — call callbacks directly (most reliable)
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

    -- Method 2: firesignal
    if not clicked then
        local ok = pcall(function() firesignal(btn.Activated) end)
        if ok then clicked = true; print("[TRADE]", label, "→ firesignal(Activated)") end
    end
    if not clicked then
        local ok = pcall(function() firesignal(btn.MouseButton1Click) end)
        if ok then clicked = true; print("[TRADE]", label, "→ firesignal(MouseButton1Click)") end
    end
    if clicked then return true end

    -- Method 3: fireclick
    if not clicked then
        local ok = pcall(function() fireclick(btn) end)
        if ok then clicked = true; print("[TRADE]", label, "→ fireclick()") end
    end
    if clicked then return true end

    -- Method 4: VirtualInputManager — simulate mouse click on button position
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
-- Fires once, no spam (toggled on/off)
local function fireReady(itemCount)
    local btn = findTradeConfirmButton()
    if btn then
        -- Wait for cooldown to finish
        for waitLoop = 1, 15 do
            if btn.Visible == false then
                if waitLoop == 1 then print("[TRADE] Trade.Accept not visible yet, waiting...") end
                task.wait(0.5)
            else
                -- Check TextLabel child for "(N)" cooldown
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
-- Waits for popup (timeout since sender may be trading with another receiver)
local function clickAcceptTradeRequest(timeoutSec)
    timeoutSec = timeoutSec or 120
    local btn = findTradeRequestButton()
    if not btn then
        warn("[TRADE] TradeRequest.Main.Accept not found!")
        return false
    end

    -- Get TradeRequest parent frame for visibility check
    local tradeRequestFrame = getButtonByPath("TradeRequest")
    local mainFrame = getButtonByPath("TradeRequest", "Main")

    -- Wait for popup to appear (check frame parent and button)
    local deadline = tick() + timeoutSec
    local printed = false
    while tick() < deadline do
        -- Check if popup is visible
        -- ScreenGui uses Enabled, Frame/Button uses Visible
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
            task.wait(0.3) -- Wait for animation
            local ok = clickButton(btn, "TradeRequest.Accept")
            if ok then return true end
            warn("[TRADE] TradeRequest.Accept click failed")
            return false
        end

        if not printed then
            print("[TRADE] Waiting for trade request popup... (timeout:", timeoutSec, "s)")
            printed = true
        end
        task.wait(0.5)
    end

    warn("[TRADE] Trade request popup never appeared (timeout", timeoutSec, "s)")
    return false
end

-- Dismiss any open Trade UI by clicking Decline/Close
local function dismissTradeUI()
    local tradeFrame = getButtonByPath("Menus", "Trade")
    if not tradeFrame then return false end
    -- Check if visible
    local isVisible = true
    if tradeFrame:IsA("ScreenGui") then
        isVisible = tradeFrame.Enabled ~= false
    elseif tradeFrame:IsA("GuiObject") then
        isVisible = tradeFrame.Visible ~= false
    end
    if not isVisible then return false end
    -- Try known button names
    for _, name in ipairs({"Decline", "Close", "Cancel", "X"}) do
        local btn = tradeFrame:FindFirstChild(name)
        if btn and (btn:IsA("TextButton") or btn:IsA("ImageButton")) then
            print("[TRADE] Dismissing trade UI via", name)
            clickButton(btn, "DismissTrade." .. name)
            task.wait(1)
            return true
        end
    end
    -- Search descendants
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
-- Returns true if found, false on timeout
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
                    -- Check parent chain visibility
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
-- direction = "decrease" (sender) or "increase" (receiver)
-- Returns: changed (bool), currentCount
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

-- Read item names from Trade UI slots
-- side = "GiveOffer" (our side) or "RecvOffer" (other player's side)
-- Returns table of item names found (skips empty slots)
local function readTradeSlots(side)
    local offerFrame = getButtonByPath("Menus", "Trade", side)
    if not offerFrame then return {} end

    -- Find ScrollingFrame with 9 Frame children (trade slots)
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
            -- Find ImageButton > FooterLabel
            for _, btn in ipairs(slotFrame:GetChildren()) do
                if btn:IsA("ImageButton") then
                    local footer = btn:FindFirstChild("FooterLabel")
                    if footer and footer:IsA("TextLabel") and footer.Text and footer.Text ~= "" then
                        -- Strip rich text tags
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

local function doTradeBatch(receiverPlayer, uuids)
    print("[TRADE][SENDER] Sending batch to", receiverPlayer.Name, "| items:", #uuids)

    -- Dismiss any leftover trade UI from previous batch
    dismissTradeUI()

    -- Check receiver still in server
    if not Players:FindFirstChild(receiverPlayer.Name) then
        warn("[TRADE][SENDER] Receiver", receiverPlayer.Name, "left the server!")
        return false
    end

    -- Send Trade Request to receiver (with timeout)
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
    -- Wait for Trade UI (Menus.Trade) to open
    local tradeUI = getButtonByPath("Menus", "Trade")
    local tradeOpened = false
    for waitLoop = 1, 30 do  -- max 15s (30 x 0.5s)
        if tradeUI and tradeUI.Visible ~= false then
            tradeOpened = true
            print("[TRADE][SENDER] Trade UI opened! Placing items...")
            break
        end
        -- Handle ScreenGui case
        if tradeUI and tradeUI:IsA("ScreenGui") and tradeUI.Enabled ~= false then
            tradeOpened = true
            print("[TRADE][SENDER] Trade UI opened! Placing items...")
            break
        end
        task.wait(0.5)
    end
    if not tradeOpened then
        warn("[TRADE][SENDER] Trade UI didn't open within 15s — placing items anyway")
    end

    -- Place items in slots 1-9 in parallel
    for slot = 1, #uuids do
        task.spawn(function()
            pcall(function()
                RF_TradeSetSlotOffer:InvokeServer(tostring(slot), uuids[slot])
            end)
        end)
    end
    task.wait(1)  -- wait for server to process
    print("[TRADE][SENDER] Placed", #uuids, "item(s) in trade slots")

    -- Verify items in Trade UI
    task.wait(0.5)
    local giveItems = readTradeSlots("GiveOffer")
    if #giveItems > 0 then
        print("[TRADE][SENDER] ✓ Trade UI confirmed:", #giveItems, "item(s) →", table.concat(giveItems, ", "))
    else
        warn("[TRADE][SENDER] ✗ No items found in GiveOffer!")
    end

    -- Send Token if configured
    if CFG_TOKEN_AMOUNT > 0 then
        pcall(function()
            RF_TradeOfferCurrency:InvokeServer(CFG_TOKEN_AMOUNT)
        end)
        print("[TRADE][SENDER] Offered", CFG_TOKEN_AMOUNT, "token(s)")
        task.wait(0.5)
    end

    -- Wait before Accept ("Trade was modified" cooldown)
    print("[TRADE][SENDER] Waiting 2s before clicking Accept...")
    task.wait(2)

    local preAcceptCount = countItems(localPlayer)

    -- Sender clicks Accept
    fireReady(#uuids)
    print("[TRADE][SENDER] Accept/Ready done!")

    -- Verify trade completion via backpack change
    local tradeVerified = false
    if #uuids > 0 then
        local changed, postCount = waitForBackpackChange(localPlayer, preAcceptCount, "decrease", 10)
        if changed then
            print("[TRADE][SENDER] ✓ Trade verified — items:", preAcceptCount, "→", postCount)
            tradeVerified = true
        else
            warn("[TRADE][SENDER] Items didn't decrease — trade may have failed")
        end
    else
        -- Token-only: fall back to UI popup detection
        local completed = waitForTradeCompleted(5)
        if completed then
            print("[TRADE][SENDER] ✓ Token-only trade completed!")
            tradeVerified = true
        else
            warn("[TRADE][SENDER] Trade Completed not detected — continuing anyway")
        end
    end
    task.wait(2)
    return tradeVerified
end

local function runSender()
    -- Resolve ItemsAmount: per-name * name count = total
    local initialCount  = countItems(localPlayer)
    local nameCount     = #getNameList()
    local itemsPerReceiver
    if CFG_ITEMS_AMOUNT_RAW > 0 then
        itemsPerReceiver = CFG_ITEMS_AMOUNT_RAW * nameCount
    else
        itemsPerReceiver = 0  -- 0 = send all
    end
    -- No items but has token → token-only trade
    local tokenOnly = false
    if itemsPerReceiver <= 0 and initialCount <= 0 then
        if CFG_TOKEN_AMOUNT > 0 then
            tokenOnly = true
            print("[TRADE][SENDER] No matching items — Token", CFG_TOKEN_AMOUNT, "→ token-only trade")
        else
            local nameList = getNameList()
            local msg = "No items matching config: " .. table.concat(nameList, ", ")
            warn("[TRADE][SENDER]", msg)
            if ENV.Horst_AccountChangeDone then
                ENV.Horst_AccountChangeDone()
            end
            task.wait(5)
            localPlayer:Kick(msg)
            return
        end
    elseif itemsPerReceiver <= 0 then
        -- send-all mode
        itemsPerReceiver = initialCount
    end

    print("[TRADE][SENDER] === SENDER === player:", localPlayer.Name)
    print("[TRADE][SENDER] Senders:", #CFG_SENDERS, "| Receivers:", #CFG_RECEIVERS)
    if tokenOnly then
        print("[TRADE][SENDER] Mode: TOKEN ONLY |", CFG_TOKEN_AMOUNT, "tokens")
    else
        print("[TRADE][SENDER] ItemsPerReceiver:", itemsPerReceiver, "| Receivers:", #CFG_RECEIVERS, "| backpack:", initialCount)
    end

    -- Wait for all Receivers to join (max 120s)
    local receivers = waitForReceivers(120)
    if #receivers == 0 then
        local msg = "No Receiver found in server (waited 120s)"
        warn("[TRADE][SENDER]", msg)
        if CFG_KICK_AFTER_DONE then
            if ENV.Horst_AccountChangeDone then
                ENV.Horst_AccountChangeDone()
            end
            task.wait(5)
            localPlayer:Kick(msg)
        end
        return
    end
    if #receivers < #CFG_RECEIVERS then
        warn("[TRADE][SENDER] Found only", #receivers, "/", #CFG_RECEIVERS, "Receivers — trading with available")
    end

    -- remaining = total still needed across all receivers
    local sentPerReceiver = {}
    local totalToSend = tokenOnly and #receivers or (itemsPerReceiver * #receivers)
    if totalToSend > initialCount and not tokenOnly then
        print("[TRADE][SENDER] Need to send", totalToSend, "but only have", initialCount, "— sending until empty")
        totalToSend = initialCount
    end
    local remaining   = totalToSend
    local receiverIdx = 1
    local retryCount  = 0
    local MAX_RETRIES = 3
    local confirmedSent = 0
    if not tokenOnly then
        print("[TRADE][SENDER] Initial matching items in backpack:", initialCount)
    end

    while remaining > 0 do
        -- Cycle through receivers
        if receiverIdx > #receivers then
            print("[TRADE][SENDER] All receivers done")
            break
        end

        local receiver  = receivers[receiverIdx]

        -- Check receiver still in server
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
            -- token-only: no items to collect
            batchSize = 0
        else
            local alreadySent = sentPerReceiver[receiverIdx] or 0
            local needForThis = itemsPerReceiver - alreadySent
            if needForThis <= 0 then
                -- This receiver is done, skip
                receiverIdx = receiverIdx + 1
                retryCount = 0
            else
                batchSize = math.min(needForThis, remaining, 9)
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
                    if ENV.Horst_AccountChangeDone then
                        ENV.Horst_AccountChangeDone()
                    end
                    task.wait(5)
                    localPlayer:Kick(msg)
                    return
                end
                if #uuids < batchSize then
                    warn("[TRADE][SENDER] Found only", #uuids, "item(s) (need", batchSize, ") — trading what's available")
                    batchSize = #uuids
                end
            end
        end

        -- Trade if batchSize > 0 or tokenOnly, otherwise skip
        if batchSize > 0 or tokenOnly then
            local beforeCount = countItems(localPlayer)

            local success = doTradeBatch(receiver, uuids)

            if success then
                task.wait(2)

                if tokenOnly then
                    print("[TRADE][SENDER] Token-only trade sent to", receiver.Name)
                    remaining = remaining - 1
                    receiverIdx = receiverIdx + 1
                    retryCount = 0
                else
                    -- Verify our items decreased
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
                        end
                        retryCount = 0
                        if remaining > 0 then
                            print("[TRADE][SENDER] Remaining:", remaining, "— waiting 3s...")
                            task.wait(3)
                        end
                    else
                        retryCount = retryCount + 1
                        warn("[TRADE][SENDER] No items sent — trade likely failed (retry", retryCount, "/", MAX_RETRIES, ")")
                        if retryCount >= MAX_RETRIES then
                            warn("[TRADE][SENDER] Max retries", MAX_RETRIES, "— skipping to next receiver")
                            receiverIdx = receiverIdx + 1
                            retryCount = 0
                        else
                            task.wait(3)
                        end
                    end
                end
            else
                retryCount = retryCount + 1
                warn("[TRADE][SENDER] Trade failed with", receiver.Name, "(retry", retryCount, "/", MAX_RETRIES, ")")
                if retryCount >= MAX_RETRIES then
                    warn("[TRADE][SENDER] Skipping to next receiver")
                    receiverIdx = receiverIdx + 1
                    retryCount = 0
                else
                    task.wait(3)
                end
            end
        end
    end

    local tradeOk = tokenOnly or (remaining <= 0)
    if tokenOnly then
        print("[TRADE][SENDER] === Token-only trade complete ===")
    elseif remaining <= 0 then
        print("[TRADE][SENDER] === All", totalToSend, "item(s) traded ===")
    else
        warn("[TRADE][SENDER] Trade incomplete —", remaining, "item(s) remaining")
    end

    -- Done + Kick
    -- Auto-filled side = alts → kick. Explicitly set side = main → stay.
    -- If neither auto-filled: sender kicks for many→1, receiver kicks otherwise.
    -- Also: if no matching items left in backpack → always done + kick
    if CFG_KICK_AFTER_DONE and tradeOk then
        local shouldKick
        if SENDERS_AUTO_FILLED then
            shouldKick = true  -- sender is alt (auto-filled) → kick
        elseif RECEIVERS_AUTO_FILLED then
            shouldKick = false -- sender is main (explicitly set) → stay
        else
            shouldKick = (#CFG_SENDERS > 1 and #CFG_RECEIVERS == 1)
        end

        -- If no matching items left → always done + kick regardless
        local remainingItems = countItems(localPlayer)
        if remainingItems <= 0 and not tokenOnly then
            print("[TRADE][SENDER] No matching items left in backpack → done + kick")
            shouldKick = true
        end

        if shouldKick then
            print("[TRADE][SENDER] Calling done...")
            if ENV.Horst_AccountChangeDone then
                ENV.Horst_AccountChangeDone()
            end
            task.wait(3)
            local msg = "Done traded sent " .. (tokenOnly and (CFG_TOKEN_AMOUNT .. " tokens") or (confirmedSent .. " items"))
            print("[TRADE][SENDER]", msg)
            localPlayer:Kick(msg)
        end
    end
end


-- =================== RECEIVER Logic ===================

local function runReceiver()
    -- Resolve ItemsAmount: per-name * name count = total per sender
    local nameCount = #getNameList()
    local itemsPerSender
    if CFG_ITEMS_AMOUNT_RAW > 0 then
        itemsPerSender = CFG_ITEMS_AMOUNT_RAW * nameCount
    else
        itemsPerSender = 0  -- send all mode
    end

    print("[TRADE][RECEIVER] === RECEIVER === player:", localPlayer.Name)
    print("[TRADE][RECEIVER] Senders:", #CFG_SENDERS, "| Receivers:", #CFG_RECEIVERS,
          "| Items per sender:", itemsPerSender > 0 and itemsPerSender or "ALL")

    -- Wait for at least 1 Sender to join (max 120s)
    local senderPlayers = waitForAnySender(120)
    if #senderPlayers == 0 then
        warn("[TRADE][RECEIVER] No Sender found within 120s")
        return
    end
    print("[TRADE][RECEIVER] Found Senders:", #senderPlayers, "/", #CFG_SENDERS)

    -- Calculate expected items
    local totalNeeded
    local tokenOnlyMode = false
    if itemsPerSender > 0 then
        totalNeeded = itemsPerSender * #senderPlayers
    else
        -- send-all mode: count sender backpacks
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

    -- Calculate totalRounds: senders x batches per sender
    local totalRounds
    if tokenOnlyMode then
        totalRounds = #senderPlayers
    elseif totalNeeded > 0 then
        local batchesPerSender = math.ceil((itemsPerSender > 0 and itemsPerSender or 9) / 9)
        totalRounds = batchesPerSender * #senderPlayers
    else
        totalRounds = 20
    end
    local totalReceived = 0
    local consecutiveFail = 0
    local hasReceivedItems = false
    local initialReceiverCount = countItems(localPlayer)
    print("[TRADE][RECEIVER] Expected total:",
          totalNeeded > 0 and totalNeeded or "unknown(send all)",
          "items | rounds:", totalRounds)

    for round = 1, totalRounds do
        -- Calculate expected batch size for this round
        local expectedBatch
        if totalNeeded > 0 then
            local remaining = totalNeeded - totalReceived
            if remaining <= 0 then break end
            expectedBatch = math.min(remaining, 9)
        else
            -- send-all mode: adaptive batch size
            if hasReceivedItems then
                expectedBatch = 9
            else
                expectedBatch = (CFG_TOKEN_AMOUNT > 0) and 1 or 9
            end
        end

        print("[TRADE][RECEIVER] Round", round, "/", totalRounds, "| expected batch:", expectedBatch)

        -- 1st Accept: Wait for trade request popup
        local waitTimeout = 120
        print("[TRADE][RECEIVER] Waiting for trade request popup (timeout:", waitTimeout, "s)...")
        local gotRequest = clickAcceptTradeRequest(waitTimeout)
        if not gotRequest then
            -- Check if any sender is still in server
            local anySenderHere = false
            for _, sName in ipairs(CFG_SENDERS) do
                if Players:FindFirstChild(sName) then anySenderHere = true; break end
            end
            if not anySenderHere then
                warn("[TRADE][RECEIVER] No senders left in server — stopping")
            else
                warn("[TRADE][RECEIVER] No trade request received within timeout — stopping")
            end
            break
        end

        -- Count items before trade
        local beforeCount = countItems(localPlayer)

        -- 2nd Accept: Wait for Sender to place items + cooldown
        local receiverWait = 8
        print("[TRADE][RECEIVER] Waiting for Sender to place items (" .. receiverWait .. "s)...")
        task.wait(receiverWait)

        -- Verify sender placed items in Trade UI
        local recvItems = readTradeSlots("RecvOffer")
        if #recvItems > 0 then
            print("[TRADE][RECEIVER] ✓ Trade UI shows sender placed:", #recvItems, "item(s) →", table.concat(recvItems, ", "))
        else
            if not tokenOnlyMode then
                warn("[TRADE][RECEIVER] ✗ No items found in RecvOffer!")
            end
        end

        -- Receiver clicks Accept
        fireReady(expectedBatch)
        print("[TRADE][RECEIVER] 2nd Accept: Ready done!")

        -- Verify trade completion via backpack change
        if not tokenOnlyMode then
            local changed, postCount = waitForBackpackChange(localPlayer, beforeCount, "increase", 10)
            if changed then
                print("[TRADE][RECEIVER] ✓ Trade verified — items:", beforeCount, "→", postCount)
            else
                warn("[TRADE][RECEIVER] Items didn't increase — trade may have failed")
            end
        else
            local completed = waitForTradeCompleted(5)
            if completed then
                print("[TRADE][RECEIVER] ✓ Token-only trade completed!")
            else
                warn("[TRADE][RECEIVER] Trade Completed not detected — checking backpack anyway")
            end
        end
        task.wait(2)

        -- Check if items were actually received
        local afterCount = countItems(localPlayer)
        local gained     = afterCount - beforeCount
        totalReceived    = totalReceived + math.max(0, gained)
        if gained > 0 then hasReceivedItems = true end
        print("[TRADE][RECEIVER] Round", round, "gained:", gained, "| total:", totalReceived)

        if gained <= 0 then
            if tokenOnlyMode then
                print("[TRADE][RECEIVER] Token-only mode: no items but got token — success!")
                break
            end
            consecutiveFail = consecutiveFail + 1
            warn("[TRADE][RECEIVER] Round", round, "no items gained — trade likely failed (fail", consecutiveFail, "/ 3 )")
            if consecutiveFail >= 3 then
                if totalNeeded == 0 then
                    print("[TRADE][RECEIVER] send-all: 3 consecutive fails — sender likely done")
                else
                    warn("[TRADE][RECEIVER] 3 consecutive fails — stopping")
                end
                break
            end
        else
            consecutiveFail = 0
            if totalNeeded > 0 and totalReceived >= totalNeeded then
                print("[TRADE][RECEIVER] Got all expected items!")
                break
            end
        end
    end

    -- === Final verification (backpack before/after comparison) ===
    task.wait(1)
    local finalCount = countItems(localPlayer)
    local verifiedGain = finalCount - initialReceiverCount
    print("[TRADE][RECEIVER] === Final Verify ===")
    print("[TRADE][RECEIVER] Backpack: before=", initialReceiverCount, "after=", finalCount, "gained=", verifiedGain)
    print("[TRADE][RECEIVER] Per-round total:", totalReceived, "| Backpack verify:", verifiedGain)

    -- Use verifiedGain as authoritative (more accurate than per-round delta)
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
        print("[TRADE][RECEIVER] ✓ Token-only mode: received", CFG_TOKEN_AMOUNT, "token(s)")
    end

    -- Partial success: got some items + tokens were configured
    local partialOk = (not itemsOk) and (actualItems > 0) and (CFG_TOKEN_AMOUNT > 0)
    if partialOk then
        print("[TRADE][RECEIVER] ✓ Partial success: got", actualItems, "item(s) + tokens", CFG_TOKEN_AMOUNT)
    end

    local isSuccess = itemsOk or tokenOk or partialOk
    print("[TRADE][RECEIVER] ===", isSuccess and "SUCCESS" or "FAILED", "===")

    if ENV.TaskAfterGetItems then
        local result = {
            items         = actualItems,
            itemsExpected = totalNeeded > 0 and totalNeeded or actualItems,
            tokens        = CFG_TOKEN_AMOUNT,
            tokenOnly     = tokenOnlyMode,
            success       = isSuccess,
        }
        print("[TRADE][CALLBACK] Sending result:", "items="..result.items,
              "expected="..result.itemsExpected, "tokens="..result.tokens,
              "success="..tostring(result.success))
        task.spawn(ENV.TaskAfterGetItems, result)
    end

    -- Done + Kick
    -- Auto-filled side = alts → kick. Explicitly set side = main → stay.
    -- If neither auto-filled: receiver kicks unless many→1.
    if CFG_KICK_AFTER_DONE and isSuccess then
        local shouldKick
        if RECEIVERS_AUTO_FILLED then
            shouldKick = true  -- receiver is alt (auto-filled) → kick
        elseif SENDERS_AUTO_FILLED then
            shouldKick = false -- receiver is main (explicitly set) → stay
        else
            shouldKick = not (#CFG_SENDERS > 1 and #CFG_RECEIVERS == 1)
        end
        if shouldKick then
            task.wait(8) -- wait for callback to finish
            local msg = "Done traded received " .. (tokenOnlyMode and (CFG_TOKEN_AMOUNT .. " tokens") or (actualItems .. " items"))
            print("[TRADE][RECEIVER]", msg)
            localPlayer:Kick(msg)
        end
    end
end


-- =================== Entry Point ===================

if isSender then
    runSender()
elseif isReceiver then
    runReceiver()
else
    warn("[TRADE] Player '", localPlayer.Name, "' not in Senders or Receivers config — doing nothing")
end
