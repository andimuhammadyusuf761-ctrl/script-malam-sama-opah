--!nonstrict
--[[
	Robscript Team - MALAM SAMA OPAH
	=============================================================
	Version		: 2.3.0  (V2.3 ULTRA)
	Target		: "[CLASS] MALAM SAMA OPAH" by Sabun Studios
	Place ID	: 101051454784523
	Universe	: 10772066587

	Single native Roblox GUI (one ScreenGui). Six pages: Home,
	Diagnostics, Visuals, Automation, Teleport, Settings.

	Preserved client-side features:
		* ESP: Opah, keys, passcode note, front door/locks, wardrobes, drawers
		* Opah radar overlay (state, distance, chase target, lair)
		* Passcode overlay + clipboard copy
		* Auto loot: drawers, keys, passcode note, flip flops (walk or teleport)
		* Auto hide: nearest wardrobe while Opah is chasing
		* Teleport / walk to live workspace markers
		* Diagnostics report + activity/error logs
		* Auto redeem code manager (redemption gated: no invented remotes)

	This build never invents game remotes, never fabricates telemetry and
	never marks a code as redeemed without server confirmation.

	Toggle UI: RightControl (configurable in Settings).
	Unload: Settings -> Unload script, or getgenv().RMSO_Unload().
]]

local VERSION = "2.3.0"
local VERSION_TAG = "V2.3 ULTRA"
local GAME_NAME = "[CLASS] MALAM SAMA OPAH"
local GAME_PLACE_ID = 101051454784523
local GAME_UNIVERSE_ID = 10772066587

--== Services ==
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local StatsService = game:GetService("Stats")
local MarketplaceService = game:GetService("MarketplaceService")

local LocalPlayer = Players.LocalPlayer

--== Re-execution guard ==
local ENV = (typeof(getgenv) == "function" and getgenv()) or _G
if type(ENV.RMSO_Unload) == "function" then
	pcall(ENV.RMSO_Unload)
end

--== Small helpers ==
local function clamp(value, low, high)
	if value < low then return low end
	if value > high then return high end
	return value
end

local function trim(text)
	if type(text) ~= "string" then return "" end
	return (text:gsub("^%s*(.-)%s*$", "%1"))
end

local function round(value)
	return math.floor(value + 0.5)
end

local function formatClock(seconds)
	seconds = math.max(0, math.floor(seconds or 0))
	local minutes = math.floor(seconds / 60)
	local rest = seconds % 60
	return string.format("%02d:%02d", minutes, rest)
end

local function sameColor(a, b)
	return a == b
end

--== Palette ==
local THEME = {
	bg = Color3.fromHex("0B0910"),
	bg2 = Color3.fromHex("130E1A"),
	panel = Color3.fromHex("171220"),
	panel2 = Color3.fromHex("1E1829"),
	panel3 = Color3.fromHex("271F35"),
	inset = Color3.fromHex("0A0710"),
	stroke = Color3.fromHex("3B2B49"),
	strokeSoft = Color3.fromHex("2B2136"),
	text = Color3.fromHex("F7F0F8"),
	muted = Color3.fromHex("A796B4"),
	dim = Color3.fromHex("766785"),
	success = Color3.fromHex("4BE39B"),
	warning = Color3.fromHex("F5C45B"),
	error = Color3.fromHex("FF6075"),
	info = Color3.fromHex("6FB8FF"),
	white = Color3.fromHex("FFFFFF"),
}

local ACCENTS = {
	{ name = "Magenta", accent = Color3.fromHex("FF3DBE"), accent2 = Color3.fromHex("B61E86") },
	{ name = "Pink", accent = Color3.fromHex("FF6AAE"), accent2 = Color3.fromHex("D93E7E") },
	{ name = "Violet", accent = Color3.fromHex("B072FF"), accent2 = Color3.fromHex("7A3FD9") },
	{ name = "Rose", accent = Color3.fromHex("FF4D6D"), accent2 = Color3.fromHex("C42847") },
}

local theme = {
	accent = ACCENTS[1].accent,
	accent2 = ACCENTS[1].accent2,
	index = 1,
}

--== Accent bindings (theme switching without rebuilding the GUI) ==
local accentBindings = {}
local themeHooks = {}

local function bindAccent(object, property, kind)
	if not object then return end
	table.insert(accentBindings, { object = object, property = property, kind = kind or "accent" })
	pcall(function() object[property] = theme[kind or "accent"] end)
end

local function applyAccent(index)
	local preset = ACCENTS[index] or ACCENTS[1]
	theme.index = index or 1
	theme.accent = preset.accent
	theme.accent2 = preset.accent2
	for _, binding in ipairs(accentBindings) do
		pcall(function()
			binding.object[binding.property] = theme[binding.kind]
		end)
	end
	for index = 1, #themeHooks do
		pcall(themeHooks[index])
	end
end

--== Shared state handles ==
local function newState(initial)
	local state = { value = initial, listeners = {} }

	function state:Get()
		return self.value
	end

	function state:Set(value)
		if self.value == value then return end
		self.value = value
		for index = 1, #self.listeners do
			local listener = self.listeners[index]
			local ok, err = pcall(listener, value)
			if not ok then
				warn("[MSO] state listener error: " .. tostring(err))
			end
		end
	end

	function state:Toggle()
		self:Set(not self.value)
	end

	function state:OnChanged(listener)
		table.insert(self.listeners, listener)
		local ok, err = pcall(listener, self.value)
		if not ok then warn("[MSO] state listener error: " .. tostring(err)) end
		return listener
	end

	return state
end

local cfg = {
	-- visual
	espOpah = newState(true),
	espKeys = newState(true),
	espNote = newState(true),
	espDoor = newState(true),
	espWardrobe = newState(false),
	espDrawer = newState(false),
	espLabels = newState(true),
	espDistance = newState(300),
	radar = newState(true),
	passOverlay = newState(true),
	-- automation
	autoLoot = newState(false),
	lootTargets = newState({ Drawers = true, Keys = true, ["Passcode note"] = true, ["Flip flops"] = false }),
	lootMode = newState("Walk"),
	lootRange = newState(250),
	pauseOnChase = newState(true),
	autoHide = newState(false),
	hideRange = newState(45),
	hideMode = newState("Teleport"),
	-- teleport / interface
	teleportTarget = newState("Passcode note"),
	guiScale = newState(1),
	performanceMode = newState(false),
	interfaceVisible = newState(true),
	-- codes
	autoRedeem = newState(false),
	codeDelay = newState(3),
}

--== Hub state ==
local hub = {
	running = true,
	loadedAt = os.clock(),
	sessionStart = os.clock(),
	initOk = false,
	scans = 0,
	espSyncs = 0,
	lastScanAt = 0,
	lastEspAt = 0,
	world = {
		valid = false,
		drawers = {},
		flipflops = {},
		wardrobes = {},
		keys = {},
		locks = {},
		note = nil,
		opah = nil,
		door = nil,
		code = nil,
		drawerTotal = 0,
	},
	esp = {},
	code = nil,
	hiddenPrompt = nil,
	hideInProgress = false,
	errors = {},
	connections = {},
}

local lootBlacklist = {}

local function track(connection)
	if connection then
		table.insert(hub.connections, connection)
	end
	return connection
end

local function captureError(scope, err)
	local message = tostring(err)
	table.insert(hub.errors, { scope = tostring(scope), message = message, clock = os.clock() })
	if #hub.errors > 40 then
		table.remove(hub.errors, 1)
	end
	warn("[MSO] " .. tostring(scope) .. ": " .. message)
end

--== Logging (shared history, rendered by every log view) ==
local LOG_LIMIT = 220
local logHistory = {}
local logViews = {}
local errorRefreshHooks = {}

local function pushLog(level, text)
	local entry = {
		level = level or "info",
		text = tostring(text),
		clock = os.clock(),
	}
	table.insert(logHistory, entry)
	if #logHistory > LOG_LIMIT then
		table.remove(logHistory, 1)
	end
	for index = 1, #logViews do
		pcall(function()
			logViews[index]:Push(entry)
		end)
	end
end

-- Forward declarations used by callbacks below the UI build.
local TOAST_PUSH = nil
local selectPage = nil
local setUIVisible = nil
local lootStep, hideStep, runDiagnostics, refreshDiagnostics
local codesRedeemAll, codesRefresh, codesDetect

local function notify(title, content, level)
	pushLog(level == "error" and "error" or (level == "warn" and "warn" or "accent"),
		tostring(title) .. " - " .. tostring(content))
	if TOAST_PUSH then
		pcall(TOAST_PUSH, tostring(title), tostring(content), level or "info")
	end
end

--== Character helpers ==
local function getRoot()
	local character = LocalPlayer.Character
	if not character then return nil end
	return character:FindFirstChild("HumanoidRootPart")
end

local function getHumanoid()
	local character = LocalPlayer.Character
	if not character then return nil end
	return character:FindFirstChildOfClass("Humanoid")
end

local function getCamera()
	return workspace.CurrentCamera
end

local function instancePosition(instance)
	if not instance then return nil end
	local ok, result = pcall(function()
		if instance:IsA("BasePart") then return instance.Position end
		if instance:IsA("Attachment") then return instance.WorldPosition end
		if instance:IsA("Model") then
			local pivot = instance:GetPivot()
			return pivot and pivot.Position or nil
		end
		return nil
	end)
	if ok then return result end
	return nil
end

local function promptPosition(prompt)
	if not prompt then return nil end
	return instancePosition(prompt.Parent)
end

local function distanceBetween(a, b)
	if not a or not b then return math.huge end
	return (a - b).Magnitude
end

local function isAlive()
	local root = getRoot()
	local humanoid = getHumanoid()
	if not root or not humanoid or humanoid.Health <= 0 then return false end
	if LocalPlayer:GetAttribute("Out") == true then return false end
	return true
end

local function toggleValue(state)
	return state ~= nil and state:Get() == true
end

local function numberValue(state, fallback)
	local value = state and state:Get()
	if type(value) == "number" then return value end
	return fallback
end

--== World scanning ==
local KEY_COLORS = {
	Red = Color3.fromRGB(255, 75, 75),
	Blue = Color3.fromRGB(80, 140, 255),
	Green = Color3.fromRGB(75, 220, 115),
	Yellow = Color3.fromRGB(255, 210, 60),
	Purple = Color3.fromRGB(185, 105, 255),
}

local KEY_ORDER = { "Red", "Blue", "Green", "Yellow", "Purple" }

local COLOR_OPAH = Color3.fromRGB(255, 60, 60)
local COLOR_KEY_UNKNOWN = Color3.fromRGB(240, 240, 240)
local COLOR_NOTE = Color3.fromRGB(255, 255, 255)
local COLOR_DOOR = Color3.fromRGB(255, 165, 40)
local COLOR_WARDROBE = Color3.fromRGB(70, 220, 120)
local COLOR_DRAWER = Color3.fromRGB(220, 200, 90)

local function readPasscodeLabel(note)
	if not note then return nil end
	local ok, codeLabel = pcall(function() return note:FindFirstChild("Code", true) end)
	if ok and codeLabel and codeLabel:IsA("TextLabel") then
		local text = codeLabel.Text
		if type(text) == "string" and text:gsub("%s", "") ~= "" then
			return text
		end
	end
	return nil
end

local function scanWorld()
	local world = {
		valid = false,
		drawers = {},
		flipflops = {},
		wardrobes = {},
		keys = {},
		locks = {},
		note = nil,
		opah = nil,
		door = nil,
		code = nil,
		drawerTotal = 0,
	}

	local ok, err = pcall(function()
		local opah = workspace:FindFirstChild("Opah")
		if not opah and hub.scans % 5 == 0 then
			opah = workspace:FindFirstChild("Opah", true)
		end
		world.opah = opah
		world.door = workspace:FindFirstChild("FrontDoor")

		local chests = workspace:FindFirstChild("PuzzleChests")
		if chests then
			for _, descendant in ipairs(chests:GetDescendants()) do
				if descendant:IsA("ProximityPrompt") then
					if descendant.ActionText == "Open" then
						table.insert(world.drawers, descendant)
						world.drawerTotal = world.drawerTotal + 1
					elseif descendant.ActionText == "Close" then
						world.drawerTotal = world.drawerTotal + 1
					end
				end
			end
		end

		local flipFlops = workspace:FindFirstChild("FlipFlops")
		if flipFlops then
			for _, descendant in ipairs(flipFlops:GetDescendants()) do
				if descendant:IsA("ProximityPrompt") and descendant.ActionText == "Pick up" then
					table.insert(world.flipflops, descendant)
				end
			end
		end

		local wardrobes = workspace:FindFirstChild("HidingWardrobes")
		if wardrobes then
			for _, descendant in ipairs(wardrobes:GetDescendants()) do
				if descendant:IsA("ProximityPrompt") and descendant.ActionText == "Hide" then
					table.insert(world.wardrobes, descendant)
				end
			end
		end

		local items = workspace:FindFirstChild("PuzzleItems")
		if items then
			for _, child in ipairs(items:GetChildren()) do
				local itemType = child:GetAttribute("ItemType")
				if itemType == "Key" then
					table.insert(world.keys, child)
				elseif itemType == "Passcode" then
					world.note = child
					world.code = readPasscodeLabel(child)
				end
			end
		end

		if world.door then
			local locks = world.door:FindFirstChild("PuzzleLocks")
			if locks then
				for _, lock in ipairs(locks:GetChildren()) do
					table.insert(world.locks, lock)
				end
			end
		end

		world.valid = true
	end)

	if not ok then
		captureError("world scan", err)
	end

	hub.world = world
	hub.scans = hub.scans + 1
	hub.lastScanAt = os.clock()

	for prompt in pairs(lootBlacklist) do
		if prompt.Parent == nil then lootBlacklist[prompt] = nil end
	end

	if world.code and world.code ~= hub.code then
		hub.code = world.code
		pushLog("accent", "Passcode found: " .. tostring(world.code))
	end

	return world
end

local function keyColor(keyModel)
	local name = keyModel and keyModel:GetAttribute("KeyColor")
	return KEY_COLORS[name] or COLOR_KEY_UNKNOWN, name
end

local function lockColor(lockModel)
	local value = lockModel and lockModel:GetAttribute("KeyColorValue")
	if typeof(value) == "Color3" then return value end
	local name = lockModel and lockModel:GetAttribute("KeyColor")
	return KEY_COLORS[name] or COLOR_DOOR
end

local function lockPrompt(lockModel)
	if not lockModel then return nil end
	local ok, prompt = pcall(function()
		for _, descendant in ipairs(lockModel:GetDescendants()) do
			if descendant:IsA("ProximityPrompt") then return descendant end
		end
		return nil
	end)
	if ok then return prompt end
	return nil
end

local function findPickupPrompt(model)
	if not model then return nil end
	local ok, prompt = pcall(function()
		for _, descendant in ipairs(model:GetDescendants()) do
			if descendant:IsA("ProximityPrompt") and descendant.ActionText == "Pick up" then
				return descendant
			end
		end
		return nil
	end)
	if ok then return prompt end
	return nil
end

local function wardrobeModelFromPrompt(prompt)
	local parent = prompt and prompt.Parent
	while parent and not parent:IsA("Model") do
		parent = parent.Parent
	end
	return parent
end

--== ESP ==
local function ensureEspBillboard(entry, instance, color, labelText)
	if not entry.billboard then
		local billboard = Instance.new("BillboardGui")
		billboard.Name = "MSO_Label"
		billboard.Size = UDim2.fromOffset(150, 22)
		billboard.StudsOffsetWorldSpace = Vector3.new(0, 2.4, 0)
		billboard.AlwaysOnTop = true
		billboard.MaxDistance = 600
		billboard.LightInfluence = 0
		billboard.Adornee = instance
		billboard.Parent = instance

		local text = Instance.new("TextLabel")
		text.BackgroundTransparency = 1
		text.Size = UDim2.fromScale(1, 1)
		text.Font = Enum.Font.GothamBold
		text.TextSize = 13
		text.TextColor3 = color
		text.TextStrokeTransparency = 0.4
		text.Text = labelText or ""
		text.Parent = billboard

		entry.billboard = billboard
		entry.text = text
	else
		if entry.text then
			if entry.text.Text ~= labelText then entry.text.Text = labelText or "" end
			if not sameColor(entry.text.TextColor3, color) then entry.text.TextColor3 = color end
		end
		entry.billboard.Adornee = instance
	end
end

local function createEspEntry(instance, color, labelText, withLabel)
	local highlight = Instance.new("Highlight")
	highlight.Name = "MSO_Highlight"
	highlight.FillColor = color
	highlight.FillTransparency = 0.72
	highlight.OutlineColor = color
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Adornee = instance
	highlight.Parent = instance

	local entry = { highlight = highlight, billboard = nil, text = nil, label = labelText }
	if withLabel and labelText then
		ensureEspBillboard(entry, instance, color, labelText)
	end
	return entry
end

local function destroyEspEntry(entry)
	if not entry then return end
	if entry.highlight then pcall(function() entry.highlight:Destroy() end) end
	if entry.billboard then pcall(function() entry.billboard:Destroy() end) end
end

local function clearEsp()
	for instance, entry in pairs(hub.esp) do
		destroyEspEntry(entry)
		hub.esp[instance] = nil
	end
end

local function cleanupStaleEsp()
	local ok = pcall(function()
		for _, descendant in ipairs(workspace:GetDescendants()) do
			if descendant.Name == "MSO_Highlight" or descendant.Name == "MSO_Label" then
				descendant:Destroy()
			end
		end
	end)
	if not ok then
		pushLog("warn", "Previous ESP cleanup skipped (workspace not ready)")
	end
end

local function syncEsp()
	local camera = getCamera()
	local origin = camera and camera.CFrame.Position or Vector3.new(0, 0, 0)
	local maxDistance = numberValue(cfg.espDistance, 300)
	local withLabels = toggleValue(cfg.espLabels)
	local desired = {}

	local function add(instance, color, labelText)
		if not instance or instance.Parent == nil then return end
		local position = instancePosition(instance)
		if position and distanceBetween(position, origin) > maxDistance then return end
		desired[instance] = { color = color, label = labelText }
	end

	local world = hub.world
	if toggleValue(cfg.espOpah) and world.opah then
		add(world.opah, COLOR_OPAH, "OPAH")
	end
	if toggleValue(cfg.espKeys) then
		for _, key in ipairs(world.keys) do
			local color, name = keyColor(key)
			add(key, color, string.upper(name or "KEY") .. " KEY")
		end
	end
	if toggleValue(cfg.espNote) and world.note then
		add(world.note, COLOR_NOTE, "PASSCODE")
	end
	if toggleValue(cfg.espDoor) and world.door then
		add(world.door, COLOR_DOOR, "EXIT")
		local keypad = world.door:FindFirstChild("Keypad")
		if keypad then
			local plate = keypad:FindFirstChild("Plate", true)
			add(plate or keypad, COLOR_DOOR, "KEYPAD")
		end
		for _, lock in ipairs(world.locks) do
			add(lock, lockColor(lock), "LOCK")
		end
	end
	if toggleValue(cfg.espWardrobe) then
		for _, prompt in ipairs(world.wardrobes) do
			local wardrobe = wardrobeModelFromPrompt(prompt)
			if wardrobe then add(wardrobe, COLOR_WARDROBE, "HIDE") end
		end
	end
	if toggleValue(cfg.espDrawer) then
		for _, prompt in ipairs(world.drawers) do
			local drawer = prompt.Parent and prompt.Parent.Parent
			if drawer then add(drawer, COLOR_DRAWER, "DRAWER") end
		end
	end

	for instance, spec in pairs(desired) do
		local entry = hub.esp[instance]
		if not entry then
			hub.esp[instance] = createEspEntry(instance, spec.color, spec.label, withLabels)
		else
			if entry.highlight then
				if not sameColor(entry.highlight.FillColor, spec.color) then
					entry.highlight.FillColor = spec.color
				end
				if not sameColor(entry.highlight.OutlineColor, spec.color) then
					entry.highlight.OutlineColor = spec.color
				end
			end
			if withLabels then
				if not entry.billboard then
					ensureEspBillboard(entry, instance, spec.color, spec.label)
				elseif entry.label ~= spec.label then
					entry.label = spec.label
					if entry.text then entry.text.Text = spec.label end
				end
			elseif entry.billboard then
				entry.billboard:Destroy()
				entry.billboard = nil
				entry.text = nil
			end
		end
	end

	for instance, entry in pairs(hub.esp) do
		if not desired[instance] or instance.Parent == nil then
			destroyEspEntry(entry)
			hub.esp[instance] = nil
		end
	end

	hub.espSyncs = hub.espSyncs + 1
	hub.lastEspAt = os.clock()
end

