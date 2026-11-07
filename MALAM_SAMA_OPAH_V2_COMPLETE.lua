--!strict
--[[
	Robscript Team - Malam Sama Opah
	Version 2.0.0

	Client-side helper for "[CLASS] MALAM SAMA OPAH" by Sabun Studios
	(place 101051454784523, universe 10772066587).

	Features:
		* ESP: Opah, keys, passcode note, front door, wardrobes, drawers
		* Opah radar: state, distance, chase target
		* Passcode overlay with clipboard copy
		* Auto loot: drawers, keys, passcode note, flip flops (walk or teleport)
		* Auto hide: nearest wardrobe while Opah is chasing
		* Teleport / walk to markers
		* Diagnostics ("Check my game")
		* 2.5D mobile-first quick control deck

	UI: Robly Airflow (bobloscript/Robly_Airflow) plus native 2.5D overlay.
	Language: English only.
]]

local VERSION = "2.0.0"
local GAME_NAME = "[CLASS] MALAM SAMA OPAH"
local GAME_PLACE_ID = 101051454784523

--== Re-execution guard ==
local environment = (typeof(getgenv) == "function" and getgenv()) or _G
if environment.RMSO_Unload then
	pcall(environment.RMSO_Unload)
end

--== Services ==
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local LocalPlayer = Players.LocalPlayer

--== Constants ==
local COLOR_OPAH = Color3.fromRGB(255, 60, 60)
local COLOR_KEY_UNKNOWN = Color3.fromRGB(240, 240, 240)
local COLOR_NOTE = Color3.fromRGB(255, 255, 255)
local COLOR_DOOR = Color3.fromRGB(255, 165, 40)
local COLOR_WARDROBE = Color3.fromRGB(70, 220, 120)
local COLOR_DRAWER = Color3.fromRGB(220, 200, 90)

local KEY_COLORS = {
	Red = Color3.fromRGB(255, 75, 75),
	Blue = Color3.fromRGB(80, 140, 255),
	Green = Color3.fromRGB(75, 220, 115),
	Yellow = Color3.fromRGB(255, 210, 60),
	Purple = Color3.fromRGB(185, 105, 255),
}

local KEY_ORDER = { "Red", "Blue", "Green", "Yellow", "Purple" }

