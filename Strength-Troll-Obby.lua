local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local VirtualUser = game:GetService("VirtualUser")

local LocalPlayer = Players.LocalPlayer

local SCRIPT_KEY = "StrengthTrollObbyController"
local globalEnv = getgenv and getgenv() or _G
local oldController = globalEnv[SCRIPT_KEY]
if oldController and oldController.Destroy then
	pcall(oldController.Destroy)
end

local controller = {
	running = true,
	connections = {},
	gui = nil,
}
globalEnv[SCRIPT_KEY] = controller

local RemoteEvents = ReplicatedStorage:WaitForChild("Packages")
	:WaitForChild("Network")
	:WaitForChild("ClientToServer")
	:WaitForChild("RemoteEvents")
local RemoteFunctions = ReplicatedStorage:WaitForChild("Packages")
	:WaitForChild("Network")
	:WaitForChild("ClientToServer")
	:WaitForChild("RemoteFunctions")

local LiftWeightRemote = RemoteEvents:WaitForChild("LiftWeight")
local PunchCharacterRemote = RemoteEvents:WaitForChild("PunchCharacter")
local RebirthRemote = RemoteEvents:WaitForChild("Rebirth")
local PunchStrengthBarrierRemote = RemoteEvents:WaitForChild("PunchStrengthBarrier")
local EquipWeightRemote = RemoteEvents:WaitForChild("EquipWeight")
local BuyWeightRemote = RemoteEvents:WaitForChild("BuyWeight")
local ClaimWinButtonRemote = RemoteFunctions:WaitForChild("ClaimWinButton")
local ClaimPlaytimeRewardRemote = RemoteFunctions:WaitForChild("ClaimPlaytimeReward")

local autoTrainEnabled = false
local autoKillEnabled = false
local autoRebirthEnabled = false
local autoWinEnabled = false
local autoEquipBestStrengthEnabled = false
local autoBuyBestWeightEnabled = false
local autoClaimPlaytimeEnabled = false
local autoServerHopEnabled = false

local BEHIND_DISTANCE = 3
local TELEPORT_UP_OFFSET = 0
local TELEPORT_MIN_MOVE = 0.35
local TARGET_SKIP_COOLDOWN = 3
local TARGET_HEALTH_STUCK_SECONDS = 3
local MOVE_TWEEN_TIME = 0.16
local AUTO_TRAIN_LOOP_DELAY = 0.05
local MAX_TARGET_DISTANCE = 3000
local MAP_GROUND_CHECK_DEPTH = 1200
local FALLEN_HEIGHT_MARGIN = 25
local AFK_CURRENT_MAP_NAME = "AFKZone"
local AUTO_WIN_PUNCH_BURST = 3
local AUTO_WIN_LOOP_DELAY = 0.05
local AUTO_WIN_POST_CLAIM_WAIT = 7
local AUTO_WIN_CLAIM_RETRY_BURST = 2
local AUTO_WIN_CLAIM_FAIL_RETRY_WAIT = 0.8
local AUTO_WIN_CLAIM_FAIL_RETRY_MAX_WAIT = 8
local AUTO_WIN_CLAIM_INITIAL_OBSERVED_WAIT = 30
local AUTO_WIN_CLAIM_MIN_READY_DELAY = 30
local AUTO_WIN_CLAIM_WINS_CHECK_WAIT = 0.35
local AUTO_WIN_CLAIM_TP_HEIGHT = 4
local AUTO_WIN_PUNCH_TP_MIN_DISTANCE = 18
local AUTO_WIN_PUNCH_TP_HEIGHT = 4
local AUTO_WIN_MOVE_LOCK_HOLD = 0.3
local AUTO_WIN_PUNCH_STANDOFF_DISTANCE = 8
local AUTO_WIN_CLAIM_STANDOFF_DISTANCE = 1.5
local AUTO_WIN_GROUND_CAST_HEIGHT = 80
local AUTO_WIN_MAX_BREAK_MINUTES = 2.5
local AUTO_WIN_EFFECTIVE_HITS_PER_SECOND = 3
local AUTO_WIN_OBSERVED_DPS_WEIGHT = 0.75
local AUTO_WIN_OBSERVED_DPS_SMOOTHING = 0.35
local AUTO_WIN_DEBUG_ENABLED = false
local AUTO_WIN_DEBUG_INTERVAL = 1.0
local AUTO_WIN_WAIT_TRAIN_BURST = 2
local AUTO_KILL_SINGLE_BURST = 6
local AUTO_KILL_LOOP_DELAY = 0.05
local AUTO_HOP_MIN_SERVER_PLAYERS = 5
local AUTO_HOP_TARGET_SERVER_PLAYERS = 20
local AUTO_HOP_CHECK_DELAY = 8
local AUTO_HOP_RETRY_DELAY = 20
local AUTO_HOP_PAGE_LIMIT = 3
local TARGET_REVISIT_COOLDOWN = 2.5
local TARGET_SPAWN_SHIELD_COOLDOWN = 1.8
local AUTO_KILL_TP_COOLDOWN = 0.3
local AUTO_KILL_MIN_TP_DISTANCE = 9
local AUTO_REBIRTH_COOLDOWN = 60
local AUTO_EQUIP_STRENGTH_DELAY = 0.35
local AUTO_EQUIP_VERIFY_TIMEOUT = 0.35
local AUTO_EQUIP_VERIFY_STEP = 0.05
local AUTO_BUY_WEIGHT_DELAY = 0.45
local AUTO_BUY_WEIGHT_ACTION_COOLDOWN = 0.7
local AUTO_PLAYTIME_CLAIM_DELAY = 4
local AUTO_PLAYTIME_REWARD_SLOTS = 12
local STRENGTH_BUTTON_CACHE_TTL = 1.2
local WEIGHT_ITEMS_CACHE_TTL = 1.2
local SETTINGS_FILE_NAME = "StrengthTrollObby.settings.json"
local SETTINGS_KEY = SCRIPT_KEY .. "Settings"

local strengthButtonsCacheData = nil
local strengthButtonsCacheAt = 0
local weightItemsCacheData = nil
local weightItemsCacheAt = 0
local strengthBarrierStaticCacheData = nil
local strengthBarrierStaticCacheCount = 0
local movementLockOwner = nil
local movementLockUntil = 0
local persistedSettingsStore = globalEnv[SETTINGS_KEY]

if type(persistedSettingsStore) ~= "table" then
	persistedSettingsStore = {}
	globalEnv[SETTINGS_KEY] = persistedSettingsStore
end

local function tryAcquireMovementLock(owner, holdSeconds)
	local now = os.clock()
	local movementPriorityByOwner = {
		["equip-touch"] = 1,
		["kill-move"] = 2,
		["win-punch"] = 3,
		["win-claim"] = 4,
	}

	local requestedPriority = movementPriorityByOwner[owner] or 0
	if movementLockOwner and movementLockOwner ~= owner and now < movementLockUntil then
		local currentPriority = movementPriorityByOwner[movementLockOwner] or 0
		if requestedPriority <= currentPriority then
			return false
		end
	end

	movementLockOwner = owner
	movementLockUntil = now + math.max(0, holdSeconds or 0)
	return true
end

local function releaseMovementLock(owner)
	if movementLockOwner == owner then
		movementLockOwner = nil
		movementLockUntil = 0
	end
end

local function isMovementLockActive(owner)
	return movementLockOwner == owner and os.clock() < movementLockUntil
end

local function isAutoWinMovementPriorityActive()
	return isMovementLockActive("win-punch") or isMovementLockActive("win-claim")
end

local function isPlayerInAfkZone(player)
	if not player then
		return false
	end

	local currentMap = player:GetAttribute("CurrentMap")
	if type(currentMap) ~= "string" then
		return false
	end

	return string.lower(currentMap) == string.lower(AFK_CURRENT_MAP_NAME)
end

local function getNonAfkPlayerCount()
	local count = 0
	for _, player in ipairs(Players:GetPlayers()) do
		if not isPlayerInAfkZone(player) then
			count = count + 1
		end
	end

	return count
end

local function bindConnection(connection)
	table.insert(controller.connections, connection)
	return connection
end

bindConnection(LocalPlayer.Idled:Connect(function()
	pcall(function()
		VirtualUser:CaptureController()
		VirtualUser:ClickButton2(Vector2.new(0, 0))
	end)
end))

local function getLocalRootPart()
	local character = LocalPlayer.Character
	if not character then
		return nil
	end

	return character:FindFirstChild("HumanoidRootPart")
end

local function sanitizeToggleSettings(settings)
	settings = type(settings) == "table" and settings or {}

	local sanitized = {
		autoTrainEnabled = settings.autoTrainEnabled == true,
		autoKillEnabled = settings.autoKillEnabled == true,
		autoRebirthEnabled = settings.autoRebirthEnabled == true,
		autoWinEnabled = settings.autoWinEnabled == true,
		autoEquipBestStrengthEnabled = settings.autoEquipBestStrengthEnabled == true,
		autoBuyBestWeightEnabled = settings.autoBuyBestWeightEnabled == true,
		autoClaimPlaytimeEnabled = settings.autoClaimPlaytimeEnabled == true,
		autoServerHopEnabled = settings.autoServerHopEnabled == true,
	}

	return sanitized
end

local function copyPersistedSettings(settings)
	for key, value in pairs(settings) do
		persistedSettingsStore[key] = value
	end
end

local function readToggleSettingsFromFile()
	if type(isfile) ~= "function" or type(readfile) ~= "function" then
		return nil
	end

	local hasFile = false
	local hasFileOk, hasFileResult = pcall(function()
		return isfile(SETTINGS_FILE_NAME)
	end)
	if hasFileOk and hasFileResult then
		hasFile = true
	end

	if not hasFile then
		return nil
	end

	local contentOk, content = pcall(function()
		return readfile(SETTINGS_FILE_NAME)
	end)
	if not contentOk or type(content) ~= "string" or content == "" then
		return nil
	end

	local decodeOk, decoded = pcall(function()
		return HttpService:JSONDecode(content)
	end)
	if not decodeOk then
		return nil
	end

	return sanitizeToggleSettings(decoded)
end

local function loadInitialToggleSettings()
	local settings = readToggleSettingsFromFile() or persistedSettingsStore
	settings = sanitizeToggleSettings(settings)
	copyPersistedSettings(settings)
	return settings
end

local function getCurrentToggleSettings()
	return {
		autoTrainEnabled = autoTrainEnabled,
		autoKillEnabled = autoKillEnabled,
		autoRebirthEnabled = autoRebirthEnabled,
		autoWinEnabled = autoWinEnabled,
		autoEquipBestStrengthEnabled = autoEquipBestStrengthEnabled,
		autoBuyBestWeightEnabled = autoBuyBestWeightEnabled,
		autoClaimPlaytimeEnabled = autoClaimPlaytimeEnabled,
		autoServerHopEnabled = autoServerHopEnabled,
	}
end

local function saveCurrentToggleSettings()
	local settings = sanitizeToggleSettings(getCurrentToggleSettings())
	copyPersistedSettings(settings)

	if type(writefile) == "function" then
		local encodeOk, encoded = pcall(function()
			return HttpService:JSONEncode(settings)
		end)
		if encodeOk and type(encoded) == "string" then
			pcall(function()
				writefile(SETTINGS_FILE_NAME, encoded)
			end)
		end
	end

	return settings
end

local initialToggleSettings = loadInitialToggleSettings()
autoTrainEnabled = initialToggleSettings.autoTrainEnabled
autoKillEnabled = initialToggleSettings.autoKillEnabled
autoRebirthEnabled = initialToggleSettings.autoRebirthEnabled
autoWinEnabled = initialToggleSettings.autoWinEnabled
autoEquipBestStrengthEnabled = initialToggleSettings.autoEquipBestStrengthEnabled
autoBuyBestWeightEnabled = initialToggleSettings.autoBuyBestWeightEnabled
autoClaimPlaytimeEnabled = initialToggleSettings.autoClaimPlaytimeEnabled
autoServerHopEnabled = initialToggleSettings.autoServerHopEnabled

controller.Destroy = function()
	if not controller.running then
		return
	end

	controller.running = false
	autoTrainEnabled = false
	autoKillEnabled = false
	autoRebirthEnabled = false
	autoWinEnabled = false
	autoEquipBestStrengthEnabled = false
	autoBuyBestWeightEnabled = false
	autoClaimPlaytimeEnabled = false
	autoServerHopEnabled = false

	for _, connection in ipairs(controller.connections) do
		if connection and connection.Connected then
			connection:Disconnect()
		end
	end
	controller.connections = {}

	if controller.gui and controller.gui.Parent then
		controller.gui:Destroy()
	end
	controller.gui = nil

	if globalEnv[SCRIPT_KEY] == controller then
		globalEnv[SCRIPT_KEY] = nil
	end
end

