--[[
	Mock Roblox/Luau runtime harness for MALAM_SAMA_OPAH_V2_3_ULTRA.lua
	--------------------------------------------------------------------------
	This is NOT Roblox Studio. It stubs the subset of Roblox APIs the script
	uses so the whole file can be executed (startup, loops, callbacks, unload)
	and runtime errors can be surfaced. Any engine behaviour (rendering,
	physics, real remote behaviour) is simulated or ignored.
]]

local vtime = 0
local threads = {}
local handlerErrors = {}
local firedPrompts = 0
local firedRemotes = 0
local clipboardValue = nil
local frameSignal = nil

os.clock = function() return vtime end

local function logError(message)
	table.insert(handlerErrors, tostring(message))
end

local function addThread(co, wake)
	table.insert(threads, { co = co, wake = wake })
end

local function resumeThread(entry)
	local ok, res = coroutine.resume(entry.co)
	if not ok then
		logError(res)
		return
	end
	if coroutine.status(entry.co) ~= "dead" then
		addThread(entry.co, vtime + (tonumber(res) or 0))
	end
end

--== task library ==
task = {}
function task.spawn(fn, ...)
	local co = coroutine.create(fn)
	local ok, res = coroutine.resume(co, ...)
	if not ok then error(res, 0) end
	if coroutine.status(co) ~= "dead" then
		addThread(co, vtime + (tonumber(res) or 0))
	end
end
function task.delay(seconds, fn, ...)
	local co = coroutine.create(fn)
	addThread(co, vtime + (tonumber(seconds) or 0))
	return co
end
function task.defer(fn, ...)
	local co = coroutine.create(fn)
	addThread(co, vtime)
	return co
end
function task.wait(seconds)
	return coroutine.yield(tonumber(seconds) or 0)
end
function task.cancel() end

-- Luau provides table.clear; plain Lua does not.
table.clear = table.clear or function(tbl)
	for key in pairs(tbl) do tbl[key] = nil end
end

--== Datatypes ==
local function clamp01(n) return math.max(0, math.min(1, n)) end

local Color3mt = {}
local function newColor(r, g, b)
	return setmetatable({ R = r, G = g, B = b }, Color3mt)
end
Color3mt.__eq = function(a, b) return a.R == b.R and a.G == b.G and a.B == b.B end
Color3mt.__tostring = function(c) return string.format("Color3(%0.2f,%0.2f,%0.2f)", c.R, c.G, c.B) end
local Color3 = {}
function Color3.new(r, g, b) return newColor(r or 0, g or 0, b or 0) end
function Color3.fromRGB(r, g, b) return newColor((r or 0) / 255, (g or 0) / 255, (b or 0) / 255) end
function Color3.fromHex(hex)
	local n = tonumber(hex, 16) or 0
	return newColor(((n >> 16) & 255) / 255, ((n >> 8) & 255) / 255, (n & 255) / 255)
end
Color3mt.Lerp = function(self, other, alpha)
	return newColor(self.R + (other.R - self.R) * alpha, self.G + (other.G - self.G) * alpha, self.B + (other.B - self.B) * alpha)
end

local Vector3mt = {}
local function newVector3(x, y, z) return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, Vector3mt) end
Vector3mt.__index = function(self, key)
	if key == "Magnitude" then return math.sqrt(self.X * self.X + self.Y * self.Y + self.Z * self.Z) end
	if key == "Unit" then
		local m = math.sqrt(self.X * self.X + self.Y * self.Y + self.Z * self.Z)
		if m == 0 then return newVector3(0, 1, 0) end
		return newVector3(self.X / m, self.Y / m, self.Z / m)
	end
	return nil