--== Prompt / movement helpers ==
local function triggerPrompt(prompt)
	if not prompt or not prompt.Enabled then return false end
	if typeof(fireproximityprompt) == "function" then
		local ok = pcall(fireproximityprompt, prompt)
		if ok then return true end
	end
	local ok = pcall(function()
		prompt:InputHoldBegin()
		if prompt.HoldDuration > 0 then task.wait(prompt.HoldDuration) end
		prompt:InputHoldEnd()
	end)
	return ok
end

local function teleportNear(position)
	local root = getRoot()
	if not root or not position then return false end
	local from = root.Position
	local direction = Vector3.new(from.X - position.X, 0, from.Z - position.Z)
	if direction.Magnitude < 1 then direction = Vector3.new(0, 0, 1) end
	local standPoint = position + direction.Unit * 3 + Vector3.new(0, 2.5, 0)
	return pcall(function()
		root.CFrame = CFrame.lookAt(standPoint, Vector3.new(position.X, standPoint.Y, position.Z))
		root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
	end)
end

local function walkTo(position, radius, timeout)
	local root = getRoot()
	local humanoid = getHumanoid()
	if not root or not humanoid or not position then return false end
	local deadline = os.clock() + (timeout or 6)
	humanoid:MoveTo(position)
	while os.clock() < deadline and hub.running do
		if not root.Parent then return false end
		local current = root.Position
		if distanceBetween(current, position) <= radius then
			humanoid:MoveTo(current)
			return true
		end
		if hub.hideInProgress then
			humanoid:MoveTo(current)
			return false
		end
		task.wait(0.08)
	end
	humanoid:MoveTo(root.Position)
	return distanceBetween(root.Position, position) <= radius + 4
end

--== Target resolution ==
local function nearestKey(origin)
	local best, bestDistance = nil, math.huge
	for _, key in ipairs(hub.world.keys) do
		local position = instancePosition(key)
		if position and origin then
			local distance = distanceBetween(position, origin)
			if distance < bestDistance then
				best = key
				bestDistance = distance
			end
		end
	end
	return best, bestDistance
end

local function nearestWardrobePrompt(origin)
	local best, bestDistance = nil, math.huge
	for _, prompt in ipairs(hub.world.wardrobes) do
		if prompt.Enabled then
			local position = promptPosition(prompt)
			if position and origin then
				local distance = distanceBetween(position, origin)
				if distance < bestDistance then
					best = prompt
					bestDistance = distance
				end
			end
		end
	end
	return best, bestDistance
end

local function nearestDrawerPrompt(origin)
	local best, bestDistance = nil, math.huge
	for _, prompt in ipairs(hub.world.drawers) do
		if prompt.Enabled then
			local position = promptPosition(prompt)
			if position and origin then
				local distance = distanceBetween(position, origin)
				if distance < bestDistance then
					best = prompt
					bestDistance = distance
				end
			end
		end
	end
	return best, bestDistance
end

local TELEPORT_TARGETS = {
	"Passcode note",
	"Nearest key",
	"Front door",
	"Keypad",
	"Nearest wardrobe",
	"Nearest drawer",
	"Spawn",
}

local function resolveTargetPosition(kind)
	local world = hub.world
	local root = getRoot()
	local camera = getCamera()
	local origin = root and root.Position or (camera and camera.CFrame.Position)
	if kind == "Passcode note" then
		return instancePosition(world.note)
	elseif kind == "Nearest key" then
		local key = nearestKey(origin)
		return instancePosition(key)
	elseif kind == "Front door" then
		return instancePosition(world.door)
	elseif kind == "Keypad" then
		local keypad = world.door and world.door:FindFirstChild("Keypad")
		local plate = keypad and keypad:FindFirstChild("Plate", true)
		return instancePosition(plate or keypad)
	elseif kind == "Nearest wardrobe" then
		local prompt = nearestWardrobePrompt(origin)
		return promptPosition(prompt)
	elseif kind == "Nearest drawer" then
		local prompt = nearestDrawerPrompt(origin)
		return promptPosition(prompt)
	elseif kind == "Spawn" then
		local ok, spawn = pcall(function()
			return workspace:FindFirstChildWhichIsA("SpawnLocation", true)
		end)
		if ok then return instancePosition(spawn) end
	end
	return nil
end

--== Summaries used by the dashboard and diagnostics ==
local function remotesSummary()
	local parts = {}
	local function addRemote(name, instance)
		table.insert(parts, name .. (instance and "=ok" or "=missing"))
	end
	addRemote("WardrobeHide", ReplicatedStorage:FindFirstChild("WardrobeHideRemote"))
	local puzzleShared = ReplicatedStorage:FindFirstChild("PuzzleShared")
	local remotes = puzzleShared and puzzleShared:FindFirstChild("Remotes")
	if remotes then
		addRemote("PuzzleRemote", remotes:FindFirstChild("PuzzleRemote"))
		addRemote("SubmitPasscode", remotes:FindFirstChild("SubmitPasscode"))
	end
	local gameShared = ReplicatedStorage:FindFirstChild("GameShared")
	if gameShared then
		addRemote("GameRemote", gameShared:FindFirstChild("GameRemote"))
		addRemote("ReviveRemote", gameShared:FindFirstChild("ReviveRemote"))
		addRemote("JumpscareRemote", gameShared:FindFirstChild("JumpscareRemote"))
	end
	return table.concat(parts, "  ")
end

local function keysSummary()
	local found = {}
	for _, key in ipairs(hub.world.keys) do
		local _, name = keyColor(key)
		if name then table.insert(found, name) end
	end
	local missing = {}
	for _, name in ipairs(KEY_ORDER) do
		local present = false
		for _, item in ipairs(found) do
			if item == name then present = true end
		end
		if not present then table.insert(missing, name) end
	end
	return found, missing
end

local function locksRemaining()
	local remaining = 0
	for _, lock in ipairs(hub.world.locks) do
		local prompt = lockPrompt(lock)
		if prompt and prompt.Enabled then remaining = remaining + 1 end
	end
	return remaining
end

local function opahSummary()
	local opah = hub.world.opah
	if not opah then return nil end
	local root = getRoot()
	local camera = getCamera()
	local origin = root and root.Position or (camera and camera.CFrame.Position)
	local position = instancePosition(opah)
	local distance = 0
	if position and origin then distance = distanceBetween(position, origin) end
	local state = opah:GetAttribute("State")
	local mode = opah:GetAttribute("Mode")
	return {
		state = state ~= nil and tostring(state) or "Unknown",
		mode = mode ~= nil and tostring(mode) or "Unknown",
		chasing = opah:GetAttribute("Chasing") == true,
		targetUserId = opah:GetAttribute("TargetUserId"),
		lair = opah:GetAttribute("Lair"),
		lairText = tostring(opah:GetAttribute("Lair")),
		distance = distance,
	}
end

--== Real telemetry (never fabricated) ==
local function getPing()
	local ok, value = pcall(function()
		return StatsService.Network.ServerStatsItem["Data Ping"]:GetValue()
	end)
	if ok and type(value) == "number" then return round(value) end
	return nil
end

local function getMemoryMb()
	local ok, value = pcall(function()
		return StatsService:GetTotalMemoryUsageMb()
	end)
	if ok and type(value) == "number" then return round(value) end
	return nil
end

local function getExecutorName()
	local ok, name = pcall(function()
		if typeof(identifyexecutor) == "function" then return identifyexecutor() end
		return nil
	end)
	if ok and name ~= nil then return tostring(name) end
	return "unavailable"
end

local function getDeviceLabel()
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return "Mobile / touch"
	elseif UserInputService.TouchEnabled then
		return "Touch + keyboard"
	end
	return "Desktop"
end

--== UI primitives ==
local function corner(object, radius)
	local element = Instance.new("UICorner")
	element.CornerRadius = UDim.new(0, radius or 12)
	element.Parent = object
	return element
end

local function stroke(object, color, thickness, transparency)
	local element = Instance.new("UIStroke")
	element.Color = color or THEME.stroke
	element.Thickness = thickness or 1
	element.Transparency = transparency or 0
	element.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	element.Parent = object
	return element
end

local function gradient(object, colorA, colorB, rotation)
	local element = Instance.new("UIGradient")
	element.Color = ColorSequence.new(colorA, colorB)
	element.Rotation = rotation or 0
	element.Parent = object
	return element
end

local function makeLabel(parent, text, textSize, color, font, alignment)
	local element = Instance.new("TextLabel")
	element.BackgroundTransparency = 1
	element.Text = tostring(text or "")
	element.TextSize = textSize or 12
	element.TextColor3 = color or THEME.text
	element.Font = font or Enum.Font.Gotham
	element.TextXAlignment = alignment or Enum.TextXAlignment.Left
	element.TextYAlignment = Enum.TextYAlignment.Center
	element.RichText = false
	element.TextWrapped = false
	element.Parent = parent
	return element
end

local function makeButton(parent, text, options)
	options = options or {}
	local button = Instance.new("TextButton")
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.BackgroundColor3 = options.bg or THEME.panel2
	button.Text = tostring(text or "")
	button.Font = options.font or Enum.Font.GothamSemibold
	button.TextSize = options.textSize or 11
	button.TextColor3 = options.color or THEME.text
	button.Size = options.size or UDim2.new(0, 110, 0, 32)
	button.TextTruncate = Enum.TextTruncate.AtEnd
	button.Parent = parent
	corner(button, options.radius or 9)
	local border = stroke(button, options.strokeColor or THEME.strokeSoft, 1)
	if options.accent then
		button.BackgroundColor3 = theme.accent2
		border.Color = theme.accent
		bindAccent(border, "Color")
		bindAccent(button, "BackgroundColor3", "accent2")
	end
	if options.onClick then
		button.Activated:Connect(function()
			task.spawn(function()
				local ok, err = pcall(options.onClick)
				if not ok then captureError("button", err) end
			end)
		end)
	end
	if options.hover ~= false then
		button.MouseEnter:Connect(function()
			TweenService:Create(button, TweenInfo.new(0.1), { BackgroundTransparency = 0.16 }):Play()
		end)
		button.MouseLeave:Connect(function()
			TweenService:Create(button, TweenInfo.new(0.1), { BackgroundTransparency = 0 }):Play()
		end)
	end
	return button
end

local function makeSwitch(parent, state, width)
	local track = Instance.new("TextButton")
	track.AutoButtonColor = false
	track.BorderSizePixel = 0
	track.Text = ""
	track.BackgroundColor3 = THEME.panel3
	track.Size = UDim2.fromOffset(width or 38, math.floor((width or 38) * 0.52))
	track.Parent = parent
	corner(track, 999)
	stroke(track, THEME.stroke, 1)

	local knobSize = math.floor((width or 38) * 0.42)
	local knob = Instance.new("Frame")
	knob.Size = UDim2.fromOffset(knobSize, knobSize)
	knob.AnchorPoint = Vector2.new(0, 0.5)
	knob.Position = UDim2.new(0, 2, 0.5, 0)
	knob.BackgroundColor3 = THEME.white
	knob.BorderSizePixel = 0
	knob.Parent = track
	corner(knob, 999)

	local function render(animate)
		local isOn = state:Get() == true
		local targetColor = isOn and theme.accent or THEME.panel3
		local targetPosition = isOn and UDim2.new(1, -(knobSize + 2), 0.5, 0) or UDim2.new(0, 2, 0.5, 0)
		if animate and hub.running then
			local info = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			TweenService:Create(track, info, { BackgroundColor3 = targetColor }):Play()
			TweenService:Create(knob, info, { Position = targetPosition }):Play()
		else
			track.BackgroundColor3 = targetColor
			knob.Position = targetPosition
		end
	end

	state:OnChanged(function()
		render(true)
	end)
	render(false)
	track.Activated:Connect(function()
		state:Toggle()
	end)

	return { track = track, knob = knob, render = render }
end

local function makeToggleRow(parent, title, description, state)
	local row = Instance.new("Frame")
	row.BackgroundColor3 = THEME.panel2
	row.BackgroundTransparency = 0.25
	row.BorderSizePixel = 0
	row.Size = UDim2.new(1, 0, 0, description and 48 or 38)
	row.Parent = parent
	corner(row, 10)
	stroke(row, THEME.strokeSoft, 1, 0.4)

	local titleLabel = makeLabel(row, title, 12, THEME.text, Enum.Font.GothamSemibold)
	titleLabel.Position = UDim2.fromOffset(10, description and 6 or 9)
	titleLabel.Size = UDim2.new(1, -68, 0, 18)

	if description then
		local descriptionLabel = makeLabel(row, description, 9.5, THEME.dim)
		descriptionLabel.Position = UDim2.fromOffset(10, 24)
		descriptionLabel.Size = UDim2.new(1, -68, 0, 16)
		descriptionLabel.TextTruncate = Enum.TextTruncate.AtEnd
	end

	local toggle = makeSwitch(row, state)
	toggle.track.AnchorPoint = Vector2.new(1, 0.5)
	toggle.track.Position = UDim2.new(1, -10, 0.5, 0)
	return row
end

local function makeChipGrid(parent, options, columns, rowHeight)
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel = 0
	local rows = math.ceil(#options / columns)
	holder.Size = UDim2.new(1, 0, 0, rows * rowHeight + math.max(0, rows - 1) * 6)
	holder.Parent = parent

	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(1 / columns, -6, 0, rowHeight)
	grid.CellPadding = UDim2.new(0, 6, 0, 6)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.FillDirection = Enum.FillDirection.Horizontal
	grid.Parent = holder
	return holder
end

local function makeSelectChips(parent, options, state, columns)
	local holder = makeChipGrid(parent, options, columns or 4, 30)
	local chips = {}
	local function render()
		for value, chip in pairs(chips) do
			local selected = state:Get() == value
			chip.BackgroundColor3 = selected and theme.accent2 or THEME.panel2
			chip.TextColor3 = selected and THEME.white or THEME.muted
			chip.BackgroundTransparency = selected and 0 or 0.3
		end
	end
	for index, value in ipairs(options) do
		local chip = Instance.new("TextButton")
		chip.AutoButtonColor = false
		chip.BorderSizePixel = 0
		chip.Text = tostring(value)
		chip.Font = Enum.Font.GothamSemibold
		chip.TextSize = 10
		chip.TextColor3 = THEME.muted
		chip.BackgroundColor3 = THEME.panel2
		chip.BackgroundTransparency = 0.3
		chip.LayoutOrder = index
		chip.TextTruncate = Enum.TextTruncate.AtEnd
		chip.Parent = holder
		corner(chip, 8)
		stroke(chip, THEME.strokeSoft, 1, 0.4)
		chip.Activated:Connect(function()
			state:Set(value)
		end)
		chips[value] = chip
	end
	state:OnChanged(render)
	render()
	return holder
end

local function makeMultiChips(parent, options, state, columns)
	local holder = makeChipGrid(parent, options, columns or 4, 30)
	local chips = {}
	local function render()
		local selected = state:Get() or {}
		for value, chip in pairs(chips) do
			local isOn = selected[value] == true
			chip.BackgroundColor3 = isOn and theme.accent2 or THEME.panel2
			chip.TextColor3 = isOn and THEME.white or THEME.muted
			chip.BackgroundTransparency = isOn and 0 or 0.3
		end
	end
	for index, value in ipairs(options) do
		local chip = Instance.new("TextButton")
		chip.AutoButtonColor = false
		chip.BorderSizePixel = 0
		chip.Text = tostring(value)
		chip.Font = Enum.Font.GothamSemibold
		chip.TextSize = 10
		chip.TextColor3 = THEME.muted
		chip.BackgroundColor3 = THEME.panel2
		chip.BackgroundTransparency = 0.3
		chip.LayoutOrder = index
		chip.Parent = holder
		corner(chip, 8)
		stroke(chip, THEME.strokeSoft, 1, 0.4)
		chip.Activated:Connect(function()
			local current = state:Get() or {}
			local nextValue = {}
			for key, flag in pairs(current) do nextValue[key] = flag end
			nextValue[value] = not (current[value] == true)
			state:Set(nextValue)
		end)
		chips[value] = chip
	end
	state:OnChanged(render)
	render()
	return holder
end

--== Slider (single shared input connection, cleaned up on unload) ==
local activeSlider = nil

local function makeSlider(parent, spec)
	local row = Instance.new("Frame")
	row.BackgroundColor3 = THEME.panel2
	row.BackgroundTransparency = 0.25
	row.BorderSizePixel = 0
	row.Size = UDim2.new(1, 0, 0, 46)
	row.Parent = parent
	corner(row, 10)
	stroke(row, THEME.strokeSoft, 1, 0.4)

	local title = makeLabel(row, spec.title, 11, THEME.text, Enum.Font.GothamSemibold)
	title.Position = UDim2.fromOffset(10, 4)
	title.Size = UDim2.new(1, -120, 0, 16)

	local valueLabel = makeLabel(row, "", 10.5, theme.accent, Enum.Font.GothamBold, Enum.TextXAlignment.Right)
	valueLabel.Position = UDim2.new(1, -112, 0, 4)
	valueLabel.Size = UDim2.fromOffset(102, 16)
	bindAccent(valueLabel, "TextColor3")

	local bar = Instance.new("Frame")
	bar.BackgroundColor3 = THEME.panel3
	bar.BorderSizePixel = 0
	bar.Position = UDim2.fromOffset(10, 27)
	bar.Size = UDim2.new(1, -20, 0, 7)
	bar.Parent = row
	corner(bar, 4)

	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = theme.accent
	fill.BorderSizePixel = 0
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.Parent = bar
	corner(fill, 4)
	bindAccent(fill, "BackgroundColor3")

	local hit = Instance.new("TextButton")
	hit.Text = ""
	hit.AutoButtonColor = false
	hit.BackgroundTransparency = 1
	hit.Position = UDim2.fromOffset(0, 17)
	hit.Size = UDim2.new(1, 0, 0, 26)
	hit.Parent = row

	local function apply(value, fromUser)
		local span = spec.max - spec.min
		local safeSpan = span > 0 and span or 1
		local stepped = spec.min + math.floor((value - spec.min) / spec.step + 0.5) * spec.step
		local clamped = clamp(stepped, spec.min, spec.max)
		local alpha = clamp((clamped - spec.min) / safeSpan, 0, 1)
		fill.Size = UDim2.new(alpha, 0, 1, 0)
		valueLabel.Text = tostring(round(clamped)) .. (spec.suffix or "")
		if fromUser then
			spec.state:Set(round(clamped))
		end
	end

	local function updateFromX(posX)
		local absolute = bar.AbsolutePosition
		local width = math.max(bar.AbsoluteSize.X, 1)
		local alpha = clamp((posX - absolute.X) / width, 0, 1)
		apply(spec.min + alpha * (spec.max - spec.min), true)
	end

	hit.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			activeSlider = { update = updateFromX }
			updateFromX(input.Position.X)
		end
	end)

	spec.state:OnChanged(function(value)
		apply(tonumber(value) or spec.min, false)
	end)
	apply(tonumber(spec.state:Get()) or spec.min, false)
	return row
end

--== Log view ==
local LEVEL_COLORS = {
	info = THEME.muted,
	success = THEME.success,
	warn = THEME.warning,
	error = THEME.error,
	accent = theme.accent,
}