local function getStrengthValue(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		return 0
	end

	local strength = leaderstats:FindFirstChild("Strength")
	if not strength then
		return 0
	end

	return strength.Value or 0
end

local function parseNumberFromText(text)
	if type(text) ~= "string" then
		return nil
	end

	local numberText = string.match(text, "%-?[%d,]+")
	if not numberText then
		return nil
	end

	numberText = string.gsub(numberText, ",", "")
	return tonumber(numberText)
end

local function parseLastNumberFromText(text)
	if type(text) ~= "string" then
		return nil
	end

	local lastNumber = nil
	for token in string.gmatch(text, "%-?[%d,]+") do
		lastNumber = token
	end

	if not lastNumber then
		return nil
	end

	lastNumber = string.gsub(lastNumber, ",", "")
	return tonumber(lastNumber)
end

local function parseMaxNumberFromText(text)
	if type(text) ~= "string" then
		return nil
	end

	local maxValue = nil
	for token in string.gmatch(text, "%-?[%d,]+") do
		local cleaned = string.gsub(token, ",", "")
		local value = tonumber(cleaned)
		if value and (not maxValue or value > maxValue) then
			maxValue = value
		end
	end

	return maxValue
end

local SHORTHAND_MULT = { K=1e3, M=1e6, B=1e9, T=1e12, k=1e3, m=1e6, b=1e9, t=1e12 }

local function parseShorthandNumber(text)
	if type(text) ~= "string" then
		return nil
	end
	local numStr, suffix = string.match(text, "([%d,%.]+)%s*([KMBTkmbt]?)")
	if not numStr then
		return nil
	end
	numStr = string.gsub(numStr, ",", "")
	local num = tonumber(numStr)
	if not num then
		return nil
	end
	local mult = SHORTHAND_MULT[suffix]
	if mult then
		num = num * mult
	end
	return num
end

local function formatShorthandNumber(n)
	if not n then
		return "?"
	end
	if n >= 1e12 then
		return string.format("%.1fT", n / 1e12)
	end
	if n >= 1e9 then
		return string.format("%.1fB", n / 1e9)
	end
	if n >= 1e6 then
		return string.format("%.1fM", n / 1e6)
	end
	if n >= 1e3 then
		return string.format("%.1fK", n / 1e3)
	end
	return tostring(math.floor(n))
end

local function getLocalWinsValue()
	local leaderstats = LocalPlayer:FindFirstChild("leaderstats")
	if not leaderstats then
		return 0
	end

	local wins = leaderstats:FindFirstChild("Wins")
	if not wins then
		return 0
	end

	return wins.Value or 0
end

local function getBarrierWinsRequirement(barrier)
	local barrierGuiPart = barrier:FindFirstChild("BarrierGuiPart")
	local barrierGui = barrierGuiPart and barrierGuiPart:FindFirstChild("BarrierGui")
	local requirementLabel = barrierGui and barrierGui:FindFirstChild("WinsRequirement")
	if not requirementLabel then
		return nil
	end

	local function parseWinsText(text)
		return parseShorthandNumber(text) or parseMaxNumberFromText(text) or parseLastNumberFromText(text)
	end

	-- Common case: dedicated child label named "Wins".
	local winsLabel = requirementLabel:FindFirstChild("Wins")
	if winsLabel and winsLabel:IsA("TextLabel") then
		local value = parseWinsText(winsLabel.Text)
		if value then
			return value
		end
	end

	-- Fallback 1: WinsRequirement itself may be a TextLabel.
	if requirementLabel:IsA("TextLabel") then
		local value = parseWinsText(requirementLabel.Text)
		if value then
			return value
		end
	end

	-- Fallback 2: scan all descendant text labels and pick the biggest number.
	local bestValue = nil
	for _, descendant in ipairs(requirementLabel:GetDescendants()) do
		if descendant:IsA("TextLabel") then
			local value = parseWinsText(descendant.Text)
			if value and (not bestValue or value > bestValue) then
				bestValue = value
			end
		end
	end

	return bestValue
end

local function getBarrierHealth(barrier)
	local barrierGuiPart = barrier:FindFirstChild("BarrierGuiPart")
	local barrierGui = barrierGuiPart and barrierGuiPart:FindFirstChild("BarrierGui")
	local healthBar = barrierGui and barrierGui:FindFirstChild("HealthBar")
	local healthLabel = healthBar and healthBar:FindFirstChild("Health")
	if not healthLabel then
		return nil
	end

	return parseShorthandNumber(healthLabel.Text) or parseNumberFromText(healthLabel.Text)
end

local function isGuiObjectEffectivelyVisible(guiObject)
	if not guiObject or not guiObject:IsA("GuiObject") then
		return false
	end

	local current = guiObject
	while current and current:IsA("GuiObject") do
		if not current.Visible then
			return false
		end
		current = current.Parent
	end

	return true
end

local function getBarrierVisibilityState(barrier)
	local barrierGuiPart = barrier:FindFirstChild("BarrierGuiPart")
	local barrierGui = barrierGuiPart and barrierGuiPart:FindFirstChild("BarrierGui")
	if not barrierGui then
		return false, false
	end

	-- Use direct nodes as authoritative source for active/destroyed state.
	local healthBar = barrierGui:FindFirstChild("HealthBar")
	local winsRequirement = barrierGui:FindFirstChild("WinsRequirement")
	local healthVisible = isGuiObjectEffectivelyVisible(healthBar)
	local winsVisible = isGuiObjectEffectivelyVisible(winsRequirement)

	return healthVisible == true, winsVisible == true
end

local function isBarrierDestroyedByVisibility(barrier)
	local healthVisible, winsVisible = getBarrierVisibilityState(barrier)

	-- Stage is active only when both health and win requirement are visible.
	return not (healthVisible and winsVisible)
end

local function getVisibleBarrierTransparency(barrier)
	if not barrier then
		return nil
	end

	local visibleBarrier = barrier:FindFirstChild("VisibleBarrier", true)
	if visibleBarrier and visibleBarrier:IsA("BasePart") then
		return visibleBarrier.Transparency
	end

	return nil
end

local function isBarrierDestroyed(barrier, health, visibleBarrierTransparency, healthVisible, winsVisible)
	if visibleBarrierTransparency == nil then
		visibleBarrierTransparency = getVisibleBarrierTransparency(barrier)
	end
	if visibleBarrierTransparency ~= nil then
		-- User-confirmed game logic:
		-- Transparency = 1   -> passed/destroyed
		-- Transparency = 0.25 -> not passed yet
		return visibleBarrierTransparency >= 0.95
	end

	if healthVisible == nil or winsVisible == nil then
		healthVisible, winsVisible = getBarrierVisibilityState(barrier)
	end

	-- Strong signal from UI: if both health/wins are visible and hp still > 0, barrier is active.
	if healthVisible and winsVisible and (health == nil or health > 0) then
		return false
	end

	if health ~= nil and health <= 0 then
		return true
	end

	local barrierPart = barrier:FindFirstChild("Barrier")
	if barrierPart and barrierPart:IsA("BasePart") then
		-- Treat physics state as a weaker fallback signal only when UI no longer says active.
		if not barrierPart.CanCollide or barrierPart.Transparency >= 0.95 then
			return true
		end
	end

	return isBarrierDestroyedByVisibility(barrier)
end

local function getBarrierPunchPosition(barrier)
	local barrierPart = barrier:FindFirstChild("Barrier")
	if barrierPart and barrierPart:IsA("BasePart") then
		return barrierPart.Position
	end

	local guiPart = barrier:FindFirstChild("BarrierGuiPart")
	if guiPart and guiPart:IsA("BasePart") then
		return guiPart.Position
	end

	local fallbackPart = barrier:FindFirstChildWhichIsA("BasePart", true)
	if fallbackPart then
		return fallbackPart.Position
	end

	return nil
end

local function getBarrierClaimPosition(barrier)
	if not barrier then
		return nil
	end

	for _, descendant in ipairs(barrier:GetDescendants()) do
		if descendant:IsA("BasePart") then
			local nameLower = string.lower(descendant.Name or "")
			if string.find(nameLower, "claim", 1, true)
				or string.find(nameLower, "winbutton", 1, true)
				or (string.find(nameLower, "win", 1, true) and string.find(nameLower, "button", 1, true)) then
				return descendant.Position
			end
		end
	end

	return nil
end

local function getBarrierStageNumber(barrier)
	local barrierGuiPart = barrier:FindFirstChild("BarrierGuiPart")
	local barrierGui = barrierGuiPart and barrierGuiPart:FindFirstChild("BarrierGui")
	local stageNode = barrierGui and barrierGui:FindFirstChild("Stage")
	if not stageNode then
		return nil
	end

	local function parseStageText(text)
		return parseMaxNumberFromText(text) or parseLastNumberFromText(text)
	end

	if stageNode:IsA("TextLabel") then
		local value = parseStageText(stageNode.Text)
		if value then
			return value
		end
	end

	for _, descendant in ipairs(stageNode:GetDescendants()) do
		if descendant:IsA("TextLabel") then
			local value = parseStageText(descendant.Text)
			if value then
				return value
			end
		end
	end

	return nil
end

local function getStrengthBarriersFolder()
	local obby = workspace:FindFirstChild("Obby")
	return obby and obby:FindFirstChild("StrengthBarriers")
end

local function isStrengthBarrierContainer(instance, root)
	if not instance or instance == root then
		return false
	end

	if not (instance:IsA("Model") or instance:IsA("Folder")) then
		return false
	end

	return instance:FindFirstChild("BarrierGuiPart") ~= nil
		or instance:FindFirstChild("Barrier") ~= nil
		or instance:FindFirstChild("VisibleBarrier", true) ~= nil
end

local function getStrengthBarrierContainers(strengthBarriers)
	if not strengthBarriers then
		return {}
	end

	local containers = {}
	for _, descendant in ipairs(strengthBarriers:GetDescendants()) do
		if isStrengthBarrierContainer(descendant, strengthBarriers) then
			table.insert(containers, descendant)
		end
	end

	return containers
end

local function getInstanceDepthFromAncestor(instance, ancestor)
	local depth = 0
	local current = instance
	while current and current ~= ancestor do
		current = current.Parent
		depth = depth + 1
	end

	return depth
end

local function getStrengthBarrierCandidateScore(candidate)
	local score = 0
	if candidate.stageNumber then
		score = score + 100
	end
	if candidate.requirement and candidate.requirement ~= math.huge then
		score = score + 20
	end
	if candidate.punchPosition then
		score = score + 10
	end
	if candidate.claimPosition then
		score = score + 8
	end
	if candidate.barrier and candidate.barrier:FindFirstChild("BarrierGuiPart") then
		score = score + 6
	end
	if candidate.barrier and candidate.barrier:FindFirstChild("Barrier") then
		score = score + 4
	end
	if candidate.barrier and candidate.barrier:FindFirstChild("VisibleBarrier") then
		score = score + 2
	end

	return score
end

local function shouldPreferStrengthBarrierCandidate(currentCandidate, nextCandidate)
	if not currentCandidate then
		return true
	end

	local currentScore = getStrengthBarrierCandidateScore(currentCandidate)
	local nextScore = getStrengthBarrierCandidateScore(nextCandidate)
	if nextScore ~= currentScore then
		return nextScore > currentScore
	end

	if (nextCandidate.depth or math.huge) ~= (currentCandidate.depth or math.huge) then
		return (nextCandidate.depth or math.huge) < (currentCandidate.depth or math.huge)
	end

	return (nextCandidate.requirement or math.huge) < (currentCandidate.requirement or math.huge)
end

local function rebuildStrengthBarrierStaticCache(strengthBarriers)
	if not strengthBarriers then
		strengthBarrierStaticCacheData = {}
		strengthBarrierStaticCacheCount = 0
		return strengthBarrierStaticCacheData
	end

	local uniqueByStageNumber = {}
	local baseList = {}
	for _, barrier in ipairs(getStrengthBarrierContainers(strengthBarriers)) do
		local punchPosition = getBarrierPunchPosition(barrier)
		local candidate = {
			barrier = barrier,
			stageNumber = getBarrierStageNumber(barrier),
			requirement = getBarrierWinsRequirement(barrier) or math.huge,
			punchPosition = punchPosition,
			claimPosition = getBarrierClaimPosition(barrier),
			sortZ = punchPosition and punchPosition.Z or math.huge,
			sortX = punchPosition and punchPosition.X or math.huge,
			depth = getInstanceDepthFromAncestor(barrier, strengthBarriers),
		}

		if candidate.stageNumber then
			local currentCandidate = uniqueByStageNumber[candidate.stageNumber]
			if shouldPreferStrengthBarrierCandidate(currentCandidate, candidate) then
				uniqueByStageNumber[candidate.stageNumber] = candidate
			end
		else
			table.insert(baseList, candidate)
		end
	end

	for _, candidate in pairs(uniqueByStageNumber) do
		table.insert(baseList, candidate)
	end

	table.sort(baseList, function(a, b)
		if a.stageNumber and b.stageNumber and a.stageNumber ~= b.stageNumber then
			return a.stageNumber < b.stageNumber
		end

		if (a.stageNumber ~= nil) ~= (b.stageNumber ~= nil) then
			return a.stageNumber ~= nil
		end

		if a.requirement == b.requirement then
			if a.sortZ == b.sortZ then
				return a.sortX < b.sortX
			end
			return a.sortZ < b.sortZ
		end
		return a.requirement < b.requirement
	end)

	for index, stage in ipairs(baseList) do
		if not stage.stageNumber then
			stage.stageNumber = index
		end
	end

	strengthBarrierStaticCacheData = baseList
	strengthBarrierStaticCacheCount = #baseList
	return baseList
end

local function getStrengthBarrierStages()
	local strengthBarriers = getStrengthBarriersFolder()
	if not strengthBarriers then
		strengthBarrierStaticCacheData = {}
		strengthBarrierStaticCacheCount = 0
		return {}
	end

	local staticStages = strengthBarrierStaticCacheData
	local childCount = #getStrengthBarrierContainers(strengthBarriers)
	if not staticStages or strengthBarrierStaticCacheCount ~= childCount then
		staticStages = rebuildStrengthBarrierStaticCache(strengthBarriers)
	else
		for _, stage in ipairs(staticStages) do
			if not stage.barrier or not stage.barrier:IsDescendantOf(strengthBarriers) then
				staticStages = rebuildStrengthBarrierStaticCache(strengthBarriers)
				break
			end
		end
	end

	local stages = {}
	for _, staticStage in ipairs(staticStages) do
		local barrier = staticStage.barrier
		local health = getBarrierHealth(barrier)
		local visibleBarrierTransparency = getVisibleBarrierTransparency(barrier)
		local healthVisible, winsVisible = getBarrierVisibilityState(barrier)
		table.insert(stages, {
			barrier = barrier,
			stageNumber = staticStage.stageNumber,
			requirement = staticStage.requirement,
			health = health,
			visibleBarrierTransparency = visibleBarrierTransparency,
			healthVisible = healthVisible,
			winsVisible = winsVisible,
			destroyed = isBarrierDestroyed(barrier, health, visibleBarrierTransparency, healthVisible, winsVisible),
			punchPosition = staticStage.punchPosition,
			claimPosition = staticStage.claimPosition,
			sortZ = staticStage.sortZ,
			sortX = staticStage.sortX,
		})
	end

	return stages
end

local function getHighestUnlockedStageIndex(stages, wins)
	local highestIndex = nil
	for index, stage in ipairs(stages) do
		local requirement = stage and stage.requirement or math.huge
		local hasKnownRequirement = requirement and requirement ~= math.huge
		local unlockedByRequirement = hasKnownRequirement and (wins >= requirement) or false

		-- Fallback for stages whose requirement text cannot be parsed.
		-- If UI is hidden/destroyed already, treat it as already cleared/unlocked in progression.
		local unlockedByState = false
		if not hasKnownRequirement and stage then
			unlockedByState = stage.destroyed == true
		end

		if unlockedByRequirement or unlockedByState then
			highestIndex = index
		end
	end

	return highestIndex
end

local function getFirstPendingUnlockedStage(stages, highestUnlockedIndex)
	if not highestUnlockedIndex then
		return nil, nil, nil
	end

	-- Progress strictly in order: always clear the earliest uncleared unlocked stage first.
	for index = 1, highestUnlockedIndex do
		local stage = stages[index]
		if stage then
			if not stage.destroyed then
				if stage.punchPosition then
					return stage, "punch", index
				end

				return stage, "waiting", index
			end
		end
	end

	return nil, nil, nil
end

local function getLatestClaimableStage(stages, highestUnlockedIndex, pendingStageIndex)
	if not highestUnlockedIndex then
		return nil, nil
	end

	local claimIndex = highestUnlockedIndex
	if pendingStageIndex and pendingStageIndex > 1 then
		claimIndex = math.min(highestUnlockedIndex, pendingStageIndex - 1)
	end

	for index = claimIndex, 1, -1 do
		local stage = stages[index]
		if stage and stage.destroyed then
			return stage, index
		end
	end

	return nil, nil
end

local function updateAutoWinObservedDps(progressByStage, stage, now)
	if not progressByStage or not stage or not stage.stageNumber then
		return nil
	end

	local stageKey = stage.stageNumber
	local currentHealth = stage.health
	if currentHealth == nil then
		return nil
	end

	local state = progressByStage[stageKey]
	if not state then
		state = {
			lastHealth = currentHealth,
			lastAt = now,
			observedDps = nil,
		}
		progressByStage[stageKey] = state
		return nil
	end

	local elapsed = math.max(0, now - (state.lastAt or now))
	if elapsed > 0 then
		local healthDelta = (state.lastHealth or currentHealth) - currentHealth
		if healthDelta > 0 then
			local instantDps = healthDelta / elapsed
			if instantDps > 0 then
				if state.observedDps then
					state.observedDps = (state.observedDps * (1 - AUTO_WIN_OBSERVED_DPS_SMOOTHING)) + (instantDps * AUTO_WIN_OBSERVED_DPS_SMOOTHING)
				else
					state.observedDps = instantDps
				end
			end
		end
	end

	state.lastHealth = currentHealth
	state.lastAt = now
	return state.observedDps
end

local function estimateAutoWinBreakSeconds(stage, localStrength, observedDps)
	if not stage then
		return nil
	end

	local health = stage.health
	if health == nil then
		return nil
	end

	if health <= 0 then
		return 0
	end

	local strength = math.max(0, localStrength or 0)
	if strength <= 0 then
		return math.huge
	end

	local theoreticalDps = math.max(1, strength * AUTO_WIN_EFFECTIVE_HITS_PER_SECOND)
	local effectiveDps = theoreticalDps

	if observedDps and observedDps > 0 then
		effectiveDps = (observedDps * AUTO_WIN_OBSERVED_DPS_WEIGHT) + (theoreticalDps * (1 - AUTO_WIN_OBSERVED_DPS_WEIGHT))
		effectiveDps = math.max(theoreticalDps * 0.6, effectiveDps)
	end

	return health / math.max(0.1, effectiveDps)
end

local function getRequiredStrengthForAutoWinEta(stage, maxBreakSeconds)
	if not stage or not stage.health or stage.health <= 0 then
		return 0
	end

	local allowedSeconds = math.max(1, maxBreakSeconds or 1)
	return math.ceil(stage.health / (AUTO_WIN_EFFECTIVE_HITS_PER_SECOND * allowedSeconds))
end

local function shouldDelayAutoWinPunchForStrength(stage, localStrength, estimatedBreakSeconds, maxBreakSeconds)
	if not stage then
		return false
	end

	local requiredStrength = getRequiredStrengthForAutoWinEta(stage, maxBreakSeconds)
	local strength = math.max(0, localStrength or 0)
	if strength < requiredStrength then
		return true
	end

	return estimatedBreakSeconds and estimatedBreakSeconds > maxBreakSeconds or false
end

local function getStrengthButtonWinsRequirement(strengthButton)
	local buttonPart = strengthButton:FindFirstChild("Button")
	local gui = buttonPart and buttonPart:FindFirstChild("StrengthButtonGui")
	local requirementLabel = gui and gui:FindFirstChild("WinsRequirement")
	if not requirementLabel or not requirementLabel:IsA("TextLabel") then
		return nil
	end

	return parseMaxNumberFromText(requirementLabel.Text) or parseLastNumberFromText(requirementLabel.Text)
end

local function getStrengthButtonStrengthAmount(strengthButton)
	local buttonPart = strengthButton:FindFirstChild("Button")
	local gui = buttonPart and buttonPart:FindFirstChild("StrengthButtonGui")
	if not gui then
		return nil
	end

	local requirementLabel = gui:FindFirstChild("WinsRequirement")
	local bestValue = nil

	for _, descendant in ipairs(gui:GetDescendants()) do
		if descendant:IsA("TextLabel") then
			local isRequirementText = requirementLabel and (descendant == requirementLabel or descendant:IsDescendantOf(requirementLabel))
			if not isRequirementText then
				local nameLower = string.lower(descendant.Name or "")
				local text = descendant.Text or ""
				local textLower = string.lower(text)
				local looksLikeStrength = string.find(nameLower, "strength", 1, true)
					or string.find(nameLower, "str", 1, true)
					or string.find(textLower, "strength", 1, true)
					or string.find(textLower, "str", 1, true)
					or string.match(text, "^%s*%+")

				if looksLikeStrength then
					local value = parseShorthandNumber(text) or parseMaxNumberFromText(text) or parseLastNumberFromText(text)
					if value and (not bestValue or value > bestValue) then
						bestValue = value
					end
				end
			end
		end
	end

	return bestValue
end

local function getStrengthButtonPad(strengthButton)
	local buttonPart = strengthButton:FindFirstChild("Button")
	if buttonPart and buttonPart:IsA("BasePart") then
		return buttonPart
	end

	return nil
end

local function getStrengthButtonState(buttonPart)
	if not buttonPart or not buttonPart:IsA("BasePart") then
		return "unknown"
	end

	local brickColorName = string.lower(buttonPart.BrickColor and buttonPart.BrickColor.Name or "")
	if brickColorName == "lime green" then
		return "equipped"
	end

	if brickColorName == "new yeller" then
		return "unlocked"
	end

	if brickColorName == "really red" then
		return "locked"
	end

	return "unknown"
end

local function refreshStrengthButtonsCache(force)
	local now = os.clock()
	if not force and strengthButtonsCacheData and (now - strengthButtonsCacheAt) < STRENGTH_BUTTON_CACHE_TTL then
		return
	end

	local obby = workspace:FindFirstChild("Obby")
	local strengthButtons = obby and obby:FindFirstChild("StrengthButtons")
	if not strengthButtons then
		strengthButtonsCacheData = {}
		strengthButtonsCacheAt = now
		return
	end

	local baseList = {}
	for _, strengthButton in ipairs(strengthButtons:GetChildren()) do
		local requirement = getStrengthButtonWinsRequirement(strengthButton)
		local strengthAmount = getStrengthButtonStrengthAmount(strengthButton)
		local buttonPart = getStrengthButtonPad(strengthButton)
		if requirement and buttonPart then
			table.insert(baseList, {
				instance = strengthButton,
				requirement = requirement,
				strengthAmount = strengthAmount,
				buttonPart = buttonPart,
			})
		end
	end

	table.sort(baseList, function(a, b)
		if a.requirement == b.requirement then
			return a.buttonPart.Position.Y < b.buttonPart.Position.Y
		end
		return a.requirement < b.requirement
	end)

	strengthButtonsCacheData = baseList
	strengthButtonsCacheAt = now
end

local function getSortedStrengthButtonsByRequirement()
	refreshStrengthButtonsCache(false)
	if not strengthButtonsCacheData then
		return {}
	end

	local list = {}
	for _, item in ipairs(strengthButtonsCacheData) do
		table.insert(list, {
			instance = item.instance,
			requirement = item.requirement,
			strengthAmount = item.strengthAmount,
			buttonPart = item.buttonPart,
			state = getStrengthButtonState(item.buttonPart),
		})
	end

	return list
end

local function getBestEligibleStrengthButton(localWins)
	local bestButton = nil
	for _, buttonInfo in ipairs(getSortedStrengthButtonsByRequirement()) do
		if localWins >= buttonInfo.requirement and buttonInfo.state ~= "locked" then
			bestButton = buttonInfo
		else
			break
		end
	end

	return bestButton
end

local function getEquippedStrengthButton()
	for _, buttonInfo in ipairs(getSortedStrengthButtonsByRequirement()) do
		if buttonInfo.state == "equipped" then
			return buttonInfo
		end
	end

	return nil
end

local function getNextStrengthButtonInfo(localWins)
	for _, buttonInfo in ipairs(getSortedStrengthButtonsByRequirement()) do
		if localWins < buttonInfo.requirement then
			return buttonInfo
		end
	end

	return nil
end

local function waitForStrengthButtonState(buttonPart, expectedState, timeout)
	local startedAt = os.clock()
	while os.clock() - startedAt <= timeout do
		if getStrengthButtonState(buttonPart) == expectedState then
			return true
		end
		task.wait(AUTO_EQUIP_VERIFY_STEP)
	end

	return getStrengthButtonState(buttonPart) == expectedState
end

local function touchStrengthButton(buttonPart)
	local localRoot = getLocalRootPart()
	if not localRoot or not buttonPart then
		return false
	end

	if not tryAcquireMovementLock("equip-touch", AUTO_EQUIP_VERIFY_TIMEOUT + 0.15) then
		return false
	end

	if firetouchinterest then
		firetouchinterest(localRoot, buttonPart, 0)
		firetouchinterest(localRoot, buttonPart, 1)
		if waitForStrengthButtonState(buttonPart, "equipped", AUTO_EQUIP_VERIFY_TIMEOUT) then
			releaseMovementLock("equip-touch")
			return true
		end
	end

	local originalCFrame = localRoot.CFrame
	local targetCFrame = CFrame.new(buttonPart.Position + Vector3.new(0, 4, 0))
	localRoot.CFrame = targetCFrame
	task.wait(AUTO_EQUIP_VERIFY_STEP)
	if firetouchinterest then
		firetouchinterest(localRoot, buttonPart, 0)
		firetouchinterest(localRoot, buttonPart, 1)
	end
	local equipped = waitForStrengthButtonState(buttonPart, "equipped", AUTO_EQUIP_VERIFY_TIMEOUT)
	localRoot.CFrame = originalCFrame
	releaseMovementLock("equip-touch")
	return equipped
end

local function getLocalGemsValue()
	local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
	local alphaGui = playerGui and playerGui:FindFirstChild("AlphaGui")
	local leftSide = alphaGui and alphaGui:FindFirstChild("LeftSide")
	local currencies = leftSide and leftSide:FindFirstChild("Currencies")
	local gems = currencies and currencies:FindFirstChild("Gems")
	local label = gems and gems:FindFirstChild("Label")
	if not label or not label:IsA("TextLabel") then
		return 0
	end

	return parseMaxNumberFromText(label.Text) or parseLastNumberFromText(label.Text) or 0
end

local function getWeightItemsSortedByPrice()
	local now = os.clock()
	if not weightItemsCacheData or (now - weightItemsCacheAt) >= WEIGHT_ITEMS_CACHE_TTL then
		local obby = workspace:FindFirstChild("Obby")
		local weightsFolder = obby and obby:FindFirstChild("Weights")
		if not weightsFolder then
			weightItemsCacheData = {}
			weightItemsCacheAt = now
			return {}
		end

		local baseList = {}
		for rawIndex, weightModel in ipairs(weightsFolder:GetChildren()) do
			local buttonPart = getStrengthButtonPad(weightModel)
			local weightGui = buttonPart and buttonPart:FindFirstChild("WeightGui")
			local weightName = weightGui and weightGui:FindFirstChild("WeightName")
			local multiplier = weightGui and weightGui:FindFirstChild("StrengthMultiplier")
			local gemsPrice = weightGui and weightGui:FindFirstChild("GemsPrice")
			local rightLabel = gemsPrice and gemsPrice:FindFirstChild("RightLabel")
			local price = rightLabel and parseMaxNumberFromText(rightLabel.Text)
			local multiplierValue = multiplier and (parseMaxNumberFromText(multiplier.Text) or parseLastNumberFromText(multiplier.Text)) or 0

			if buttonPart and price then
				table.insert(baseList, {
					rawIndex = rawIndex,
					shopIndex = 0,
					shopKey = "",
					buttonPart = buttonPart,
					name = weightName and weightName.Text or ("Weight " .. tostring(rawIndex)),
					multiplier = multiplierValue,
					price = price,
				})
			end
		end

		table.sort(baseList, function(a, b)
			if a.price == b.price then
				if a.multiplier == b.multiplier then
					return a.rawIndex < b.rawIndex
				end
				return a.multiplier < b.multiplier
			end
			return a.price < b.price
		end)

		for progressionIndex, item in ipairs(baseList) do
			item.shopIndex = progressionIndex
			item.shopKey = "ShopWeight" .. tostring(progressionIndex)
		end

		weightItemsCacheData = baseList
		weightItemsCacheAt = now
	end

	local list = {}
	for _, item in ipairs(weightItemsCacheData) do
		table.insert(list, {
			rawIndex = item.rawIndex,
			shopIndex = item.shopIndex,
			shopKey = item.shopKey,
			buttonPart = item.buttonPart,
			state = getStrengthButtonState(item.buttonPart),
			name = item.name,
			multiplier = item.multiplier,
			price = item.price,
		})
	end

	return list
end

local function getNextLockedWeightUpgrade(currentWeight)
	local currentMultiplier = currentWeight and (currentWeight.multiplier or 0) or 0
	local nextUpgrade = nil

	for _, item in ipairs(getWeightItemsSortedByPrice()) do
		local itemMultiplier = item.multiplier or 0
		if item.state == "locked" and itemMultiplier > currentMultiplier then
			if not nextUpgrade then
				nextUpgrade = item
			else
				local nextMultiplier = nextUpgrade.multiplier or 0
				if itemMultiplier < nextMultiplier then
					nextUpgrade = item
				elseif itemMultiplier == nextMultiplier then
					if item.price < nextUpgrade.price then
						nextUpgrade = item
					elseif item.price == nextUpgrade.price and item.shopIndex < nextUpgrade.shopIndex then
						nextUpgrade = item
					end
				end
			end
		end
	end

	return nextUpgrade
end

local function getNextWeightPrice(gems)
	for _, item in ipairs(getWeightItemsSortedByPrice()) do
		if gems < item.price then
			return item.price
		end
	end

	return nil
end

local function getEquippedWeight()
	for _, item in ipairs(getWeightItemsSortedByPrice()) do
		if item.state == "equipped" then
			return item
		end
	end

	return nil
end

local function isOwnedWeightState(state)
	return state == "unlocked" or state == "equipped"
end

local function getBestOwnedWeightByMultiplier()
	local bestWeight = nil
	for _, item in ipairs(getWeightItemsSortedByPrice()) do
		if isOwnedWeightState(item.state) then
			if not bestWeight then
				bestWeight = item
			else
				local itemMultiplier = item.multiplier or 0
				local bestMultiplier = bestWeight.multiplier or 0
				if itemMultiplier > bestMultiplier then
					bestWeight = item
				elseif itemMultiplier == bestMultiplier then
					if item.price > bestWeight.price then
						bestWeight = item
					elseif item.price == bestWeight.price and item.shopIndex > bestWeight.shopIndex then
						bestWeight = item
					end
				end
			end
		end
	end

	return bestWeight
end

local function buyWeightItem(item)
	if not item then
		return false
	end

	local ok = pcall(function()
		BuyWeightRemote:FireServer(item.shopKey)
	end)
	if not ok then
		return false
	end

	task.wait(0.1)
	return true
end

local function equipWeightItem(item)
	if not item then
		return false
	end

	local remoteOk = pcall(function()
		EquipWeightRemote:FireServer(item.shopKey)
	end)

	if waitForStrengthButtonState(item.buttonPart, "equipped", AUTO_EQUIP_VERIFY_TIMEOUT) then
		return true
	end

	local prompt = item.buttonPart:FindFirstChildOfClass("ProximityPrompt")
	if prompt and fireproximityprompt then
		pcall(function()
			fireproximityprompt(prompt, math.max(prompt.HoldDuration + 0.1, 0.2))
		end)
		if waitForStrengthButtonState(item.buttonPart, "equipped", AUTO_EQUIP_VERIFY_TIMEOUT) then
			return true
		end
	end

	return remoteOk and getStrengthButtonState(item.buttonPart) == "equipped"
end

local function isPlaytimeClaimSuccess(result)
	if result == nil then
		return true
	end

	if type(result) == "boolean" then
		return result
	end

	if type(result) == "number" then
		return result > 0
	end

	if type(result) == "string" then
		local lowered = string.lower(result)
		if string.find(lowered, "claim", 1, true) or string.find(lowered, "success", 1, true) then
			return true
		end
		return false
	end

	if type(result) == "table" then
		if result.success ~= nil then
			return isTruthyAttributeValue(result.success)
		end
		if result.claimed ~= nil then
			return isTruthyAttributeValue(result.claimed)
		end
		if result.canClaim ~= nil then
			return isTruthyAttributeValue(result.canClaim)
		end
	end

	return false
end

local function formatAutoWinDebugValue(value)
	local valueType = type(value)
	if valueType == "nil" then
		return "nil"
	end

	if valueType == "string" or valueType == "number" or valueType == "boolean" then
		return tostring(value)
	end

	local ok, encoded = pcall(function()
		return HttpService:JSONEncode(value)
	end)
	if ok and type(encoded) == "string" then
		return encoded
	end

	return valueType
end

local function getGroundSnappedPosition(basePosition, heightOffset)
	if typeof(basePosition) ~= "Vector3" then
		return nil
	end

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.IgnoreWater = true

	local filterInstances = {}
	if LocalPlayer.Character then
		table.insert(filterInstances, LocalPlayer.Character)
	end
	raycastParams.FilterDescendantsInstances = filterInstances

	local castOrigin = basePosition + Vector3.new(0, AUTO_WIN_GROUND_CAST_HEIGHT, 0)
	local castDirection = Vector3.new(0, -(AUTO_WIN_GROUND_CAST_HEIGHT + MAP_GROUND_CHECK_DEPTH), 0)
	local result = workspace:Raycast(castOrigin, castDirection, raycastParams)
	if not result then
		return nil
	end

	return result.Position + Vector3.new(0, math.max(2, heightOffset or 0), 0)
end

local function getSafeAutoWinTeleportCFrame(targetPosition, standoffDistance, heightOffset)
	if typeof(targetPosition) ~= "Vector3" then
		return nil
	end

	local localRoot = getLocalRootPart()
	local horizontalAway = Vector3.new(0, 0, -1)
	if localRoot then
		local delta = localRoot.Position - targetPosition
		horizontalAway = Vector3.new(delta.X, 0, delta.Z)
		if horizontalAway.Magnitude <= 0.001 then
			horizontalAway = Vector3.new(0, 0, -1)
		else
			horizontalAway = horizontalAway.Unit
		end
	end

	local sideVector = Vector3.new(-horizontalAway.Z, 0, horizontalAway.X)
	local distance = math.max(0, standoffDistance or 0)
	local candidates = {
		targetPosition + (horizontalAway * distance),
		targetPosition + (horizontalAway * math.max(3, distance * 0.5)),
		targetPosition + (sideVector * distance),
		targetPosition - (sideVector * distance),
		targetPosition,
	}

	for _, candidate in ipairs(candidates) do
		local grounded = getGroundSnappedPosition(candidate, heightOffset)
		if grounded then
			local lookAt = Vector3.new(targetPosition.X, grounded.Y, targetPosition.Z)
			return CFrame.lookAt(grounded, lookAt)
		end
	end

	return nil
end


local function tryMoveNearClaimStage(stage)
	if not stage or not stage.claimPosition then
		return false, "no-claim-pos", nil
	end

	local localRoot = getLocalRootPart()
	if not localRoot then
		return false, "no-root", nil
	end

	local claimDistance = (localRoot.Position - stage.claimPosition).Magnitude
	local claimAlreadyCloseEnoughDistance = 1.75
	if claimDistance <= claimAlreadyCloseEnoughDistance then
		return false, "already-close", claimDistance
	end

	if not tryAcquireMovementLock("win-claim", AUTO_WIN_MOVE_LOCK_HOLD) then
		return false, "lock-blocked:" .. tostring(movementLockOwner or "unknown"), claimDistance
	end

	local groundedClaimPosition = getGroundSnappedPosition(stage.claimPosition, AUTO_WIN_CLAIM_TP_HEIGHT)
	local teleportCFrame = groundedClaimPosition and CFrame.new(groundedClaimPosition)
	if not teleportCFrame then
		teleportCFrame = CFrame.new(stage.claimPosition + Vector3.new(0, AUTO_WIN_CLAIM_TP_HEIGHT, 0))
	end
	if not teleportCFrame then
		releaseMovementLock("win-claim")
		return false, "no-teleport-cframe", claimDistance
	end

	localRoot.CFrame = teleportCFrame
	return true, "teleported", claimDistance
end

local function tryClaimWinStage(stage)
	if not stage or not stage.stageNumber then
		return false, false, 0, getLocalWinsValue(), getLocalWinsValue(), "invalid-stage", nil, false, nil
	end

	local didClaimTeleport = false
	local claimMoveReason = "remote-only"
	local claimMoveDistance = nil
	if stage.claimPosition then
		didClaimTeleport, claimMoveReason, claimMoveDistance = tryMoveNearClaimStage(stage)
	end
	if didClaimTeleport then
		task.wait(0.12)
	end
	local winsBeforeClaim = getLocalWinsValue()
	local bestWinsAfterClaim = winsBeforeClaim
	local attempts = 0
	local lastInvokeOk = false
	local lastInvokeResult = nil

	for attempt = 1, AUTO_WIN_CLAIM_RETRY_BURST do
		attempts = attempt
		local invokeOk, result = pcall(function()
			return ClaimWinButtonRemote:InvokeServer(stage.stageNumber)
		end)
		lastInvokeOk = invokeOk
		lastInvokeResult = result

		task.wait(AUTO_WIN_CLAIM_WINS_CHECK_WAIT)
		local winsAfterAttempt = getLocalWinsValue()
		if winsAfterAttempt > bestWinsAfterClaim then
			bestWinsAfterClaim = winsAfterAttempt
		end

		local claimSucceeded = bestWinsAfterClaim > winsBeforeClaim

		if claimSucceeded then
			return true, didClaimTeleport, attempts, winsBeforeClaim, bestWinsAfterClaim, claimMoveReason, claimMoveDistance, lastInvokeOk, lastInvokeResult
		end

		if attempt < AUTO_WIN_CLAIM_RETRY_BURST then
			task.wait(0.15)
		end
	end

	return false, didClaimTeleport, attempts, winsBeforeClaim, bestWinsAfterClaim, claimMoveReason, claimMoveDistance, lastInvokeOk, lastInvokeResult
end

local function tryMoveNearPunchStage(stage)
	if not stage or not stage.punchPosition then
		return false
	end

	local localRoot = getLocalRootPart()
	if not localRoot then
		return false
	end

	if (localRoot.Position - stage.punchPosition).Magnitude < AUTO_WIN_PUNCH_TP_MIN_DISTANCE then
		return false
	end

	if not tryAcquireMovementLock("win-punch", AUTO_WIN_MOVE_LOCK_HOLD) then
		return false
	end

	local teleportCFrame = getSafeAutoWinTeleportCFrame(stage.punchPosition, AUTO_WIN_PUNCH_STANDOFF_DISTANCE, AUTO_WIN_PUNCH_TP_HEIGHT)
	if not teleportCFrame then
		releaseMovementLock("win-punch")
		return false
	end

	localRoot.CFrame = teleportCFrame
	return true
end

local function getAliveHumanoid(character)
	if not character then
		return nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		return humanoid
	end

	return nil
end

local function getFlatLookVector(rootPart)
	local look = rootPart.CFrame.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z)
	if flatLook.Magnitude <= 0.001 then
		return Vector3.new(0, 0, -1)
	end

	return flatLook.Unit