--== State ==
local hub = {
	running = true,
	world = {
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
}

local lootBlacklist = {}

--== Helpers ==
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
	if instance:IsA("BasePart") then return instance.Position end
	if instance:IsA("Attachment") then return instance.WorldPosition end
	if instance:IsA("Model") then
		local ok, pivot = pcall(function() return instance:GetPivot() end)
		if ok and pivot then return pivot.Position end
	end
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

local function escapeRich(text)
	if type(text) ~= "string" then return "" end
	local result = text:gsub("&", "&amp;")
	result = result:gsub("<", "&lt;")
	result = result:gsub(">", "&gt;")
	return result
end

local function isAlive()
	local root = getRoot()
	local humanoid = getHumanoid()
	if not root or not humanoid or humanoid.Health <= 0 then return false end
	if LocalPlayer:GetAttribute("Out") == true then return false end
	return true
end

local function toggleValue(handle)
	return handle ~= nil and handle.Value == true
end

local function numberValue(handle, fallback)
	local value = handle and handle.Value
	if type(value) == "number" then return value end
	return fallback
end

local function selectedValues(handle)
	local value = handle and handle.Value
	if type(value) == "table" then return value end
	if type(value) == "string" then return { value } end
	return {}
end

local function listContains(list, value)
	for _, item in ipairs(list) do
		if item == value then return true end
	end
	return false
end

--== Airflow UI ==
local UI_SOURCES = {
	"https://raw.githubusercontent.com/bobloscript/Robly_Airflow/main/Source.luau",
	"https://raw.githubusercontent.com/PookiePepelsss/Airflow-UI/refs/heads/main/Source.luau",
}

local Airflow = nil
for _, url in ipairs(UI_SOURCES) do
	local ok, library = pcall(function()
		return loadstring(game:HttpGet(url))()
	end)
	if ok and type(library) == "table" and type(library.CreateWindow) == "function" then
		Airflow = library
		break
	end
end

if not Airflow then
	warn("[RMSO] Airflow UI could not be loaded")
	return
end

local THEME = {
	Background = Color3.fromHex("#0A0A0C"),
	Surface = Color3.fromHex("#141418"),
	Surface2 = Color3.fromHex("#1A1A20"),
	Surface3 = Color3.fromHex("#2A2A33"),
	Stroke = Color3.fromRGB(38, 38, 46),
	StrokeHover = Color3.fromRGB(60, 60, 73),
	Accent = Color3.fromHex("#FF3B7F"),
	AccentDark = Color3.fromHex("#1A0710"),
	Text = Color3.fromHex("#F5F5F7"),
	Muted = Color3.fromHex("#8D8D99"),
}

if Airflow.ThemePresets then Airflow.ThemePresets.Robscript = THEME end
Airflow:SetDefaultTheme(THEME)

local cameraForSize = workspace.CurrentCamera
local initialViewport = cameraForSize and cameraForSize.ViewportSize or Vector2.new(800, 640)
local Window = Airflow:CreateWindow({
	Name = "Robscript Team - Malam Sama Opah",
	LoadingSubtitle = "esp, radar, auto loot",
	ToggleUIKeybind = "RightControl",
	Size = UDim2.fromOffset(
		math.min(780, math.max(300, initialViewport.X - 32)),
		math.min(540, math.max(360, initialViewport.Y - 100))
	),
	Backdrop = { Weather = "Fireflies", Tint = 0.35 },
	Theme = THEME,
	ConfigurationSaving = { Enabled = true, FolderName = "RobscriptMalamSamaOpah" },
	Home = {
		Title = "Malam Sama Opah",
		Welcome = "Welcome back,",
		Tier = "v" .. VERSION,
		Stats = { "Players", "Session", "FPS", "Ping", "Game", "Executor" },
	},
})

--== UI handles (assigned below, read by the loops) ==
local EspOpah, EspKeys, EspNote, EspDoor, EspWardrobe, EspDrawer
local EspLabels, EspMaxDistance, RadarEnabled, PasscodeOverlay
local AutoLoot, LootTargets, LootMode, LootRange, PauseOnChase
local AutoHide, HideRange, HideMode
local TeleportTarget
local ActivityLog
local KeysStatus, LocksStatus, PasscodeStatus, OpahStateStatus, LootStatus, HideStatus

local function pushLog(text)
	if ActivityLog then
		pcall(function() ActivityLog:Push(text) end)
	end
end

local function notify(title, content, style)
	pcall(function()
		Window:Notify({ Title = title, Content = content, Type = style or "Info" })
	end)
end

--== World scan ==
local function readPasscodeLabel(note)
	if not note then return nil end
	local label = note:FindFirstChild("Code", true)
	if label and label:IsA("TextLabel") then
		local text = label.Text
		if type(text) == "string" and text:gsub("%s", "") ~= "" then return text end
	end
	return nil
end

local function scanWorld()
	local world = {
		drawers = {}, flipflops = {}, wardrobes = {}, keys = {}, locks = {},
		note = nil, opah = workspace:FindFirstChild("Opah"),
		door = workspace:FindFirstChild("FrontDoor"), code = nil, drawerTotal = 0,
	}
	local chests = workspace:FindFirstChild("PuzzleChests")
	if chests then
		for _, instance in ipairs(chests:GetDescendants()) do
			if instance:IsA("ProximityPrompt") then
				if instance.ActionText == "Open" then
					table.insert(world.drawers, instance)
					world.drawerTotal += 1
				elseif instance.ActionText == "Close" then
					world.drawerTotal += 1
				end
			end
		end
	end
	local flipFlops = workspace:FindFirstChild("FlipFlops")
	if flipFlops then
		for _, instance in ipairs(flipFlops:GetDescendants()) do
			if instance:IsA("ProximityPrompt") and instance.ActionText == "Pick up" then
				table.insert(world.flipflops, instance)
			end
		end
	end
	local wardrobes = workspace:FindFirstChild("HidingWardrobes")
	if wardrobes then
		for _, instance in ipairs(wardrobes:GetDescendants()) do
			if instance:IsA("ProximityPrompt") and instance.ActionText == "Hide" then
				table.insert(world.wardrobes, instance)
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
	local door = world.door
	if door then
		local locks = door:FindFirstChild("PuzzleLocks")
		if locks then
			for _, lock in ipairs(locks:GetChildren()) do table.insert(world.locks, lock) end
		end
	end
	hub.world = world
	for prompt in pairs(lootBlacklist) do
		if prompt.Parent == nil then lootBlacklist[prompt] = nil end
	end
	if world.code and world.code ~= hub.code then
		hub.code = world.code
		pushLog("<Accent>Passcode</Accent> found: <b>" .. escapeRich(world.code) .. "</b>")
	end
end

local function keyColor(keyModel)
	local name = keyModel:GetAttribute("KeyColor")
	return KEY_COLORS[name] or COLOR_KEY_UNKNOWN, name
end

local function lockColor(lockModel)
	local value = lockModel:GetAttribute("KeyColorValue")
	if typeof(value) == "Color3" then return value end
	local name = lockModel:GetAttribute("KeyColor")
	return KEY_COLORS[name] or COLOR_DOOR
end

local function lockPrompt(lockModel)
	for _, descendant in ipairs(lockModel:GetDescendants()) do
		if descendant:IsA("ProximityPrompt") then return descendant end
	end
	return nil
end

local function findPickupPrompt(model)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("ProximityPrompt") and descendant.ActionText == "Pick up" then
			return descendant
		end
	end
	return nil
end

local function wardrobeModelFromPrompt(prompt)
	local parent = prompt.Parent
	while parent and not parent:IsA("Model") do parent = parent.Parent end
	return parent
end

--== ESP ==
local function createEspEntry(instance, color, labelText, withLabel)
	local highlight = Instance.new("Highlight")
	highlight.Name = "RMSO_Highlight"
	highlight.FillColor = color
	highlight.FillTransparency = 0.72
	highlight.OutlineColor = color
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Adornee = instance
	highlight.Parent = instance
	local billboard = nil
	if withLabel and labelText then
		billboard = Instance.new("BillboardGui")
		billboard.Name = "RMSO_Label"
		billboard.Size = UDim2.fromOffset(150, 22)
		billboard.StudsOffsetWorldSpace = Vector3.new(0, 2.4, 0)
		billboard.AlwaysOnTop = true
		billboard.MaxDistance = 600
		billboard.LightInfluence = 0
		billboard.Adornee = instance
		local text = Instance.new("TextLabel")
		text.BackgroundTransparency = 1
		text.Size = UDim2.fromScale(1, 1)
		text.Font = Enum.Font.GothamBold
		text.TextSize = 13
		text.TextColor3 = color
		text.TextStrokeTransparency = 0.35
		text.Text = labelText
		text.Parent = billboard
		billboard.Parent = instance
	end
	return { highlight = highlight, billboard = billboard, labelText = labelText }
end

local function destroyEspEntry(entry)
	if entry.highlight then pcall(function() entry.highlight:Destroy() end) end
	if entry.billboard then pcall(function() entry.billboard:Destroy() end) end
end

local function syncEsp()
	local camera = getCamera()
	local origin = camera and camera.CFrame.Position or Vector3.new(0, 0, 0)
	local maxDistance = numberValue(EspMaxDistance, 300)
	local withLabels = toggleValue(EspLabels)
	local desired = {}
	local function add(instance, color, labelText)
		if not instance or instance.Parent == nil then return end
		local position = instancePosition(instance)
		if position and distanceBetween(position, origin) > maxDistance then return end
		desired[instance] = { color = color, label = labelText }
	end
	local world = hub.world
	if toggleValue(EspOpah) and world.opah then add(world.opah, COLOR_OPAH, "OPAH") end
	if toggleValue(EspKeys) then
		for _, key in ipairs(world.keys) do
			local color, name = keyColor(key)
			add(key, color, string.upper(name or "KEY") .. " KEY")
		end
	end
	if toggleValue(EspNote) and world.note then add(world.note, COLOR_NOTE, "PASSCODE") end
	if toggleValue(EspDoor) and world.door then
		add(world.door, COLOR_DOOR, "EXIT")
		local keypad = world.door:FindFirstChild("Keypad")
		if keypad then
			local plate = keypad:FindFirstChild("Plate", true)
			add(plate or keypad, COLOR_DOOR, "KEYPAD")
		end
		for _, lock in ipairs(world.locks) do add(lock, lockColor(lock), "LOCK") end
	end
	if toggleValue(EspWardrobe) then
		for _, prompt in ipairs(world.wardrobes) do
			local wardrobe = wardrobeModelFromPrompt(prompt)
			if wardrobe then add(wardrobe, COLOR_WARDROBE, "HIDE") end
		end
	end
	if toggleValue(EspDrawer) then
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
			entry.highlight.FillColor = spec.color
			entry.highlight.OutlineColor = spec.color
			if entry.billboard and entry.labelText ~= spec.label then
				destroyEspEntry(entry)
				hub.esp[instance] = createEspEntry(instance, spec.color, spec.label, withLabels)
			elseif withLabels and not entry.billboard then
				hub.esp[instance] = createEspEntry(instance, spec.color, spec.label, true)
			elseif not withLabels and entry.billboard then
				entry.billboard:Destroy()
				entry.billboard = nil
			end
		end
	end
	for instance, entry in pairs(hub.esp) do
		if not desired[instance] or instance.Parent == nil then
			destroyEspEntry(entry)
			hub.esp[instance] = nil
		end
	end
end

local function clearEsp()
	for instance, entry in pairs(hub.esp) do
		destroyEspEntry(entry)
		hub.esp[instance] = nil
	end
end

--== Overlay GUIs ==
local guiParent = LocalPlayer:WaitForChild("PlayerGui")
if typeof(gethui) == "function" then
	local ok, hidden = pcall(gethui)
	if ok and hidden then guiParent = hidden end
end

local radarGui = Instance.new("ScreenGui")
radarGui.Name = "RMSO_Radar"
radarGui.ResetOnSpawn = false
radarGui.IgnoreGuiInset = true
radarGui.DisplayOrder = 900
radarGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
radarGui.Parent = guiParent

local radarFrame = Instance.new("Frame")
radarFrame.Name = "Panel"
radarFrame.AnchorPoint = Vector2.new(0, 0)
radarFrame.Position = UDim2.fromOffset(16, 96)
radarFrame.Size = UDim2.fromOffset(232, 108)
radarFrame.BackgroundColor3 = THEME.Background
radarFrame.BackgroundTransparency = 0.12
radarFrame.BorderSizePixel = 0
radarFrame.Parent = radarGui
Instance.new("UICorner", radarFrame).CornerRadius = UDim.new(0, 10)
local radarStroke = Instance.new("UIStroke")
radarStroke.Color = THEME.Stroke
radarStroke.Thickness = 1
radarStroke.Parent = radarFrame

local radarTitle = Instance.new("TextLabel")
radarTitle.BackgroundTransparency = 1
radarTitle.Position = UDim2.fromOffset(12, 8)
radarTitle.Size = UDim2.new(1, -24, 0, 16)
radarTitle.Font = Enum.Font.GothamBold
radarTitle.TextSize = 11
radarTitle.TextXAlignment = Enum.TextXAlignment.Left
radarTitle.TextColor3 = THEME.Muted
radarTitle.Text = "OPAH RADAR - v" .. VERSION
radarTitle.Parent = radarFrame

local function makeRadarLine(offsetY, textSize, color)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromOffset(12, offsetY)
	label.Size = UDim2.new(1, -24, 0, textSize + 4)
	label.Font = Enum.Font.GothamMedium
	label.TextSize = textSize
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = color
	label.Text = ""
	label.Parent = radarFrame
	return label
end
local radarState = makeRadarLine(28, 13, THEME.Text)
local radarDistance = makeRadarLine(48, 12, THEME.Muted)
local radarTarget = makeRadarLine(68, 12, THEME.Muted)
local radarFooter = makeRadarLine(87, 11, THEME.Muted)

local passGui = Instance.new("ScreenGui")
passGui.Name = "RMSO_Passcode"
passGui.ResetOnSpawn = false
passGui.IgnoreGuiInset = true
passGui.DisplayOrder = 900
passGui.Parent = guiParent

local passFrame = Instance.new("Frame")
passFrame.AnchorPoint = Vector2.new(0.5, 0)
passFrame.Position = UDim2.new(0.5, 0, 0, 14)
passFrame.Size = UDim2.fromOffset(268, 56)
passFrame.BackgroundColor3 = THEME.Background
passFrame.BackgroundTransparency = 0.1
passFrame.BorderSizePixel = 0
passFrame.Parent = passGui
Instance.new("UICorner", passFrame).CornerRadius = UDim.new(0, 10)
local passStroke = Instance.new("UIStroke")
passStroke.Color = THEME.Accent
passStroke.Thickness = 1
passStroke.Transparency = 0.35
passStroke.Parent = passFrame

local passCaption = Instance.new("TextLabel")
passCaption.BackgroundTransparency = 1
passCaption.Position = UDim2.fromOffset(12, 6)
passCaption.Size = UDim2.new(1, -24, 0, 14)
passCaption.Font = Enum.Font.GothamBold
passCaption.TextSize = 10
passCaption.TextXAlignment = Enum.TextXAlignment.Left
passCaption.TextColor3 = THEME.Muted
passCaption.Text = "PASSCODE NOTE"
passCaption.Parent = passFrame

local passValue = Instance.new("TextLabel")
passValue.BackgroundTransparency = 1
passValue.Position = UDim2.fromOffset(12, 22)
passValue.Size = UDim2.new(1, -70, 0, 26)
passValue.Font = Enum.Font.GothamBold
passValue.TextSize = 22
passValue.TextXAlignment = Enum.TextXAlignment.Left
passValue.TextColor3 = THEME.Text
passValue.Text = "- - - -"
passValue.Parent = passFrame

local passCopy = Instance.new("TextButton")
passCopy.AnchorPoint = Vector2.new(1, 0.5)
passCopy.Position = UDim2.new(1, -10, 0.5, 0)
passCopy.Size = UDim2.fromOffset(52, 26)
passCopy.BackgroundColor3 = THEME.Surface3
passCopy.BorderSizePixel = 0
passCopy.Font = Enum.Font.GothamBold
passCopy.TextSize = 11
passCopy.TextColor3 = THEME.Text
passCopy.Text = "COPY"
passCopy.AutoButtonColor = true
passCopy.Parent = passFrame
Instance.new("UICorner", passCopy).CornerRadius = UDim.new(0, 6)

passCopy.MouseButton1Click:Connect(function()
	local code = hub.code
	if code then
		local digits = code:gsub("%s", "")
		if typeof(setclipboard) == "function" then
			pcall(setclipboard, digits)
			passCopy.Text = "COPIED"
			task.delay(1.2, function() passCopy.Text = "COPY" end)
		end
	end
end)

--== Prompt and movement helpers ==
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
		if position then
			local distance = distanceBetween(position, origin)
			if distance < bestDistance then best, bestDistance = key, distance end
		end
	end
	return best, bestDistance
end

local function nearestWardrobePrompt(origin)
	local best, bestDistance = nil, math.huge
	for _, prompt in ipairs(hub.world.wardrobes) do
		if prompt.Enabled then
			local position = promptPosition(prompt)
			if position then
				local distance = distanceBetween(position, origin)
				if distance < bestDistance then best, bestDistance = prompt, distance end
			end
		end
	end
	return best, bestDistance
end

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
		local best, bestDistance = nil, math.huge
		for _, prompt in ipairs(world.drawers) do
			if prompt.Enabled then
				local position = promptPosition(prompt)
				if position then
					local distance = distanceBetween(position, origin)
					if distance < bestDistance then best, bestDistance = prompt, distance end
				end
			end
		end
		return promptPosition(best)
	elseif kind == "Spawn" then
		return instancePosition(workspace:FindFirstChildWhichIsA("SpawnLocation", true))
	end
	return nil
end

--== Diagnostics ==
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
	return table.concat(parts, " ")
end

local function keysSummary()
	local found = {}
	for _, key in ipairs(hub.world.keys) do
		local _, name = keyColor(key)
		if name then table.insert(found, name) end
	end
	local missing = {}
	for _, name in ipairs(KEY_ORDER) do
		if not listContains(found, name) then table.insert(missing, name) end
	end
	return found, missing
end

local function locksRemaining()
	local remaining = 0
	for _, lock in ipairs(hub.world.locks) do
		local prompt = lockPrompt(lock)
		if prompt and prompt.Enabled then remaining += 1 end
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
	return {
		state = tostring(opah:GetAttribute("State")),
		mode = tostring(opah:GetAttribute("Mode")),
		chasing = opah:GetAttribute("Chasing") == true,
		targetUserId = opah:GetAttribute("TargetUserId"),
		lair = tostring(opah:GetAttribute("Lair")),
		distance = distance,
	}
end

local function runDiagnostics()
	local lines = {}
	local root = getRoot()
	local lives = LocalPlayer:GetAttribute("Lives")
	local maxLives = LocalPlayer:GetAttribute("MaxLives")
	local duit = LocalPlayer:FindFirstChild("leaderstats") and LocalPlayer.leaderstats:FindFirstChild("Duit")
	local flops = LocalPlayer:GetAttribute("FlipFlopsFound")
	local found, missing = keysSummary()
	local opah = opahSummary()
	table.insert(lines, "<b>Diagnostics v" .. VERSION .. "</b>")
	table.insert(lines, "Game: " .. escapeRich(GAME_NAME) .. " | place " .. GAME_PLACE_ID)
	table.insert(lines, "Executor: " .. escapeRich(tostring(identifyexecutor and identifyexecutor() or "unknown")))
	table.insert(lines, "Character: " .. (root and "alive" or "none") .. " | Out=" .. tostring(LocalPlayer:GetAttribute("Out")))
	table.insert(lines, "Lives: " .. tostring(lives) .. "/" .. tostring(maxLives) .. " | Duit: " .. tostring(duit and duit.Value) .. " | Flip flops: " .. tostring(flops))
	table.insert(lines, "Keys in house: " .. #found .. "/5 | missing: " .. (#missing > 0 and table.concat(missing, ", ") or "none"))
	table.insert(lines, "Locks with active prompt: " .. locksRemaining() .. "/" .. #hub.world.locks)
	table.insert(lines, "Passcode: " .. (hub.code and escapeRich(hub.code) or "not read yet") .. (hub.world.note and "" or " (note picked up)"))
	table.insert(lines, "Drawers: openable " .. #hub.world.drawers .. " / total " .. hub.world.drawerTotal .. " | Wardrobes: " .. #hub.world.wardrobes)
	if opah then
		table.insert(lines, "Opah: state=" .. escapeRich(opah.state) .. " mode=" .. escapeRich(opah.mode) .. " chasing=" .. tostring(opah.chasing))
		table.insert(lines, "Opah distance: " .. tostring(math.floor(opah.distance)) .. " studs | target=" .. tostring(opah.targetUserId) .. " | lair=" .. escapeRich(opah.lair))
	else
		table.insert(lines, "Opah: not found in workspace")
	end
	table.insert(lines, "Remotes: " .. remotesSummary())
	for _, line in ipairs(lines) do pushLog(line) end
	notify("Diagnostics", "Report added to Activity", "Success")
end

--== Radar / overlay updates ==
local function playerNameFromUserId(userId)
	if not userId then return nil end
	local player = Players:GetPlayerByUserId(userId)
	return player and player.Name or nil
end

local function updateRadar()
	if not toggleValue(RadarEnabled) then
		radarFrame.Visible = false
		return
	end
	radarFrame.Visible = true
	local opah = opahSummary()
	if not opah then
		radarState.Text = "No Opah in workspace"
		radarState.TextColor3 = THEME.Muted
		radarDistance.Text = ""
		radarTarget.Text = ""
		radarFooter.Text = "Hidden: " .. (hub.hiddenPrompt and "yes" or "no")
		radarStroke.Color = THEME.Stroke
		return
	end
	local isMine = opah.targetUserId == LocalPlayer.UserId
	local stateText = opah.state
	if opah.chasing then stateText = "CHASING - " .. opah.mode end
	radarState.Text = "State: " .. stateText
	radarDistance.Text = string.format("Distance: %d studs", math.floor(opah.distance or 0))
	if isMine then
		radarState.TextColor3 = Color3.fromRGB(255, 80, 80)
		radarStroke.Color = Color3.fromRGB(255, 60, 60)
	elseif opah.chasing then
		radarState.TextColor3 = Color3.fromRGB(255, 170, 60)
		radarStroke.Color = Color3.fromRGB(255, 160, 40)
	else
		radarState.TextColor3 = Color3.fromRGB(120, 220, 150)
		radarStroke.Color = THEME.Stroke
	end
	if isMine then
		radarTarget.Text = "Target: YOU"
		radarTarget.TextColor3 = Color3.fromRGB(255, 120, 120)
	else
		local name = playerNameFromUserId(opah.targetUserId)
		radarTarget.Text = "Target: " .. (name or "none")
		radarTarget.TextColor3 = THEME.Muted
	end
	radarFooter.Text = "Lair: " .. tostring(opah.lair) .. " | Hidden: " .. (hub.hiddenPrompt and "yes" or "no")
end

local function updatePasscodeOverlay()
	if not toggleValue(PasscodeOverlay) then
		passFrame.Visible = false
		return
	end
	passFrame.Visible = true
	passValue.Text = hub.code or "- - - -"
end

--== Auto loot ==
local function findLootTarget(origin)
	local selected = selectedValues(LootTargets)
	local best, bestDistance = nil, math.huge
	local maxRange = numberValue(LootRange, 250)
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
	if listContains(selected, "Drawers") then
		for _, prompt in ipairs(hub.world.drawers) do consider(prompt, promptPosition(prompt), "drawer") end
	end
	if listContains(selected, "Keys") then
		for _, key in ipairs(hub.world.keys) do consider(findPickupPrompt(key), instancePosition(key), "key") end
	end
	if listContains(selected, "Passcode note") and hub.world.note then
		consider(findPickupPrompt(hub.world.note), instancePosition(hub.world.note), "note")
	end
	if listContains(selected, "Flip flops") then
		for _, prompt in ipairs(hub.world.flipflops) do consider(prompt, promptPosition(prompt), "flip flop") end
	end
	return best
end

local function lootStep()
	if not toggleValue(AutoLoot) or hub.hideInProgress or hub.hiddenPrompt or not isAlive() then return end
	local root = getRoot()
	if not root then return end
	if toggleValue(PauseOnChase) then
		local opah = opahSummary()
		if opah and opah.chasing and opah.distance < 55 then return end
	end
	local target = findLootTarget(root.Position)
	if not target then return end
	local mode = LootMode and LootMode.Value or "Walk"
	if mode == "Teleport" then
		teleportNear(target.position)
		task.wait(0.15)
	else
		local reached = walkTo(target.position, 7, 6)
		if not reached then
			lootBlacklist[target.prompt] = os.clock() + 15
			pushLog("<Muted>Skipped " .. escapeRich(target.kind) .. " (unreachable)</Muted>")
			return
		end
	end
	local fired = triggerPrompt(target.prompt)
	if fired then
		lootBlacklist[target.prompt] = os.clock() + 8
		pushLog("<Success>Looted</Success> " .. escapeRich(target.kind))
	else
		lootBlacklist[target.prompt] = os.clock() + 3
	end
	task.wait(0.2)
end

--== Auto hide ==
local function hideStep()
	if not toggleValue(AutoHide) then
		if hub.hiddenPrompt then
			triggerPrompt(hub.hiddenPrompt)
			hub.hiddenPrompt = nil
			pushLog("<Muted>Left the wardrobe (auto hide off)</Muted>")
		end
		return
	end
	local opah = opahSummary()
	local root = getRoot()
	if hub.hiddenPrompt then
		local safe = true
		if opah and opah.chasing then safe = opah.distance > numberValue(HideRange, 45) + 25 end
		if safe or not root then
			triggerPrompt(hub.hiddenPrompt)
			pushLog("<Muted>Left the wardrobe</Muted>")
			hub.hiddenPrompt = nil
		end
		return
	end
	if not root or not opah or not opah.chasing or opah.distance > numberValue(HideRange, 45) then return end
	local prompt = nearestWardrobePrompt(root.Position)
	if not prompt then return end
	hub.hideInProgress = true
	local mode = HideMode and HideMode.Value or "Teleport"
	if mode == "Walk" then
		walkTo(promptPosition(prompt), 7, 5)
	else
		teleportNear(promptPosition(prompt))
		task.wait(0.2)
	end
	triggerPrompt(prompt)
	hub.hideInProgress = false
	hub.hiddenPrompt = prompt
	pushLog("<Warning>Hiding</Warning> - Opah is chasing")
end

--== UI construction ==
local DiagnosticsTab = Window:CreateTab({ Name = "Diagnostics", Icon = "activity" })
local DiagBox = DiagnosticsTab:CreateGroupbox({ Name = "Checklist", Side = "Left" })
local LogBox = DiagnosticsTab:CreateGroupbox({ Name = "Activity", Side = "Right" })

KeysStatus = DiagBox:CreateStatus({
	Name = "Keys", Style = "Row",
	Update = function()
		local found, missing = keysSummary()
		local text = #found .. "/5 in house"
		if #missing > 0 then text = text .. " | " .. table.concat(missing, ", ") end
		return "<Text>" .. text .. "</Text>"
	end,
	UpdateRate = 1,
})
LocksStatus = DiagBox:CreateStatus({
	Name = "Locks", Style = "Row",
	Update = function() return "<Text>" .. locksRemaining() .. " active prompts</Text>" end,
	UpdateRate = 1,
})
PasscodeStatus = DiagBox:CreateStatus({
	Name = "Passcode", Style = "Row",
	Update = function()
		if hub.code then return "<Success>" .. escapeRich(hub.code) .. "</Success>" end
		return "<Muted>waiting for note</Muted>"
	end,
	UpdateRate = 1,
})
OpahStateStatus = DiagBox:CreateStatus({
	Name = "Opah", Style = "Row", Pin = true,
	Update = function()
		local opah = opahSummary()
		if not opah then return "<Muted>not spawned</Muted>" end
		local text = escapeRich(opah.state) .. " | " .. math.floor(opah.distance) .. " studs"
		if opah.chasing then return "<Error>" .. text .. "</Error>" end
		return "<Success>" .. text .. "</Success>"
	end,
	UpdateRate = 0.5,
})
DiagBox:CreateButton({
	Name = "Check my game", Icon = "stethoscope",
	Callback = function() runDiagnostics() end,
})
ActivityLog = LogBox:CreateLog({
	Name = "Activity", MaxEntries = 300, MaxRows = 14,
	Timestamps = true, EmptyText = "Nothing yet",
})

local VisualsTab = Window:CreateTab({ Name = "Visuals", Icon = "eye" })
local EspBox = VisualsTab:CreateGroupbox({ Name = "ESP", Side = "Left" })
local OverlayBox = VisualsTab:CreateGroupbox({ Name = "Overlays", Side = "Right" })
local RangeBox = VisualsTab:CreateGroupbox({ Name = "Range", Side = "Right" })

EspOpah = EspBox:CreateToggle({
	Name = "Opah", Desc = "Highlight the ghost through walls",
	Flag = "EspOpah", CurrentValue = true,
})
EspKeys = EspBox:CreateToggle({
	Name = "Keys", Desc = "Colored highlight for every key still in the house",
	Flag = "EspKeys", CurrentValue = true,
})
EspNote = EspBox:CreateToggle({ Name = "Passcode note", Flag = "EspNote", CurrentValue = true })
EspDoor = EspBox:CreateToggle({ Name = "Front door and locks", Flag = "EspDoor", CurrentValue = true })
EspWardrobe = EspBox:CreateToggle({ Name = "Wardrobes", Flag = "EspWardrobe", CurrentValue = false })
EspDrawer = EspBox:CreateToggle({
	Name = "Drawers", Desc = "Heavy: 60+ highlights",
	Flag = "EspDrawer", CurrentValue = false,
})
EspLabels = EspBox:CreateToggle({ Name = "Text labels", Flag = "EspLabels", CurrentValue = true })

RadarEnabled = OverlayBox:CreateToggle({
	Name = "Opah radar", Desc = "State, distance and chase target",
	Flag = "RadarEnabled", CurrentValue = true,
})
PasscodeOverlay = OverlayBox:CreateToggle({
	Name = "Passcode overlay", Desc = "Reads the note and copies digits",
	Flag = "PasscodeOverlay", CurrentValue = true,
})
EspMaxDistance = RangeBox:CreateSlider({
	Name = "Max ESP distance", Range = { 50, 600 },
	Increment = 25, Suffix = " studs", CurrentValue = 300,
	Flag = "EspMaxDistance",
})

local AutomationTab = Window:CreateTab({ Name = "Automation", Icon = "bot" })
local LootBox = AutomationTab:CreateGroupbox({ Name = "Auto loot", Side = "Left" })
local HideBox = AutomationTab:CreateGroupbox({ Name = "Auto hide", Side = "Right" })
local StateBox = AutomationTab:CreateGroupbox({ Name = "State", Side = "Right" })

AutoLoot = LootBox:CreateToggle({
	Name = "Auto loot", Desc = "Opens drawers and picks up selected items",
	Flag = "AutoLoot", CurrentValue = false,
})
LootTargets = LootBox:CreateDropdown({
	Name = "Targets", Options = { "Drawers", "Keys", "Passcode note", "Flip flops" },
	MultipleOptions = true, CurrentOption = { "Drawers", "Keys", "Passcode note" },
	Flag = "LootTargets",
})
LootMode = LootBox:CreateDropdown({
	Name = "Mode", Options = { "Walk", "Teleport" },
	CurrentOption = "Walk", Flag = "LootMode",
})
LootRange = LootBox:CreateSlider({
	Name = "Search range", Range = { 50, 500 }, Increment = 25,
	Suffix = " studs", CurrentValue = 250, Flag = "LootRange",
})
PauseOnChase = LootBox:CreateToggle({
	Name = "Pause while chased", Flag = "PauseOnChase", CurrentValue = true,
})
AutoHide = HideBox:CreateToggle({
	Name = "Auto hide", Desc = "Runs to the nearest wardrobe when Opah chases",
	Flag = "AutoHide", CurrentValue = false,
})
HideRange = HideBox:CreateSlider({
	Name = "Trigger distance", Range = { 10, 120 }, Increment = 5,
	Suffix = " studs", CurrentValue = 45, Flag = "HideRange",
})
HideMode = HideBox:CreateDropdown({
	Name = "Mode", Options = { "Teleport", "Walk" },
	CurrentOption = "Teleport", Flag = "HideMode",
})
HideBox:CreateButton({
	Name = "Leave wardrobe now", Icon = "door-open",
	Callback = function()
		if hub.hiddenPrompt then
			triggerPrompt(hub.hiddenPrompt)
			hub.hiddenPrompt = nil
			pushLog("<Muted>Leave wardrobe requested</Muted>")
		else
			pushLog("<Muted>Not hidden</Muted>")
		end
	end,
})
LootStatus = StateBox:CreateStatus({
	Name = "Loot", Style = "Row",
	Update = function()
		if toggleValue(AutoLoot) then return "<Success>running</Success>" end
		return "<Muted>idle</Muted>"
	end,
	UpdateRate = 0.5,
})
HideStatus = StateBox:CreateStatus({
	Name = "Hide", Style = "Row",
	Update = function()
		if hub.hiddenPrompt then return "<Warning>hidden</Warning>" end
		if toggleValue(AutoHide) then return "<Text>armed</Text>" end
		return "<Muted>idle</Muted>"
	end,
	UpdateRate = 0.5,
})

local TeleportTab = Window:CreateTab({ Name = "Teleport", Icon = "map-pin" })
local TeleportBox = TeleportTab:CreateGroupbox({ Name = "Markers", Side = "Left" })
local TeleportInfo = TeleportTab:CreateGroupbox({ Name = "Info", Side = "Right" })
TeleportTarget = TeleportBox:CreateDropdown({
	Name = "Destination",
	Options = { "Passcode note", "Nearest key", "Front door", "Keypad", "Nearest wardrobe", "Nearest drawer", "Spawn" },
	CurrentOption = "Passcode note", Flag = "TeleportTarget",
})
TeleportBox:CreateButton({
	Name = "Teleport", Icon = "move", Style = "Primary",
	Callback = function()
		local kind = TeleportTarget and TeleportTarget.Value or "Passcode note"
		local position = resolveTargetPosition(kind)
		if not position then
			notify("Teleport", "Target not found", "Warning")
			return
		end
		teleportNear(position)
		pushLog("<Success>Teleported</Success> to " .. escapeRich(kind))
	end,
})
TeleportBox:CreateButton({
	Name = "Walk to", Icon = "footprints",
	Callback = function()
		local kind = TeleportTarget and TeleportTarget.Value or "Passcode note"
		local position = resolveTargetPosition(kind)
		if not position then
			notify("Walk", "Target not found", "Warning")
			return
		end
		task.spawn(function()
			local ok = walkTo(position, 8, 15)
			if not ok then notify("Walk", "Target unreachable", "Warning") end
		end)
	end,
})
TeleportInfo:CreateParagraph({
	Title = "Targets",
	Content = "Positions are resolved from the live workspace: note, keys, door, keypad, wardrobes and drawers.",
})

local SettingsTab = Window:CreateTab({ Name = "Settings", Icon = "settings" })
local AboutBox = SettingsTab:CreateGroupbox({ Name = "About", Side = "Right" })
SettingsTab:CreateConfigManager({ Name = "Configs", Side = "Left" })
SettingsTab:CreateThemeManager({ Name = "Theme", Side = "Right" })
SettingsTab:CreateButton({
	Name = "Copy passcode", Icon = "clipboard-copy",
	Callback = function()
		if hub.code and typeof(setclipboard) == "function" then
			pcall(setclipboard, hub.code:gsub("%s", ""))
			notify("Copied", "Passcode digits copied", "Success")
		else
			notify("Copy", "No passcode read yet", "Warning")
		end
	end,
})
SettingsTab:CreateButton({
	Name = "Unload", Icon = "power", Style = "Primary",
	Callback = function()
		if environment.RMSO_Unload then environment.RMSO_Unload() end
	end,
})
AboutBox:CreateParagraph({
	Title = "Robscript Team - Malam Sama Opah v" .. VERSION,
	Content = "Client helper for [CLASS] MALAM SAMA OPAH. ESP, radar, passcode overlay, auto loot, auto hide, teleport. RightControl toggles the window.",
})
AboutBox:CreateDivider()
AboutBox:CreateLabel({ Text = "Game: " .. GAME_NAME })
AboutBox:CreateLabel({ Text = "Place: " .. GAME_PLACE_ID })

--== 2.5D mobile control deck ==
local deckGui = Instance.new("ScreenGui")
deckGui.Name = "RMSO_3DDeck"
deckGui.ResetOnSpawn = false
deckGui.IgnoreGuiInset = true
deckGui.DisplayOrder = 950
deckGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
deckGui.Parent = guiParent

local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(800, 600)
local compact = viewport.X < 600
local deckWidth = compact and math.max(290, math.min(350, viewport.X - 24)) or 370
local deckHeight = compact and 370 or 410

local shadow = Instance.new("Frame")
shadow.Name = "DepthShadow"
shadow.AnchorPoint = Vector2.new(0.5, 0.5)
shadow.Position = UDim2.new(0.5, 0, 0.48, 8)
shadow.Size = UDim2.fromOffset(deckWidth, deckHeight)
shadow.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
shadow.BackgroundTransparency = 0.38
shadow.BorderSizePixel = 0
shadow.ZIndex = 1
shadow.Parent = deckGui
Instance.new("UICorner", shadow).CornerRadius = UDim.new(0, 18)

local deck = Instance.new("Frame")
deck.Name = "MainDeck"
deck.AnchorPoint = Vector2.new(0.5, 0.5)
deck.Position = UDim2.new(0.5, 0, 0.48, 0)
deck.Size = UDim2.fromOffset(deckWidth, deckHeight)
deck.BackgroundColor3 = Color3.fromRGB(15, 13, 19)
deck.BorderSizePixel = 0
deck.ZIndex = 2
deck.Parent = deckGui
Instance.new("UICorner", deck).CornerRadius = UDim.new(0, 18)

local deckStroke = Instance.new("UIStroke")
deckStroke.Color = THEME.Accent
deckStroke.Transparency = 0.18
deckStroke.Thickness = 1.4
deckStroke.Parent = deck

local deckGradient = Instance.new("UIGradient")
deckGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(38, 19, 33)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(18, 16, 24)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(10, 11, 16)),
})
deckGradient.Rotation = 35
deckGradient.Parent = deck

local deckScale = Instance.new("UIScale")
deckScale.Scale = compact and math.clamp(viewport.X / 390, 0.82, 1) or 1
deckScale.Parent = deck

local function deckText(parent, text, textSize, color, position, size, font)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = position
	label.Size = size
	label.Font = font or Enum.Font.GothamMedium
	label.Text = text
	label.TextSize = textSize
	label.TextColor3 = color
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Parent = parent
	return label
end

local header = Instance.new("Frame")
header.BackgroundTransparency = 1
header.Position = UDim2.fromOffset(17, 12)
header.Size = UDim2.new(1, -34, 0, 54)
header.ZIndex = 3
header.Parent = deck
deckText(header, "MALAM SAMA OPAH", 15, THEME.Text,
	UDim2.fromOffset(0, 0), UDim2.new(1, -50, 0, 23), Enum.Font.GothamBold)
deckText(header, "3D CONTROL DECK  /  v" .. VERSION, 9, THEME.Muted,
	UDim2.fromOffset(1, 25), UDim2.new(1, -50, 0, 17))

local closeButton = Instance.new("TextButton")
closeButton.Position = UDim2.new(1, -32, 0, 1)
closeButton.Size = UDim2.fromOffset(32, 30)
closeButton.BackgroundColor3 = Color3.fromRGB(58, 25, 43)
closeButton.BorderSizePixel = 0
closeButton.Text = "—"
closeButton.TextColor3 = THEME.Text
closeButton.TextSize = 17
closeButton.Font = Enum.Font.GothamBold
closeButton.ZIndex = 4
closeButton.Parent = header
Instance.new("UICorner", closeButton).CornerRadius = UDim.new(0, 9)

local statusCard = Instance.new("Frame")
statusCard.Position = UDim2.fromOffset(16, 76)
statusCard.Size = UDim2.new(1, -32, 0, 58)
statusCard.BackgroundColor3 = Color3.fromRGB(28, 24, 34)
statusCard.BackgroundTransparency = 0.08
statusCard.BorderSizePixel = 0
statusCard.ZIndex = 3
statusCard.Parent = deck
Instance.new("UICorner", statusCard).CornerRadius = UDim.new(0, 12)
local statusStroke = Instance.new("UIStroke")
statusStroke.Color = THEME.StrokeHover
statusStroke.Transparency = 0.3
statusStroke.Parent = statusCard
deckText(statusCard, "SESSION STATUS", 9, THEME.Muted,
	UDim2.fromOffset(12, 7), UDim2.new(1, -24, 0, 15), Enum.Font.GothamBold)
local statusValue = deckText(statusCard, "SCANNING WORLD...", 12, THEME.Text,
	UDim2.fromOffset(12, 25), UDim2.new(1, -24, 0, 22), Enum.Font.GothamBold)

deckText(deck, "QUICK CONTROLS", 9, THEME.Muted,
	UDim2.fromOffset(18, 145), UDim2.new(1, -36, 0, 18), Enum.Font.GothamBold)

local controlGrid = Instance.new("Frame")
controlGrid.BackgroundTransparency = 1
controlGrid.Position = UDim2.fromOffset(16, 168)
controlGrid.Size = UDim2.new(1, -32, 0, 126)
controlGrid.ZIndex = 3
controlGrid.Parent = deck
local grid = Instance.new("UIGridLayout")
grid.CellSize = UDim2.new(0.5, -5, 0, 56)
grid.CellPadding = UDim2.fromOffset(10, 10)
grid.SortOrder = Enum.SortOrder.LayoutOrder
grid.Parent = controlGrid

local controlSpecs = {
	{ label = "OPAH ESP", name = "EspOpah" },
	{ label = "KEY ESP", name = "EspKeys" },
	{ label = "OPAH RADAR", name = "RadarEnabled" },
	{ label = "AUTO LOOT", name = "AutoLoot" },
	{ label = "AUTO HIDE", name = "AutoHide" },
	{ label = "PASSCODE", name = "PasscodeOverlay" },
}

local function getDeckHandle(name)
	local handles = {
		EspOpah = EspOpah,
		EspKeys = EspKeys,
		RadarEnabled = RadarEnabled,
		AutoLoot = AutoLoot,
		AutoHide = AutoHide,
		PasscodeOverlay = PasscodeOverlay,
	}
	return handles[name]
end

local function setDeckHandle(handle, value)
	if not handle then return end
	pcall(function()
		if handle.Set then
			handle:Set(value)
		elseif handle.Value ~= nil then
			handle.Value = value
		end
	end)
end

local deckButtons = {}
for index, spec in ipairs(controlSpecs) do
	local button = Instance.new("TextButton")
	button.Name = spec.name
	button.BackgroundColor3 = Color3.fromRGB(34, 29, 39)
	button.BorderSizePixel = 0
	button.Text = spec.label .. "  •  OFF"
	button.TextColor3 = THEME.Muted
	button.TextSize = 10
	button.Font = Enum.Font.GothamBold
	button.AutoButtonColor = false
	button.LayoutOrder = index
	button.ZIndex = 4
	button.Parent = controlGrid
	Instance.new("UICorner", button).CornerRadius = UDim.new(0, 10)
	local stroke = Instance.new("UIStroke")
	stroke.Color = THEME.StrokeHover
	stroke.Transparency = 0.35
	stroke.Parent = button
	button.MouseButton1Click:Connect(function()
		local handle = getDeckHandle(spec.name)
		setDeckHandle(handle, not (handle and handle.Value == true))
	end)
	deckButtons[spec.name] = button
end

local footer = Instance.new("Frame")
footer.BackgroundTransparency = 1
footer.Position = UDim2.new(0, 16, 1, -58)
footer.Size = UDim2.new(1, -32, 0, 42)
footer.ZIndex = 3
footer.Parent = deck

local function footerButton(text, position, callback, color)
	local button = Instance.new("TextButton")
	button.Position = position
	button.Size = UDim2.new(0.5, -5, 1, 0)
	button.BackgroundColor3 = color
	button.BorderSizePixel = 0
	button.Text = text
	button.TextColor3 = THEME.Text
	button.TextSize = 10
	button.Font = Enum.Font.GothamBold
	button.ZIndex = 4
	button.Parent = footer
	Instance.new("UICorner", button).CornerRadius = UDim.new(0, 10)
	button.MouseButton1Click:Connect(callback)
	return button
end

footerButton("RESCAN WORLD", UDim2.new(0, 0, 0, 0), function()
	pcall(scanWorld)
	pcall(syncEsp)
	notify("World scan", "World data refreshed", "Success")
end, Color3.fromRGB(67, 28, 49))

footerButton("DIAGNOSTICS", UDim2.new(0.5, 5, 0, 0), runDiagnostics,
	Color3.fromRGB(37, 36, 46))

local floating = Instance.new("TextButton")
floating.Name = "FloatingToggle"
floating.AnchorPoint = Vector2.new(1, 1)
floating.Position = UDim2.new(1, -18, 1, -110)
floating.Size = UDim2.fromOffset(54, 54)
floating.BackgroundColor3 = Color3.fromRGB(75, 25, 52)
floating.BorderSizePixel = 0
floating.Text = "R"
floating.TextColor3 = THEME.Text
floating.TextSize = 21
floating.Font = Enum.Font.GothamBlack
floating.ZIndex = 20
floating.Parent = deckGui
Instance.new("UICorner", floating).CornerRadius = UDim.new(0, 17)
local floatingStroke = Instance.new("UIStroke")
floatingStroke.Color = THEME.Accent
floatingStroke.Thickness = 1.5
floatingStroke.Parent = floating

local function setDeckVisible(visible)
	deck.Visible = visible
	shadow.Visible = visible
	if visible then
		deck.Position = UDim2.new(0.5, 0, 0.48, 8)
		TweenService:Create(deck, TweenInfo.new(0.18, Enum.EasingStyle.Quint,
			Enum.EasingDirection.Out), {
			Position = UDim2.new(0.5, 0, 0.48, 0)
		}):Play()
	end
end

closeButton.MouseButton1Click:Connect(function() setDeckVisible(false) end)
floating.MouseButton1Click:Connect(function() setDeckVisible(not deck.Visible) end)

-- Drag the header with either touch or mouse.
local dragging, dragInput, dragStart, startPosition
header.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		dragging = true
		dragStart = input.Position
		startPosition = deck.Position
		input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then dragging = false end
		end)
	end