local function makeLogView(parent, height)
	local frame = Instance.new("ScrollingFrame")
	frame.BackgroundColor3 = THEME.inset
	frame.BorderSizePixel = 0
	frame.Size = UDim2.new(1, 0, 0, height or 120)
	frame.ScrollBarThickness = 3
	frame.ScrollBarImageColor3 = theme.accent
	frame.CanvasSize = UDim2.new(0, 0, 0, 0)
	frame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	frame.ScrollingDirection = Enum.ScrollingDirection.Y
	frame.Parent = parent
	corner(frame, 10)
	stroke(frame, THEME.strokeSoft, 1, 0.5)

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.PaddingTop = UDim.new(0, 6)
	pad.PaddingBottom = UDim.new(0, 6)
	pad.Parent = frame

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 3)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = frame

	local view = { frame = frame, count = 0 }

	local function scrollToEnd()
		task.defer(function()
			if frame.Parent then
				frame.CanvasPosition = Vector2.new(0, math.max(0, frame.AbsoluteCanvasSize.Y))
			end
		end)
	end

	function view:Push(entry)
		local row = Instance.new("Frame")
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, 0, 0, 16)
		row.Parent = frame

		local dot = Instance.new("Frame")
		dot.BackgroundColor3 = LEVEL_COLORS[entry.level] or THEME.muted
		dot.BorderSizePixel = 0
		dot.Size = UDim2.fromOffset(5, 5)
		dot.Position = UDim2.fromOffset(2, 6)
		dot.Parent = row
		corner(dot, 999)

		local text = makeLabel(row, entry.text, 9.5, LEVEL_COLORS[entry.level] or THEME.muted)
		text.Position = UDim2.fromOffset(12, 0)
		text.Size = UDim2.new(1, -12, 1, 0)
		text.TextTruncate = Enum.TextTruncate.AtEnd

		self.count = self.count + 1
		if self.count > 140 then
			local oldest = frame:FindFirstChild("Frame")
			if oldest then
				oldest:Destroy()
				self.count = self.count - 1
			end
		end
		scrollToEnd()
	end

	function view:Clear()
		for _, child in ipairs(frame:GetChildren()) do
			if child:IsA("Frame") then child:Destroy() end
		end
		self.count = 0
	end

	table.insert(logViews, view)

	local start = math.max(1, #logHistory - 60)
	for index = start, #logHistory do
		pcall(function()
			view:Push(logHistory[index])
		end)
	end
	return view
end

--== Cards ==
local pages = {}
local searchables = {}
local cardsByPage = {}

local function makeCard(pageName, title, glyph, description)
	local page = pages[pageName]
	if not page then return nil end

	local card = Instance.new("Frame")
	card.Name = title
	card.BackgroundColor3 = THEME.panel
	card.BorderSizePixel = 0
	card.Size = UDim2.new(1, 0, 0, 0)
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.Parent = page
	corner(card, 14)
	stroke(card, THEME.strokeSoft, 1)

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 12)
	pad.PaddingRight = UDim.new(0, 12)
	pad.PaddingTop = UDim.new(0, 10)
	pad.PaddingBottom = UDim.new(0, 12)
	pad.Parent = card

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 7)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = card

	local head = Instance.new("Frame")
	head.BackgroundTransparency = 1
	head.Size = UDim2.new(1, 0, 0, 20)
	head.Parent = card

	local icon = makeLabel(head, glyph or "✦", 13, theme.accent, Enum.Font.GothamBold)
	icon.Position = UDim2.fromOffset(0, 0)
	icon.Size = UDim2.fromOffset(18, 20)
	bindAccent(icon, "TextColor3")

	local titleLabel = makeLabel(head, title, 12, THEME.text, Enum.Font.GothamBold)
	titleLabel.Position = UDim2.fromOffset(20, 0)
	titleLabel.Size = UDim2.new(1, -20, 0, 20)

	if description then
		local info = makeLabel(card, description, 9.5, THEME.dim)
		info.Size = UDim2.new(1, 0, 0, 15)
		info.TextTruncate = Enum.TextTruncate.AtEnd
	end

	local body = Instance.new("Frame")
	body.BackgroundTransparency = 1
	body.BorderSizePixel = 0
	body.Size = UDim2.new(1, 0, 0, 0)
	body.AutomaticSize = Enum.AutomaticSize.Y
	body.Parent = card

	local bodyLayout = Instance.new("UIListLayout")
	bodyLayout.Padding = UDim.new(0, 7)
	bodyLayout.SortOrder = Enum.SortOrder.LayoutOrder
	bodyLayout.Parent = body

	table.insert(searchables, { page = pageName, title = title, card = card })
	cardsByPage[pageName] = cardsByPage[pageName] or {}
	table.insert(cardsByPage[pageName], card)

	return { frame = card, body = body, head = head }
end

local function makeValueRow(parent, title, valueColor)
	local row = Instance.new("Frame")
	row.BackgroundColor3 = THEME.panel2
	row.BackgroundTransparency = 0.35
	row.BorderSizePixel = 0
	row.Size = UDim2.new(1, 0, 0, 26)
	row.Parent = parent
	corner(row, 8)

	local nameLabel = makeLabel(row, title, 10.5, THEME.muted)
	nameLabel.Position = UDim2.fromOffset(10, 0)
	nameLabel.Size = UDim2.new(0.4, -10, 1, 0)
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd

	local valueLabel = makeLabel(row, "N/A", 10.5, valueColor or THEME.text, Enum.Font.GothamSemibold)
	valueLabel.Position = UDim2.new(0.4, 0, 0, 0)
	valueLabel.Size = UDim2.new(0.6, -10, 1, 0)
	valueLabel.TextXAlignment = Enum.TextXAlignment.Right
	valueLabel.TextTruncate = Enum.TextTruncate.AtEnd

	return valueLabel
end

--== Window shell: exactly one ScreenGui for the whole interface ==
local guiParent = LocalPlayer:WaitForChild("PlayerGui")
if typeof(gethui) == "function" then
	local ok, hidden = pcall(gethui)
	if ok and hidden and hidden ~= nil then
		guiParent = hidden
	end
end

local previousGui = guiParent:FindFirstChild("MSO_Ultra")
if previousGui then previousGui:Destroy() end
cleanupStaleEsp()

local screen = Instance.new("ScreenGui")
screen.Name = "MSO_Ultra"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
screen.DisplayOrder = 1000
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.Parent = guiParent

local UI = {
	navLabels = {},
	quickTiles = {},
	home = {},
	pages = {},
}

local viewport = (workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize)
	or Vector2.new(1280, 720)

local glow = Instance.new("Frame")
glow.Name = "NeonGlow"
glow.AnchorPoint = Vector2.new(0.5, 0.5)
glow.Position = UDim2.fromScale(0.5, 0.5)
glow.Size = UDim2.fromScale(0.6, 0.6)
glow.BackgroundColor3 = theme.accent
glow.BackgroundTransparency = 0.93
glow.BorderSizePixel = 0
glow.ZIndex = 1
glow.Parent = screen
corner(glow, 30)
bindAccent(glow, "BackgroundColor3")

local root = Instance.new("Frame")
root.Name = "MainWindow"
root.AnchorPoint = Vector2.new(0.5, 0.5)
root.Position = UDim2.fromScale(0.5, 0.5)
root.BackgroundColor3 = THEME.bg
root.BorderSizePixel = 0
root.ZIndex = 2
root.Parent = screen
corner(root, 20)
gradient(root, Color3.fromHex("181022"), Color3.fromHex("0A0810"), 35)

local rootStroke = stroke(root, theme.accent, 1.4, 0.55)
bindAccent(rootStroke, "Color")

local rootScale = Instance.new("UIScale")
rootScale.Scale = 1
rootScale.Parent = root

UI.root = root
UI.glow = glow
UI.rootScale = rootScale

--== Sidebar ==
local sidebar = Instance.new("Frame")
sidebar.Name = "Sidebar"
sidebar.BackgroundColor3 = THEME.panel
sidebar.BorderSizePixel = 0
sidebar.Size = UDim2.new(0, 218, 1, 0)
sidebar.Parent = root
corner(sidebar, 18)
gradient(sidebar, Color3.fromHex("1B1327"), Color3.fromHex("0E0A15"), 90)
UI.sidebar = sidebar

local brand = Instance.new("Frame")
brand.Name = "Brand"
brand.BackgroundColor3 = THEME.panel2
brand.BorderSizePixel = 0
brand.Position = UDim2.fromOffset(10, 10)
brand.Size = UDim2.new(1, -20, 0, 104)
brand.Parent = sidebar
corner(brand, 16)
local brandStroke = stroke(brand, theme.accent, 1.2, 0.45)
bindAccent(brandStroke, "Color")
gradient(brand, Color3.fromHex("2B1332"), Color3.fromHex("150D1D"), 70)

local brandTop = makeLabel(brand, "MALAM SAMA", 10.5, THEME.text, Enum.Font.GothamBold, Enum.TextXAlignment.Center)
brandTop.Position = UDim2.new(0, 0, 0, 12)
brandTop.Size = UDim2.new(1, 0, 0, 14)

local brandMain = makeLabel(brand, "OPAH", 27, theme.accent, Enum.Font.GothamBlack, Enum.TextXAlignment.Center)
brandMain.Position = UDim2.new(0, 0, 0, 26)
brandMain.Size = UDim2.new(1, 0, 0, 34)
bindAccent(brandMain, "TextColor3")

local brandVer = makeLabel(brand, "v" .. VERSION .. "  " .. VERSION_TAG, 8.5, THEME.muted, Enum.Font.GothamSemibold, Enum.TextXAlignment.Center)
brandVer.Position = UDim2.new(0, 0, 0, 64)
brandVer.Size = UDim2.new(1, 0, 0, 12)

local brandTag = makeLabel(brand, "ROBSCRIPT TEAM", 8, THEME.dim, Enum.Font.Gotham, Enum.TextXAlignment.Center)
brandTag.Position = UDim2.new(0, 0, 0, 80)
brandTag.Size = UDim2.new(1, 0, 0, 12)

UI.brand = brand
UI.brandTop = brandTop
UI.brandMain = brandMain
UI.brandVer = brandVer
UI.brandTag = brandTag

--== Navigation ==
local PAGE_ORDER = { "Home", "Diagnostics", "Visuals", "Automation", "Teleport", "Settings" }
local PAGE_ICONS = { Home = "⌂", Diagnostics = "◈", Visuals = "◉", Automation = "⚙", Teleport = "⌖", Settings = "☰" }
local navButtons = {}
local currentPage = nil

local navHolder = Instance.new("Frame")
navHolder.Name = "Navigation"
navHolder.BackgroundTransparency = 1
navHolder.Position = UDim2.fromOffset(8, 122)
navHolder.Size = UDim2.new(1, -16, 1, -220)
navHolder.Parent = sidebar

local navLayout = Instance.new("UIListLayout")
navLayout.Padding = UDim.new(0, 6)
navLayout.SortOrder = Enum.SortOrder.LayoutOrder
navLayout.Parent = navHolder

for index, name in ipairs(PAGE_ORDER) do
	local button = Instance.new("TextButton")
	button.Name = name
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.Text = ""
	button.BackgroundColor3 = THEME.panel2
	button.BackgroundTransparency = 1
	button.Size = UDim2.new(1, 0, 0, 44)
	button.LayoutOrder = index
	button.Parent = navHolder
	corner(button, 11)

	local border = stroke(button, THEME.strokeSoft, 1, 0.5)

	local bar = Instance.new("Frame")
	bar.BackgroundColor3 = theme.accent
	bar.BorderSizePixel = 0
	bar.Position = UDim2.fromOffset(4, 13)
	bar.Size = UDim2.fromOffset(3, 18)
	bar.Visible = false
	bar.Parent = button
	corner(bar, 999)
	bindAccent(bar, "BackgroundColor3")

	local icon = makeLabel(button, PAGE_ICONS[name], 16, THEME.muted, Enum.Font.GothamBold, Enum.TextXAlignment.Center)
	icon.Position = UDim2.fromOffset(12, 0)
	icon.Size = UDim2.fromOffset(24, 44)

	local text = makeLabel(button, name, 11.5, THEME.muted, Enum.Font.GothamSemibold)
	text.Position = UDim2.fromOffset(44, 0)
	text.Size = UDim2.new(1, -52, 0, 44)

	button.Activated:Connect(function()
		if selectPage then selectPage(name) end
	end)

	navButtons[name] = button
	UI.navLabels[name] = { button = button, icon = icon, text = text, bar = bar, border = border }
end

local function setActiveNav(name)
	for pageName, visuals in pairs(UI.navLabels) do
		local isActive = pageName == name
		visuals.button.BackgroundColor3 = isActive and theme.accent2 or THEME.panel2
		visuals.button.BackgroundTransparency = isActive and 0.05 or 1
		visuals.icon.TextColor3 = isActive and THEME.white or THEME.muted
		visuals.text.TextColor3 = isActive and THEME.white or THEME.muted
		visuals.bar.Visible = isActive
		visuals.border.Transparency = isActive and 0.2 or 0.6
	end
end

table.insert(themeHooks, function()
	if currentPage then setActiveNav(currentPage) end
end)

--== Profile card ==
local profile = Instance.new("Frame")
profile.Name = "Profile"
profile.AnchorPoint = Vector2.new(0, 1)
profile.Position = UDim2.new(0, 10, 1, -10)
profile.Size = UDim2.new(1, -20, 0, 76)
profile.BackgroundColor3 = THEME.panel2
profile.BorderSizePixel = 0
profile.Parent = sidebar
corner(profile, 14)
stroke(profile, THEME.strokeSoft, 1, 0.4)

local avatarFrame = Instance.new("Frame")
avatarFrame.BackgroundColor3 = THEME.panel3
avatarFrame.BorderSizePixel = 0
avatarFrame.Position = UDim2.fromOffset(9, 18)
avatarFrame.Size = UDim2.fromOffset(40, 40)
avatarFrame.Parent = profile
corner(avatarFrame, 999)
stroke(avatarFrame, theme.accent, 1, 0.4)

local avatarInitials = makeLabel(avatarFrame, string.upper(string.sub(LocalPlayer.DisplayName or LocalPlayer.Name or "P", 1, 2)), 13, THEME.muted, Enum.Font.GothamBold, Enum.TextXAlignment.Center)
avatarInitials.Size = UDim2.fromScale(1, 1)

local avatarImage = Instance.new("ImageLabel")
avatarImage.BackgroundTransparency = 1
avatarImage.Size = UDim2.fromScale(1, 1)
avatarImage.Image = ""
avatarImage.Visible = false
avatarImage.Parent = avatarFrame
corner(avatarImage, 999)

local profileName = makeLabel(profile, LocalPlayer.DisplayName or LocalPlayer.Name or "Player", 11.5, THEME.text, Enum.Font.GothamBold)
profileName.Position = UDim2.fromOffset(58, 18)
profileName.Size = UDim2.new(1, -66, 0, 16)
profileName.TextTruncate = Enum.TextTruncate.AtEnd

local profileHandle = makeLabel(profile, "@" .. tostring(LocalPlayer.Name or "unknown"), 9, THEME.dim)
profileHandle.Position = UDim2.fromOffset(58, 34)
profileHandle.Size = UDim2.new(1, -66, 0, 14)
profileHandle.TextTruncate = Enum.TextTruncate.AtEnd

local profileDot = Instance.new("Frame")
profileDot.BackgroundColor3 = THEME.success
profileDot.BorderSizePixel = 0
profileDot.Position = UDim2.fromOffset(58, 52)
profileDot.Size = UDim2.fromOffset(6, 6)
profileDot.Parent = profile
corner(profileDot, 999)

local profileState = makeLabel(profile, "session active", 8.5, THEME.dim)
profileState.Position = UDim2.fromOffset(69, 46)
profileState.Size = UDim2.new(1, -78, 0, 16)

UI.profile = profile
UI.avatarImage = avatarImage
UI.avatarInitials = avatarInitials
UI.profileName = profileName
UI.profileHandle = profileHandle
UI.profileState = profileState
UI.profileDot = profileDot

--== Main column ==
local main = Instance.new("Frame")
main.Name = "Main"
main.BackgroundTransparency = 1
main.Position = UDim2.new(0, 218, 0, 0)
main.Size = UDim2.new(1, -218, 1, 0)
main.Parent = root
UI.main = main

local header = Instance.new("Frame")
header.Name = "Header"
header.BackgroundTransparency = 1
header.Position = UDim2.fromOffset(14, 8)
header.Size = UDim2.new(1, -28, 0, 46)
header.Parent = main
UI.header = header

local headerIcon = makeLabel(header, PAGE_ICONS.Home, 17, theme.accent, Enum.Font.GothamBold)
headerIcon.Position = UDim2.fromOffset(2, 0)
headerIcon.Size = UDim2.fromOffset(24, 46)
bindAccent(headerIcon, "TextColor3")

local pageTitle = makeLabel(header, "Home", 18, THEME.text, Enum.Font.GothamBold)
pageTitle.Position = UDim2.fromOffset(30, 0)
pageTitle.Size = UDim2.new(0.4, 0, 0, 46)
UI.pageTitle = pageTitle
UI.headerIcon = headerIcon

local searchWrap = Instance.new("Frame")
searchWrap.Name = "Search"
searchWrap.BackgroundColor3 = THEME.panel2
searchWrap.BackgroundTransparency = 0.15
searchWrap.BorderSizePixel = 0
searchWrap.AnchorPoint = Vector2.new(1, 0)
searchWrap.Position = UDim2.new(1, -88, 0, 5)
searchWrap.Size = UDim2.new(0, 300, 0, 36)
searchWrap.Parent = header
corner(searchWrap, 18)
stroke(searchWrap, THEME.strokeSoft, 1, 0.25)
UI.searchWrap = searchWrap

local searchGlyph = makeLabel(searchWrap, "⌕", 15, THEME.dim, Enum.Font.GothamBold, Enum.TextXAlignment.Center)
searchGlyph.Position = UDim2.fromOffset(8, 0)
searchGlyph.Size = UDim2.fromOffset(20, 36)

local searchBox = Instance.new("TextBox")
searchBox.Name = "SearchInput"
searchBox.BackgroundTransparency = 1
searchBox.BorderSizePixel = 0
searchBox.ClearTextOnFocus = false
searchBox.PlaceholderText = "Search pages and features..."
searchBox.PlaceholderColor3 = THEME.dim
searchBox.Font = Enum.Font.Gotham
searchBox.TextSize = 11
searchBox.TextColor3 = THEME.text
searchBox.Text = ""
searchBox.TextXAlignment = Enum.TextXAlignment.Left
searchBox.Position = UDim2.fromOffset(30, 0)
searchBox.Size = UDim2.new(1, -40, 1, 0)
searchBox.Parent = searchWrap
UI.searchBox = searchBox

local minimizeButton = makeButton(header, "—", {
	size = UDim2.fromOffset(30, 30),
	textSize = 14,
	bg = THEME.panel2,
	color = THEME.text,
	onClick = function()
		if UI.toggleMinimized then UI.toggleMinimized() end
	end,
})
minimizeButton.AnchorPoint = Vector2.new(1, 0)
minimizeButton.Position = UDim2.new(1, -74, 0, 8)
UI.minimizeButton = minimizeButton

local closeButton = makeButton(header, "✕", {
	size = UDim2.fromOffset(30, 30),
	textSize = 12,
	bg = THEME.panel2,
	color = theme.accent,
	onClick = function()
		if setUIVisible then setUIVisible(false) end
	end,
})
closeButton.AnchorPoint = Vector2.new(1, 0)
closeButton.Position = UDim2.new(1, -38, 0, 8)
UI.closeButton = closeButton

local pageHost = Instance.new("Frame")
pageHost.Name = "Pages"
pageHost.BackgroundTransparency = 1
pageHost.Position = UDim2.fromOffset(14, 62)
pageHost.Size = UDim2.new(1, -28, 1, -76)
pageHost.Parent = main
UI.pageHost = pageHost

local function createPage(name)
	local page = Instance.new("ScrollingFrame")
	page.Name = name .. "Page"
	page.BackgroundTransparency = 1
	page.BorderSizePixel = 0
	page.Size = UDim2.fromScale(1, 1)
	page.ScrollBarThickness = 4
	page.ScrollBarImageColor3 = theme.accent
	page.CanvasSize = UDim2.new(0, 0, 0, 0)
	page.AutomaticCanvasSize = Enum.AutomaticSize.Y
	page.ScrollingDirection = Enum.ScrollingDirection.Y
	page.Visible = false
	page.Parent = pageHost
	corner(page, 10)

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 10)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = page

	local pad = Instance.new("UIPadding")
	pad.PaddingBottom = UDim.new(0, 16)
	pad.PaddingRight = UDim.new(0, 6)
	pad.Parent = page

	pages[name] = page
	UI.pages[name] = page
	return page
end

for _, name in ipairs(PAGE_ORDER) do
	createPage(name)
end

local function resetPageScroll(name)
	local page = pages[name]
	if page then
		pcall(function()
			page.CanvasPosition = Vector2.new(0, 0)
		end)
	end
end

selectPage = function(name)
	if not pages[name] then return end
	if currentPage and pages[currentPage] then
		pages[currentPage].Visible = false
	end
	currentPage = name
	pages[name].Visible = true
	pageTitle.Text = name
	headerIcon.Text = PAGE_ICONS[name] or "✦"
	setActiveNav(name)
	resetPageScroll(name)
	if UI.applySearch then UI.applySearch(searchBox.Text) end
end

--== Avatar (real Roblox headshot; falls back to initials) ==
task.spawn(function()
	local ok, image = pcall(function()
		return Players:GetUserThumbnailAsync(LocalPlayer.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
	end)
	if ok and type(image) == "string" and image ~= "" and avatarImage.Parent and avatarFrame.Parent then
		avatarImage.Image = image
		avatarImage.Visible = true
		avatarInitials.Visible = false
		if UI.home.bannerAvatar then
			UI.home.bannerAvatar.Image = image
			UI.home.bannerAvatar.Visible = true
			if UI.home.bannerAvatarFallback then
				UI.home.bannerAvatarFallback.Visible = false
			end
		end
	end
end)

--== Home dashboard ==
local function makeNote(parent, text, color)
	local note = makeLabel(parent, text, 9.5, color or THEME.dim)
	note.TextWrapped = true
	note.TextYAlignment = Enum.TextYAlignment.Top
	note.Size = UDim2.new(1, 0, 0, 0)
	note.AutomaticSize = Enum.AutomaticSize.Y
	return note
end

local function makeButtonRow(parent, specs)
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 32)
	row.Parent = parent
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = row

	for index, spec in ipairs(specs) do
		local button = makeButton(row, spec.text, {
			size = spec.width or UDim2.new(0.5, -4, 1, 0),
			accent = spec.accent,
			bg = spec.bg or THEME.panel2,
			color = spec.color,
			onClick = spec.onClick,
		})
		button.LayoutOrder = index
	end
	return row