end

local function getBehindHitPosition(character)
	if not character then
		return nil
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return nil
	end

 	local flatLook = getFlatLookVector(rootPart)

	return rootPart.Position - (flatLook * BEHIND_DISTANCE)
end

local function getDirectHitPosition(character)
	if not character then
		return nil
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return nil
	end

	return rootPart.Position
end

local function getBehindTargetCFrame(localRoot, character)
	if not localRoot or not character then
		return nil
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return nil
	end

	local flatLook = getFlatLookVector(rootPart)
	local targetPos = rootPart.Position
	local desiredBehindPos = targetPos - (flatLook * BEHIND_DISTANCE)
	local lockedY = localRoot.Position.Y + TELEPORT_UP_OFFSET
	local finalPos = Vector3.new(desiredBehindPos.X, lockedY, desiredBehindPos.Z)

	local currentFlat = Vector3.new(localRoot.Position.X, 0, localRoot.Position.Z)
	local desiredFlat = Vector3.new(finalPos.X, 0, finalPos.Z)
	if (currentFlat - desiredFlat).Magnitude < TELEPORT_MIN_MOVE then
		return nil
	end

	local lookAtPos = Vector3.new(targetPos.X, lockedY, targetPos.Z)
	return CFrame.lookAt(finalPos, lookAtPos)