end)
header.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseMovement
		or input.UserInputType == Enum.UserInputType.Touch then
		dragInput = input
	end
end)
UserInputService.InputChanged:Connect(function(input)
	if dragging and (input == dragInput or input.UserInputType == Enum.UserInputType.Touch) then
		local delta = input.Position - dragStart
		deck.Position = UDim2.new(startPosition.X.Scale, startPosition.X.Offset + delta.X,
			startPosition.Y.Scale, startPosition.Y.Offset + delta.Y)
		shadow.Position = UDim2.new(deck.Position.X.Scale, deck.Position.X.Offset,
			deck.Position.Y.Scale, deck.Position.Y.Offset + 8)
	end
end)

local viewportConnection
if workspace.CurrentCamera then
	viewportConnection = workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		local size = workspace.CurrentCamera.ViewportSize
		deckScale.Scale = size.X < 600 and math.clamp(size.X / 390, 0.82, 1) or 1
	end)
end

task.spawn(function()
	while hub.running and deckGui.Parent do
		local opah = opahSummary()
		if not isAlive() then
			statusValue.Text = "PLAYER NOT ACTIVE"
			statusValue.TextColor3 = THEME.Muted
		elseif opah and opah.chasing then
			statusValue.Text = string.format("DANGER  •  OPAH %.0f STUDS", opah.distance)
			statusValue.TextColor3 = Color3.fromRGB(255, 100, 115)
		elseif opah then
			statusValue.Text = string.format("SAFE  •  OPAH %.0f STUDS", opah.distance)
			statusValue.TextColor3 = Color3.fromRGB(120, 225, 165)
		else
			statusValue.Text = "WAITING FOR OPAH"
			statusValue.TextColor3 = THEME.Muted
		end
		for _, spec in ipairs(controlSpecs) do
			local handle = getDeckHandle(spec.name)
			local enabled = handle and handle.Value == true
			local button = deckButtons[spec.name]
			button.Text = spec.label .. (enabled and "  •  ON" or "  •  OFF")
			button.BackgroundColor3 = enabled and Color3.fromRGB(78, 29, 55)
				or Color3.fromRGB(34, 29, 39)
			button.TextColor3 = enabled and Color3.fromRGB(255, 205, 225) or THEME.Muted
		end
		task.wait(0.25)
	end
end)