end

local function buildHome()
	local homePage = pages.Home

local banner = Instance.new("Frame")
banner.Name = "WelcomeBanner"
banner.BackgroundColor3 = THEME.panel2
banner.BorderSizePixel = 0
banner.Size = UDim2.new(1, 0, 0, 118)
banner.LayoutOrder = 1
banner.Parent = homePage
corner(banner, 16)
local bannerStroke = stroke(banner, theme.accent, 1, 0.6)
bindAccent(bannerStroke, "Color")
gradient(banner, Color3.fromHex("2B0F35"), Color3.fromHex("120D1A"), 20)

local bannerPortrait = Instance.new("ImageLabel")
bannerPortrait.Name = "Portrait"
bannerPortrait.BackgroundColor3 = THEME.panel3
bannerPortrait.BorderSizePixel = 0
bannerPortrait.Position = UDim2.fromOffset(12, 12)
bannerPortrait.Size = UDim2.new(0, 150, 1, -24)
bannerPortrait.ScaleType = Enum.ScaleType.Crop
bannerPortrait.Image = ""
bannerPortrait.Visible = false
bannerPortrait.Parent = banner
corner(bannerPortrait, 12)
stroke(bannerPortrait, theme.accent, 1, 0.5)

local bannerPortraitFallback = Instance.new("Frame")
bannerPortraitFallback.BackgroundColor3 = THEME.panel3
bannerPortraitFallback.BorderSizePixel = 0
bannerPortraitFallback.Position = UDim2.fromOffset(12, 12)
bannerPortraitFallback.Size = UDim2.new(0, 150, 1, -24)
bannerPortraitFallback.Parent = banner
corner(bannerPortraitFallback, 12)
stroke(bannerPortraitFallback, THEME.strokeSoft, 1, 0.3)
gradient(bannerPortraitFallback, Color3.fromHex("33203F"), Color3.fromHex("1A1226"), 45)
local fallbackGlyph = makeLabel(bannerPortraitFallback, "☾", 40, theme.accent, Enum.Font.GothamBold, Enum.TextXAlignment.Center)
fallbackGlyph.Position = UDim2.new(0, 0, 0, 18)
fallbackGlyph.Size = UDim2.new(1, 0, 0, 46)
local fallbackText = makeLabel(bannerPortraitFallback, "OPAH", 10, THEME.muted, Enum.Font.GothamBold, Enum.TextXAlignment.Center)
fallbackText.Position = UDim2.new(0, 0, 0, 66)
fallbackText.Size = UDim2.new(1, 0, 0, 14)

local bannerText = Instance.new("Frame")
bannerText.BackgroundTransparency = 1
bannerText.Position = UDim2.fromOffset(178, 12)
bannerText.Size = UDim2.new(1, -396, 1, -24)
bannerText.Parent = banner

local welcome = makeLabel(bannerText, "Welcome back!", 22, THEME.text, Enum.Font.GothamBold)
welcome.Position = UDim2.fromOffset(0, 6)
welcome.Size = UDim2.new(1, 0, 0, 30)

local bannerSub = makeLabel(bannerText, "Malam Sama Opah", 14.5, theme.accent, Enum.Font.GothamBold)
bannerSub.Position = UDim2.fromOffset(0, 34)
bannerSub.Size = UDim2.new(1, 0, 0, 22)
bindAccent(bannerSub, "TextColor3")

local bannerNote = makeLabel(bannerText, "Good luck, jangan sampai ketahuan ya...", 10, THEME.muted)
bannerNote.Position = UDim2.fromOffset(0, 58)
bannerNote.Size = UDim2.new(1, 0, 0, 16)
bannerNote.TextTruncate = Enum.TextTruncate.AtEnd

local mobileStatus = makeLabel(bannerText, "Opah: N/A", 10, THEME.muted, Enum.Font.GothamSemibold)
mobileStatus.Position = UDim2.fromOffset(0, 76)
mobileStatus.Size = UDim2.new(1, 0, 0, 16)
mobileStatus.Visible = false

local bannerPill = Instance.new("Frame")
bannerPill.Name = "OpahStatus"
bannerPill.BackgroundColor3 = THEME.panel
bannerPill.BackgroundTransparency = 0.1
bannerPill.BorderSizePixel = 0
bannerPill.AnchorPoint = Vector2.new(1, 0)
bannerPill.Position = UDim2.new(1, -14, 0, 14)
bannerPill.Size = UDim2.fromOffset(196, 66)
bannerPill.Parent = banner
corner(bannerPill, 12)
local pillStroke = stroke(bannerPill, theme.accent, 1, 0.55)
bindAccent(pillStroke, "Color")

local pillDot = Instance.new("Frame")
pillDot.BackgroundColor3 = THEME.success
pillDot.BorderSizePixel = 0
pillDot.Position = UDim2.fromOffset(12, 18)
pillDot.Size = UDim2.fromOffset(8, 8)
pillDot.Parent = bannerPill
corner(pillDot, 999)

local pillState = makeLabel(bannerPill, "Opah: N/A", 12, THEME.text, Enum.Font.GothamBold)
pillState.Position = UDim2.fromOffset(28, 10)
pillState.Size = UDim2.new(1, -38, 0, 22)

local pillDistance = makeLabel(bannerPill, "Distance: --", 9.5, THEME.muted)
pillDistance.Position = UDim2.fromOffset(12, 36)
pillDistance.Size = UDim2.new(1, -24, 0, 18)

UI.home.banner = banner
UI.home.bannerPortrait = bannerPortrait
UI.home.bannerAvatar = bannerPortrait
UI.home.bannerPortraitFallback = bannerPortraitFallback
UI.home.bannerText = bannerText
UI.home.bannerPill = bannerPill
UI.home.mobileStatus = mobileStatus
UI.home.pillDot = pillDot
UI.home.pillState = pillState
UI.home.pillDistance = pillDistance

-- Stats row
local statRow = Instance.new("Frame")
statRow.Name = "Stats"
statRow.BackgroundTransparency = 1
statRow.Size = UDim2.new(1, 0, 0, 74)
statRow.LayoutOrder = 2
statRow.Parent = homePage

local statGrid = Instance.new("UIGridLayout")
statGrid.CellSize = UDim2.new(0.25, -6, 0, 72)
statGrid.CellPadding = UDim2.new(0, 8, 0, 0)
statGrid.SortOrder = Enum.SortOrder.LayoutOrder
statGrid.FillDirection = Enum.FillDirection.Horizontal
statGrid.Parent = statRow

local function makeStatCard(parent, glyph, title, layoutOrder)
	local card = Instance.new("Frame")
	card.BackgroundColor3 = THEME.panel
	card.BorderSizePixel = 0
	card.Size = UDim2.fromScale(1, 1)
	card.LayoutOrder = layoutOrder
	card.Parent = parent
	corner(card, 12)
	stroke(card, THEME.strokeSoft, 1, 0.25)

	local icon = makeLabel(card, glyph, 17, theme.accent, Enum.Font.GothamBold, Enum.TextXAlignment.Center)
	icon.Position = UDim2.fromOffset(10, 0)
	icon.Size = UDim2.fromOffset(26, 72)
	bindAccent(icon, "TextColor3")

	local caption = makeLabel(card, title, 9.5, THEME.muted)
	caption.Position = UDim2.fromOffset(38, 16)
	caption.Size = UDim2.new(1, -46, 0, 14)
	caption.TextTruncate = Enum.TextTruncate.AtEnd

	local value = makeLabel(card, "N/A", 15, THEME.text, Enum.Font.GothamBold)
	value.Position = UDim2.fromOffset(38, 32)
	value.Size = UDim2.new(1, -46, 0, 24)
	value.TextTruncate = Enum.TextTruncate.AtEnd

	return value
end

UI.home.keysValue = makeStatCard(statRow, "⚿", "Keys", 1)
UI.home.passValue = makeStatCard(statRow, "⛨", "Passcode", 2)
UI.home.playersValue = makeStatCard(statRow, "☷", "Players", 3)
UI.home.timeValue = makeStatCard(statRow, "◷", "Time", 4)
UI.home.statRow = statRow
UI.home.statGrid = statGrid

-- Quick actions
local quickCard = Instance.new("Frame")
quickCard.Name = "QuickActions"
quickCard.BackgroundColor3 = THEME.panel
quickCard.BorderSizePixel = 0
quickCard.Size = UDim2.new(1, 0, 0, 156)
quickCard.LayoutOrder = 3
quickCard.Parent = homePage
corner(quickCard, 14)
stroke(quickCard, THEME.strokeSoft, 1, 0.25)

local quickHead = Instance.new("Frame")
quickHead.BackgroundTransparency = 1
quickHead.Position = UDim2.fromOffset(12, 10)
quickHead.Size = UDim2.new(1, -24, 0, 20)
quickHead.Parent = quickCard

local quickIcon = makeLabel(quickHead, "✦", 13, theme.accent, Enum.Font.GothamBold)
quickIcon.Position = UDim2.fromOffset(0, 0)
quickIcon.Size = UDim2.fromOffset(18, 20)
bindAccent(quickIcon, "TextColor3")

local quickTitle = makeLabel(quickHead, "Quick Actions", 12, THEME.text, Enum.Font.GothamBold)
quickTitle.Position = UDim2.fromOffset(20, 0)
quickTitle.Size = UDim2.new(0.5, 0, 0, 20)

local moreOptions = Instance.new("TextButton")
moreOptions.Name = "MoreOptions"
moreOptions.BackgroundTransparency = 1
moreOptions.BorderSizePixel = 0
moreOptions.Text = "More Options →"
moreOptions.AutoButtonColor = false
moreOptions.Font = Enum.Font.GothamSemibold
moreOptions.TextSize = 9
moreOptions.TextColor3 = theme.accent
moreOptions.TextXAlignment = Enum.TextXAlignment.Right
moreOptions.AnchorPoint = Vector2.new(1, 0)
moreOptions.Position = UDim2.new(1, 0, 0, 0)
moreOptions.Size = UDim2.fromOffset(120, 20)
moreOptions.Parent = quickHead
bindAccent(moreOptions, "TextColor3")
moreOptions.Activated:Connect(function()
	selectPage("Visuals")
end)

local quickGrid = Instance.new("Frame")
quickGrid.Name = "Tiles"
quickGrid.BackgroundTransparency = 1
quickGrid.Position = UDim2.fromOffset(12, 40)
quickGrid.Size = UDim2.new(1, -24, 0, 92)
quickGrid.Parent = quickCard

local quickLayout = Instance.new("UIGridLayout")
quickLayout.CellSize = UDim2.new(1 / 6, -7, 0, 92)
quickLayout.CellPadding = UDim2.new(0, 8, 0, 8)
quickLayout.SortOrder = Enum.SortOrder.LayoutOrder
quickLayout.FillDirection = Enum.FillDirection.Horizontal
quickLayout.Parent = quickGrid

UI.home.quickCard = quickCard
UI.home.quickGrid = quickGrid
UI.home.quickLayout = quickLayout
UI.home.moreOptions = moreOptions

local function makeQuickTile(parent, spec)
	local tile = Instance.new("TextButton")
	tile.AutoButtonColor = false
	tile.BorderSizePixel = 0
	tile.Text = ""
	tile.BackgroundColor3 = THEME.panel2
	tile.Size = UDim2.fromScale(1, 1)
	tile.Parent = parent
	corner(tile, 12)
	local border = stroke(tile, THEME.strokeSoft, 1, 0.3)

	local icon = makeLabel(tile, spec.glyph, 19, theme.accent, Enum.Font.GothamBold, Enum.TextXAlignment.Center)
	icon.Position = UDim2.new(0, 0, 0, 10)
	icon.Size = UDim2.new(1, 0, 0, 26)
	bindAccent(icon, "TextColor3")

	local nameLabel = makeLabel(tile, spec.title, 9.5, THEME.text, Enum.Font.GothamBold, Enum.TextXAlignment.Center)
	nameLabel.Position = UDim2.new(0, 0, 0, 38)
	nameLabel.Size = UDim2.new(1, -4, 0, 14)
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd

	if spec.state then
		local toggle = makeSwitch(tile, spec.state, 32)
		toggle.track.AnchorPoint = Vector2.new(0.5, 0)
		toggle.track.Position = UDim2.new(0.5, 0, 0, 60)
		spec.state:OnChanged(function(value)
			border.Color = value and theme.accent or THEME.strokeSoft
			border.Transparency = value and 0.25 or 0.4
		end)
		tile.Activated:Connect(function()
			spec.state:Toggle()
		end)
	else
		local play = makeLabel(tile, "▶", 12, THEME.muted, Enum.Font.GothamBold, Enum.TextXAlignment.Center)
		play.Position = UDim2.new(0, 0, 0, 58)
		play.Size = UDim2.new(1, 0, 0, 18)
		tile.Activated:Connect(function()
			if spec.action then
				task.spawn(function()
					local ok, err = pcall(spec.action)
					if not ok then captureError("quick action", err) end
				end)
			end
		end)
	end

	table.insert(UI.quickTiles, { tile = tile, spec = spec })
	return tile
end

makeQuickTile(quickGrid, {
	glyph = "◎", title = "ESP", state = cfg.espOpah, layout = 1,
})
makeQuickTile(quickGrid, {
	glyph = "◉", title = "Radar", state = cfg.radar, layout = 2,
})
makeQuickTile(quickGrid, {
	glyph = "▣", title = "Auto Loot", state = cfg.autoLoot, layout = 3,
})
makeQuickTile(quickGrid, {
	glyph = "✕", title = "Auto Hide", state = cfg.autoHide, layout = 4,
})
makeQuickTile(quickGrid, {
	glyph = "⟳", title = "Rescan", layout = 5,
	action = function()
		scanWorld()
		syncEsp()
		notify("World scan", "World data refreshed", "success")
	end,
})
makeQuickTile(quickGrid, {
	glyph = "▤", title = "Diagnostics", layout = 6,
	action = function()
		selectPage("Diagnostics")
		if UI.refreshDiagnostics then UI.refreshDiagnostics() end
	end,
})

for index, record in ipairs(UI.quickTiles) do
	record.tile.LayoutOrder = index
end

-- Bottom row: status + performance
local bottomRow = Instance.new("Frame")
bottomRow.Name = "BottomRow"
bottomRow.BackgroundTransparency = 1
bottomRow.Size = UDim2.new(1, 0, 0, 150)
bottomRow.LayoutOrder = 4
bottomRow.Parent = homePage
UI.home.bottomRow = bottomRow

local statusCard = Instance.new("Frame")
statusCard.Name = "StatusCard"
statusCard.BackgroundColor3 = THEME.panel
statusCard.BorderSizePixel = 0
statusCard.Size = UDim2.new(0.5, -5, 1, 0)
statusCard.Parent = bottomRow
corner(statusCard, 14)
stroke(statusCard, THEME.strokeSoft, 1, 0.25)
UI.home.statusCard = statusCard

local statusHead = Instance.new("Frame")
statusHead.BackgroundTransparency = 1
statusHead.Position = UDim2.fromOffset(12, 10)
statusHead.Size = UDim2.new(1, -24, 0, 20)
statusHead.Parent = statusCard

local statusIcon = makeLabel(statusHead, "✦", 13, theme.accent, Enum.Font.GothamBold)
statusIcon.Position = UDim2.fromOffset(0, 0)
statusIcon.Size = UDim2.fromOffset(18, 20)
bindAccent(statusIcon, "TextColor3")

local statusTitle = makeLabel(statusHead, "Status", 12, THEME.text, Enum.Font.GothamBold)
statusTitle.Position = UDim2.fromOffset(20, 0)
statusTitle.Size = UDim2.new(1, -20, 0, 20)

local staySafe = makeLabel(statusCard, "Stay Safe! ♥", 17, theme.accent, Enum.Font.GothamBold, Enum.TextXAlignment.Right)
staySafe.AnchorPoint = Vector2.new(1, 0)
staySafe.Position = UDim2.new(1, -14, 0, 62)
staySafe.Size = UDim2.fromOffset(150, 30)
bindAccent(staySafe, "TextColor3")

local statusPanel = Instance.new("Frame")
statusPanel.BackgroundTransparency = 1
statusPanel.Position = UDim2.fromOffset(12, 38)
statusPanel.Size = UDim2.new(0.56, -12, 0, 96)
statusPanel.Parent = statusCard

UI.home.statusRows = {}

local function makeStatusLine(order, title)
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 19)
	row.LayoutOrder = order
	row.Parent = statusPanel

	local dot = Instance.new("Frame")
	dot.BackgroundColor3 = THEME.success
	dot.BorderSizePixel = 0
	dot.Position = UDim2.fromOffset(2, 7)
	dot.Size = UDim2.fromOffset(5, 5)
	dot.Parent = row
	corner(dot, 999)

	local nameLabel = makeLabel(row, title .. ":", 9.5, THEME.muted)
	nameLabel.Position = UDim2.fromOffset(13, 0)
	nameLabel.Size = UDim2.new(0.45, -13, 1, 0)
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd

	local valueLabel = makeLabel(row, "N/A", 9.5, THEME.text, Enum.Font.GothamSemibold)
	valueLabel.Position = UDim2.new(0.45, 0, 0, 0)
	valueLabel.Size = UDim2.new(0.55, 0, 1, 0)
	valueLabel.TextTruncate = Enum.TextTruncate.AtEnd

	return { row = row, dot = dot, value = valueLabel }
end