end

local function isTargetOutOfMap(targetPlayer, targetCharacter)
	if not targetPlayer then
		return true, "missing player"
	end

	if isPlayerInAfkZone(targetPlayer) then
		return true, "afk zone (CurrentMap)"
	end

	if not targetCharacter then
		return true, "missing character"
	end

	local targetRoot = targetCharacter:FindFirstChild("HumanoidRootPart")
	if not targetRoot then
		return true, "missing root"
	end

	local targetPos = targetRoot.Position

	if targetPos.Y <= (workspace.FallenPartsDestroyHeight + FALLEN_HEIGHT_MARGIN) then
		return true, "below map"
	end

	local localRoot = getLocalRootPart()
	if localRoot and (targetPos - localRoot.Position).Magnitude > MAX_TARGET_DISTANCE then
		return true, "too far"
	end

	return false, nil
end

local function isTruthyAttributeValue(value)
	local valueType = type(value)
	if valueType == "boolean" then
		return value
	end

	if valueType == "number" then
		return value > 0
	end

	if valueType == "string" then
		local lowered = string.lower(value)
		return lowered ~= "" and lowered ~= "false" and lowered ~= "0" and lowered ~= "none"
	end

	return false
end

local function isTargetSpawnShielded(targetPlayer, targetCharacter)
	if not targetPlayer or not targetCharacter then
		return false, nil
	end

	local attributeNames = {
		"ForceShield",
		"SpawnShield",
		"SpawnProtection",
		"HasSpawnShield",
		"InSpawnProtection",
		"SafeZone",
		"SafeZoneProtected",
		"Invincible",
		"IsProtected",
	}

	for _, attributeName in ipairs(attributeNames) do
		local playerValue = targetPlayer:GetAttribute(attributeName)
		if isTruthyAttributeValue(playerValue) then
			return true, string.lower(attributeName)
		end

		local characterValue = targetCharacter:GetAttribute(attributeName)
		if isTruthyAttributeValue(characterValue) then
			return true, string.lower(attributeName)
		end
	end

	return false, nil
end

local function getHttpRequestImpl()
	if syn and syn.request then
		return syn.request
	end

	if type(http_request) == "function" then
		return http_request
	end

	if type(request) == "function" then
		return request
	end

	if fluxus and fluxus.request then
		return fluxus.request
	end

	return nil
end

local function decodeJsonPayload(content)
	if type(content) ~= "string" or content == "" then
		return nil
	end

	local ok, decoded = pcall(function()
		return HttpService:JSONDecode(content)
	end)
	if ok then
		return decoded
	end

	return nil
end

local function urlEncode(value)
	local text = tostring(value or "")
	local ok, encoded = pcall(function()
		return HttpService:UrlEncode(text)
	end)
	if ok and type(encoded) == "string" then
		return encoded
	end

	return text
end

local function fetchJson(url)
	local requestImpl = getHttpRequestImpl()
	if requestImpl then
		local requestOk, response = pcall(function()
			return requestImpl({
				Url = url,
				Method = "GET",
			})
		end)
		if requestOk and type(response) == "table" then
			local statusCode = tonumber(response.StatusCode)
			local succeeded = response.Success ~= false and (not statusCode or (statusCode >= 200 and statusCode < 300))
			local body = response.Body or response.body
			if succeeded then
				local decoded = decodeJsonPayload(body)
				if decoded then
					return decoded
				end
			end
		end
	end

	local httpOk, body = pcall(function()
		return game:HttpGet(url)
	end)
	if httpOk then
		return decodeJsonPayload(body)
	end

	return nil
end

local function findBetterServer(currentPlayerCount)
	local cursor = nil
	local bestServer = nil
	local bestPopulation = math.max(0, currentPlayerCount or 0)

	for _ = 1, AUTO_HOP_PAGE_LIMIT do
		local url = string.format(
			"https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Desc&limit=100&excludeFullGames=true",
			game.PlaceId
		)
		if cursor and cursor ~= "" then
			url = url .. "&cursor=" .. urlEncode(cursor)
		end

		local payload = fetchJson(url)
		if type(payload) ~= "table" then
			return nil, "http unavailable"
		end

		for _, server in ipairs(payload.data or {}) do
			local serverId = server.id
			local playing = tonumber(server.playing) or 0
			local maxPlayers = tonumber(server.maxPlayers) or 0
			if serverId and serverId ~= game.JobId and playing > bestPopulation and playing < maxPlayers then
				bestPopulation = playing
				bestServer = {
					id = serverId,
					playing = playing,
					maxPlayers = maxPlayers,
				}
			end
		end

		if bestServer and bestPopulation >= AUTO_HOP_TARGET_SERVER_PLAYERS then
			break
		end

		cursor = payload.nextPageCursor
		if not cursor then
			break
		end
	end

	if bestServer then
		return bestServer, nil
	end

	return nil, "no busier server"
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "StrengthTrollUI"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

if syn and syn.protect_gui then
	syn.protect_gui(screenGui)
end

screenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
controller.gui = screenGui

local oldGui = LocalPlayer.PlayerGui:FindFirstChild("StrengthTrollUI")
if oldGui and oldGui ~= screenGui then
	oldGui:Destroy()
end

local FRAME_BG = Color3.fromRGB(7, 13, 24)
local FRAME_STROKE = Color3.fromRGB(103, 137, 187)
local CARD_BG = Color3.fromRGB(20, 30, 50)
local CARD_STROKE = Color3.fromRGB(105, 141, 196)
local STATUS_BG = Color3.fromRGB(6, 11, 20)
local TEXT_PRIMARY = Color3.fromRGB(245, 248, 255)
local TEXT_MUTED = Color3.fromRGB(184, 198, 223)
local SECTION_BG = Color3.fromRGB(8, 14, 24)

local frame = Instance.new("Frame")
frame.Name = "Main"
frame.Size = UDim2.new(0, 356, 0, 676)
frame.Position = UDim2.new(0, 20, 0.5, -338)
frame.BackgroundColor3 = FRAME_BG
frame.BorderSizePixel = 0
frame.Parent = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 12)
corner.Parent = frame

local frameStroke = Instance.new("UIStroke")
frameStroke.Color = FRAME_STROKE
frameStroke.Thickness = 1.2
frameStroke.Transparency = 0.05
frameStroke.Parent = frame

local frameGradient = Instance.new("UIGradient")
frameGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(18, 31, 56)),
	ColorSequenceKeypoint.new(0.55, Color3.fromRGB(9, 17, 31)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(5, 10, 18)),
})
frameGradient.Rotation = 90
frameGradient.Parent = frame

local title = Instance.new("TextLabel")
title.Name = "Title"
title.Size = UDim2.new(1, -48, 0, 30)
title.Position = UDim2.new(0, 12, 0, 10)
title.BackgroundTransparency = 1
title.Text = "Strength Troll Obby"
title.TextColor3 = TEXT_PRIMARY
title.TextSize = 20
title.Font = Enum.Font.GothamBold
title.TextXAlignment = Enum.TextXAlignment.Left
title.Active = true
title.Parent = frame

local subtitle = Instance.new("TextLabel")
subtitle.Name = "Subtitle"
subtitle.Size = UDim2.new(1, -24, 0, 16)
subtitle.Position = UDim2.new(0, 12, 0, 38)
subtitle.BackgroundTransparency = 1
subtitle.Text = "Focused control for combat, progress, rewards | PawSHOP"
subtitle.TextColor3 = TEXT_MUTED
subtitle.TextSize = 11
subtitle.Font = Enum.Font.Gotham
subtitle.TextXAlignment = Enum.TextXAlignment.Left
subtitle.Parent = frame

local headerAccent = Instance.new("Frame")
headerAccent.Name = "HeaderAccent"
headerAccent.Size = UDim2.new(1, -24, 0, 3)
headerAccent.Position = UDim2.new(0, 12, 0, 60)
headerAccent.BackgroundColor3 = Color3.fromRGB(74, 163, 255)
headerAccent.BorderSizePixel = 0
headerAccent.Parent = frame

local headerAccentCorner = Instance.new("UICorner")
headerAccentCorner.CornerRadius = UDim.new(1, 0)
headerAccentCorner.Parent = headerAccent

local headerAccentGradient = Instance.new("UIGradient")
headerAccentGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(74, 163, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(86, 230, 192)),
})
headerAccentGradient.Parent = headerAccent

local closeButton = Instance.new("TextButton")
closeButton.Name = "CloseButton"
closeButton.Size = UDim2.new(0, 28, 0, 28)
closeButton.Position = UDim2.new(1, -40, 0, 10)
closeButton.BackgroundColor3 = Color3.fromRGB(110, 34, 34)
closeButton.TextColor3 = TEXT_PRIMARY
closeButton.Text = "X"
closeButton.TextSize = 14
closeButton.Font = Enum.Font.GothamBold
closeButton.Parent = frame

local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UDim.new(0, 8)
closeCorner.Parent = closeButton

local closeStroke = Instance.new("UIStroke")
closeStroke.Color = Color3.fromRGB(237, 118, 118)
closeStroke.Thickness = 1
closeStroke.Transparency = 0.02
closeStroke.Parent = closeButton