--== Unload ==
local function unload()
	hub.running = false
	clearEsp()
	if viewportConnection then pcall(function() viewportConnection:Disconnect() end) end
	pcall(function() deckGui:Destroy() end)
	pcall(function() radarGui:Destroy() end)
	pcall(function() passGui:Destroy() end)
	pcall(function() Window:Destroy() end)
	environment.RMSO_Unload = nil
	print("[RMSO] unloaded")
end
environment.RMSO_Unload = unload

--== Debug API (also used by the test harness) ==
environment.RMSO = {
	version = VERSION,
	hub = hub,
	triggerPrompt = triggerPrompt,
	walkTo = walkTo,
	teleportNear = teleportNear,
	lootStep = lootStep,
	hideStep = hideStep,
	runDiagnostics = runDiagnostics,
	toggle = function(name, value)
		local handles = {
			AutoLoot = AutoLoot,
			AutoHide = AutoHide,
			LootTargets = LootTargets,
			LootMode = LootMode,
			HideMode = HideMode,
			EspDrawer = EspDrawer,
			EspWardrobe = EspWardrobe,
		}
		local handle = handles[name]
		if handle and handle.Set then
			handle:Set(value)
			return true
		end
		return false
	end,
}

--== Background loops ==
task.spawn(function()
	while hub.running do
		local ok, err = pcall(scanWorld)
		if not ok then warn("[RMSO] scan: " .. tostring(err)) end
		task.wait(1)
	end
end)