end
Vector3mt.__add = function(a, b) return newVector3(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
Vector3mt.__sub = function(a, b) return newVector3(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
Vector3mt.__mul = function(a, b)
	if type(b) == "number" then return newVector3(a.X * b, a.Y * b, a.Z * b) end
	return newVector3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
Vector3mt.__eq = function(a, b) return a.X == b.X and a.Y == b.Y and a.Z == b.Z end
Vector3mt.__tostring = function(v) return string.format("Vector3(%0.1f, %0.1f, %0.1f)", v.X, v.Y, v.Z) end
local Vector3 = {}
function Vector3.new(x, y, z) return newVector3(x, y, z) end

local Vector2mt = {}
local function newVector2(x, y) return setmetatable({ X = x or 0, Y = y or 0 }, Vector2mt) end
Vector2mt.__add = function(a, b) return newVector2(a.X + b.X, a.Y + b.Y) end
Vector2mt.__sub = function(a, b) return newVector2(a.X - b.X, a.Y - b.Y) end
Vector2mt.__eq = function(a, b) return a.X == b.X and a.Y == b.Y end
local Vector2 = {}
function Vector2.new(x, y) return newVector2(x, y) end

local UDim = {}
function UDim.new(scale, offset) return { Scale = scale or 0, Offset = offset or 0 } end

local UDim2mt = {}
UDim2mt.__index = function(self, key)
	if key == "X" then return self._x end
	if key == "Y" then return self._y end
	return nil
end
local UDim2 = {}
local function newUDim2(xs, xo, ys, yo)
	return setmetatable({ _x = { Scale = xs or 0, Offset = xo or 0 }, _y = { Scale = ys or 0, Offset = yo or 0 } }, UDim2mt)
end
function UDim2.new(xs, xo, ys, yo) return newUDim2(xs, xo, ys, yo) end
function UDim2.fromOffset(x, y) return newUDim2(0, x or 0, 0, y or 0) end
function UDim2.fromScale(x, y) return newUDim2(x or 0, 0, y or 0, 0) end

local CFrame = {}
function CFrame.new(x, y, z)
	return { Position = newVector3(x or 0, y or 0, z or 0), LookVector = newVector3(0, 0, -1) }
end
function CFrame.lookAt(fromPos, toPos)
	local dir = toPos - fromPos
	return { Position = fromPos, LookVector = dir.Unit }
end

local ColorSequence = {}
function ColorSequence.new(a, b)
	return { keypoints = { a, b } }
end
local ColorSequenceKeypoint = {}
function ColorSequenceKeypoint.new(time, color) return { Time = time, Value = color } end
local NumberSequence = {}
function NumberSequence.new(a, b) return { a = a, b = b } end
local NumberSequenceKeypoint = {}
function NumberSequenceKeypoint.new(time, value) return { Time = time, Value = value } end
local NumberRange = {}
function NumberRange.new(a, b) return { Min = a, Max = b or a } end

local TweenInfo = {}
function TweenInfo.new(time, style, direction) return { Time = time, Style = style, Direction = direction } end

--== Enum (auto-generating, identity-stable) ==
local enumCache = {}
local Enum = setmetatable({}, {
	__index = function(_, category)
		local existing = enumCache[category]
		if existing then return existing end
		local cat = setmetatable({}, {
			__index = function(tbl, item)
				local entry = { Name = item, Value = 0 }
				rawset(tbl, item, entry)
				return entry
			end,
		})
		enumCache[category] = cat
		return cat
	end,
})

--== Signals ==
local Signal = {}
Signal.__index = Signal
function Signal.new() return setmetatable({ handlers = {} }, Signal) end
function Signal:Connect(fn)
	local entry = { fn = fn, connected = true }
	table.insert(self.handlers, entry)
	return {
		Connected = true,
		Disconnect = function()
			entry.connected = false
		end,
	}
end
function Signal:Fire(...)
	local snapshot = {}
	for index, entry in ipairs(self.handlers) do snapshot[index] = entry end
	for _, entry in ipairs(snapshot) do
		if entry.connected then
			local ok, err = pcall(entry.fn, ...)
			if not ok then logError(err) end
		end
	end
end

--== Instance ==
local guiClasses = {
	Frame = true, TextLabel = true, TextButton = true, TextBox = true, ImageLabel = true,
	ImageButton = true, ScrollingFrame = true, ViewportFrame = true,
}
local layerClasses = { ScreenGui = true, BillboardGui = true, SurfaceGui = true }

local ancestors = {
	Frame = { "GuiObject", "GuiBase2d", "Instance" },
	TextLabel = { "GuiObject", "GuiBase2d", "Instance" },
	TextButton = { "GuiObject", "GuiBase2d", "Instance" },
	TextBox = { "GuiObject", "GuiBase2d", "Instance" },
	ImageLabel = { "GuiObject", "GuiBase2d", "Instance" },
	ImageButton = { "GuiObject", "GuiBase2d", "Instance" },
	ScrollingFrame = { "GuiObject", "GuiBase2d", "Instance" },
	ScreenGui = { "LayerCollector", "GuiBase2d", "Instance" },
	BillboardGui = { "LayerCollector", "GuiBase2d", "Instance" },
	Model = { "PVInstance", "Instance" },
	Part = { "BasePart", "PVInstance", "Instance" },
	SpawnLocation = { "BasePart", "PVInstance", "Instance" },
	Humanoid = { "Instance" },
	ProximityPrompt = { "Instance" },
	Highlight = { "Instance" },
}

local eventNames = {
	Changed = true, ChildAdded = true, ChildRemoved = true, AncestryChanged = true, Destroying = true,
	InputBegan = true, InputChanged = true, InputEnded = true, MouseButton1Click = true,
	MouseButton1Down = true, MouseButton1Up = true, MouseEnter = true, MouseLeave = true,
	Activated = true, FocusLost = true, TextChanged = true, Triggered = true, TouchEnded = true,
	PromptButtonHoldBegan = true, PromptButtonHoldEnded = true,
	CharacterAdded = true, CharacterRemoving = true, PlayerAdded = true, PlayerRemoving = true,
	RenderStepped = true, Heartbeat = true, Stepped = true, Died = true, HealthChanged = true,
}

local imt = {}
local Instance = {}

local methods = {}

local function propSignals(self)
	local signals = rawget(self, "_propSignals")
	if not signals then
		signals = {}
		rawset(self, "_propSignals", signals)
	end
	return signals
end

local function fireProperty(self, key, oldValue, newValue)
	if oldValue == newValue then return end
	local signals = propSignals(self)
	local signal = signals[key]
	if signal then signal:Fire() end
	local changed = rawget(self, "_signals").Changed
	if changed then changed:Fire(key) end
end

imt.__index = function(self, key)
	local props = rawget(self, "_props")
	local value = props[key]
	if value ~= nil then return value end
	if eventNames[key] then
		local signals = rawget(self, "_signals")
		local signal = signals[key]
		if not signal then
			signal = Signal.new()
			signals[key] = signal
		end
		return signal
	end
	return methods[key]
end

imt.__newindex = function(self, key, value)
	local props = rawget(self, "_props")
	if key == "Parent" then
		local old = props.Parent
		if old == value then return end
		local oldChildren = old and rawget(old, "_children")
		if oldChildren then
			for index = #oldChildren, 1, -1 do
				if oldChildren[index] == self then table.remove(oldChildren, index) end
			end
		end
		props.Parent = value
		local newChildren = value and rawget(value, "_children")
		if newChildren then table.insert(newChildren, self) end
		local signals = rawget(self, "_signals")
		if signals.AncestryChanged then signals.AncestryChanged:Fire(self, value) end
		if signals.Changed then signals.Changed:Fire("Parent") end
		return
	end
	local old = props[key]
	props[key] = value
	fireProperty(self, key, old, value)
end

function Instance.new(className, parent)
	local self = setmetatable({}, imt)
	rawset(self, "_className", className)
	rawset(self, "_children", {})
	rawset(self, "_signals", {})
	rawset(self, "_attrs", {})
	rawset(self, "_destroyed", false)
	local props = {
		Name = "",
		ClassName = className,
		Parent = nil,
	}
	if guiClasses[className] or layerClasses[className] then
		props.Visible = true
		props.AbsoluteSize = newVector2(0, 0)
		props.AbsolutePosition = newVector2(0, 0)
		props.Position = newUDim2()
		props.Size = newUDim2()
		if className ~= "ScreenGui" and className ~= "BillboardGui" and className ~= "SurfaceGui" then
			props.Text = ""
			props.Image = ""
		end
	else
		props.Position = newVector3()
		props.CFrame = CFrame.new()
		props.Enabled = true
	end
	if className == "ProximityPrompt" then
		props.ActionText = ""
		props.ObjectText = ""
		props.HoldDuration = 0
		props.Enabled = true
	end
	if className == "Humanoid" then
		props.Health = 100
		props.MaxHealth = 100
	end
	if className == "ScrollingFrame" then
		props.AbsoluteCanvasSize = newVector2(0, 0)
		props.AbsoluteWindowSize = newVector2(0, 0)
		props.CanvasPosition = newVector2(0, 0)
		props.CanvasSize = newUDim2()
		props.ScrollBarThickness = 6
	end
	if className == "TextBox" then
		props.Text = ""
		props.PlaceholderText = ""
	end
	if className == "ScreenGui" then
		props.ResetOnSpawn = true
		props.DisplayOrder = 0
	end
	rawset(self, "_props", props)
	if parent then self.Parent = parent end
	return self
end

function methods.IsA(self, class)
	if rawget(self, "_className") == class then return true end
	for _, name in ipairs(ancestors[rawget(self, "_className")] or {}) do
		if name == class then return true end
	end
	return false
end

function methods.GetChildren(self)
	local copy = {}
	for index, child in ipairs(rawget(self, "_children")) do copy[index] = child end
	return copy
end

function methods.GetDescendants(self)
	local out = {}
	local function walk(node)
		for _, child in ipairs(rawget(node, "_children")) do
			table.insert(out, child)
			walk(child)
		end
	end
	walk(self)
	return out
end

function methods.FindFirstChild(self, name, recursive)
	for _, child in ipairs(rawget(self, "_children")) do
		if child.Name == name then return child end
	end
	if recursive then
		for _, descendant in ipairs(methods.GetDescendants(self)) do
			if descendant.Name == name then return descendant end
		end
	end
	return nil
end

function methods.FindFirstChildOfClass(self, class)
	for _, child in ipairs(rawget(self, "_children")) do
		if child.ClassName == class then return child end
	end
	return nil
end

function methods.FindFirstChildWhichIsA(self, class, recursive)
	for _, child in ipairs(rawget(self, "_children")) do
		if child:IsA(class) then return child end
	end
	if recursive then
		for _, descendant in ipairs(methods.GetDescendants(self)) do
			if descendant:IsA(class) then return descendant end
		end
	end
	return nil
end

function methods.WaitForChild(self, name)
	local child = methods.FindFirstChild(self, name)
	if child then return child end
	local created = Instance.new("Folder")
	created.Name = name
	created.Parent = self
	return created
end

function methods.GetFullName(self)
	local parts = {}
	local node = self
	while node do
		local name = node.Name
		if name == nil or name == "" then name = node.ClassName end
		table.insert(parts, 1, name)
		node = node.Parent
	end
	return table.concat(parts, ".")
end

function methods.IsDescendantOf(self, other)
	local node = self.Parent
	while node do
		if node == other then return true end
		node = node.Parent
	end
	return false
end

function methods.GetAttribute(self, name)
	return rawget(self, "_attrs")[name]
end

function methods.SetAttribute(self, name, value)
	rawget(self, "_attrs")[name] = value
end

function methods.GetAttributes(self)
	local copy = {}
	for key, value in pairs(rawget(self, "_attrs")) do copy[key] = value end
	return copy
end

function methods.GetPropertyChangedSignal(self, name)
	local signals = propSignals(self)
	if not signals[name] then signals[name] = Signal.new() end
	return signals[name]
end

function methods.Destroy(self)
	if rawget(self, "_destroyed") then return end
	rawset(self, "_destroyed", true)
	local children = methods.GetChildren(self)
	for _, child in ipairs(children) do
		methods.Destroy(child)
	end
	local signals = rawget(self, "_signals")
	if signals.Destroying then signals.Destroying:Fire() end
	self.Parent = nil
	rawset(self, "_children", {})
end

function methods.ClearAllChildren(self)
	for _, child in ipairs(methods.GetChildren(self)) do
		methods.Destroy(child)
	end
end

function methods.GetPivot(self)
	local primary = self.PrimaryPart or methods.FindFirstChildWhichIsA(self, "BasePart")
	if primary then return primary.CFrame end
	return CFrame.new()
end

function methods.MoveTo(self, position)
	rawget(self, "_props").MoveTarget = position
end

function methods.InputHoldBegin() end
function methods.InputHoldEnd() end
function methods.Play() end
function methods.GetValue() end
function methods.Clear() end
function methods.Clone(self)
	local copy = Instance.new(self.ClassName)
	for key, value in pairs(rawget(self, "_props")) do
		if key ~= "Parent" then copy[key] = value end
	end
	return copy
end

--== Services and game ==
local services = {}

local function newService(class, name)
	local service = Instance.new(class)
	service.Name = name
	service.ClassName = name
	rawset(service, "_className", name)
	services[name] = service
	return service
end

local game = {}
function game:GetService(name)
	local existing = services[name]
	if existing then return existing end
	if name == "Stats" then
		local stats = { Network = { ServerStatsItem = { } } }
		stats.Network.ServerStatsItem["Data Ping"] = { GetValue = function() return 48 end }
		function stats:GetTotalMemoryUsageMb() return 612 end
		services.Stats = stats
		return stats
	end
	if name == "MarketplaceService" then
		local market = {}
		function market:GetProductInfo() return { Description = "MALAM SAMA OPAH - use key MALAM2025 (example)", Name = "MALAM SAMA OPAH" } end
		services.MarketplaceService = market
		return market
	end
	if name == "TweenService" then
		local tweenService = {}
		function tweenService:Create(instance, info, goals)
			local tween = Instance.new("Folder")
			tween.ClassName = "Tween"
			function tween:Play()
				for key, value in pairs(goals) do
					pcall(function() instance[key] = value end)
				end
			end
			function tween:Cancel() end
			return tween
		end
		services.TweenService = tweenService
		return tweenService
	end
	return newService("Instance", name)
end

local workspaceService = newService("Workspace", "Workspace")
workspaceService.Name = "Workspace"

local camera = Instance.new("Camera")
camera.Name = "Camera"
camera.CFrame = CFrame.new(0, 10, 20)
camera.ViewportSize = newVector2(1600, 900)
camera.Parent = workspaceService
workspaceService.CurrentCamera = camera

local Players = newService("Folder", "Players")
Players.MaxPlayers = 12

local ReplicatedStorage = newService("Folder", "ReplicatedStorage")
local UserInputService = newService("Folder", "UserInputService")
UserInputService.TouchEnabled = false
UserInputService.KeyboardEnabled = true
UserInputService.MouseEnabled = true
function UserInputService:GetMouseLocation() return newVector2(400, 300) end
function UserInputService:GetFocusedTextBox() return nil end

local RunService = newService("Folder", "RunService")
function RunService:IsStudio() return false end

local guiService = newService("Folder", "GuiService")

--== Seed a representative game world ==
local function part(name, position, parent)
	local p = Instance.new("Part")
	p.Name = name
	p.Position = position
	p.CFrame = CFrame.new(position.X, position.Y, position.Z)
	p.Parent = parent
	return p
end

local opah = Instance.new("Model")
opah.Name = "Opah"
part("HumanoidRootPart", newVector3(0, 3, 80), opah)
opah:SetAttribute("State", "Wander")
opah:SetAttribute("Mode", "Roam")
opah:SetAttribute("Chasing", false)
opah:SetAttribute("Lair", "Cabin")
opah:SetAttribute("TargetUserId", nil)
opah.Parent = workspaceService

local door = Instance.new("Model")
door.Name = "FrontDoor"
part("DoorPart", newVector3(0, 3, -30), door)
local keypad = Instance.new("Model")
keypad.Name = "Keypad"
part("Plate", newVector3(2, 4, -30), keypad)
keypad.Parent = door
local locks = Instance.new("Model")
locks.Name = "PuzzleLocks"
for index, colorName in ipairs({ "Red", "Blue", "Green" }) do
	local lock = Instance.new("Model")
	lock.Name = "Lock" .. colorName
	lock:SetAttribute("KeyColor", colorName)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Unlock"
	prompt.Enabled = true
	prompt.Parent = part("Body", newVector3(index * 2, 3, -28), lock)
	prompt.Parent = lock
	lock.Parent = locks
end
locks.Parent = door
door.Parent = workspaceService

local chests = Instance.new("Model")
chests.Name = "PuzzleChests"
for index = 1, 3 do
	local chest = Instance.new("Model")
	chest.Name = "Chest" .. index
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Open"
	prompt.Enabled = true
	prompt.HoldDuration = 0
	prompt.Parent = part("Drawer", newVector3(index * 4, 2, 12), chest)
	prompt.Parent = chest
	chest.Parent = chests
end
chests.Parent = workspaceService

local wardrobes = Instance.new("Model")
wardrobes.Name = "HidingWardrobes"
for index = 1, 2 do
	local wardrobe = Instance.new("Model")
	wardrobe.Name = "Wardrobe" .. index
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Hide"
	prompt.Enabled = true
	prompt.Parent = wardrobe
	wardrobe.Parent = wardrobes
end
wardrobes.Parent = workspaceService

local flipflops = Instance.new("Model")
flipflops.Name = "FlipFlops"
local slippers = Instance.new("Model")
slippers.Name = "Slippers"
local slipperPrompt = Instance.new("ProximityPrompt")
slipperPrompt.ActionText = "Pick up"
slipperPrompt.Parent = slippers
slippers.Parent = flipflops
flipflops.Parent = workspaceService

local items = Instance.new("Model")
items.Name = "PuzzleItems"
for index, colorName in ipairs({ "Red", "Blue" }) do
	local key = Instance.new("Model")
	key.Name = "Key" .. colorName
	key:SetAttribute("ItemType", "Key")
	key:SetAttribute("KeyColor", colorName)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Pick up"
	prompt.Parent = part("Handle", newVector3(index * 6, 2, 20), key)
	prompt.Parent = key
	key.Parent = items
end
local note = Instance.new("Model")
note.Name = "CodeNote"
note:SetAttribute("ItemType", "Passcode")
local notePart = part("Handle", newVector3(8, 2, 22), note)
local codeLabel = Instance.new("TextLabel")
codeLabel.Name = "Code"
codeLabel.Text = "4821"
codeLabel.Parent = note
local notePrompt = Instance.new("ProximityPrompt")
notePrompt.ActionText = "Pick up"
notePrompt.Parent = note
note.Parent = items
items.Parent = workspaceService

local spawnLocation = Instance.new("SpawnLocation")
spawnLocation.Name = "SpawnLocation"
spawnLocation.Parent = workspaceService

local puzzleShared = Instance.new("Folder")
puzzleShared.Name = "PuzzleShared"
local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
local puzzleRemote = Instance.new("RemoteEvent")
puzzleRemote.Name = "PuzzleRemote"
puzzleRemote.Parent = remotes
local submitPasscode = Instance.new("RemoteEvent")
submitPasscode.Name = "SubmitPasscode"
submitPasscode.Parent = remotes
remotes.Parent = puzzleShared
puzzleShared.Parent = ReplicatedStorage

local wardrobeHide = Instance.new("RemoteEvent")
wardrobeHide.Name = "WardrobeHideRemote"
wardrobeHide.Parent = ReplicatedStorage

local gameShared = Instance.new("Folder")
gameShared.Name = "GameShared"
local gameRemote = Instance.new("RemoteEvent")
gameRemote.Name = "GameRemote"
gameRemote.Parent = gameShared
gameShared.Parent = ReplicatedStorage

local codeRemote = Instance.new("RemoteEvent")
codeRemote.Name = "RedeemCode"
codeRemote.Parent = ReplicatedStorage

-- Local player + character
local playerGui = Instance.new("Folder")
playerGui.Name = "PlayerGui"

local localPlayer = Instance.new("Model")
localPlayer.Name = "selfdestruct"
localPlayer.ClassName = "Player"
localPlayer.UserId = 1234567
localPlayer.DisplayName = "selfdestruct"
localPlayer.Parent = Players
playerGui.Parent = localPlayer

local character = Instance.new("Model")
character.Name = "selfdestruct"
local humanoid = Instance.new("Humanoid")
humanoid.Name = "Humanoid"
humanoid.Parent = character
local rootPart = part("HumanoidRootPart", newVector3(0, 3, 0), character)
rootPart.Position = newVector3(0, 3, 0)
character.Parent = workspaceService
localPlayer.Character = character
Players.LocalPlayer = localPlayer

function Players:GetPlayers() return { localPlayer } end
function Players:GetPlayerByUserId(userId)
	if userId == localPlayer.UserId then return localPlayer end
	return nil
end
function Players:GetUserThumbnailAsync()
	return "rbxthumb://type=AvatarHeadShot&id=1234567&w=150&h=150", true
end

--== Globals the script expects ==
function typeof(value)
	if type(value) == "table" then
		local mt = getmetatable(value)
		if mt == Color3mt then return "Color3" end
		if mt == Vector3mt then return "Vector3" end
		if mt == Vector2mt then return "Vector2" end
		if mt == imt then return "Instance" end
		return "table"
	end
	return type(value)
end

function warn(...)
	local parts = {}
	for index = 1, select("#", ...) do parts[index] = tostring(select(index, ...)) end
	print("[warn] " .. table.concat(parts, " "))
end

function setclipboard(value)
	clipboardValue = value
	return true
end

function fireproximityprompt(prompt)
	firedPrompts = firedPrompts + 1
	return true
end

-- Any FireServer call is counted so we can prove no invented remote is fired.
local remoteEventProto = Instance.new("Folder")
local remoteMt = {}
remoteMt.__index = function(self, key)
	if key == "FireServer" then
		return function() firedRemotes = firedRemotes + 1 end
	end
	return imt.__index(self, key)
end

for _, remote in ipairs({ puzzleRemote, submitPasscode, wardrobeHide, gameRemote, codeRemote }) do
	setmetatable(remote, remoteMt)
end

_G.game = game
_G.workspace = workspaceService
_G.Instance = Instance
_G.Enum = Enum
_G.UDim = UDim
_G.UDim2 = UDim2
_G.Vector2 = Vector2
_G.Vector3 = Vector3
_G.Color3 = Color3
_G.CFrame = CFrame
_G.ColorSequence = ColorSequence
_G.ColorSequenceKeypoint = ColorSequenceKeypoint
_G.NumberSequence = NumberSequence
_G.NumberSequenceKeypoint = NumberSequenceKeypoint
_G.NumberRange = NumberRange
_G.TweenInfo = TweenInfo
_G.gethui = nil
_G.getgenv = nil
_G.identifyexecutor = nil

frameSignal = RunService.RenderStepped

local function step(dt)
	vtime = vtime + dt
	frameSignal:Fire(dt)
	local due, keep = {}, {}
	for _, entry in ipairs(threads) do
		if entry.wake <= vtime then
			table.insert(due, entry)
		else
			table.insert(keep, entry)
		end
	end
	threads = keep
	for _, entry in ipairs(due) do
		resumeThread(entry)
	end
end

local function run(seconds)
	local steps = math.floor(seconds * 60)
	for _ = 1, steps do step(1 / 60) end
end

--== Execute the script ==
print("[harness] loading MALAM_SAMA_OPAH_V2_3_ULTRA.lua")
local chunk = assert(loadfile("MALAM_SAMA_OPAH_V2_3_ULTRA.lua"))
local ok, err = pcall(chunk)
if not ok then
	print("[harness] TOP-LEVEL ERROR: " .. tostring(err))
	os.exit(1)
end

local MSO = _G.MSO
if type(MSO) ~= "table" then
	print("[harness] script did not expose MSO debug table")
	os.exit(1)
end

run(6)

local function guiCount()
	local count = 0
	for _, child in ipairs(playerGui:GetChildren()) do
		if child.ClassName == "ScreenGui" and child.Name == "MSO_Ultra" then count = count + 1 end
	end
	return count
end

print(string.format("[harness] after boot: scans=%d espSyncs=%d screenGuis=%d logs ok",
	MSO.hub.scans, MSO.hub.espSyncs, guiCount()))

-- drive the UI from one coroutine so task.wait behaves like Roblox
local driver = coroutine.create(function()
	local cfg = MSO.cfg

	cfg.espWardrobe:Set(true)
	cfg.espDrawer:Set(true)
	cfg.espLabels:Set(false)
	task.wait(1)
	cfg.espLabels:Set(true)
	cfg.autoLoot:Set(true)
	cfg.lootMode:Set("Teleport")
	task.wait(3)
	cfg.autoLoot:Set(false)

	local opahModel = workspaceService:FindFirstChild("Opah")
	opahModel:SetAttribute("Chasing", true)
	opahModel:SetAttribute("TargetUserId", localPlayer.UserId)
	opahModel:SetAttribute("State", "Chase")
	cfg.autoHide:Set(true)
	cfg.hideMode:Set("Teleport")
	task.wait(3)
	cfg.autoHide:Set(false)
	opahModel:SetAttribute("Chasing", false)

	if MSO.ui.applySearch then
		MSO.ui.applySearch("esp")
		task.wait(0.2)
		MSO.ui.applySearch("")
	end
	if MSO.ui.toggleMinimized then MSO.ui.toggleMinimized() end
	task.wait(0.5)
	MSO.ui.toggleMinimized()
	task.wait(0.5)

	cfg.radar:Set(false)
	cfg.radar:Set(true)
	cfg.passOverlay:Set(false)
	cfg.passOverlay:Set(true)
	cfg.guiScale:Set(0.85)
	task.wait(1)

	if MSO.ui.copyPasscode then MSO.ui.copyPasscode() end
	if MSO.ui.codesRenderList then MSO.ui.codesRenderList() end
	if MSO.ui.codesRedeemAll then MSO.ui.codesRedeemAll() end
	task.wait(2)

	MSO.runDiagnostics()
	task.wait(0.5)

	cfg.interfaceVisible:Set(false)
	task.wait(0.5)
	cfg.interfaceVisible:Set(true)
	task.wait(0.5)

	local keybind = MSO.ui.keybindState
	UserInputService.InputBegan:Fire({ KeyCode = keybind.key, UserInputType = Enum.UserInputType.Keyboard }, false)
	task.wait(0.3)
	UserInputService.InputBegan:Fire({ KeyCode = keybind.key, UserInputType = Enum.UserInputType.Keyboard }, false)
	task.wait(0.3)
end)

addThread(driver, vtime)
run(30)

local connectionsBefore = #MSO.hub.connections
MSO.unload()
run(1)

local problems = {}
for _, message in ipairs(handlerErrors) do table.insert(problems, "handler: " .. message) end
for _, entry in ipairs(MSO.hub.errors) do
	table.insert(problems, tostring(entry.scope) .. ": " .. tostring(entry.message))
end

local espCount = 0
for _ in pairs(MSO.hub.esp) do espCount = espCount + 1 end

print("=======================================================")
print("[harness] summary")
print("  virtual seconds        : " .. string.format("%.1f", vtime))
print("  world scans            : " .. MSO.hub.scans)
print("  esp syncs              : " .. MSO.hub.espSyncs)
print("  esp entries (remaining): " .. espCount)
print("  prompts fired          : " .. firedPrompts)
print("  remote FireServer calls: " .. firedRemotes .. " (expected 0, redemption is gated)")
print("  clipboard value        : " .. tostring(clipboardValue))
print("  tracked connections    : " .. connectionsBefore .. " -> " .. #MSO.hub.connections)
print("  hub.running after load : " .. tostring(MSO.hub.running))
print("  screen GUIs alive      : " .. guiCount() .. " (expected 0 after unload)")
print("  runtime problems       : " .. #problems)
for _, problem in ipairs(problems) do print("    - " .. problem) end
print("=======================================================")
if #problems > 0 then
	print("[harness] RESULT: FAIL")
	os.exit(1)
end
print("[harness] RESULT: PASS (mock runtime only, not Roblox Studio)")