local openButton = Instance.new("TextButton")
openButton.Name = "OpenButton"
openButton.Size = UDim2.new(0, 146, 0, 42)
openButton.Position = UDim2.new(0, 20, 0.5, -17)
openButton.BackgroundColor3 = Color3.fromRGB(19, 36, 63)
openButton.TextColor3 = TEXT_PRIMARY
openButton.Text = "Open Control"
openButton.TextSize = 14
openButton.Font = Enum.Font.GothamSemibold
openButton.Visible = false
openButton.Parent = screenGui

local openCorner = Instance.new("UICorner")
openCorner.CornerRadius = UDim.new(0, 10)
openCorner.Parent = openButton

local openStroke = Instance.new("UIStroke")
openStroke.Color = CARD_STROKE
openStroke.Thickness = 1.1
openStroke.Transparency = 0.02
openStroke.Parent = openButton

local controlsScroll = Instance.new("ScrollingFrame")
controlsScroll.Name = "ControlsScroll"
controlsScroll.Size = UDim2.new(1, -24, 0, 326)
controlsScroll.Position = UDim2.new(0, 12, 0, 78)
controlsScroll.BackgroundTransparency = 1
controlsScroll.BorderSizePixel = 0
controlsScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
controlsScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
controlsScroll.ScrollBarThickness = 4
controlsScroll.ScrollBarImageColor3 = Color3.fromRGB(118, 173, 242)
controlsScroll.ScrollingDirection = Enum.ScrollingDirection.Y
controlsScroll.Parent = frame

local controlsLayout = Instance.new("UIListLayout")
controlsLayout.Padding = UDim.new(0, 10)
controlsLayout.FillDirection = Enum.FillDirection.Vertical
controlsLayout.SortOrder = Enum.SortOrder.LayoutOrder
controlsLayout.Parent = controlsScroll

local controlsPadding = Instance.new("UIPadding")
controlsPadding.PaddingRight = UDim.new(0, 2)
controlsPadding.Parent = controlsScroll

local function createSectionCard(name, sectionTitle, sectionSubtitle, accentColor, layoutOrder)
	local card = Instance.new("Frame")
	card.Name = name
	card.LayoutOrder = layoutOrder or 0
	card.Size = UDim2.new(1, -4, 0, 0)
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.BackgroundColor3 = SECTION_BG
	card.BorderSizePixel = 0
	card.Parent = controlsScroll

	local cardCorner = Instance.new("UICorner")
	cardCorner.CornerRadius = UDim.new(0, 12)
	cardCorner.Parent = card

	local cardStroke = Instance.new("UIStroke")
	cardStroke.Color = CARD_STROKE
	cardStroke.Thickness = 1.1
	cardStroke.Transparency = 0.04
	cardStroke.Parent = card

	local cardGradient = Instance.new("UIGradient")
	cardGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(17, 28, 48)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(6, 12, 21)),
	})
	cardGradient.Rotation = 90
	cardGradient.Parent = card

	local accent = Instance.new("Frame")
	accent.Name = "Accent"
	accent.Size = UDim2.new(0, 4, 0, 44)
	accent.Position = UDim2.new(0, 10, 0, 10)
	accent.BackgroundColor3 = accentColor
	accent.BorderSizePixel = 0
	accent.Parent = card

	local accentCorner = Instance.new("UICorner")
	accentCorner.CornerRadius = UDim.new(1, 0)
	accentCorner.Parent = accent

	local header = Instance.new("TextLabel")
	header.Name = "Header"
	header.Size = UDim2.new(1, -38, 0, 20)
	header.Position = UDim2.new(0, 24, 0, 9)
	header.BackgroundTransparency = 1
	header.Text = sectionTitle
	header.TextColor3 = TEXT_PRIMARY
	header.TextSize = 15
	header.Font = Enum.Font.GothamBold
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.Parent = card

	local subheader = Instance.new("TextLabel")
	subheader.Name = "Subheader"
	subheader.Size = UDim2.new(1, -38, 0, 14)
	subheader.Position = UDim2.new(0, 24, 0, 29)
	subheader.BackgroundTransparency = 1
	subheader.Text = sectionSubtitle
	subheader.TextColor3 = TEXT_MUTED
	subheader.TextSize = 10
	subheader.Font = Enum.Font.Gotham
	subheader.TextXAlignment = Enum.TextXAlignment.Left
	subheader.Parent = card

	local body = Instance.new("Frame")
	body.Name = "Body"
	body.Size = UDim2.new(1, -20, 0, 0)
	body.Position = UDim2.new(0, 10, 0, 56)
	body.BackgroundTransparency = 1
	body.AutomaticSize = Enum.AutomaticSize.Y
	body.Parent = card

	local bodyLayout = Instance.new("UIListLayout")
	bodyLayout.Padding = UDim.new(0, 8)
	bodyLayout.FillDirection = Enum.FillDirection.Vertical
	bodyLayout.SortOrder = Enum.SortOrder.LayoutOrder
	bodyLayout.Parent = body

	local bodyPadding = Instance.new("UIPadding")
	bodyPadding.PaddingBottom = UDim.new(0, 10)
	bodyPadding.Parent = body

	return card, body
end

local function styleToggleButton(button, accentColor)
	button.Size = UDim2.new(1, 0, 0, 38)
	button.Position = UDim2.new(0, 0, 0, 0)
	button.AutoButtonColor = true
	button.BackgroundColor3 = CARD_BG
	button.BorderSizePixel = 0
	button.TextColor3 = Color3.fromRGB(248, 251, 255)
	button.TextSize = 14
	button.Font = Enum.Font.GothamSemibold

	local buttonCorner = Instance.new("UICorner")
	buttonCorner.CornerRadius = UDim.new(0, 10)
	buttonCorner.Parent = button

	local buttonStroke = Instance.new("UIStroke")
	buttonStroke.Color = accentColor or CARD_STROKE
	buttonStroke.Thickness = 1.15
	buttonStroke.Transparency = 0.04
	buttonStroke.Parent = button

	return buttonStroke
end

local function createInfoPill(text, bgColor, textColor, parent, layoutOrder)
	local pill = Instance.new("TextLabel")
	pill.Name = string.gsub(text, "%s+", "") .. "Pill"
	pill.LayoutOrder = layoutOrder or 0
	pill.Size = UDim2.new(0, 0, 0, 26)
	pill.AutomaticSize = Enum.AutomaticSize.X
	pill.BackgroundColor3 = bgColor
	pill.BorderSizePixel = 0
	pill.Text = "  " .. text .. "  "
	pill.TextColor3 = textColor
	pill.TextSize = 10
	pill.Font = Enum.Font.GothamBold
	pill.Parent = parent

	local pillCorner = Instance.new("UICorner")
	pillCorner.CornerRadius = UDim.new(1, 0)
	pillCorner.Parent = pill

	local pillStroke = Instance.new("UIStroke")
	pillStroke.Color = textColor
	pillStroke.Thickness = 1
	pillStroke.Transparency = 0.3
	pillStroke.Parent = pill

	return pill
end

local combatSection, combatSectionBody = createSectionCard(
	"CombatSection",
	"Combat",
	"Training, player hunting, and lane clearing",
	Color3.fromRGB(255, 126, 112),
	1
)
local progressionSection, progressionSectionBody = createSectionCard(
	"ProgressSection",
	"Progress",
	"Rebirth, strength loadout, and weight upgrades",
	Color3.fromRGB(90, 185, 255),
	2
)
local utilitySection, utilitySectionBody = createSectionCard(
	"UtilitySection",
	"Rewards & Utility",
	"Claim loops, anti-AFK, and saved preferences",
	Color3.fromRGB(120, 225, 182),
	3
)

local autoTrainButton = Instance.new("TextButton")
autoTrainButton.Name = "AutoTrainToggle"
autoTrainButton.Text = "Auto Train: OFF"
autoTrainButton.Parent = progressionSectionBody
styleToggleButton(autoTrainButton, Color3.fromRGB(91, 190, 142))

local autoKillButton = Instance.new("TextButton")
autoKillButton.Name = "AutoKillToggle"
autoKillButton.Text = "Auto Kill: OFF"
autoKillButton.Parent = combatSectionBody
styleToggleButton(autoKillButton, Color3.fromRGB(214, 103, 103))

local autoHopButton = Instance.new("TextButton")
autoHopButton.Name = "AutoServerHopToggle"
autoHopButton.Text = "Auto Hop: LOCKED"
autoHopButton.Parent = combatSectionBody
styleToggleButton(autoHopButton, Color3.fromRGB(214, 171, 93))

local autoWinButton = Instance.new("TextButton")
autoWinButton.Name = "AutoWinToggle"
autoWinButton.Text = "Auto Win: OFF"
autoWinButton.Parent = progressionSectionBody
styleToggleButton(autoWinButton, Color3.fromRGB(243, 184, 82))

local autoRebirthButton = Instance.new("TextButton")
autoRebirthButton.Name = "AutoRebirthToggle"
autoRebirthButton.Text = "Auto Rebirth: OFF"
autoRebirthButton.Parent = progressionSectionBody
styleToggleButton(autoRebirthButton, Color3.fromRGB(105, 150, 233))

local autoEquipStrengthButton = Instance.new("TextButton")
autoEquipStrengthButton.Name = "AutoEquipStrengthToggle"
autoEquipStrengthButton.Text = "Auto Equip STR: OFF"
autoEquipStrengthButton.Parent = progressionSectionBody
styleToggleButton(autoEquipStrengthButton, Color3.fromRGB(112, 164, 237))

local autoBuyWeightButton = Instance.new("TextButton")
autoBuyWeightButton.Name = "AutoBuyWeightToggle"
autoBuyWeightButton.Text = "Auto Buy Weight: OFF"
autoBuyWeightButton.Parent = progressionSectionBody
styleToggleButton(autoBuyWeightButton, Color3.fromRGB(84, 201, 177))

local autoPlaytimeButton = Instance.new("TextButton")
autoPlaytimeButton.Name = "AutoPlaytimeToggle"
autoPlaytimeButton.Text = "Auto Playtime: OFF"
autoPlaytimeButton.Parent = utilitySectionBody
styleToggleButton(autoPlaytimeButton, Color3.fromRGB(143, 167, 219))

local utilityMetaRow = Instance.new("Frame")
utilityMetaRow.Name = "UtilityMetaRow"
utilityMetaRow.Size = UDim2.new(1, 0, 0, 28)
utilityMetaRow.BackgroundTransparency = 1
utilityMetaRow.Parent = utilitySectionBody

local utilityMetaLayout = Instance.new("UIListLayout")
utilityMetaLayout.FillDirection = Enum.FillDirection.Horizontal
utilityMetaLayout.Padding = UDim.new(0, 8)
utilityMetaLayout.SortOrder = Enum.SortOrder.LayoutOrder
utilityMetaLayout.Parent = utilityMetaRow

createInfoPill("ANTI AFK ON", Color3.fromRGB(28, 54, 52), Color3.fromRGB(146, 236, 214), utilityMetaRow, 1)
createInfoPill("TOGGLES SAVE", Color3.fromRGB(24, 47, 78), Color3.fromRGB(184, 220, 255), utilityMetaRow, 2)
createInfoPill("PawSHOP", Color3.fromRGB(61, 40, 20), Color3.fromRGB(255, 215, 154), utilityMetaRow, 3)

local utilityHint = Instance.new("TextLabel")
utilityHint.Name = "UtilityHint"
utilityHint.Size = UDim2.new(1, 0, 0, 32)
utilityHint.BackgroundTransparency = 1
utilityHint.Text = "Auto Hop checks server population and only runs while Auto Kill is active."
utilityHint.TextColor3 = TEXT_MUTED
utilityHint.TextSize = 11
utilityHint.TextWrapped = true
utilityHint.Font = Enum.Font.Gotham
utilityHint.TextXAlignment = Enum.TextXAlignment.Left
utilityHint.TextYAlignment = Enum.TextYAlignment.Top
utilityHint.Parent = utilitySectionBody

local statusPanel = Instance.new("Frame")
statusPanel.Name = "StatusPanel"
statusPanel.Size = UDim2.new(1, -24, 0, 232)
statusPanel.Position = UDim2.new(0, 12, 1, -244)
statusPanel.BackgroundColor3 = STATUS_BG
statusPanel.BorderSizePixel = 0
statusPanel.Parent = frame

local statusCorner = Instance.new("UICorner")
statusCorner.CornerRadius = UDim.new(0, 10)
statusCorner.Parent = statusPanel

local statusStroke = Instance.new("UIStroke")
statusStroke.Color = CARD_STROKE
statusStroke.Thickness = 1.1
statusStroke.Transparency = 0.03
statusStroke.Parent = statusPanel

local statusGradient = Instance.new("UIGradient")
statusGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(12, 21, 35)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(4, 9, 17)),
})
statusGradient.Rotation = 90
statusGradient.Parent = statusPanel

local statusTitle = Instance.new("TextLabel")
statusTitle.Name = "StatusTitle"
statusTitle.Size = UDim2.new(1, -16, 0, 16)
statusTitle.Position = UDim2.new(0, 8, 0, 6)
statusTitle.BackgroundTransparency = 1
statusTitle.Text = "LIVE STATUS"
statusTitle.TextColor3 = TEXT_MUTED
statusTitle.TextSize = 10
statusTitle.Font = Enum.Font.GothamMedium
statusTitle.TextXAlignment = Enum.TextXAlignment.Left
statusTitle.Parent = statusPanel

local statusMetaLabel = Instance.new("TextLabel")
statusMetaLabel.Name = "StatusMeta"
statusMetaLabel.Size = UDim2.new(0, 72, 0, 20)
statusMetaLabel.Position = UDim2.new(1, -80, 0, 6)
statusMetaLabel.BackgroundColor3 = Color3.fromRGB(28, 52, 83)
statusMetaLabel.TextColor3 = Color3.fromRGB(214, 234, 255)
statusMetaLabel.Text = "IDLE"
statusMetaLabel.TextSize = 10
statusMetaLabel.Font = Enum.Font.GothamBold
statusMetaLabel.Parent = statusPanel

local statusMetaCorner = Instance.new("UICorner")
statusMetaCorner.CornerRadius = UDim.new(1, 0)
statusMetaCorner.Parent = statusMetaLabel

local statusMetaStroke = Instance.new("UIStroke")
statusMetaStroke.Color = Color3.fromRGB(111, 164, 228)
statusMetaStroke.Thickness = 1
statusMetaStroke.Transparency = 0.05
statusMetaStroke.Parent = statusMetaLabel

local statusScroll = Instance.new("ScrollingFrame")
statusScroll.Name = "StatusScroll"
statusScroll.Size = UDim2.new(1, -16, 1, -40)
statusScroll.Position = UDim2.new(0, 8, 0, 28)
statusScroll.BackgroundTransparency = 1
statusScroll.BorderSizePixel = 0
statusScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
statusScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
statusScroll.ScrollBarThickness = 4
statusScroll.ScrollBarImageColor3 = Color3.fromRGB(118, 173, 242)
statusScroll.ScrollingDirection = Enum.ScrollingDirection.Y
statusScroll.Parent = statusPanel

local targetLabel = Instance.new("TextLabel")
targetLabel.Name = "TargetLabel"
targetLabel.Size = UDim2.new(1, -6, 0, 0)
targetLabel.Position = UDim2.new(0, 0, 0, 0)
targetLabel.BackgroundTransparency = 1
targetLabel.Text = ""
targetLabel.TextColor3 = TEXT_PRIMARY
targetLabel.TextSize = 12
targetLabel.Font = Enum.Font.GothamMedium
targetLabel.TextXAlignment = Enum.TextXAlignment.Left
targetLabel.TextYAlignment = Enum.TextYAlignment.Top
targetLabel.TextWrapped = true
targetLabel.RichText = true
targetLabel.AutomaticSize = Enum.AutomaticSize.Y
targetLabel.Parent = statusScroll