for _, spec in ipairs({
	{ key = "esp", title = "ESP", state = cfg.espOpah },
	{ key = "radar", title = "Radar", state = cfg.radar },
	{ key = "loot", title = "Auto Loot", state = cfg.autoLoot },
	{ key = "hide", title = "Auto Hide", state = cfg.autoHide },
}) do
	local line = makeStatusLine(#UI.home.statusRows + 1, spec.title)
	line.state = spec.state
	UI.home.statusRows[spec.key] = line
	spec.state:OnChanged(function(value)
		line.value.Text = value and "Enabled" or "Disabled"
		line.value.TextColor3 = value and THEME.success or THEME.dim
		line.dot.BackgroundColor3 = value and THEME.success or THEME.dim
	end)
end

local statusLayout = Instance.new("UIListLayout")
statusLayout.SortOrder = Enum.SortOrder.LayoutOrder
statusLayout.Parent = statusPanel

local perfCard = Instance.new("Frame")
perfCard.Name = "PerformanceCard"
perfCard.BackgroundColor3 = THEME.panel
perfCard.BorderSizePixel = 0
perfCard.AnchorPoint = Vector2.new(1, 0)
perfCard.Position = UDim2.new(1, 0, 0, 0)
perfCard.Size = UDim2.new(0.5, -5, 1, 0)
perfCard.Parent = bottomRow
corner(perfCard, 14)
stroke(perfCard, THEME.strokeSoft, 1, 0.25)
UI.home.perfCard = perfCard

local perfHead = Instance.new("Frame")
perfHead.BackgroundTransparency = 1
perfHead.Position = UDim2.fromOffset(12, 10)
perfHead.Size = UDim2.new(1, -24, 0, 20)
perfHead.Parent = perfCard

local perfIcon = makeLabel(perfHead, "▮", 12, theme.accent, Enum.Font.GothamBold)
perfIcon.Position = UDim2.fromOffset(0, 0)
perfIcon.Size = UDim2.fromOffset(18, 20)
bindAccent(perfIcon, "TextColor3")

local perfTitle = makeLabel(perfHead, "Performance", 12, THEME.text, Enum.Font.GothamBold)
perfTitle.Position = UDim2.fromOffset(20, 0)
perfTitle.Size = UDim2.new(1, -20, 0, 20)

local function makeMetric(caption, offsetX)
	local captionLabel = makeLabel(perfCard, caption, 9, THEME.muted)
	captionLabel.Position = UDim2.fromOffset(offsetX, 40)
	captionLabel.Size = UDim2.fromOffset(76, 14)

	local valueLabel = makeLabel(perfCard, "N/A", 15, THEME.text, Enum.Font.GothamBold)
	valueLabel.Position = UDim2.fromOffset(offsetX, 54)
	valueLabel.Size = UDim2.fromOffset(90, 22)
	valueLabel.TextTruncate = Enum.TextTruncate.AtEnd
	return valueLabel
end

UI.home.fpsValue = makeMetric("FPS", 14)
UI.home.pingValue = makeMetric("Ping", 96)
UI.home.memoryValue = makeMetric("Memory", 178)

local graph = Instance.new("Frame")
graph.Name = "FPSGraph"
graph.BackgroundColor3 = THEME.inset
graph.BackgroundTransparency = 0.35
graph.BorderSizePixel = 0
graph.AnchorPoint = Vector2.new(1, 0)
graph.Position = UDim2.new(1, -14, 0, 40)
graph.Size = UDim2.fromOffset(150, 92)
graph.ClipsDescendants = true
graph.Parent = perfCard
corner(graph, 10)
stroke(graph, THEME.strokeSoft, 1, 0.5)

local graphBars = {}
local BAR_COUNT = 26
for index = 1, BAR_COUNT do
	local bar = Instance.new("Frame")
	bar.BackgroundColor3 = theme.accent
	bar.BorderSizePixel = 0
	bar.AnchorPoint = Vector2.new(0, 1)
	bar.Position = UDim2.fromOffset(4 + (index - 1) * 5.5, 84)
	bar.Size = UDim2.fromOffset(3, 6)
	bar.Parent = graph
	corner(bar, 2)
	bindAccent(bar, "BackgroundColor3")
	graphBars[index] = bar
end

UI.home.graphBars = graphBars
UI.home.graph = graph

local function pushGraphSample(fps)
	local bar = graphBars[1]
	if not bar then return end
	for index = 1, BAR_COUNT - 1 do
		graphBars[index].Size = graphBars[index + 1].Size
	end
	local normalized = clamp((fps or 0) / 60, 0, 1)
	local height = 6 + normalized * 72
	graphBars[BAR_COUNT].Size = UDim2.fromOffset(3, height)
end

UI.pushGraphSample = pushGraphSample
end
buildHome()


local function buildFeaturePages()
--== Visuals page ==
local function copyPasscode()
	if not hub.code then
		notify("Passcode", "No passcode read yet", "warn")
		return
	end
	if typeof(setclipboard) ~= "function" then
		notify("Passcode", "Clipboard API unavailable in this executor", "warn")
		return
	end
	local digits = tostring(hub.code):gsub("%s", "")
	local ok = pcall(setclipboard, digits)
	if ok then
		notify("Passcode", "Digits copied to clipboard", "success")
	else
		notify("Passcode", "Copy failed", "warn")
	end
end

UI.copyPasscode = copyPasscode
local espCard = makeCard("Visuals", "ESP", "◉", "One cached Highlight per instance, no per-frame scans")
makeToggleRow(espCard.body, "Opah ESP", "Ghost highlight through walls", cfg.espOpah)
makeToggleRow(espCard.body, "Key ESP", "Colored highlight for keys still in the house", cfg.espKeys)
makeToggleRow(espCard.body, "Passcode note ESP", "Marks the note that carries the keypad code", cfg.espNote)
makeToggleRow(espCard.body, "Front door & locks", "Exit, keypad plate and color-coded locks", cfg.espDoor)
makeToggleRow(espCard.body, "Wardrobes", "Hide spots", cfg.espWardrobe)
makeToggleRow(espCard.body, "Drawers", "Heavier: one highlight per openable drawer", cfg.espDrawer)
makeToggleRow(espCard.body, "Text labels", "Billboard labels above highlighted objects", cfg.espLabels)

local overlayCard = makeCard("Visuals", "Overlays", "▣", "Radar and passcode overlays live inside this GUI")
makeToggleRow(overlayCard.body, "Opah radar", "State, distance, chase target and lair", cfg.radar)
makeToggleRow(overlayCard.body, "Passcode overlay", "Large passcode readout with copy button", cfg.passOverlay)
makeButtonRow(overlayCard.body, {
	{ text = "Copy passcode", width = UDim2.new(1, 0, 1, 0), onClick = copyPasscode },
})

local rangeCard = makeCard("Visuals", "Range & performance", "◈", "Tune update cost for low-end devices")
makeSlider(rangeCard.body, {
	title = "Max ESP distance", min = 50, max = 600, step = 25, suffix = " studs", state = cfg.espDistance,
})
makeToggleRow(rangeCard.body, "Performance mode", "World scan every 2s and slower ESP sync", cfg.performanceMode)
makeNote(rangeCard.body, "Performance mode only slows scans and ESP sync. No feature is disabled and no value is invented.")

local notesCard = makeCard("Visuals", "ESP hygiene", "✦")
makeNote(notesCard.body, "Highlights are removed when their instance leaves the world, when a toggle turns off, or on unload. Stale highlights from a previous run are cleaned at startup.")

--== Automation page: auto loot ==
local lootCard = makeCard("Automation", "Auto Loot", "◍", "Opens drawers and collects the selected items")
makeToggleRow(lootCard.body, "Auto loot", "Runs while alive, visible and not hidden", cfg.autoLoot)
makeNote(lootCard.body, "TARGETS")
makeMultiChips(lootCard.body, { "Drawers", "Keys", "Passcode note", "Flip flops" }, cfg.lootTargets, 2)
makeNote(lootCard.body, "MOVEMENT")
makeSelectChips(lootCard.body, { "Walk", "Teleport" }, cfg.lootMode, 2)
makeSlider(lootCard.body, {
	title = "Search range", min = 50, max = 500, step = 25, suffix = " studs", state = cfg.lootRange,
})
makeToggleRow(lootCard.body, "Pause while chased", "Stops looting while Opah is within 55 studs", cfg.pauseOnChase)

local hideCard = makeCard("Automation", "Auto Hide", "⌂", "Uses the nearest wardrobe while Opah is chasing")
makeToggleRow(hideCard.body, "Auto hide", "Leaves the wardrobe once Opah is far enough", cfg.autoHide)
makeSlider(hideCard.body, {
	title = "Trigger distance", min = 10, max = 120, step = 5, suffix = " studs", state = cfg.hideRange,
})
makeSelectChips(hideCard.body, { "Teleport", "Walk" }, cfg.hideMode, 2)
makeButtonRow(hideCard.body, {
	{
		text = "Leave wardrobe now",
		width = UDim2.new(1, 0, 1, 0),
		onClick = function()
			if hub.hiddenPrompt then
				triggerPrompt(hub.hiddenPrompt)
				hub.hiddenPrompt = nil
				pushLog("info", "Leave wardrobe requested")
			else
				pushLog("info", "Not hidden right now")
			end
		end,
	},
})

--== Teleport page ==
local teleportStatusLabel = nil

local function refreshTeleportStatus()
	if not teleportStatusLabel then return end
	local kind = cfg.teleportTarget:Get()
	local position = resolveTargetPosition(kind)
	if position then
		teleportStatusLabel.Text = string.format("Resolved: %s  ->  %.0f, %.0f, %.0f", tostring(kind), position.X, position.Y, position.Z)
		teleportStatusLabel.TextColor3 = THEME.success
	else
		teleportStatusLabel.Text = "Resolved: " .. tostring(kind) .. "  ->  not found"
		teleportStatusLabel.TextColor3 = THEME.warning
	end
end

local function doTeleport()
	local kind = cfg.teleportTarget:Get()
	local position = resolveTargetPosition(kind)
	if not position then
		notify("Teleport", "Target not found: " .. tostring(kind), "warn")
		return
	end
	if not isAlive() then
		notify("Teleport", "Character is not active", "warn")
		return
	end
	if teleportNear(position) then
		pushLog("success", "Teleported to " .. tostring(kind))
	else
		notify("Teleport", "Teleport failed", "warn")
	end
	refreshTeleportStatus()
end

local function doWalk()
	local kind = cfg.teleportTarget:Get()
	local position = resolveTargetPosition(kind)
	if not position then
		notify("Walk", "Target not found: " .. tostring(kind), "warn")
		return
	end
	task.spawn(function()
		local reached = walkTo(position, 8, 15)
		if reached then
			pushLog("success", "Reached " .. tostring(kind))
		else
			notify("Walk", "Target unreachable", "warn")
		end
	end)
end

local destCard = makeCard("Teleport", "Destination", "⌖", "Targets resolve from the live workspace on every use")
makeSelectChips(destCard.body, TELEPORT_TARGETS, cfg.teleportTarget, 2)
teleportStatusLabel = makeLabel(destCard.body, "Resolved: N/A", 9, THEME.dim)
teleportStatusLabel.Size = UDim2.new(1, 0, 0, 16)
teleportStatusLabel.TextTruncate = Enum.TextTruncate.AtEnd
cfg.teleportTarget:OnChanged(function()
	refreshTeleportStatus()
end)

local actionCard = makeCard("Teleport", "Actions", "◈", "Teleport writes the HumanoidRootPart; Walk uses Humanoid:MoveTo")
makeButtonRow(actionCard.body, {
	{ text = "Teleport", accent = true, onClick = doTeleport },
	{ text = "Walk to", onClick = doWalk },
})
makeButtonRow(actionCard.body, {
	{
		text = "Copy position",
		onClick = function()
			local root = getRoot()
			if not root then
				notify("Position", "Character not available", "warn")
				return
			end
			if typeof(setclipboard) ~= "function" then
				notify("Position", "Clipboard API unavailable", "warn")
				return
			end
			local position = root.Position
			pcall(setclipboard, string.format("%.2f, %.2f, %.2f", position.X, position.Y, position.Z))
			notify("Position", "Coordinates copied", "success")
		end,
	},
	{
		text = "Rescan world",
		onClick = function()
			scanWorld()
			syncEsp()
			refreshTeleportStatus()
			notify("World scan", "World data refreshed", "success")
		end,
	},
})

local teleportInfo = makeCard("Teleport", "How targets resolve", "✦")
makeNote(teleportInfo.body, "Passcode note, keys, door, keypad plate, wardrobes and drawers are located by the world scan. When a target is missing the action reports it instead of guessing a position.")
end
buildFeaturePages()

local function buildCodes()
--== Auto Redeem Codes (code manager + gated redemption) ==
local CODE_STOPWORDS = {}
for _, word in ipairs({
	"MALAM", "SAMA", "OPAH", "CLASS", "ROBLOX", "GROUP", "JOIN", "UPDATE", "NEW", "CODE", "CODES",
	"REWARD", "REWARDS", "SPIN", "SPINS", "DUIT", "GAME", "PLAY", "THANKS", "LUCK", "WELCOME",
	"ENJOY", "MAP", "BOSS", "NORMAL", "SECRET", "FREE", "LIKE", "SHARE", "FOLLOW", "STUDIO",
}) do
	CODE_STOPWORDS[word] = true
end

local codes = {
	entries = {
		{
			code = "SETTINGS",
			source = "Third-party trackers",
			status = "Unknown",
			note = "Reported reward: 3 Normal Spins + 500 Duit. Not verified in this session.",
		},
	},
	history = {},
	running = false,
	interface = nil,
	sources = {
		{ id = "description", name = "Official game description", kind = "auto", enabled = true, note = "Read through MarketplaceService" },
		{ id = "robloxden", name = "robloxden.com", kind = "manual", enabled = false, note = "No machine-readable feed" },
		{ id = "bloxrant", name = "bloxrant.com", kind = "manual", enabled = false, note = "No machine-readable feed" },
		{ id = "obbydrop", name = "obbydrop.com", kind = "manual", enabled = false, note = "No machine-readable feed" },
		{ id = "community", name = "Sabun Studios community", kind = "manual", enabled = false, note = "Manual entry only" },
	},
}

local function codeStatusColor(status)
	if status == "Redeemed" then return THEME.success end
	if status == "Expired" then return THEME.warning end
	if status == "Invalid" then return THEME.error end
	if status == "Already redeemed" then return THEME.info end
	if status == "Blocked" then return THEME.warning end
	return THEME.dim
end

local function findCodeIndex(code)
	local lower = string.lower(tostring(code))
	for index, entry in ipairs(codes.entries) do
		if string.lower(entry.code) == lower then return index end
	end
	return nil
end

local function addCode(code, source, note)
	local candidate = trim(code)
	if #candidate < 3 or #candidate > 24 then
		return false, "Code must be 3 to 24 characters"
	end
	if not string.match(candidate, "^[%w_]+$") then
		return false, "Only letters, digits and underscore are allowed"
	end
	if findCodeIndex(candidate) then
		return false, "That code is already listed"
	end
	if #codes.entries >= 40 then
		return false, "Session list is full (40 codes maximum)"
	end
	table.insert(codes.entries, {
		code = candidate,
		source = source or "Manual",
		status = "Unknown",
		note = note,
	})
	return true
end

local function codeCounters()
	local counters = { success = 0, expired = 0, invalid = 0, already = 0, blocked = 0, pending = 0 }
	for _, entry in ipairs(codes.entries) do
		local status = entry.status
		if status == "Redeemed" then
			counters.success = counters.success + 1
		elseif status == "Expired" then
			counters.expired = counters.expired + 1
		elseif status == "Invalid" then
			counters.invalid = counters.invalid + 1
		elseif status == "Already redeemed" then
			counters.already = counters.already + 1
		elseif status == "Blocked" then
			counters.blocked = counters.blocked + 1
		else
			counters.pending = counters.pending + 1
		end
	end
	return counters
end

local function looksLikePromoCodeName(name)
	local lower = string.lower(tostring(name))
	if string.find(lower, "passcode", 1, true) then return false end
	if string.find(lower, "promo", 1, true) then return true end
	if string.find(lower, "redeem", 1, true) then return true end
	if string.find(lower, "code", 1, true) then return true end
	return false
end

local function detectRedemptionInterface()
	local result = { remotes = {}, textboxes = {}, scannedAt = os.clock() }
	pcall(function()
		local puzzleShared = ReplicatedStorage:FindFirstChild("PuzzleShared")
		for _, instance in ipairs(ReplicatedStorage:GetDescendants()) do
			if instance:IsA("RemoteEvent") or instance:IsA("RemoteFunction") then
				-- SubmitPasscode belongs to the door keypad, not to promo codes.
				local isKeypadRemote = puzzleShared ~= nil and instance:IsDescendantOf(puzzleShared)
				if not isKeypadRemote and looksLikePromoCodeName(instance.Name) then
					table.insert(result.remotes, instance:GetFullName())
				end
			end
		end
	end)
	pcall(function()
		local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
		if not playerGui then return end
		for _, instance in ipairs(playerGui:GetDescendants()) do
			if instance:IsA("TextBox") then
				local placeholder = string.lower(tostring(instance.PlaceholderText or ""))
				if string.find(placeholder, "code", 1, true) then
					table.insert(result.textboxes, instance:GetFullName())
				end
			end
		end
	end)
	result.available = (#result.remotes > 0 or #result.textboxes > 0)
	codes.interface = result
	return result
end

-- Codes card
local codesCard = makeCard("Automation", "Auto Redeem Codes", "✧", "Session code manager with gated redemption")
local codesDetectLabel = makeNote(codesCard.body, "Redemption interface: not checked yet.", THEME.warning)

makeToggleRow(codesCard.body, "Auto Redeem", "Needs a verified interface and server confirmation", cfg.autoRedeem)

local inputRow = Instance.new("Frame")
inputRow.BackgroundTransparency = 1
inputRow.Size = UDim2.new(1, 0, 0, 34)
inputRow.Parent = codesCard.body

local codeInput = Instance.new("TextBox")
codeInput.Name = "CodeInput"
codeInput.BackgroundColor3 = THEME.inset
codeInput.BorderSizePixel = 0
codeInput.ClearTextOnFocus = false
codeInput.PlaceholderText = "Type or paste a code..."
codeInput.PlaceholderColor3 = THEME.dim
codeInput.Font = Enum.Font.Gotham
codeInput.TextSize = 10.5
codeInput.TextColor3 = THEME.text
codeInput.TextXAlignment = Enum.TextXAlignment.Left
codeInput.Text = ""
codeInput.Position = UDim2.fromOffset(0, 0)
codeInput.Size = UDim2.new(1, -150, 1, 0)
codeInput.Parent = inputRow
corner(codeInput, 9)
stroke(codeInput, THEME.strokeSoft, 1, 0.4)

local addCodeButton = makeButton(inputRow, "Add", {
	size = UDim2.fromOffset(64, 34),
	bg = THEME.panel2,
	textSize = 10,
})
addCodeButton.AnchorPoint = Vector2.new(1, 0)
addCodeButton.Position = UDim2.new(1, -72, 0, 0)

local cancelEditButton = makeButton(inputRow, "Cancel", {
	size = UDim2.fromOffset(64, 34),
	bg = THEME.panel2,
	textSize = 10,
})
cancelEditButton.AnchorPoint = Vector2.new(1, 0)
cancelEditButton.Position = UDim2.new(1, 0, 0, 0)
cancelEditButton.Visible = false

local codesList = Instance.new("ScrollingFrame")
codesList.BackgroundColor3 = THEME.inset
codesList.BackgroundTransparency = 0.15
codesList.BorderSizePixel = 0
codesList.Size = UDim2.new(1, 0, 0, 128)
codesList.ScrollBarThickness = 3
codesList.ScrollBarImageColor3 = theme.accent
codesList.CanvasSize = UDim2.new(0, 0, 0, 0)
codesList.AutomaticCanvasSize = Enum.AutomaticSize.Y
codesList.ScrollingDirection = Enum.ScrollingDirection.Y
codesList.Parent = codesCard.body
corner(codesList, 10)
stroke(codesList, THEME.strokeSoft, 1, 0.5)

local codesListPad = Instance.new("UIPadding")
codesListPad.PaddingLeft = UDim.new(0, 6)
codesListPad.PaddingRight = UDim.new(0, 6)
codesListPad.PaddingTop = UDim.new(0, 6)
codesListPad.PaddingBottom = UDim.new(0, 6)
codesListPad.Parent = codesList

local codesListLayout = Instance.new("UIListLayout")
codesListLayout.Padding = UDim.new(0, 4)
codesListLayout.SortOrder = Enum.SortOrder.LayoutOrder
codesListLayout.Parent = codesList

local codesActionsOne = makeButtonRow(codesCard.body, {
	{ text = "Redeem All", accent = true, onClick = function() if codesRedeemAll then codesRedeemAll() end end },
	{ text = "Refresh Codes", onClick = function() if codesRefresh then codesRefresh() end end },
})
makeButtonRow(codesCard.body, {
	{ text = "Detect interface", onClick = function() if codesDetect then codesDetect() end end },
	{ text = "Clear history", onClick = function()
		table.clear(codes.history)
		table.clear(codes.entries)
		pushLog("info", "Session code list and attempt history cleared")
		if UI.codesRenderList then UI.codesRenderList() end
		if UI.codesRenderHistory then UI.codesRenderHistory() end
		if UI.codesRenderCounters then UI.codesRenderCounters() end
	end },
})

makeSlider(codesCard.body, {
	title = "Delay between attempts", min = 1, max = 15, step = 1, suffix = " sec", state = cfg.codeDelay,
})

local progressHolder = Instance.new("Frame")
progressHolder.BackgroundTransparency = 1
progressHolder.Size = UDim2.new(1, 0, 0, 32)
progressHolder.Parent = codesCard.body

local progressTrack = Instance.new("Frame")
progressTrack.BackgroundColor3 = THEME.panel3
progressTrack.BorderSizePixel = 0
progressTrack.Position = UDim2.fromOffset(0, 4)
progressTrack.Size = UDim2.new(1, 0, 0, 8)
progressTrack.Parent = progressHolder
corner(progressTrack, 4)

local progressFill = Instance.new("Frame")
progressFill.BackgroundColor3 = theme.accent
progressFill.BorderSizePixel = 0
progressFill.Size = UDim2.new(0, 0, 1, 0)
progressFill.Parent = progressTrack
corner(progressFill, 4)
bindAccent(progressFill, "BackgroundColor3")

local progressLabel = makeLabel(progressHolder, "Redemption queue idle", 8.5, THEME.dim)
progressLabel.Position = UDim2.fromOffset(0, 16)
progressLabel.Size = UDim2.new(1, 0, 0, 12)

local codesCounters = makeLabel(codesCard.body, "Redeemed 0 | Expired 0 | Invalid 0 | Already 0 | Blocked 0 | Pending 0", 9, THEME.muted)
codesCounters.Size = UDim2.new(1, 0, 0, 16)
codesCounters.TextTruncate = Enum.TextTruncate.AtEnd

local codesActivity = makeCard("Automation", "Redemption activity", "▤", "Session attempt history for this stream session")
local codesHistoryFrame = Instance.new("ScrollingFrame")
codesHistoryFrame.BackgroundColor3 = THEME.inset
codesHistoryFrame.BackgroundTransparency = 0.15
codesHistoryFrame.BorderSizePixel = 0
codesHistoryFrame.Size = UDim2.new(1, 0, 0, 96)
codesHistoryFrame.ScrollBarThickness = 3
codesHistoryFrame.ScrollBarImageColor3 = theme.accent
codesHistoryFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
codesHistoryFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
codesHistoryFrame.ScrollingDirection = Enum.ScrollingDirection.Y
codesHistoryFrame.Parent = codesActivity.body
corner(codesHistoryFrame, 10)
stroke(codesHistoryFrame, THEME.strokeSoft, 1, 0.5)

local codesHistoryPad = Instance.new("UIPadding")
codesHistoryPad.PaddingLeft = UDim.new(0, 6)
codesHistoryPad.PaddingRight = UDim.new(0, 6)
codesHistoryPad.PaddingTop = UDim.new(0, 6)
codesHistoryPad.PaddingBottom = UDim.new(0, 6)
codesHistoryPad.Parent = codesHistoryFrame

local codesHistoryLayout = Instance.new("UIListLayout")
codesHistoryLayout.Padding = UDim.new(0, 3)
codesHistoryLayout.SortOrder = Enum.SortOrder.LayoutOrder
codesHistoryLayout.Parent = codesHistoryFrame

local codesNote = makeNote(codesActivity.body, "Attempts are recorded only when a pass actually runs. This build never marks a code as redeemed without a server response.")
codesNote.TextColor3 = THEME.dim

local codesLogView = makeLogView((makeCard("Automation", "Codes activity log", "≡")).body, 120)

--== Codes: rendering + actions ==
local codesEditingIndex = nil

local function resetCodeEditor()
	codesEditingIndex = nil
	codeInput.Text = ""
	addCodeButton.Text = "Add"
	cancelEditButton.Visible = false
end

local function renderCodeDetection()
	local result = codes.interface
	if not result then
		codesDetectLabel.Text = "Redemption interface: not checked yet. Open the game's own code UI once, then press Detect interface."
		codesDetectLabel.TextColor3 = THEME.warning
	elseif result.available then
		codesDetectLabel.Text = string.format(
			"Interface candidate(s): %d remote(s), %d code field(s). Arguments are unverified, so automatic submission stays disabled.",
			#result.remotes, #result.textboxes)
		codesDetectLabel.TextColor3 = THEME.warning
	else
		codesDetectLabel.Text = "No redemption remote or code field detected. Automatic redemption is disabled; copy and manual entry still work."
		codesDetectLabel.TextColor3 = THEME.muted
	end
end

local function renderCodeCounters()
	local counters = codeCounters()
	codesCounters.Text = string.format(
		"Redeemed %d | Expired %d | Invalid %d | Already %d | Blocked %d | Pending %d",
		counters.success, counters.expired, counters.invalid, counters.already, counters.blocked, counters.pending)
end

local function renderCodeList()
	for _, child in ipairs(codesList:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end
	if #codes.entries == 0 then
		local empty = makeLabel(codesList, "No codes in the session list yet.", 9.5, THEME.dim)
		empty.Size = UDim2.new(1, 0, 0, 22)
		return
	end
	for index, entry in ipairs(codes.entries) do
		local row = Instance.new("Frame")
		row.BackgroundColor3 = THEME.panel2
		row.BackgroundTransparency = 0.35
		row.BorderSizePixel = 0
		row.Size = UDim2.new(1, 0, 0, 34)
		row.LayoutOrder = index
		row.Parent = codesList
		corner(row, 8)

		local codeLabel = makeLabel(row, tostring(entry.code), 10.5, THEME.text, Enum.Font.GothamBold)
		codeLabel.Position = UDim2.fromOffset(8, 2)
		codeLabel.Size = UDim2.new(0.36, -8, 0, 16)
		codeLabel.TextTruncate = Enum.TextTruncate.AtEnd

		local sourceLabel = makeLabel(row, tostring(entry.source or "Manual"), 8, THEME.dim)
		sourceLabel.Position = UDim2.fromOffset(8, 17)
		sourceLabel.Size = UDim2.new(0.36, -8, 0, 13)
		sourceLabel.TextTruncate = Enum.TextTruncate.AtEnd

		local statusLabel = makeLabel(row, tostring(entry.status), 9, codeStatusColor(entry.status), Enum.Font.GothamSemibold)
		statusLabel.Position = UDim2.new(0.36, 0, 0, 2)
		statusLabel.Size = UDim2.new(0.24, 0, 0, 16)
		statusLabel.TextTruncate = Enum.TextTruncate.AtEnd

		local copyButton = makeButton(row, "Copy", {
			size = UDim2.fromOffset(38, 22),
			textSize = 9,
			bg = THEME.panel3,
			hover = false,
			onClick = function()
				if typeof(setclipboard) ~= "function" then
					notify("Codes", "Clipboard API unavailable", "warn")
					return
				end
				pcall(setclipboard, tostring(entry.code))
				notify("Codes", tostring(entry.code) .. " copied", "success")
			end,
		})
		copyButton.AnchorPoint = Vector2.new(1, 0.5)
		copyButton.Position = UDim2.new(1, -68, 0.5, 0)

		local editButton = makeButton(row, "Edit", {
			size = UDim2.fromOffset(34, 22),
			textSize = 9,
			bg = THEME.panel3,
			hover = false,
			onClick = function()
				codesEditingIndex = index
				codeInput.Text = tostring(entry.code)
				addCodeButton.Text = "Update"
				cancelEditButton.Visible = true
			end,
		})
		editButton.AnchorPoint = Vector2.new(1, 0.5)
		editButton.Position = UDim2.new(1, -30, 0.5, 0)

		local removeButton = makeButton(row, "✕", {
			size = UDim2.fromOffset(22, 22),
			textSize = 9,
			bg = THEME.panel3,
			color = THEME.error,
			hover = false,
			onClick = function()
				local removed = table.remove(codes.entries, index)
				if UI.resetCodeEditor then UI.resetCodeEditor() end
				renderCodeList()
				renderCodeCounters()
				if removed then pushLog("info", "Removed code " .. tostring(removed.code)) end
			end,
		})
		removeButton.AnchorPoint = Vector2.new(1, 0.5)
		removeButton.Position = UDim2.new(1, -4, 0.5, 0)
	end
end

local function renderCodeHistory()
	for _, child in ipairs(codesHistoryFrame:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end
	if #codes.history == 0 then
		local empty = makeLabel(codesHistoryFrame, "No redemption attempts in this session.", 9, THEME.dim)
		empty.Size = UDim2.new(1, 0, 0, 20)
		return
	end
	local start = math.max(1, #codes.history - 30)
	for index = start, #codes.history do
		local item = codes.history[index]
		local row = Instance.new("Frame")
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, 0, 0, 17)
		row.LayoutOrder = index
		row.Parent = codesHistoryFrame

		local dot = Instance.new("Frame")
		dot.BackgroundColor3 = codeStatusColor(item.status)
		dot.BorderSizePixel = 0
		dot.Position = UDim2.fromOffset(2, 6)
		dot.Size = UDim2.fromOffset(5, 5)
		dot.Parent = row
		corner(dot, 999)

		local text = makeLabel(row, tostring(item.code) .. "  " .. tostring(item.status), 9, codeStatusColor(item.status))
		text.Position = UDim2.fromOffset(12, 0)
		text.Size = UDim2.new(1, -12, 1, 0)
		text.TextTruncate = Enum.TextTruncate.AtEnd
	end
end

addCodeButton.Activated:Connect(function()
	local value = trim(codeInput.Text)

	if codesEditingIndex and codes.entries[codesEditingIndex] then
		local entry = codes.entries[codesEditingIndex]
		if value == "" then
			notify("Codes", "Enter a code first", "warn")
			return
		end
		if #value < 3 or #value > 24 or not string.match(value, "^[%w_]+$") then
			notify("Codes", "Codes use 3-24 letters, digits or underscore", "warn")
			return
		end
		local existing = findCodeIndex(value)
		if existing and existing ~= codesEditingIndex then
			notify("Codes", "That code is already listed", "warn")
			return
		end
		entry.code = value
		entry.source = "Manual edit"
		entry.status = "Unknown"
		resetCodeEditor()
		renderCodeList()
		renderCodeCounters()
		pushLog("success", "Updated code to " .. value)
		return
	end

	local added, message = addCode(value, "Manual")
	if added then
		resetCodeEditor()
		renderCodeList()
		renderCodeCounters()
		pushLog("success", "Added code " .. value)
	else
		notify("Codes", message or "Could not add that code", "warn")
	end
end)

cancelEditButton.Activated:Connect(function()
	resetCodeEditor()
	pushLog("info", "Code edit cancelled")
end)

cfg.autoRedeem:OnChanged(function(value)
	if value then
		pushLog("warn", "Auto redeem armed - no verified submission path exists, so no request is sent")
	end
end)

codesDetect = function()
	local result = detectRedemptionInterface()
	renderCodeDetection()
	if result.available then
		notify("Codes", "Interface candidate found - arguments still unverified", "warn")
	else
		notify("Codes", "No redemption interface detected", "warn")
	end
end

codesRefresh = function()
	local added = 0
	local descriptionEnabled = false
	for _, source in ipairs(codes.sources) do
		if source.id == "description" and source.enabled then
			descriptionEnabled = true
		end
	end

	if descriptionEnabled then
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfo(GAME_PLACE_ID, Enum.InfoType.Asset)
		end)
		if ok and type(info) == "table" then
			local description = tostring(info.Description or "")
			for token in string.gmatch(description, "%f[%w_]%u[%u%d_]+") do
				local candidate = trim(token)
				if #candidate >= 4 and #candidate <= 18 and not CODE_STOPWORDS[candidate] then
					local success = addCode(candidate, "Official description", "Extracted from the official game description")
					if success then added = added + 1 end
				end
			end
			pushLog("success", "Official description scanned: " .. added .. " new candidate(s)")
		else
			pushLog("warn", "Official description is not reachable right now")
		end
	else
		pushLog("info", "Official description source is disabled")
	end

	local manual = 0
	for _, source in ipairs(codes.sources) do
		if source.enabled and source.kind ~= "auto" then
			manual = manual + 1
		end
	end

	renderCodeList()
	renderCodeCounters()
	if added > 0 then
		notify("Refresh Codes", added .. " candidate(s) added - all unverified", "success")
	elseif manual > 0 then
		notify("Refresh Codes", "No new candidates. " .. manual .. " manual source(s) need human review.", "warn")
	else
		notify("Refresh Codes", "No new candidates from the official description", "warn")
	end
end

codesRedeemAll = function()
	if codes.running then
		notify("Codes", "A redemption pass is already running", "warn")
		return
	end
	if #codes.entries == 0 then
		notify("Codes", "The session code list is empty", "warn")
		return
	end

	codes.running = true
	local result = detectRedemptionInterface()
	renderCodeDetection()
	table.clear(codes.history)

	local total = #codes.entries
	pushLog("accent", "Redemption pass started with " .. total .. " code(s)")
	for index = 1, total do
		if not hub.running then break end
		local entry = codes.entries[index]
		if entry then
			-- Deliberate: no RemoteEvent is fired here because this build has no
			-- verified redemption remote or argument layout. Server-side
			-- validation is never bypassed and success is never assumed.
			entry.status = "Blocked"
			entry.lastAttempt = os.clock()
			table.insert(codes.history, {
				code = entry.code,
				status = "Blocked",
				clock = os.clock(),
			})
			pushLog("warn", "Blocked " .. tostring(entry.code) .. " - no verified redemption interface")
		end
		progressFill.Size = UDim2.new(index / total, 0, 1, 0)
		progressLabel.Text = string.format("Pass progress %d / %d - nothing submitted", index, total)
		renderCodeHistory()
		renderCodeCounters()
		task.wait(math.max(1, numberValue(cfg.codeDelay, 3)))
	end

	codes.running = false
	renderCodeList()
	renderCodeCounters()
	progressLabel.Text = "Pass finished - nothing was submitted"
	if result and result.available then
		notify("Codes", "Interface candidate found, arguments unverified - nothing submitted", "warn")
	else
		notify("Codes", "No verified redemption interface - " .. total .. " code(s) left blocked", "warn")
	end
end

UI.resetCodeEditor = resetCodeEditor
UI.codesRedeemAll = function() if codesRedeemAll then codesRedeemAll() end end
UI.codesRefresh = function() if codesRefresh then codesRefresh() end end
UI.codesDetect = function() if codesDetect then codesDetect() end end
UI.codesRenderList = renderCodeList
UI.codesRenderCounters = renderCodeCounters
UI.codesRenderHistory = renderCodeHistory
UI.codesRenderDetection = renderCodeDetection

local sourcesCard = makeCard("Automation", "Code sources", "◈", "Only the official description is machine-readable")
for _, source in ipairs(codes.sources) do
	local row = Instance.new("Frame")
	row.BackgroundColor3 = THEME.panel2
	row.BackgroundTransparency = 0.35
	row.BorderSizePixel = 0
	row.Size = UDim2.new(1, 0, 0, 40)
	row.Parent = sourcesCard.body
	corner(row, 9)

	local nameLabel = makeLabel(row, source.name, 10.5, THEME.text, Enum.Font.GothamSemibold)
	nameLabel.Position = UDim2.fromOffset(9, 4)
	nameLabel.Size = UDim2.new(1, -56, 0, 15)
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd

	local noteLabel = makeLabel(row, source.note or (source.kind == "auto" and "Automatic" or "Manual"), 8, THEME.dim)
	noteLabel.Position = UDim2.fromOffset(9, 20)
	noteLabel.Size = UDim2.new(1, -56, 0, 13)
	noteLabel.TextTruncate = Enum.TextTruncate.AtEnd

	local sourceState = newState(source.enabled == true)
	sourceState:OnChanged(function(value)
		source.enabled = value
		if value and source.kind ~= "auto" then
			pushLog("info", source.name .. " enabled for reference only (no automated fetch)")
		end
	end)
	local toggle = makeSwitch(row, sourceState, 30)
	toggle.track.AnchorPoint = Vector2.new(1, 0.5)
	toggle.track.Position = UDim2.new(1, -9, 0.5, 0)
end

makeNote(sourcesCard.body, "Third-party trackers are listed for reference only. Their pages are human-friendly, not an API, and are never treated as proof that a code works.")

renderCodeDetection()
renderCodeList()
renderCodeCounters()
renderCodeHistory()
end
buildCodes()

local function buildDiagnostics()
--== Diagnostics page ==
local diagFields = {}
local gameInfo = { name = GAME_NAME, creator = "Sabun Studios", description = nil, fetched = false }

local function refreshGameInfo()
	local ok, info = pcall(function()
		return MarketplaceService:GetProductInfo(GAME_PLACE_ID, Enum.InfoType.Asset)
	end)
	if ok and type(info) == "table" then
		gameInfo.name = tostring(info.Name or GAME_NAME)
		local creator = info.Creator
		gameInfo.creator = tostring(creator and creator.Name or "Sabun Studios")
		gameInfo.description = tostring(info.Description or "")
		gameInfo.fetched = true
		return true
	end
	return false
end

local function diagRow(card, key, title)
	local valueLabel = makeValueRow(card.body, title)
	diagFields[key] = valueLabel
	return valueLabel
end

local clientCard = makeCard("Diagnostics", "Client & executor", "◈", "Only values this client can actually read")
diagRow(clientCard, "executor", "Executor")
diagRow(clientCard, "device", "Device")
diagRow(clientCard, "viewport", "Viewport")
diagRow(clientCard, "clipboard", "Clipboard API")
diagRow(clientCard, "prompt", "Proximity trigger")
diagRow(clientCard, "gui", "GUI parent")

local gameCard = makeCard("Diagnostics", "Game", "⌂", "Place identity and live world counters")
diagRow(gameCard, "gameName", "Game")
diagRow(gameCard, "creator", "Creator")
diagRow(gameCard, "placeId", "Place ID")
diagRow(gameCard, "placeVersion", "Place version")
diagRow(gameCard, "players", "Players")
diagRow(gameCard, "keys", "Keys in house")
diagRow(gameCard, "locks", "Active lock prompts")
diagRow(gameCard, "drawers", "Openable drawers")
diagRow(gameCard, "wardrobes", "Wardrobes")

local scriptCard = makeCard("Diagnostics", "Script status", "✦", "Initialisation, uptime and scan counters")
diagRow(scriptCard, "version", "Version")
diagRow(scriptCard, "initialized", "Initialised")
diagRow(scriptCard, "uptime", "Uptime")
diagRow(scriptCard, "scans", "World scans")
diagRow(scriptCard, "esp", "ESP highlights")
diagRow(scriptCard, "errors", "Captured errors")
diagRow(scriptCard, "lastScan", "Last scan age")

local playerCard = makeCard("Diagnostics", "Player", "☷", "Local character and game attributes")
diagRow(playerCard, "character", "Character")
diagRow(playerCard, "out", "Out attribute")
diagRow(playerCard, "lives", "Lives")
diagRow(playerCard, "duit", "Duit")
diagRow(playerCard, "flipflops", "Flip flops found")

local featureCard = makeCard("Diagnostics", "Feature status", "◎", "Live toggle state")
diagRow(featureCard, "fEsp", "ESP")
diagRow(featureCard, "fRadar", "Radar")
diagRow(featureCard, "fLoot", "Auto loot")
diagRow(featureCard, "fHide", "Auto hide")
diagRow(featureCard, "fCodes", "Auto redeem")

local remoteCard = makeCard("Diagnostics", "Remotes observed", "⌁", "Read from ReplicatedStorage, never guessed")
local remoteLabel = makeNote(remoteCard.body, "Not scanned yet.", THEME.dim)

local diagActions = makeCard("Diagnostics", "Checks", "◍", "Rescan, copy and clear")
local function buildReport()
	local lines = {}
	lines[#lines + 1] = "MALAM SAMA OPAH " .. VERSION_TAG .. " (v" .. VERSION .. ")"
	lines[#lines + 1] = "Game: " .. gameInfo.name .. " | creator: " .. gameInfo.creator
	lines[#lines + 1] = "Place: " .. GAME_PLACE_ID .. " | universe: " .. GAME_UNIVERSE_ID
	lines[#lines + 1] = "Executor: " .. getExecutorName()
	lines[#lines + 1] = "Device: " .. getDeviceLabel()
	lines[#lines + 1] = "Initialised: " .. tostring(hub.initOk) .. " | uptime: " .. formatClock(os.clock() - hub.sessionStart)
	lines[#lines + 1] = "World scans: " .. hub.scans .. " | ESP highlights: " .. #hub.esp
	lines[#lines + 1] = "Keys in house: " .. #hub.world.keys .. " | locks: " .. #hub.world.locks
	lines[#lines + 1] = "Drawers: " .. #hub.world.drawers .. "/" .. hub.world.drawerTotal .. " | wardrobes: " .. #hub.world.wardrobes
	lines[#lines + 1] = "Passcode: " .. (hub.code and tostring(hub.code) or "not read")
	local opah = opahSummary()
	if opah then
		lines[#lines + 1] = string.format("Opah: %s | chasing=%s | %.0f studs | lair=%s",
			opah.state, tostring(opah.chasing), opah.distance, opah.lairText)
	else
		lines[#lines + 1] = "Opah: not in workspace"
	end
	lines[#lines + 1] = "Remotes: " .. remotesSummary()
	lines[#lines + 1] = "Captured errors: " .. #hub.errors
	return table.concat(lines, "\n")
end
UI.buildReport = buildReport

local function copyReport()
	if typeof(setclipboard) ~= "function" then
		notify("Diagnostics", "Clipboard API unavailable", "warn")
		return
	end
	pcall(setclipboard, buildReport())
	notify("Diagnostics", "Report copied to clipboard", "success")
end

makeButtonRow(diagActions.body, {
	{
		text = "Run full check",
		accent = true,
		onClick = function()
			if runDiagnostics then runDiagnostics() end
		end,
	},
	{ text = "Copy report", onClick = copyReport },
})
makeButtonRow(diagActions.body, {
	{
		text = "Rescan world",
		onClick = function()
			scanWorld()
			syncEsp()
			if refreshDiagnostics then refreshDiagnostics() end
			notify("World scan", "World data refreshed", "success")
		end,
	},
	{
		text = "Clear ESP",
		onClick = function()
			clearEsp()
			pushLog("info", "All ESP highlights cleared")
		end,
	},
})

local diagLogCard = makeCard("Diagnostics", "Activity log", "≡", "Shared session log")
local diagLogView = makeLogView(diagLogCard.body, 150)

local errorCard = makeCard("Diagnostics", "Error log", "⚠", "Caught errors only, never invented reports")
local errorFrame = Instance.new("ScrollingFrame")
errorFrame.BackgroundColor3 = THEME.inset
errorFrame.BackgroundTransparency = 0.15
errorFrame.BorderSizePixel = 0
errorFrame.Size = UDim2.new(1, 0, 0, 96)
errorFrame.ScrollBarThickness = 3
errorFrame.ScrollBarImageColor3 = theme.accent
errorFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
errorFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
errorFrame.Parent = errorCard.body
corner(errorFrame, 10)
stroke(errorFrame, THEME.strokeSoft, 1, 0.5)

local errorLayout = Instance.new("UIListLayout")
errorLayout.Padding = UDim.new(0, 3)
errorLayout.SortOrder = Enum.SortOrder.LayoutOrder
errorLayout.Parent = errorFrame

local errorPad = Instance.new("UIPadding")
errorPad.PaddingLeft = UDim.new(0, 6)
errorPad.PaddingRight = UDim.new(0, 6)
errorPad.PaddingTop = UDim.new(0, 6)
errorPad.PaddingBottom = UDim.new(0, 6)
errorPad.Parent = errorFrame

makeButtonRow(errorCard.body, {
	{
		text = "Clear error log",
		width = UDim2.new(1, 0, 1, 0),
		onClick = function()
			table.clear(hub.errors)
			if refreshDiagnostics then refreshDiagnostics() end
			pushLog("info", "Error log cleared")
		end,
	},
})

local function formatAge(seconds)
	if not seconds then return "N/A" end
	if seconds < 60 then return string.format("%.1fs ago", seconds) end
	return string.format("%dm %02ds ago", math.floor(seconds / 60), math.floor(seconds % 60))
end

refreshDiagnostics = function()
	diagFields.executor.Text = getExecutorName()
	diagFields.device.Text = getDeviceLabel()
	diagFields.viewport.Text = string.format("%d x %d", round(viewport.X), round(viewport.Y))
	diagFields.clipboard.Text = typeof(setclipboard) == "function" and "available" or "unavailable"
	diagFields.prompt.Text = typeof(fireproximityprompt) == "function" and "available" or "manual fallback"
	diagFields.gui.Text = tostring(guiParent:GetFullName())

	diagFields.gameName.Text = gameInfo.name
	diagFields.creator.Text = gameInfo.creator .. (gameInfo.fetched and "" or " (unverified)")
	diagFields.placeId.Text = tostring(GAME_PLACE_ID)
	local placeVersion = nil
	pcall(function()
		placeVersion = game.PlaceVersion
	end)
	diagFields.placeVersion.Text = placeVersion ~= nil and tostring(placeVersion) or "N/A"
	local playerCount = #Players:GetPlayers()
	local maxPlayers = Players.MaxPlayers
	diagFields.players.Text = (maxPlayers and maxPlayers > 0) and (playerCount .. " / " .. maxPlayers) or tostring(playerCount)
	local found, missing = keysSummary()
	diagFields.keys.Text = hub.world.valid and (#found .. " / 5 (missing: " .. (#missing > 0 and table.concat(missing, ", ") or "none") .. ")") or "N/A"
	diagFields.locks.Text = tostring(locksRemaining()) .. " / " .. tostring(#hub.world.locks)
	diagFields.drawers.Text = tostring(#hub.world.drawers) .. " / " .. tostring(hub.world.drawerTotal)
	diagFields.wardrobes.Text = tostring(#hub.world.wardrobes)

	diagFields.version.Text = VERSION .. " " .. VERSION_TAG
	diagFields.initialized.Text = hub.initOk and "yes" or "no"
	diagFields.uptime.Text = formatClock(os.clock() - hub.sessionStart)
	diagFields.scans.Text = tostring(hub.scans)
	diagFields.esp.Text = tostring(#hub.esp)
	diagFields.errors.Text = tostring(#hub.errors)
	diagFields.lastScan.Text = hub.lastScanAt > 0 and formatAge(os.clock() - hub.lastScanAt) or "N/A"

	local root = getRoot()
	local humanoid = getHumanoid()
	diagFields.character.Text = (root and humanoid and humanoid.Health > 0) and "alive" or "not active"
	local out = LocalPlayer:GetAttribute("Out")
	diagFields.out.Text = out ~= nil and tostring(out) or "N/A"
	local lives = LocalPlayer:GetAttribute("Lives")
	local maxLives = LocalPlayer:GetAttribute("MaxLives")
	diagFields.lives.Text = lives ~= nil and (tostring(lives) .. (maxLives ~= nil and (" / " .. tostring(maxLives)) or "")) or "N/A"
	local duit = nil
	pcall(function()
		local leaderstats = LocalPlayer:FindFirstChild("leaderstats")
		local value = leaderstats and leaderstats:FindFirstChild("Duit")
		duit = value and value.Value
	end)
	diagFields.duit.Text = duit ~= nil and tostring(duit) or "N/A"
	local flops = LocalPlayer:GetAttribute("FlipFlopsFound")
	diagFields.flipflops.Text = flops ~= nil and tostring(flops) or "N/A"

	diagFields.fEsp.Text = toggleValue(cfg.espOpah) and "enabled" or "disabled"
	diagFields.fRadar.Text = toggleValue(cfg.radar) and "enabled" or "disabled"
	diagFields.fLoot.Text = toggleValue(cfg.autoLoot) and "enabled" or "disabled"
	diagFields.fHide.Text = toggleValue(cfg.autoHide) and "enabled" or "disabled"
	diagFields.fCodes.Text = toggleValue(cfg.autoRedeem) and "armed (gated)" or "disabled"

	remoteLabel.Text = "Remotes: " .. remotesSummary()

	for _, child in ipairs(errorFrame:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end
	if #hub.errors == 0 then
		local empty = makeLabel(errorFrame, "No errors captured this session.", 9, THEME.dim)
		empty.Size = UDim2.new(1, 0, 0, 20)
	else
		local start = math.max(1, #hub.errors - 15)
		for index = start, #hub.errors do
			local item = hub.errors[index]
			local row = Instance.new("Frame")
			row.BackgroundTransparency = 1
			row.Size = UDim2.new(1, 0, 0, 28)
			row.LayoutOrder = index
			row.Parent = errorFrame

			local scopeLabel = makeLabel(row, item.scope, 9, THEME.error, Enum.Font.GothamBold)
			scopeLabel.Position = UDim2.fromOffset(0, 0)
			scopeLabel.Size = UDim2.new(0.32, 0, 0, 13)
			scopeLabel.TextTruncate = Enum.TextTruncate.AtEnd

			local messageLabel = makeLabel(row, item.message, 8.5, THEME.muted)
			messageLabel.Position = UDim2.fromOffset(0, 13)
			messageLabel.Size = UDim2.new(1, 0, 0, 14)
			messageLabel.TextTruncate = Enum.TextTruncate.AtEnd
		end
	end
end

UI.refreshDiagnostics = refreshDiagnostics
UI.refreshGameInfo = refreshGameInfo

runDiagnostics = function()
	refreshDiagnostics()
	pushLog("accent", "Diagnostics report refreshed (v" .. VERSION .. ")")
	notify("Diagnostics", "Report refreshed - see the Diagnostics page", "success")
end
end
buildDiagnostics()

local function buildSettings()
--== Settings page ==
local scaleOptions = { "75%", "85%", "100%", "115%" }
local scaleValues = { 0.75, 0.85, 1, 1.15 }
local scaleState = newState("100%")

local interfaceCard = makeCard("Settings", "Interface", "▣", "Scaling, visibility and window position")
makeNote(interfaceCard.body, "GUI scale")
makeSelectChips(interfaceCard.body, scaleOptions, scaleState, 4)

scaleState:OnChanged(function(value)
	for index, option in ipairs(scaleOptions) do
		if option == value then
			cfg.guiScale:Set(scaleValues[index])
			return
		end
	end
end)

makeButtonRow(interfaceCard.body, {
	{
		text = "Hide window",
		onClick = function()
			if setUIVisible then setUIVisible(false) end
		end,
	},
	{
		text = "Center window",
		onClick = function()
			root.Position = UDim2.fromScale(0.5, 0.5)
			glow.Position = UDim2.fromScale(0.5, 0.5)
			pushLog("info", "Window re-centered")
		end,
	},
})

local keybindState = { key = Enum.KeyCode.RightControl, capturing = false }
UI.keybindState = keybindState

local keybindRow = Instance.new("Frame")
keybindRow.BackgroundColor3 = THEME.panel2
keybindRow.BackgroundTransparency = 0.25
keybindRow.BorderSizePixel = 0
keybindRow.Size = UDim2.new(1, 0, 0, 44)
keybindRow.Parent = interfaceCard.body
corner(keybindRow, 10)

local keybindTitle = makeLabel(keybindRow, "Toggle interface key", 11, THEME.text, Enum.Font.GothamSemibold)
keybindTitle.Position = UDim2.fromOffset(10, 4)
keybindTitle.Size = UDim2.new(1, -90, 0, 16)

local keybindValue = makeLabel(keybindRow, keybindState.key.Name, 9, theme.accent, Enum.Font.GothamBold)
keybindValue.Position = UDim2.fromOffset(10, 21)
keybindValue.Size = UDim2.new(1, -90, 0, 16)
bindAccent(keybindValue, "TextColor3")
UI.keybindValue = keybindValue

local bindButton = makeButton(keybindRow, "Bind", {
	size = UDim2.fromOffset(64, 26),
	textSize = 9.5,
	bg = THEME.panel3,
	onClick = function()
		keybindState.capturing = true
		keybindValue.Text = "press any key..."
	end,
})
bindButton.AnchorPoint = Vector2.new(1, 0.5)
bindButton.Position = UDim2.new(1, -9, 0.5, 0)

local themeCard = makeCard("Settings", "Theme", "◈", "Accent colours apply instantly without rebuilding the GUI")
local themeGridHolder = makeChipGrid(themeCard.body, ACCENTS, 4, 34)
local themeChips = {}
for index, preset in ipairs(ACCENTS) do
	local chip = Instance.new("TextButton")
	chip.AutoButtonColor = false
	chip.BorderSizePixel = 0
	chip.Text = preset.name
	chip.Font = Enum.Font.GothamBold
	chip.TextSize = 10
	chip.LayoutOrder = index
	chip.Parent = themeGridHolder
	corner(chip, 9)
	stroke(chip, preset.accent, 1, 0.5)
	themeChips[index] = chip
	chip.Activated:Connect(function()
		applyAccent(index)
	end)
end

local function renderThemeChips()
	for index, chip in ipairs(themeChips) do
		local active = index == theme.index
		chip.BackgroundColor3 = active and ACCENTS[index].accent2 or THEME.panel2
		chip.TextColor3 = active and THEME.white or THEME.muted
	end
end
table.insert(themeHooks, renderThemeChips)
renderThemeChips()

local overlayPolicyCard = makeCard("Settings", "Visibility", "◎", "Overlays keep their own toggles")
makeToggleRow(overlayPolicyCard.body, "Show interface", "Same state as the close button and the keybind", cfg.interfaceVisible)
makeNote(overlayPolicyCard.body, "Hiding the window keeps ESP, automation and enabled overlays running. Unload stops everything and removes this GUI.")

local function resetConfiguration()
	cfg.espOpah:Set(true)
	cfg.espKeys:Set(true)
	cfg.espNote:Set(true)
	cfg.espDoor:Set(true)
	cfg.espWardrobe:Set(false)
	cfg.espDrawer:Set(false)
	cfg.espLabels:Set(true)
	cfg.espDistance:Set(300)
	cfg.radar:Set(true)
	cfg.passOverlay:Set(true)
	cfg.autoLoot:Set(false)
	cfg.lootTargets:Set({ Drawers = true, Keys = true, ["Passcode note"] = true, ["Flip flops"] = false })
	cfg.lootMode:Set("Walk")
	cfg.lootRange:Set(250)
	cfg.pauseOnChase:Set(true)
	cfg.autoHide:Set(false)
	cfg.hideRange:Set(45)
	cfg.hideMode:Set("Teleport")
	cfg.teleportTarget:Set("Passcode note")
	cfg.autoRedeem:Set(false)
	cfg.codeDelay:Set(3)
	cfg.performanceMode:Set(false)
	cfg.guiScale:Set(1)
	scaleState:Set("100%")
	applyAccent(1)
	resetCodeEditor()
	pushLog("accent", "Configuration reset to defaults")
	notify("Configuration", "Defaults restored", "success")
end

local dangerCard = makeCard("Settings", "Session", "⏻", "Reset or unload safely")
makeButtonRow(dangerCard.body, {
	{ text = "Reset configuration", onClick = resetConfiguration },
	{
		text = "Unload script",
		accent = true,
		onClick = function()
			if ENV.RMSO_Unload then ENV.RMSO_Unload() end
		end,
	},
})

local aboutCard = makeCard("Settings", "About", "✦", "Client helper, unaffiliated with the game developer")
makeValueRow(aboutCard.body, "Version").Text = VERSION .. " " .. VERSION_TAG
makeValueRow(aboutCard.body, "Game").Text = GAME_NAME
makeValueRow(aboutCard.body, "Place ID").Text = tostring(GAME_PLACE_ID)
makeValueRow(aboutCard.body, "Universe").Text = tostring(GAME_UNIVERSE_ID)
makeValueRow(aboutCard.body, "Team").Text = "Robscript Team"
makeNote(aboutCard.body, "Features: ESP, radar, passcode overlay, auto loot, auto hide, teleport, diagnostics and a gated code manager. No game remote names or arguments are invented.")
end
buildSettings()

--== Radar overlay (frame inside the same ScreenGui) ==
local radarPanel = Instance.new("Frame")
radarPanel.Name = "RadarOverlay"
radarPanel.BackgroundColor3 = THEME.bg
radarPanel.BackgroundTransparency = 0.08
radarPanel.BorderSizePixel = 0
radarPanel.Position = UDim2.fromOffset(18, 108)
radarPanel.Size = UDim2.fromOffset(226, 126)
radarPanel.Parent = screen
corner(radarPanel, 14)
local radarStroke = stroke(radarPanel, theme.accent, 1, 0.5)
bindAccent(radarStroke, "Color")
gradient(radarPanel, Color3.fromHex("20132B"), Color3.fromHex("0A0710"), 55)

local radarHead = Instance.new("Frame")
radarHead.BackgroundTransparency = 1
radarHead.Position = UDim2.fromOffset(12, 8)
radarHead.Size = UDim2.new(1, -24, 0, 18)
radarHead.Parent = radarPanel

local radarHeadDot = Instance.new("Frame")
radarHeadDot.BackgroundColor3 = theme.accent
radarHeadDot.BorderSizePixel = 0
radarHeadDot.Position = UDim2.fromOffset(0, 6)
radarHeadDot.Size = UDim2.fromOffset(6, 6)
radarHeadDot.Parent = radarHead
corner(radarHeadDot, 999)
bindAccent(radarHeadDot, "BackgroundColor3")

local radarTitle = makeLabel(radarHead, "OPAH RADAR  ·  v" .. VERSION, 9, THEME.muted, Enum.Font.GothamBold)
radarTitle.Position = UDim2.fromOffset(12, 0)
radarTitle.Size = UDim2.new(1, -46, 0, 18)

local radarHide = makeButton(radarPanel, "✕", {
	size = UDim2.fromOffset(18, 18),
	textSize = 8,
	bg = THEME.panel3,
	color = THEME.muted,
	hover = false,
	onClick = function()
		cfg.radar:Set(false)
	end,
})
radarHide.AnchorPoint = Vector2.new(1, 0)
radarHide.Position = UDim2.new(1, -8, 0, 8)

local radarState = makeLabel(radarPanel, "State: N/A", 11, THEME.text, Enum.Font.GothamBold)
radarState.Position = UDim2.fromOffset(12, 30)
radarState.Size = UDim2.new(1, -24, 0, 18)

local radarDistance = makeLabel(radarPanel, "Distance: --", 9.5, THEME.muted)
radarDistance.Position = UDim2.fromOffset(12, 48)
radarDistance.Size = UDim2.new(1, -24, 0, 16)

local radarTarget = makeLabel(radarPanel, "Target: --", 9.5, THEME.muted)
radarTarget.Position = UDim2.fromOffset(12, 65)
radarTarget.Size = UDim2.new(1, -24, 0, 16)

local radarFooter = makeLabel(radarPanel, "Lair: --", 8.5, THEME.dim)
radarFooter.Position = UDim2.fromOffset(12, 88)
radarFooter.Size = UDim2.new(1, -24, 0, 28)
radarFooter.TextWrapped = true

UI.radar = radarPanel

--== Passcode overlay ==
local passPanel = Instance.new("Frame")
passPanel.Name = "PasscodeOverlay"
passPanel.AnchorPoint = Vector2.new(0.5, 0)
passPanel.Position = UDim2.new(0.5, 0, 0, 14)
passPanel.Size = UDim2.fromOffset(302, 74)
passPanel.BackgroundColor3 = THEME.bg
passPanel.BackgroundTransparency = 0.06
passPanel.BorderSizePixel = 0
passPanel.Parent = screen
corner(passPanel, 14)
local passStroke = stroke(passPanel, theme.accent, 1.2, 0.4)
bindAccent(passStroke, "Color")
gradient(passPanel, Color3.fromHex("241330"), Color3.fromHex("0B0711"), 50)

local passCaption = makeLabel(passPanel, "PASSCODE NOTE", 8, THEME.muted, Enum.Font.GothamBold)
passCaption.Position = UDim2.fromOffset(14, 9)
passCaption.Size = UDim2.new(1, -92, 0, 14)

local passValue = makeLabel(passPanel, "- - - -", 22, THEME.text, Enum.Font.GothamBold)
passValue.Position = UDim2.fromOffset(14, 24)
passValue.Size = UDim2.new(1, -100, 0, 32)

local passCopy = makeButton(passPanel, "COPY", {
	size = UDim2.fromOffset(62, 28),
	textSize = 9,
	bg = THEME.panel3,
	onClick = function()
		if UI.copyPasscode then UI.copyPasscode() end
	end,
})
passCopy.AnchorPoint = Vector2.new(1, 0.5)
passCopy.Position = UDim2.new(1, -12, 0.5, 0)

UI.passPanel = passPanel

--== Toasts ==
local toastHolder = Instance.new("Frame")
toastHolder.Name = "Toasts"
toastHolder.BackgroundTransparency = 1
toastHolder.AnchorPoint = Vector2.new(0.5, 0)
toastHolder.Position = UDim2.new(0.5, 0, 0, 14)
toastHolder.Size = UDim2.fromOffset(320, 240)
toastHolder.Parent = screen

local toastLayout = Instance.new("UIListLayout")
toastLayout.Padding = UDim.new(0, 6)
toastLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
toastLayout.SortOrder = Enum.SortOrder.LayoutOrder
toastLayout.Parent = toastHolder

local toastCount = 0
TOAST_PUSH = function(title, content, level)
	if not screen.Parent then return end
	local color = THEME.muted
	if level == "success" then color = THEME.success end
	if level == "warn" then color = THEME.warning end
	if level == "error" then color = THEME.error end

	if toastCount >= 3 then
		for _, child in ipairs(toastHolder:GetChildren()) do
			if child:IsA("Frame") then
				child:Destroy()
				toastCount = toastCount - 1
				break
			end
		end
	end

	local toast = Instance.new("Frame")
	toast.BackgroundColor3 = THEME.panel2
	toast.BackgroundTransparency = 0.05
	toast.BorderSizePixel = 0
	toast.Size = UDim2.fromOffset(300, 44)
	toast.Parent = toastHolder
	corner(toast, 10)
	stroke(toast, color, 1, 0.4)

	local accentBar = Instance.new("Frame")
	accentBar.BackgroundColor3 = color
	accentBar.BorderSizePixel = 0
	accentBar.Position = UDim2.fromOffset(0, 10)
	accentBar.Size = UDim2.fromOffset(3, 24)
	accentBar.Parent = toast
	corner(accentBar, 999)

	local titleLabel = makeLabel(toast, title, 10.5, THEME.text, Enum.Font.GothamBold)
	titleLabel.Position = UDim2.fromOffset(11, 5)
	titleLabel.Size = UDim2.new(1, -20, 0, 16)
	titleLabel.TextTruncate = Enum.TextTruncate.AtEnd

	local contentLabel = makeLabel(toast, content, 8.5, THEME.muted)
	contentLabel.Position = UDim2.fromOffset(11, 21)
	contentLabel.Size = UDim2.new(1, -20, 0, 14)
	contentLabel.TextTruncate = Enum.TextTruncate.AtEnd

	toastCount = toastCount + 1
	task.delay(3.4, function()
		if toast.Parent then
			toast:Destroy()
			toastCount = math.max(0, toastCount - 1)
		end
	end)
end

--== Floating reopen control (same ScreenGui) ==
local floatingButton = makeButton(screen, "MSO", {
	size = UDim2.fromOffset(54, 54),
	accent = true,
	radius = 16,
	textSize = 12,
	onClick = function()
		if setUIVisible then setUIVisible(true) end
	end,
})
floatingButton.Name = "ReopenButton"
floatingButton.AnchorPoint = Vector2.new(1, 1)
floatingButton.Position = UDim2.new(1, -16, 1, -16)
floatingButton.Visible = false
floatingButton.ZIndex = 60

--== Dragging ==
local function makeDraggable(target, handle)
	local dragging = false
	local dragStart = nil
	local startPosition = nil

	track(handle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPosition = target.Position
		end
	end))

	track(UserInputService.InputChanged:Connect(function(input)
		if not dragging or not dragStart or not startPosition then return end
		if input.UserInputType ~= Enum.UserInputType.MouseMovement
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		local delta = input.Position - dragStart
		target.Position = UDim2.new(
			startPosition.X.Scale,
			startPosition.X.Offset + delta.X,
			startPosition.Y.Scale,
			startPosition.Y.Offset + delta.Y)
		if target == root then
			glow.Position = target.Position
		end
	end))

	track(UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end))
end

makeDraggable(root, header)
makeDraggable(radarPanel, radarHead)

--== Responsive layout ==
local minimized = false

local function applyLayout()
	viewport = (workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize) or viewport
	local scale = clamp(cfg.guiScale:Get() or 1, 0.7, 1.2)
	local availableWidth = math.max(280, viewport.X - 16)
	local availableHeight = math.max(320, viewport.Y - 16)
	local baseWidth = clamp(availableWidth / scale, 300, 1180)
	local baseHeight = clamp(availableHeight / scale, 340, 780)

	rootScale.Scale = scale
	root.Size = UDim2.fromOffset(baseWidth, minimized and 58 or baseHeight)
	glow.Size = UDim2.fromOffset(baseWidth + 18, (minimized and 58 or baseHeight) + 18)
	glow.Visible = cfg.interfaceVisible:Get() and not minimized

	local compact = viewport.X < 940
	local mobile = viewport.X < 660
	local sidebarWidth = compact and 74 or 218

	sidebar.Size = UDim2.new(0, sidebarWidth, 1, 0)
	main.Position = UDim2.new(0, sidebarWidth, 0, 0)
	main.Size = UDim2.new(1, -sidebarWidth, 1, 0)

	brand.Visible = not compact
	navHolder.Position = compact and UDim2.fromOffset(8, 10) or UDim2.fromOffset(8, 122)
	navHolder.Size = compact and UDim2.new(1, -16, 1, -100) or UDim2.new(1, -16, 1, -220)
	for _, visuals in pairs(UI.navLabels) do
		visuals.text.Visible = not compact
		visuals.icon.Position = compact and UDim2.new(0, 0, 0, 0) or UDim2.fromOffset(12, 0)
		visuals.icon.Size = compact and UDim2.new(1, 0, 1, 0) or UDim2.fromOffset(24, 44)
	end

	profile.Size = compact and UDim2.new(1, -12, 0, 56) or UDim2.new(1, -20, 0, 76)
	profile.Position = UDim2.new(0, compact and 6 or 10, 1, -10)
	avatarFrame.Position = compact and UDim2.new(0.5, -20, 0.5, -20) or UDim2.fromOffset(9, 18)
	profileName.Visible = not compact
	profileHandle.Visible = not compact
	profileState.Visible = not compact
	profileDot.Visible = not compact

	searchWrap.Visible = (not mobile) and (not minimized)
	pageHost.Visible = not minimized
	sidebar.Visible = not minimized

	pageHost.Position = UDim2.fromOffset(mobile and 10 or 14, 62)
	pageHost.Size = UDim2.new(1, mobile and -20 or -28, 1, -76)

	local home = UI.home
	if home and home.banner then
		local hasAvatar = home.bannerAvatar and home.bannerAvatar.Image ~= nil and home.bannerAvatar.Image ~= ""
		home.banner.Size = UDim2.new(1, 0, 0, mobile and 172 or 118)
		home.bannerAvatar.Visible = hasAvatar and not mobile
		home.bannerPortraitFallback.Visible = (not hasAvatar) and not mobile
		if mobile then
			home.bannerText.Position = UDim2.fromOffset(14, 10)
			home.bannerText.Size = UDim2.new(1, -28, 1, -20)
			home.bannerPill.Visible = false
			home.mobileStatus.Visible = true
			home.statRow.Size = UDim2.new(1, 0, 0, 150)
			home.statGrid.CellSize = UDim2.new(0.5, -6, 0, 72)
			home.quickCard.Size = UDim2.new(1, 0, 0, 238)
			home.quickLayout.CellSize = UDim2.new(1 / 3, -7, 0, 92)
			home.bottomRow.Size = UDim2.new(1, 0, 0, 312)
			home.statusCard.Size = UDim2.new(1, 0, 0, 150)
			home.perfCard.Size = UDim2.new(1, 0, 0, 150)
			home.perfCard.AnchorPoint = Vector2.new(0, 0)
			home.perfCard.Position = UDim2.new(0, 0, 0, 162)
		else
			home.bannerText.Position = UDim2.fromOffset(hasAvatar and 178 or 14, 12)
			home.bannerText.Size = UDim2.new(1, hasAvatar and -396 or -232, 1, -24)
			home.bannerPill.Visible = true
			home.mobileStatus.Visible = false
			home.statRow.Size = UDim2.new(1, 0, 0, 74)
			home.statGrid.CellSize = UDim2.new(0.25, -6, 0, 72)
			home.quickCard.Size = UDim2.new(1, 0, 0, 156)
			home.quickLayout.CellSize = UDim2.new(1 / 6, -7, 0, 92)
			home.bottomRow.Size = UDim2.new(1, 0, 0, 150)
			home.statusCard.Size = UDim2.new(0.5, -5, 1, 0)
			home.perfCard.Size = UDim2.new(0.5, -5, 1, 0)
			home.perfCard.AnchorPoint = Vector2.new(1, 0)
			home.perfCard.Position = UDim2.new(1, 0, 0, 0)
		end
	end

	radarPanel.Position = UDim2.fromOffset(mobile and 10 or 18, mobile and 96 or 108)
	passPanel.Size = UDim2.fromOffset(math.min(302, baseWidth - 24), 74)
	toastHolder.Size = UDim2.fromOffset(math.min(320, baseWidth - 24), 240)
	toastHolder.Position = UDim2.new(0.5, 0, 0, 14)
end

cfg.guiScale:OnChanged(function()
	applyLayout()
end)

if workspace.CurrentCamera then
	track(workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		if workspace.CurrentCamera then
			viewport = workspace.CurrentCamera.ViewportSize
			applyLayout()
		end
	end))
end

--== Search ==
UI.applySearch = function(text)
	local query = string.lower(trim(text or ""))
	for _, item in ipairs(searchables) do
		item.card.Visible = true
	end
	for _, visuals in pairs(UI.navLabels) do
		visuals.button.Visible = true
	end
	if query == "" then return end

	local matchedPages = {}
	for _, item in ipairs(searchables) do
		if string.find(string.lower(item.title), query, 1, true) then
			matchedPages[item.page] = true
		end
	end
	for pageName, visuals in pairs(UI.navLabels) do
		local pageMatches = string.find(string.lower(pageName), query, 1, true) ~= nil
		visuals.button.Visible = pageMatches or matchedPages[pageName] == true
	end
	if currentPage then
		for _, item in ipairs(searchables) do
			if item.page == currentPage then
				item.card.Visible = string.find(string.lower(item.title), query, 1, true) ~= nil
			end
		end
	end
end

track(searchBox:GetPropertyChangedSignal("Text"):Connect(function()
	UI.applySearch(searchBox.Text)
end))

--== Interface visibility ==
setUIVisible = function(visible)
	visible = visible == true
	cfg.interfaceVisible:Set(visible)
	root.Visible = visible
	glow.Visible = visible and not minimized
	floatingButton.Visible = not visible
	if not visible then
		pushLog("info", "Interface hidden - press the toggle key to reopen")
	end
end

UI.toggleMinimized = function()
	minimized = not minimized
	minimizeButton.Text = minimized and "+" or "—"
	applyLayout()
end

applyLayout()

--== Slider input (single shared connection) ==
track(UserInputService.InputChanged:Connect(function(input)
	if not activeSlider then return end
	if input.UserInputType == Enum.UserInputType.MouseMovement
		or input.UserInputType == Enum.UserInputType.Touch then
		activeSlider.update(input.Position.X)
	end
end))

track(UserInputService.InputEnded:Connect(function(input)
	if activeSlider and (input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch) then
		activeSlider = nil
	end
end))

--== Keybind (toggle window, capture new key) ==
track(UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	local keybind = UI.keybindState
	if keybind and keybind.capturing then
		keybind.capturing = false
		if input.KeyCode ~= Enum.KeyCode.Unknown then
			keybind.key = input.KeyCode
			if UI.keybindValue then UI.keybindValue.Text = input.KeyCode.Name end
			pushLog("accent", "Interface toggle key set to " .. input.KeyCode.Name)
		end
		return
	end
	if keybind and input.KeyCode == keybind.key then
		setUIVisible(not cfg.interfaceVisible:Get())
	end
end))

--== Auto loot ==
local function playerNameFromUserId(userId)
	if not userId then return nil end
	local ok, player = pcall(function() return Players:GetPlayerByUserId(userId) end)
	if ok and player then return player.Name end
	return nil
end

local function findLootTarget(origin)
	local selected = cfg.lootTargets:Get() or {}
	local best, bestDistance = nil, math.huge
	local maxRange = numberValue(cfg.lootRange, 250)

	local function consider(prompt, position, kind)
		if not prompt or not prompt.Enabled or not position then return end
		local expires = lootBlacklist[prompt]
		if expires and expires > os.clock() then return end
		local distance = distanceBetween(position, origin)
		if distance > maxRange then return end
		if distance < bestDistance then
			bestDistance = distance
			best = { prompt = prompt, position = position, kind = kind }
		end
	end

	if selected["Drawers"] then
		for _, prompt in ipairs(hub.world.drawers) do
			consider(prompt, promptPosition(prompt), "drawer")
		end
	end
	if selected["Keys"] then
		for _, key in ipairs(hub.world.keys) do
			consider(findPickupPrompt(key), instancePosition(key), "key")
		end
	end
	if selected["Passcode note"] and hub.world.note then
		consider(findPickupPrompt(hub.world.note), instancePosition(hub.world.note), "passcode note")
	end
	if selected["Flip flops"] then
		for _, prompt in ipairs(hub.world.flipflops) do
			consider(prompt, promptPosition(prompt), "flip flop")
		end
	end

	return best
end

lootStep = function()
	if not toggleValue(cfg.autoLoot) or hub.hideInProgress or hub.hiddenPrompt or not isAlive() then return end
	local root = getRoot()
	if not root then return end
	if toggleValue(cfg.pauseOnChase) then
		local opah = opahSummary()
		if opah and opah.chasing and opah.distance < 55 then return end
	end
	local target = findLootTarget(root.Position)
	if not target then return end

	local mode = cfg.lootMode:Get()
	if mode == "Teleport" then
		teleportNear(target.position)
		task.wait(0.15)
	else
		local reached = walkTo(target.position, 7, 6)
		if not reached then
			lootBlacklist[target.prompt] = os.clock() + 15
			pushLog("info", "Skipped " .. tostring(target.kind) .. " (unreachable)")
			return
		end
	end

	local fired = triggerPrompt(target.prompt)
	if fired then
		lootBlacklist[target.prompt] = os.clock() + 8
		pushLog("success", "Looted " .. tostring(target.kind))
	else
		lootBlacklist[target.prompt] = os.clock() + 3
	end
	task.wait(0.2)
end

--== Auto hide ==
hideStep = function()
	if not toggleValue(cfg.autoHide) then
		if hub.hiddenPrompt then
			triggerPrompt(hub.hiddenPrompt)
			hub.hiddenPrompt = nil
			pushLog("info", "Left the wardrobe (auto hide off)")
		end
		return
	end

	local opah = opahSummary()
	local root = getRoot()

	if hub.hiddenPrompt then
		local safe = true
		if opah and opah.chasing then
			safe = opah.distance > numberValue(cfg.hideRange, 45) + 25
		end
		if safe or not root then
			triggerPrompt(hub.hiddenPrompt)
			pushLog("info", "Left the wardrobe")
			hub.hiddenPrompt = nil
		end
		return
	end

	if not root or not opah or not opah.chasing or opah.distance > numberValue(cfg.hideRange, 45) then
		return
	end

	local prompt = nearestWardrobePrompt(root.Position)
	if not prompt then return end

	hub.hideInProgress = true
	local mode = cfg.hideMode:Get()
	if mode == "Walk" then
		walkTo(promptPosition(prompt), 7, 5)
	else
		teleportNear(promptPosition(prompt))
		task.wait(0.2)
	end
	triggerPrompt(prompt)
	hub.hideInProgress = false
	hub.hiddenPrompt = prompt
	pushLog("warn", "Hiding - Opah is chasing")
end

--== Overlay + dashboard refresh ==
local function updateRadar()
	local visible = toggleValue(cfg.radar) and cfg.interfaceVisible:Get()
	radarPanel.Visible = visible
	if not visible then return end

	local opah = opahSummary()
	if not opah then
		radarState.Text = "No Opah in workspace"
		radarState.TextColor3 = THEME.muted
		radarDistance.Text = "Distance: --"
		radarTarget.Text = "Target: --"
		radarTarget.TextColor3 = THEME.muted
		radarFooter.Text = "Hidden: " .. (hub.hiddenPrompt and "yes" or "no")
		radarStroke.Color = THEME.strokeSoft
		radarHeadDot.BackgroundColor3 = THEME.dim
		return
	end

	local isMine = opah.targetUserId == LocalPlayer.UserId
	radarState.Text = "State: " .. (opah.chasing and ("CHASING - " .. opah.mode) or opah.state)
	radarDistance.Text = string.format("Distance: %d stud", round(opah.distance))
	radarTarget.Text = "Target: " .. (isMine and "YOU" or (playerNameFromUserId(opah.targetUserId) or "none"))
	radarTarget.TextColor3 = isMine and THEME.error or THEME.muted
	radarState.TextColor3 = isMine and THEME.error or (opah.chasing and THEME.warning or THEME.success)
	radarStroke.Color = isMine and THEME.error or (opah.chasing and THEME.warning or theme.accent)
	radarHeadDot.BackgroundColor3 = isMine and THEME.error or (opah.chasing and THEME.warning or theme.accent)
	radarFooter.Text = "Lair: " .. opah.lairText .. "  ·  Hidden: " .. (hub.hiddenPrompt and "yes" or "no")
end

local function updatePasscodePanel()
	local visible = toggleValue(cfg.passOverlay) and cfg.interfaceVisible:Get()
	passPanel.Visible = visible
	if visible then
		passValue.Text = hub.code and tostring(hub.code) or "- - - -"
	end
end

local function updateHomeUI()
	local home = UI.home
	if not home or not home.keysValue then return end

	if hub.world.valid then
		home.keysValue.Text = clamp(5 - #hub.world.keys, 0, 5) .. " / 5"
	else
		home.keysValue.Text = "N/A"
	end
	home.passValue.Text = hub.code and tostring(hub.code) or "- - - -"

	local count = #Players:GetPlayers()
	local maxPlayers = Players.MaxPlayers
	home.playersValue.Text = (maxPlayers and maxPlayers > 0) and (count .. " / " .. maxPlayers) or tostring(count)
	home.timeValue.Text = formatClock(os.clock() - hub.sessionStart)

	local opah = opahSummary()
	if opah then
		local stateText = opah.chasing and ("Chasing - " .. opah.mode) or opah.state
		home.pillState.Text = "Opah: " .. stateText
		home.pillState.TextColor3 = opah.chasing and THEME.error or THEME.text
		home.pillDistance.Text = string.format("Distance: %d stud", round(opah.distance))
		home.pillDot.BackgroundColor3 = opah.chasing and THEME.error or THEME.success
		home.mobileStatus.Text = string.format("Opah: %s  ·  %d stud", stateText, round(opah.distance))
		home.mobileStatus.TextColor3 = opah.chasing and THEME.error or THEME.muted
	else
		home.pillState.Text = "Opah: N/A"
		home.pillState.TextColor3 = THEME.muted
		home.pillDistance.Text = "Distance: --"
		home.pillDot.BackgroundColor3 = THEME.dim
		home.mobileStatus.Text = "Opah: N/A"
		home.mobileStatus.TextColor3 = THEME.muted
	end

	UI.profileState.Text = "session " .. formatClock(os.clock() - hub.sessionStart)
end

cfg.interfaceVisible:OnChanged(function(value)
	root.Visible = value
	glow.Visible = value and not minimized
	floatingButton.Visible = not value
end)

--== Performance metrics (measured, never fabricated) ==
local frameCount = 0
local frameTime = 0
track(RunService.RenderStepped:Connect(function(delta)
	frameCount = frameCount + 1
	frameTime = frameTime + delta
end))

local function updateMetrics()
	local fps = nil
	if frameTime > 0 then
		fps = frameCount / frameTime
	end
	frameCount = 0
	frameTime = 0

	if fps and fps > 0 then
		UI.home.fpsValue.Text = string.format("%d FPS", round(fps))
		if UI.pushGraphSample then UI.pushGraphSample(fps) end
	else
		UI.home.fpsValue.Text = "N/A"
	end

	local ping = getPing()
	UI.home.pingValue.Text = ping ~= nil and (tostring(ping) .. " MS") or "N/A"

	local memory = getMemoryMb()
	UI.home.memoryValue.Text = memory ~= nil and (tostring(memory) .. " MB") or "N/A"
end

updateHomeUI()
updateRadar()
updatePasscodePanel()

--== Unload ==
local function unload()
	if not hub.running then return end
	hub.running = false
	hub.initOk = false
	clearEsp()
	for index = #hub.connections, 1, -1 do
		local connection = hub.connections[index]
		hub.connections[index] = nil
		if connection then
			pcall(function() connection:Disconnect() end)
		end
	end
	pcall(function() screen:Destroy() end)
	if ENV.RMSO_Unload == unload then
		ENV.RMSO_Unload = nil
	end
	ENV.MSO = nil
	print("[MSO] unloaded v" .. VERSION)
end

ENV.RMSO_Unload = unload
ENV.MSO = {
	version = VERSION,
	tag = VERSION_TAG,
	hub = hub,
	cfg = cfg,
	ui = UI,
	unload = unload,
	scanWorld = scanWorld,
	syncEsp = syncEsp,
	clearEsp = clearEsp,
	runDiagnostics = runDiagnostics,
	refreshDiagnostics = refreshDiagnostics,
	resolveTargetPosition = resolveTargetPosition,
}

--== Startup ==
selectPage("Home")
applyLayout()
refreshDiagnostics()
hub.initOk = true

pushLog("accent", "Loaded " .. VERSION_TAG .. " (v" .. VERSION .. ")")
pushLog("info", "Press " .. UI.keybindState.key.Name .. " to toggle the interface")
notify("Loaded", "Malam Sama Opah v" .. VERSION .. " ready", "success")

scanWorld()
syncEsp()
updateHomeUI()

task.spawn(function()
	if UI.refreshGameInfo and UI.refreshGameInfo() then
		refreshDiagnostics()
		pushLog("success", "Official game info refreshed")
	else
		pushLog("info", "Official game info unavailable - diagnostics shows unverified")
	end
end)

--== Background loops (interval based, no Heartbeat spam) ==
task.spawn(function()
	while hub.running do
		local ok, err = pcall(scanWorld)
		if not ok then captureError("world scan", err) end
		task.wait(toggleValue(cfg.performanceMode) and 2 or 1)
	end
end)

task.spawn(function()
	while hub.running do
		local ok, err = pcall(syncEsp)
		if not ok then captureError("esp sync", err) end
		task.wait(toggleValue(cfg.performanceMode) and 0.8 or 0.45)
	end
end)

task.spawn(function()
	while hub.running do
		local ok, err = pcall(function()
			updateRadar()
			updatePasscodePanel()
			updateHomeUI()
			updateMetrics()
		end)
		if not ok then captureError("dashboard", err) end
		task.wait(toggleValue(cfg.performanceMode) and 0.8 or 0.5)
	end
end)

task.spawn(function()
	while hub.running do
		if toggleValue(cfg.autoLoot) then
			local ok, err = pcall(lootStep)
			if not ok then captureError("auto loot", err) end
		end
		task.wait(0.35)
	end
end)

task.spawn(function()
	while hub.running do
		local ok, err = pcall(hideStep)
		if not ok then captureError("auto hide", err) end
		task.wait(0.3)
	end
end)

print(string.format("[MSO] loaded v%s %s | drawers=%d wardrobes=%d keys=%d locks=%d",
	VERSION, VERSION_TAG, #hub.world.drawers, #hub.world.wardrobes, #hub.world.keys, #hub.world.locks))