task.spawn(function()
	while hub.running do
		local ok, err = pcall(syncEsp)
		if not ok then warn("[RMSO] esp: " .. tostring(err)) end
		task.wait(0.5)
	end
end)

task.spawn(function()
	while hub.running do
		local ok, err = pcall(updateRadar)
		if not ok then warn("[RMSO] radar: " .. tostring(err)) end
		task.wait(0.2)
	end
end)

task.spawn(function()
	while hub.running do
		local ok, err = pcall(updatePasscodeOverlay)
		if not ok then warn("[RMSO] overlay: " .. tostring(err)) end
		task.wait(0.5)
	end
end)

task.spawn(function()
	while hub.running do
		if toggleValue(AutoLoot) then
			local ok, err = pcall(lootStep)
			if not ok then pushLog("<Error>Loot error</Error> " .. escapeRich(tostring(err))) end
		end
		task.wait(0.35)
	end
end)

task.spawn(function()
	while hub.running do
		local ok, err = pcall(hideStep)
		if not ok then warn("[RMSO] hide: " .. tostring(err)) end
		task.wait(0.25)
	end
end)

Window:LoadAutoload()
pushLog("<Accent>Loaded</Accent> Robscript Team - Malam Sama Opah v" .. VERSION)
pushLog("<Muted>RightControl toggles the Airflow window</Muted>")
notify("Loaded", "Robscript Team - Malam Sama Opah v" .. VERSION, "Success")
pcall(scanWorld)
print("[RMSO] loaded v" .. VERSION .. " | drawers=" .. #hub.world.drawers
	.. " wardrobes=" .. #hub.world.wardrobes .. " keys=" .. #hub.world.keys
	.. " locks=" .. #hub.world.locks)