local statusLines = {
	train = "",
	kill = "",
	hop = "",
	rebirth = "",
	win = "",
	equip = "",
	weightcur = "",
	weight = "",
	playtime = "",
}

local function escapeRichText(text)
	text = string.gsub(text, "&", "&amp;")
	text = string.gsub(text, "<", "&lt;")
	text = string.gsub(text, ">", "&gt;")
	return text
end

local function getStatusLabelColor(key)
	local colors = {
		win = "#F7B84B",
		kill = "#FF8A7A",
		hop = "#F1C36A",
		equip = "#8BC3FF",
		weightcur = "#79E2C0",
		weight = "#79E2C0",
		playtime = "#C0C7D6",
		rebirth = "#7DB3FF",
		train = "#8EE4A1",
	}
	return colors[key] or "#F1F5FC"
end

local function formatStatusDisplayLine(key, line)
	local prefix, rest = string.match(line, "^(.-):%s*(.*)$")
	if prefix and rest then
		return string.format('<font color="%s">%s</font>  %s', getStatusLabelColor(key), escapeRichText(prefix), escapeRichText(rest))
	end

	return string.format('<font color="%s">%s</font>', getStatusLabelColor(key), escapeRichText(line))
end

local function refreshStatusLabel()
	local visibleLines = {}
	local statusOrder = { "train", "kill", "hop", "rebirth", "win", "equip", "weightcur", "weight", "playtime" }

	for _, key in ipairs(statusOrder) do
		local line = statusLines[key]
		if type(line) == "string" and line ~= "" then
			table.insert(visibleLines, formatStatusDisplayLine(key, line))
		end
	end

	if #visibleLines == 0 then
		targetLabel.Text = '<font color="#98A7C1">No active modules</font>'
		statusMetaLabel.Text = "IDLE"
		statusMetaLabel.BackgroundColor3 = Color3.fromRGB(28, 52, 83)
	else
		targetLabel.Text = table.concat(visibleLines, "\n")
		statusMetaLabel.Text = string.format("%d ACTIVE", #visibleLines)
		statusMetaLabel.BackgroundColor3 = Color3.fromRGB(24, 92, 80)
	end
end

local function setStatusLine(key, value)
	if statusLines[key] == value then
		return
	end
	statusLines[key] = value
	refreshStatusLabel()
end

local refreshButtonStates

local function setToggleState(toggleName, enabled)
	if toggleName == "autoServerHopEnabled" and enabled and not autoKillEnabled then
		setStatusLine("hop", "Hop: enable Auto Kill first")
		refreshStatusLabel()
		return false
	end

	if toggleName == "autoTrainEnabled" then
		autoTrainEnabled = enabled
	elseif toggleName == "autoKillEnabled" then
		autoKillEnabled = enabled
	elseif toggleName == "autoRebirthEnabled" then
		autoRebirthEnabled = enabled
	elseif toggleName == "autoWinEnabled" then
		autoWinEnabled = enabled
	elseif toggleName == "autoEquipBestStrengthEnabled" then
		autoEquipBestStrengthEnabled = enabled
	elseif toggleName == "autoBuyBestWeightEnabled" then
		autoBuyBestWeightEnabled = enabled
	elseif toggleName == "autoClaimPlaytimeEnabled" then
		autoClaimPlaytimeEnabled = enabled
	elseif toggleName == "autoServerHopEnabled" then
		autoServerHopEnabled = enabled
	else
		return false
	end

	saveCurrentToggleSettings()
	refreshButtonStates()
	return true
end

function refreshButtonStates()
	autoTrainButton.Text = autoTrainEnabled and "Auto Train: ON" or "Auto Train: OFF"
	autoTrainButton.BackgroundColor3 = autoTrainEnabled and Color3.fromRGB(23, 121, 92) or Color3.fromRGB(22, 35, 55)

	autoKillButton.Text = autoKillEnabled and "Auto Kill: ON" or "Auto Kill: OFF"
	autoKillButton.BackgroundColor3 = autoKillEnabled and Color3.fromRGB(150, 53, 53) or Color3.fromRGB(22, 35, 55)

	if autoServerHopEnabled then
		autoHopButton.Text = autoKillEnabled and "Auto Hop: ON" or "Auto Hop: STANDBY"
		autoHopButton.BackgroundColor3 = autoKillEnabled and Color3.fromRGB(143, 102, 28) or Color3.fromRGB(67, 78, 99)
	else
		autoHopButton.Text = autoKillEnabled and "Auto Hop: OFF" or "Auto Hop: LOCKED"
		autoHopButton.BackgroundColor3 = autoKillEnabled and Color3.fromRGB(22, 35, 55) or Color3.fromRGB(17, 24, 37)
	end
	autoHopButton.AutoButtonColor = autoKillEnabled or autoServerHopEnabled

	autoRebirthButton.Text = autoRebirthEnabled and "Auto Rebirth: ON" or "Auto Rebirth: OFF"
	autoRebirthButton.BackgroundColor3 = autoRebirthEnabled and Color3.fromRGB(36, 91, 173) or Color3.fromRGB(22, 35, 55)

	autoWinButton.Text = autoWinEnabled and "Auto Win: ON" or "Auto Win: OFF"
	autoWinButton.BackgroundColor3 = autoWinEnabled and Color3.fromRGB(177, 124, 34) or Color3.fromRGB(22, 35, 55)

	autoEquipStrengthButton.Text = autoEquipBestStrengthEnabled and "Auto Equip STR: ON" or "Auto Equip STR: OFF"
	autoEquipStrengthButton.BackgroundColor3 = autoEquipBestStrengthEnabled and Color3.fromRGB(66, 108, 179) or Color3.fromRGB(22, 35, 55)

	autoBuyWeightButton.Text = autoBuyBestWeightEnabled and "Auto Buy Weight: ON" or "Auto Buy Weight: OFF"
	autoBuyWeightButton.BackgroundColor3 = autoBuyBestWeightEnabled and Color3.fromRGB(27, 128, 111) or Color3.fromRGB(22, 35, 55)

	autoPlaytimeButton.Text = autoClaimPlaytimeEnabled and "Auto Playtime: ON" or "Auto Playtime: OFF"
	autoPlaytimeButton.BackgroundColor3 = autoClaimPlaytimeEnabled and Color3.fromRGB(67, 98, 156) or Color3.fromRGB(22, 35, 55)

	setStatusLine("train", "")
	setStatusLine("rebirth", "")

	if not autoKillEnabled then
		setStatusLine("kill", "")
	end

	if not autoServerHopEnabled then
		setStatusLine("hop", "")
	elseif not autoKillEnabled then
		setStatusLine("hop", "Hop: standby (Auto Kill OFF)")
	end

	if not autoWinEnabled then
		setStatusLine("win", "")
	end

	if not autoEquipBestStrengthEnabled then
		setStatusLine("equip", "")
	end

	if not autoBuyBestWeightEnabled then
		setStatusLine("weight", "")
	end

	if not autoClaimPlaytimeEnabled then
		setStatusLine("playtime", "")
	end
end

bindConnection(autoTrainButton.MouseButton1Click:Connect(function()
	setToggleState("autoTrainEnabled", not autoTrainEnabled)
end))

bindConnection(autoKillButton.MouseButton1Click:Connect(function()
	setToggleState("autoKillEnabled", not autoKillEnabled)
end))

bindConnection(autoHopButton.MouseButton1Click:Connect(function()
	if not autoKillEnabled and not autoServerHopEnabled then
		setStatusLine("hop", "Hop: enable Auto Kill first")
		refreshStatusLabel()
		return
	end

	setToggleState("autoServerHopEnabled", not autoServerHopEnabled)
end))

bindConnection(autoRebirthButton.MouseButton1Click:Connect(function()
	setToggleState("autoRebirthEnabled", not autoRebirthEnabled)
end))

bindConnection(autoWinButton.MouseButton1Click:Connect(function()
	setToggleState("autoWinEnabled", not autoWinEnabled)
end))

bindConnection(autoEquipStrengthButton.MouseButton1Click:Connect(function()
	setToggleState("autoEquipBestStrengthEnabled", not autoEquipBestStrengthEnabled)
end))

bindConnection(autoBuyWeightButton.MouseButton1Click:Connect(function()
	setToggleState("autoBuyBestWeightEnabled", not autoBuyBestWeightEnabled)
end))

bindConnection(autoPlaytimeButton.MouseButton1Click:Connect(function()
	setToggleState("autoClaimPlaytimeEnabled", not autoClaimPlaytimeEnabled)
end))

bindConnection(closeButton.MouseButton1Click:Connect(function()
	frame.Visible = false
	openButton.Visible = true
end))

bindConnection(openButton.MouseButton1Click:Connect(function()
	frame.Visible = true
	openButton.Visible = false
end))

do
	local dragging = false
	local dragInput = nil
	local dragStart = nil
	local startPos = nil

	local function updateDrag(input)
		local delta = input.Position - dragStart
		frame.Position = UDim2.new(
			startPos.X.Scale,
			startPos.X.Offset + delta.X,
			startPos.Y.Scale,
			startPos.Y.Offset + delta.Y
		)
	end

	bindConnection(title.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = frame.Position
			bindConnection(input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
				end
			end))
		end
	end))

	bindConnection(title.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			dragInput = input
		end
	end))

	bindConnection(UserInputService.InputChanged:Connect(function(input)
		if dragging and input == dragInput then
			updateDrag(input)
		end
	end))
end

refreshButtonStates()
refreshStatusLabel()

task.spawn(function()
	while controller.running do
		local equippedWeight = getEquippedWeight()
		local bestOwnedWeight = getBestOwnedWeightByMultiplier()
		local currentWeightForUpgrade = equippedWeight or bestOwnedWeight
		local nextUpgradeWeight = getNextLockedWeightUpgrade(currentWeightForUpgrade)
		if not autoBuyBestWeightEnabled then
			if currentWeightForUpgrade then
				setStatusLine("weightcur", string.format("Current Weight: x %d", currentWeightForUpgrade.multiplier or 0))
			else
				setStatusLine("weightcur", "Current Weight: -")
			end
		else
			if currentWeightForUpgrade and nextUpgradeWeight then
				setStatusLine("weightcur", string.format("Current Weight: x %d | next %d gem x %d", currentWeightForUpgrade.multiplier or 0, nextUpgradeWeight.price or 0, nextUpgradeWeight.multiplier or 0))
			elseif currentWeightForUpgrade then
				setStatusLine("weightcur", string.format("Current Weight: x %d", currentWeightForUpgrade.multiplier or 0))
			elseif nextUpgradeWeight then
				setStatusLine("weightcur", string.format("Current Weight: - | next %d gem x %d", nextUpgradeWeight.price or 0, nextUpgradeWeight.multiplier or 0))
			else
				setStatusLine("weightcur", "Current Weight: - | next - gem x -")
			end
		end
		task.wait(0.35)
	end
end)

task.spawn(function()
	while controller.running do
		if autoTrainEnabled then
			LiftWeightRemote:FireServer()
		end
		task.wait(AUTO_TRAIN_LOOP_DELAY)
	end
end)

task.spawn(function()
	while controller.running do
		if autoRebirthEnabled then
			RebirthRemote:FireServer()
			task.wait(AUTO_REBIRTH_COOLDOWN)
		else
			task.wait(0.5)
		end
	end
end)

task.spawn(function()
	while controller.running do
		if autoEquipBestStrengthEnabled then
			local localWins = getLocalWinsValue()
			local bestButton = getBestEligibleStrengthButton(localWins)
			local equippedButton = getEquippedStrengthButton()
			local nextButton = getNextStrengthButtonInfo(localWins)
			local currentStrengthText = bestButton and string.format("+%s STR", formatShorthandNumber(bestButton.strengthAmount)) or nil
			local nextStrengthText = nextButton and string.format("+%s STR need %s wins", formatShorthandNumber(nextButton.strengthAmount), formatShorthandNumber(nextButton.requirement)) or nil
			if bestButton then
				if equippedButton and equippedButton.requirement == bestButton.requirement then
					if nextStrengthText then
						setStatusLine("equip", string.format("Equip STR: using %s | next %s", currentStrengthText or (formatShorthandNumber(bestButton.requirement) .. " wins"), nextStrengthText))
					else
						setStatusLine("equip", string.format("Equip STR: using %s", currentStrengthText or (formatShorthandNumber(bestButton.requirement) .. " wins")))
					end
				else
					local ok, touched = pcall(function()
						return touchStrengthButton(bestButton.buttonPart)
					end)
					if ok and touched then
						if equippedButton then
							setStatusLine("equip", string.format("Equip STR: switch %s -> %s", string.format("+%s STR", formatShorthandNumber(equippedButton.strengthAmount)), currentStrengthText or string.format("%s wins", formatShorthandNumber(bestButton.requirement))))
						else
							setStatusLine("equip", string.format("Equip STR: trying %s", currentStrengthText or string.format("%s wins", formatShorthandNumber(bestButton.requirement))))
						end
					else
						setStatusLine("equip", string.format("Equip STR: failed %s", currentStrengthText or string.format("%s wins", formatShorthandNumber(bestButton.requirement))))
					end
				end
			else
				if nextButton then
					setStatusLine("equip", string.format("Equip STR: next %s | require %s wins", string.format("+%s STR", formatShorthandNumber(nextButton.strengthAmount)), formatShorthandNumber(nextButton.requirement)))
				else
					setStatusLine("equip", "Equip STR: no strength pads")
				end
			end

			task.wait(AUTO_EQUIP_STRENGTH_DELAY)
		else
			task.wait(0.15)
		end
	end
end)

task.spawn(function()
	local lastWeightActionAt = 0

	while controller.running do
		if autoBuyBestWeightEnabled then
			local now = os.clock()
			local gems = getLocalGemsValue()
			local bestOwnedWeight = getBestOwnedWeightByMultiplier()
			local equippedWeight = getEquippedWeight()
			local currentWeightForUpgrade = equippedWeight or bestOwnedWeight
			local nextUpgradeWeight = getNextLockedWeightUpgrade(currentWeightForUpgrade)
			local nextAffordablePrice = getNextWeightPrice(gems)

			if bestOwnedWeight or currentWeightForUpgrade or nextUpgradeWeight then
				if bestOwnedWeight and equippedWeight and equippedWeight.shopKey == bestOwnedWeight.shopKey and not nextUpgradeWeight then
					setStatusLine("weight", "Weight: max upgrade reached")
				else
					if now - lastWeightActionAt >= AUTO_BUY_WEIGHT_ACTION_COOLDOWN then
						local bought = false
						if nextUpgradeWeight and gems >= nextUpgradeWeight.price then
							bought = buyWeightItem(nextUpgradeWeight)
							if bought then
								setStatusLine("weight", string.format("Weight: bought x%d", nextUpgradeWeight.multiplier or 0))
							else
								setStatusLine("weight", string.format("Weight: buy failed x%d", nextUpgradeWeight.multiplier or 0))
							end
						end

						bestOwnedWeight = getBestOwnedWeightByMultiplier()
						equippedWeight = getEquippedWeight()

						local equippedBestOwned = bestOwnedWeight and equippedWeight and equippedWeight.shopKey == bestOwnedWeight.shopKey
						if bestOwnedWeight and not equippedBestOwned then
							local equipOk = equipWeightItem(bestOwnedWeight)
							if equipOk then
								setStatusLine("weight", string.format("Weight: equipped x%d", bestOwnedWeight.multiplier or 0))
							else
								setStatusLine("weight", string.format("Weight: equip failed x%d", bestOwnedWeight.multiplier or 0))
							end
						end

						if bought or (bestOwnedWeight and not equippedBestOwned) then
							lastWeightActionAt = os.clock()
						elseif nextUpgradeWeight and gems < nextUpgradeWeight.price then
							setStatusLine("weight", string.format("Weight: need more %s gems to get next weight", formatShorthandNumber(math.max(0, nextUpgradeWeight.price - gems))))
						else
							setStatusLine("weight", "Weight: scanning upgrades")
						end
					else
						setStatusLine("weight", string.format("Weight: cooldown %.1fs", math.max(0, AUTO_BUY_WEIGHT_ACTION_COOLDOWN - (now - lastWeightActionAt))))
					end
				end
			else
				if nextAffordablePrice then
					setStatusLine("weight", string.format("Weight: need more %s gems to get next weight", formatShorthandNumber(math.max(0, nextAffordablePrice - gems))))
				else
					setStatusLine("weight", "Weight: no items")
				end
			end

			task.wait(AUTO_BUY_WEIGHT_DELAY)
		else
			task.wait(0.15)
		end
	end
end)

task.spawn(function()
	local claimCooldownUntil = 0
	local lastAutoWinDebugAt = 0
	local stageProgressByStageNumber = {}
	local claimRetryStateByStageNumber = {}
	local lastPunchTeleportStageNumber = nil
	local lastSuccessfulClaimStageNumber = nil
	local lastSuccessfulClaimWinsValue = 0
	local lastClaimAttemptSummary = "last=none"
	local learnedClaimReadyDelay = math.max(AUTO_WIN_CLAIM_INITIAL_OBSERVED_WAIT, AUTO_WIN_CLAIM_MIN_READY_DELAY)

	local function getClaimRetryState(stageNumber)
		if not stageNumber then
			return nil
		end

		local state = claimRetryStateByStageNumber[stageNumber]
		if not state then
			state = {
				firstEligibleAt = nil,
				nextAttemptAt = 0,
				failCount = 0,
			}
			claimRetryStateByStageNumber[stageNumber] = state
		end

		return state
	end

	local function debugAutoWin(now, message)
		if not AUTO_WIN_DEBUG_ENABLED then
			return
		end
		if now - lastAutoWinDebugAt < AUTO_WIN_DEBUG_INTERVAL then
			return
		end
		lastAutoWinDebugAt = now
		warn("[AUTO_WIN] " .. tostring(message))
	end

	local function getClaimStatusSeconds(now)
		return math.max(0, claimCooldownUntil - now)
	end

	while controller.running do
		if autoWinEnabled then
			local localWins = getLocalWinsValue()
			local localStrength = getStrengthValue(LocalPlayer)
			local stages = getStrengthBarrierStages()
			local now = os.clock()

			if lastSuccessfulClaimStageNumber and localWins > lastSuccessfulClaimWinsValue then
				lastSuccessfulClaimStageNumber = nil
				lastSuccessfulClaimWinsValue = 0
			end

			local highestUnlockedIndex = getHighestUnlockedStageIndex(stages, localWins)
			if not highestUnlockedIndex then
				setStatusLine("win", "Win: No unlocked stage")
				debugAutoWin(now, string.format("wins=%d highest=nil stages=%d", localWins or 0, #stages))
			else
				local currentStage = stages[highestUnlockedIndex]
				local highestStage = currentStage
				local nextStage = stages[highestUnlockedIndex + 1]
				local pendingStage = nil
				local pendingAction = nil
				local pendingStageIndex = nil
				local nextStageForInfo = nil
				local nextStageStatusSuffix = ""
				local claimTargetStage = nil
				local claimedThisLoop = false
				local didPunchTeleport = false
				local estimatedBreakSeconds = nil
				local shouldDelayPunchForStrength = false
				local isActivelyPunchingPendingStage = false
				local isWaitingOnPendingStage = false
				local shouldSkipClaimForPendingPunch = false
				local maxBreakSeconds = AUTO_WIN_MAX_BREAK_MINUTES * 60
				local requiredStrengthForPendingStage = 0
				local shouldTeleportToPendingStage = false
				local canCheckNextStage = false
				local latestClaimableStage = nil
				local claimAttemptReadyAt = claimCooldownUntil

				pendingStage, pendingAction, pendingStageIndex = getFirstPendingUnlockedStage(stages, highestUnlockedIndex)
				latestClaimableStage = getLatestClaimableStage(stages, highestUnlockedIndex, pendingStageIndex)

				if nextStage then
					local nextRequirement = nextStage.requirement
					canCheckNextStage = nextRequirement and nextRequirement ~= math.huge and localWins >= nextRequirement or false
				end

				if pendingStage then
					nextStageForInfo = pendingStage
				else
					claimTargetStage = latestClaimableStage
					nextStageForInfo = nextStage or currentStage

					if not claimTargetStage and nextStage and canCheckNextStage and nextStage.destroyed then
						claimTargetStage = nextStage
					end
				end

				if pendingStage and pendingAction == "punch" then
					local observedDps = updateAutoWinObservedDps(stageProgressByStageNumber, pendingStage, now)
					estimatedBreakSeconds = estimateAutoWinBreakSeconds(pendingStage, localStrength, observedDps)
					requiredStrengthForPendingStage = getRequiredStrengthForAutoWinEta(pendingStage, maxBreakSeconds)
					shouldDelayPunchForStrength = shouldDelayAutoWinPunchForStrength(pendingStage, localStrength, estimatedBreakSeconds, maxBreakSeconds)
					if shouldDelayPunchForStrength and pendingStageIndex and pendingStageIndex > 1 then
						local waitClaimStage = stages[pendingStageIndex - 1]
						if waitClaimStage and waitClaimStage.stageNumber then
							claimTargetStage = waitClaimStage
						end
					end
					if pendingStage.punchPosition and not shouldDelayPunchForStrength then
						isActivelyPunchingPendingStage = true
						shouldTeleportToPendingStage = lastPunchTeleportStageNumber ~= pendingStage.stageNumber
					end
				end

				isWaitingOnPendingStage = pendingStage ~= nil and not isActivelyPunchingPendingStage
				shouldSkipClaimForPendingPunch = isActivelyPunchingPendingStage

				if isActivelyPunchingPendingStage then
					claimTargetStage = nil
				end

				if not isActivelyPunchingPendingStage then
					lastPunchTeleportStageNumber = nil
				end

				if isWaitingOnPendingStage and pendingStageIndex and pendingStageIndex > 1 then
					local waitingClaimStage = stages[pendingStageIndex - 1]
					if waitingClaimStage and waitingClaimStage.stageNumber then
						claimTargetStage = waitingClaimStage
					end
				end

				if not isActivelyPunchingPendingStage and not claimTargetStage and latestClaimableStage then
					claimTargetStage = latestClaimableStage
				elseif not isActivelyPunchingPendingStage and not claimTargetStage and pendingStageIndex and pendingStageIndex > 1 then
					local previousStage = stages[pendingStageIndex - 1]
					if previousStage and previousStage.stageNumber and previousStage.destroyed then
						claimTargetStage = previousStage
					end
				end

				if claimTargetStage
					and not isWaitingOnPendingStage
					and lastSuccessfulClaimStageNumber
					and claimTargetStage.stageNumber == lastSuccessfulClaimStageNumber
					and localWins <= lastSuccessfulClaimWinsValue then
					claimTargetStage = nil
				end

				if claimTargetStage and not shouldSkipClaimForPendingPunch then
					local claimRetryState = getClaimRetryState(claimTargetStage.stageNumber)
					if claimRetryState then
						if not claimRetryState.firstEligibleAt then
							claimRetryState.firstEligibleAt = now
							claimRetryState.nextAttemptAt = math.max(claimRetryState.nextAttemptAt or 0, now)
						end
						claimAttemptReadyAt = math.max(claimCooldownUntil, claimRetryState.nextAttemptAt or 0)
					end
				end
				local nextStageDebugText = string.format(
					"next=%s hp=%s destroyed=%s",
					nextStageForInfo and tostring(nextStageForInfo.stageNumber) or "nil",
					nextStageForInfo and tostring(nextStageForInfo.health) or "nil",
					nextStageForInfo and tostring(nextStageForInfo.destroyed) or "nil"
				)

				debugAutoWin(now, string.format(
					"wins=%d str=%d highest=%s pending=%s(%s) claim=%s cooldown=%.1f eta=%.1fs delayPunch=%s | highest vb=%s hv=%s wv=%s hp=%s destroyed=%s | pending vb=%s hv=%s wv=%s hp=%s destroyed=%s | %s",
					localWins or 0,
					localStrength or 0,
					tostring(highestUnlockedIndex),
					pendingStageIndex and tostring(pendingStageIndex) or "nil",
					pendingAction or "nil",
					claimTargetStage and tostring(claimTargetStage.stageNumber) or "nil",
					math.max(0, claimCooldownUntil - now),
					estimatedBreakSeconds or -1,
					tostring(shouldDelayPunchForStrength),
					highestStage and tostring(highestStage.visibleBarrierTransparency) or "nil",
					highestStage and tostring(highestStage.healthVisible) or "nil",
					highestStage and tostring(highestStage.winsVisible) or "nil",
					highestStage and tostring(highestStage.health) or "nil",
					highestStage and tostring(highestStage.destroyed) or "nil",
					pendingStage and tostring(pendingStage.visibleBarrierTransparency) or "nil",
					pendingStage and tostring(pendingStage.healthVisible) or "nil",
					pendingStage and tostring(pendingStage.winsVisible) or "nil",
					pendingStage and tostring(pendingStage.health) or "nil",
					pendingStage and tostring(pendingStage.destroyed) or "nil",
					nextStageDebugText
				))

				if claimTargetStage and not shouldSkipClaimForPendingPunch and now >= claimAttemptReadyAt then
					local claimRetryState = getClaimRetryState(claimTargetStage.stageNumber)
					local claimSucceeded, didClaimTeleport, claimAttempts, winsBeforeClaim, winsAfterClaim, claimMoveReason, claimMoveDistance, claimInvokeOk, claimInvokeResult = tryClaimWinStage(claimTargetStage)
					local claimResolvedAt = os.clock()
					now = claimResolvedAt
					local claimMoveDistanceText = claimMoveDistance and string.format("%.1f", claimMoveDistance) or "nil"
					local claimInvokeResultText = formatAutoWinDebugValue(claimInvokeResult)

					if claimSucceeded then
						local observedClaimDelay = learnedClaimReadyDelay
						if claimRetryState and claimRetryState.firstEligibleAt then
							observedClaimDelay = math.max(0, claimResolvedAt - claimRetryState.firstEligibleAt)
						end
						learnedClaimReadyDelay = math.max(AUTO_WIN_CLAIM_MIN_READY_DELAY, (learnedClaimReadyDelay * 0.5) + (observedClaimDelay * 0.5))
						claimRetryStateByStageNumber[claimTargetStage.stageNumber] = nil
						lastSuccessfulClaimStageNumber = claimTargetStage.stageNumber
						lastSuccessfulClaimWinsValue = math.max(localWins or 0, winsAfterClaim or 0)
						claimCooldownUntil = claimResolvedAt + AUTO_WIN_POST_CLAIM_WAIT
						claimedThisLoop = true
						lastClaimAttemptSummary = string.format("last=s%d ok tp=%s(%s %s) tries=%d wins %d>%d ready=%.1fs", claimTargetStage.stageNumber, tostring(didClaimTeleport), tostring(claimMoveReason), claimMoveDistanceText, claimAttempts, winsBeforeClaim, winsAfterClaim, observedClaimDelay)
						debugAutoWin(now, string.format("claim stage=%s ok wins %d->%d tp=%s move=%s dist=%s tries=%d invokeOk=%s result=%s ready=%.1fs learn=%.1fs", tostring(claimTargetStage.stageNumber), winsBeforeClaim, winsAfterClaim, tostring(didClaimTeleport), tostring(claimMoveReason), claimMoveDistanceText, claimAttempts, tostring(claimInvokeOk), claimInvokeResultText, observedClaimDelay, learnedClaimReadyDelay))
					else
						local nextRetryWait = AUTO_WIN_CLAIM_FAIL_RETRY_WAIT
						if claimRetryState then
							claimRetryState.failCount = (claimRetryState.failCount or 0) + 1
							nextRetryWait = math.min(AUTO_WIN_CLAIM_FAIL_RETRY_MAX_WAIT, AUTO_WIN_CLAIM_FAIL_RETRY_WAIT * (2 ^ math.max(0, claimRetryState.failCount - 1)))
							claimRetryState.nextAttemptAt = claimResolvedAt + nextRetryWait
							claimAttemptReadyAt = claimRetryState.nextAttemptAt
						else
							claimAttemptReadyAt = claimResolvedAt + nextRetryWait
						end
						claimCooldownUntil = claimAttemptReadyAt
						lastClaimAttemptSummary = string.format("last=s%d fail tp=%s(%s %s) tries=%d wins %d>%d retry=%.1fs", claimTargetStage.stageNumber, tostring(didClaimTeleport), tostring(claimMoveReason), claimMoveDistanceText, claimAttempts, winsBeforeClaim, winsAfterClaim, nextRetryWait)
						debugAutoWin(now, string.format("claim stage=%s fail wins=%d->%d tp=%s move=%s dist=%s tries=%d invokeOk=%s result=%s retry=%.1fs failCount=%d learn=%.1fs", tostring(claimTargetStage.stageNumber), winsBeforeClaim, winsAfterClaim, tostring(didClaimTeleport), tostring(claimMoveReason), claimMoveDistanceText, claimAttempts, tostring(claimInvokeOk), claimInvokeResultText, nextRetryWait, claimRetryState and claimRetryState.failCount or 0, learnedClaimReadyDelay))
					end
				end

				if claimTargetStage then
					local localRoot = getLocalRootPart()
					local debugMode = "IDLE"
					if isActivelyPunchingPendingStage then
						debugMode = "PUNCH"
					elseif isWaitingOnPendingStage then
						debugMode = "WAIT"
					end

					local debugClaimDistance = "nil"
					if localRoot and claimTargetStage.claimPosition then
						debugClaimDistance = string.format("%.1f", (localRoot.Position - claimTargetStage.claimPosition).Magnitude)
					end

					debugAutoWin(now, string.format(
						"mode=%s target=%s pos=%s dist=%s cooldown=%.1f %s",
						debugMode,
						tostring(claimTargetStage.stageNumber),
						claimTargetStage.claimPosition and "Y" or "N",
						debugClaimDistance,
						math.max(0, claimCooldownUntil - now),
						lastClaimAttemptSummary
					))
				end

				if pendingStage then
					local claimStatusSeconds = getClaimStatusSeconds(now)
					if pendingAction == "punch" and pendingStage.punchPosition and not shouldDelayPunchForStrength then
						if shouldTeleportToPendingStage then
							didPunchTeleport = tryMoveNearPunchStage(pendingStage)
							if didPunchTeleport then
								lastPunchTeleportStageNumber = pendingStage.stageNumber
							end
						end
						if claimedThisLoop and claimTargetStage then
							setStatusLine("win", string.format("Win: Claim stage %d + punch %d (%s HP)%s", claimTargetStage.stageNumber, pendingStage.stageNumber, formatShorthandNumber(pendingStage.health), didPunchTeleport and " | moved in" or "") .. nextStageStatusSuffix)
						elseif claimTargetStage and now < claimCooldownUntil then
							setStatusLine("win", string.format("Win: Punch %d (%s HP)%s | claim stage %d in %.1fs", pendingStage.stageNumber, formatShorthandNumber(pendingStage.health), didPunchTeleport and " | moved in" or "", claimTargetStage.stageNumber, claimStatusSeconds) .. nextStageStatusSuffix)
						else
							setStatusLine("win", string.format("Win: Punch %d (%s HP)%s", pendingStage.stageNumber, formatShorthandNumber(pendingStage.health), didPunchTeleport and " | moved in" or "") .. nextStageStatusSuffix)
						end
						local args = {
							pendingStage.stageNumber,
							pendingStage.punchPosition,
						}
						for _ = 1, AUTO_WIN_PUNCH_BURST do
							if not (controller.running and autoWinEnabled) then
								break
							end
							PunchStrengthBarrierRemote:FireServer(unpack(args))
						end
					else
						if shouldDelayPunchForStrength then
							for _ = 1, AUTO_WIN_WAIT_TRAIN_BURST do
								if not (controller.running and autoWinEnabled) then
									break
								end
								LiftWeightRemote:FireServer()
							end
						end

						if shouldDelayPunchForStrength and estimatedBreakSeconds then
							if claimTargetStage and now >= claimCooldownUntil and not claimedThisLoop then
								setStatusLine("win", string.format("Win: Train STR + claim stage %d | ETA stage %d %.1fm", claimTargetStage.stageNumber, pendingStage.stageNumber, estimatedBreakSeconds / 60) .. nextStageStatusSuffix)
							elseif claimTargetStage and now < claimCooldownUntil then
								setStatusLine("win", string.format("Win: Train STR for stage %d (ETA %.1fm) | claim stage %d in %.1fs", pendingStage.stageNumber, estimatedBreakSeconds / 60, claimTargetStage.stageNumber, claimStatusSeconds) .. nextStageStatusSuffix)
							else
								setStatusLine("win", string.format("Win: Train STR for stage %d (ETA %.1fm | need >= %s STR)", pendingStage.stageNumber, estimatedBreakSeconds / 60, formatShorthandNumber(requiredStrengthForPendingStage)) .. nextStageStatusSuffix)
							end
						elseif shouldDelayPunchForStrength then
							setStatusLine("win", string.format("Win: Train STR for stage %d (need >= %s STR)", pendingStage.stageNumber, formatShorthandNumber(requiredStrengthForPendingStage)) .. nextStageStatusSuffix)
						elseif pendingAction == "punch" and not pendingStage.punchPosition then
							setStatusLine("win", string.format("Win: Stage %d waiting (no punch position)", pendingStage.stageNumber) .. nextStageStatusSuffix)
						elseif claimedThisLoop and claimTargetStage then
							setStatusLine("win", string.format("Win: Claim stage %d + stage %d waiting", claimTargetStage.stageNumber, pendingStage.stageNumber) .. nextStageStatusSuffix)
						elseif claimTargetStage and now < claimCooldownUntil then
							setStatusLine("win", string.format("Win: Stage %d waiting | claim stage %d in %.1fs", pendingStage.stageNumber, claimTargetStage.stageNumber, claimStatusSeconds) .. nextStageStatusSuffix)
						else
							setStatusLine("win", string.format("Win: Stage %d waiting", pendingStage.stageNumber) .. nextStageStatusSuffix)
						end
					end
				else
					local claimStatusSeconds = getClaimStatusSeconds(now)
					if claimTargetStage then
						if claimedThisLoop then
							setStatusLine("win", string.format("Win: Claim stage %d", claimTargetStage.stageNumber) .. nextStageStatusSuffix)
						else
							setStatusLine("win", string.format("Win: Claim stage %d in %.1fs", claimTargetStage.stageNumber, claimStatusSeconds) .. nextStageStatusSuffix)
						end
					else
						if nextStage and nextStage.requirement and nextStage.requirement ~= math.huge and localWins < nextStage.requirement then
							setStatusLine("win", string.format("Win: Need %s wins for stage %d (%s HP)", formatShorthandNumber(nextStage.requirement), nextStage.stageNumber, formatShorthandNumber(nextStage.health)))
						elseif currentStage and currentStage.destroyed then
							setStatusLine("win", string.format("Win: Scanning next stage after %d", currentStage.stageNumber))
						else
							setStatusLine("win", "Win: Waiting stage data")
						end
					end
				end
			end

			task.wait(AUTO_WIN_LOOP_DELAY)
		else
			task.wait(0.15)
		end
	end
end)

task.spawn(function()
	while controller.running do
		if autoClaimPlaytimeEnabled then
			local claimedCount = 0
			for slot = 1, AUTO_PLAYTIME_REWARD_SLOTS do
				if not (controller.running and autoClaimPlaytimeEnabled) then
					break
				end

				local ok, result = pcall(function()
					return ClaimPlaytimeRewardRemote:InvokeServer(slot)
				end)

				if ok and isPlaytimeClaimSuccess(result) then
					claimedCount = claimedCount + 1
				end
			end

			if claimedCount > 0 then
				setStatusLine("playtime", string.format("Playtime: claimed %d", claimedCount))
			else
				setStatusLine("playtime", "Playtime: waiting")
			end

			task.wait(AUTO_PLAYTIME_CLAIM_DELAY)
		else
			task.wait(0.2)
		end
	end
end)

task.spawn(function()
	local nextHopCheckAt = 0

	while controller.running do
		if autoServerHopEnabled and autoKillEnabled then
			local now = os.clock()
			local currentPlayerCount = getNonAfkPlayerCount()

			if currentPlayerCount >= AUTO_HOP_MIN_SERVER_PLAYERS then
				setStatusLine("hop", string.format("Hop: server healthy (%d non-AFK)", currentPlayerCount))
				nextHopCheckAt = now + AUTO_HOP_CHECK_DELAY
				task.wait(1)
			elseif now < nextHopCheckAt then
				setStatusLine("hop", string.format("Hop: recheck in %.1fs (%d non-AFK)", nextHopCheckAt - now, currentPlayerCount))
				task.wait(0.5)
			else
				setStatusLine("hop", string.format("Hop: finding busier server (%d non-AFK)", currentPlayerCount))
				local targetServer, reason = findBetterServer(currentPlayerCount)
				if targetServer and targetServer.id then
					setStatusLine("hop", string.format("Hop: joining %d/%d players", targetServer.playing or 0, targetServer.maxPlayers or 0))
					local teleportOk, teleportError = pcall(function()
						TeleportService:TeleportToPlaceInstance(game.PlaceId, targetServer.id)
					end)
					if not teleportOk then
						setStatusLine("hop", "Hop: teleport failed")
						nextHopCheckAt = os.clock() + AUTO_HOP_RETRY_DELAY
					elseif teleportError then
						nextHopCheckAt = os.clock() + AUTO_HOP_RETRY_DELAY
					end
				else
					setStatusLine("hop", "Hop: " .. tostring(reason or "no server found"))
					nextHopCheckAt = os.clock() + AUTO_HOP_RETRY_DELAY
				end
				task.wait(1)
			end
		elseif autoServerHopEnabled then
			setStatusLine("hop", "Hop: standby (Auto Kill OFF)")
			task.wait(0.5)
		else
			task.wait(0.5)
		end
	end
end)

task.spawn(function()
	local skippedTargets = {}
	local recentTargetHits = {}
	local targetCycle = {}
	local targetCycleIndex = 1
	local focusedTargetUserId = nil
	local focusedTargetHealth = nil
	local focusedTargetHealthChangedAt = 0
	local nextTeleportAt = 0
	local activeMoveTween = nil
	local lastMoveGoalPos = nil

	local function rebuildTargetCycle()
		targetCycle = {}
		for _, player in ipairs(Players:GetPlayers()) do
			if player ~= LocalPlayer then
				table.insert(targetCycle, player)
			end
		end

		table.sort(targetCycle, function(a, b)
			return getStrengthValue(a) > getStrengthValue(b)
		end)

		targetCycleIndex = 1
	end

	local function getPlayerByUserId(userId)
		if not userId then
			return nil
		end

		for _, player in ipairs(Players:GetPlayers()) do
			if player.UserId == userId then
				return player
			end
		end

		return nil
	end

	local function validateAttackTarget(targetPlayer, now, ignoreRevisit)
		if not targetPlayer or targetPlayer == LocalPlayer or targetPlayer.Parent ~= Players then
			return nil, nil, nil
		end

		local skipUntil = skippedTargets[targetPlayer.UserId]
		if skipUntil and now < skipUntil then
			return nil, nil, nil
		end

		if not ignoreRevisit then
			local revisitUntil = recentTargetHits[targetPlayer.UserId]
			if revisitUntil and now < revisitUntil then
				return nil, nil, nil
			end
		end

		local targetCharacter = targetPlayer.Character
		if not targetCharacter then
			skippedTargets[targetPlayer.UserId] = now + 0.8
			return nil, nil, nil
		end

		local outOfMap = isTargetOutOfMap(targetPlayer, targetCharacter)
		if outOfMap then
			skippedTargets[targetPlayer.UserId] = now + TARGET_SKIP_COOLDOWN
			return nil, nil, nil
		end

		local hasSpawnShield = isTargetSpawnShielded(targetPlayer, targetCharacter)
		if hasSpawnShield then
			skippedTargets[targetPlayer.UserId] = now + TARGET_SPAWN_SHIELD_COOLDOWN
			return nil, nil, nil
		end

		local targetHumanoid = getAliveHumanoid(targetCharacter)
		if not targetHumanoid then
			skippedTargets[targetPlayer.UserId] = now + 0.8
			return nil, nil, nil
		end

		local hitPosition = getBehindHitPosition(targetCharacter) or getDirectHitPosition(targetCharacter)
		if not hitPosition then
			skippedTargets[targetPlayer.UserId] = now + TARGET_SKIP_COOLDOWN
			return nil, nil, nil
		end

		return targetCharacter, hitPosition, getStrengthValue(targetPlayer)
	end

	local function getNextTargetFromCycle(now)
		local earliestReadyAt = nil

		if targetCycleIndex > #targetCycle then
			rebuildTargetCycle()
			if #targetCycle == 0 then
				return nil, nil, nil, nil
			end
		end

		for pass = 1, 2 do
			local ignoreRevisit = (pass == 2)
			local scanned = 0
			while scanned < #targetCycle do
				local targetPlayer = targetCycle[targetCycleIndex]
				targetCycleIndex = targetCycleIndex + 1
				scanned = scanned + 1

				if targetPlayer and targetPlayer.Parent == Players then
					local skipUntil = skippedTargets[targetPlayer.UserId]
					local revisitUntil = recentTargetHits[targetPlayer.UserId]
					local blockedUntil = skipUntil
					if not blockedUntil or (revisitUntil and revisitUntil > blockedUntil) then
						blockedUntil = revisitUntil
					end

					if blockedUntil and blockedUntil > now and (not earliestReadyAt or blockedUntil < earliestReadyAt) then
						earliestReadyAt = blockedUntil
					end

					local targetCharacter, hitPosition, targetStrength = validateAttackTarget(targetPlayer, now, ignoreRevisit)
					if targetCharacter and hitPosition then
						return targetPlayer, targetCharacter, hitPosition, targetStrength
					end
				end
			end
		end

		return nil, nil, nil, earliestReadyAt
	end

	rebuildTargetCycle()

	while controller.running do
		if autoKillEnabled then
			local now = os.clock()
			local localRoot = getLocalRootPart()
			if #targetCycle == 0 then
				rebuildTargetCycle()
			end

			local targetPlayer = getPlayerByUserId(focusedTargetUserId)
			local targetCharacter = nil
			local hitPosition = nil
			local targetStrength = nil
			local waitUntil = nil

			if targetPlayer then
				local rawCharacter = targetPlayer.Character
				local rawHumanoid = rawCharacter and rawCharacter:FindFirstChildOfClass("Humanoid")
				if not rawHumanoid or rawHumanoid.Health <= 0 then
					recentTargetHits[targetPlayer.UserId] = now + TARGET_REVISIT_COOLDOWN
					focusedTargetUserId = nil
					focusedTargetHealth = nil
				else
					targetCharacter, hitPosition, targetStrength = validateAttackTarget(targetPlayer, now, true)
					if not targetCharacter then
						focusedTargetUserId = nil
						focusedTargetHealth = nil
					end
				end
			end

			if not targetCharacter then
				targetPlayer, targetCharacter, hitPosition, targetStrength = getNextTargetFromCycle(now)
				if targetPlayer and targetCharacter then
					if focusedTargetUserId ~= targetPlayer.UserId then
						focusedTargetHealth = nil
						focusedTargetHealthChangedAt = now
					end
					focusedTargetUserId = targetPlayer.UserId
				else
					waitUntil = targetStrength
				end
			end

			if not targetPlayer or not targetCharacter then
				if waitUntil and waitUntil > now then
					setStatusLine("kill", string.format("Kill: waiting %.1fs", waitUntil - now))
				else
					setStatusLine("kill", "Kill: scanning...")
				end
			else
				local shouldAttackTarget = true
				local targetHumanoid = getAliveHumanoid(targetCharacter)
				local targetHealthText = "?"
				if targetHumanoid then
					local currentHealth = targetHumanoid.Health
					targetHealthText = formatShorthandNumber(currentHealth)
					if focusedTargetHealth == nil then
						focusedTargetHealth = currentHealth
						focusedTargetHealthChangedAt = now
					elseif currentHealth + 0.01 < focusedTargetHealth then
						focusedTargetHealth = currentHealth
						focusedTargetHealthChangedAt = now
					elseif now - focusedTargetHealthChangedAt >= TARGET_HEALTH_STUCK_SECONDS then
						skippedTargets[targetPlayer.UserId] = now + TARGET_SKIP_COOLDOWN
						recentTargetHits[targetPlayer.UserId] = now + TARGET_REVISIT_COOLDOWN
						setStatusLine("kill", string.format("Kill: skip %s (hp stuck)", targetPlayer.Name))
						focusedTargetUserId = nil
						focusedTargetHealth = nil
						shouldAttackTarget = false
					end
				end

				if shouldAttackTarget then
					local targetRoot = targetCharacter:FindFirstChild("HumanoidRootPart")
					if isAutoWinMovementPriorityActive() then
						if activeMoveTween then
							activeMoveTween:Cancel()
							activeMoveTween = nil
						end
						releaseMovementLock("kill-move")
						lastMoveGoalPos = nil
					elseif localRoot and targetRoot and now >= nextTeleportAt then
						local flatDistance = (Vector3.new(localRoot.Position.X, 0, localRoot.Position.Z) - Vector3.new(targetRoot.Position.X, 0, targetRoot.Position.Z)).Magnitude
						if flatDistance >= AUTO_KILL_MIN_TP_DISTANCE then
							local behindCFrame = getBehindTargetCFrame(localRoot, targetCharacter)
							if behindCFrame then
								local goalPos = behindCFrame.Position
								local moveDelta = (not lastMoveGoalPos) and math.huge or (goalPos - lastMoveGoalPos).Magnitude
								local tweenIsBusy = activeMoveTween and activeMoveTween.PlaybackState == Enum.PlaybackState.Playing
								if (not tweenIsBusy) or moveDelta >= 2.5 then
									if tryAcquireMovementLock("kill-move", MOVE_TWEEN_TIME + 0.08) then
										if activeMoveTween then
											activeMoveTween:Cancel()
										end

										activeMoveTween = TweenService:Create(
											localRoot,
											TweenInfo.new(MOVE_TWEEN_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
											{ CFrame = behindCFrame }
										)
										activeMoveTween:Play()
										lastMoveGoalPos = goalPos
										nextTeleportAt = now + AUTO_KILL_TP_COOLDOWN
										task.delay(MOVE_TWEEN_TIME + 0.08, function()
											releaseMovementLock("kill-move")
										end)
									end
								end
							end
						end
					end

					local hits = 0
					for _ = 1, AUTO_KILL_SINGLE_BURST do
						local ok = pcall(function()
							PunchCharacterRemote:FireServer(targetCharacter, hitPosition)
						end)
						if ok then
							hits = hits + 1
						end
					end

					setStatusLine("kill", string.format("Kill: %s (%d STR | %s HP) | hits %d", targetPlayer.Name, targetStrength or 0, targetHealthText, hits))
				end
			end

			task.wait(AUTO_KILL_LOOP_DELAY)
		else
			focusedTargetUserId = nil
			focusedTargetHealth = nil
			lastMoveGoalPos = nil
			if activeMoveTween then
				activeMoveTween:Cancel()
				activeMoveTween = nil
			end
			releaseMovementLock("kill-move")
			task.wait(0.15)
		end
	end
end)
