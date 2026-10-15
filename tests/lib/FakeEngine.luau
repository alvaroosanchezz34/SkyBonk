--[[
	FakeEngine
	Emulación mínima del motor de Roblox para ejecutar los servicios del
	servidor sin Studio: instancias en memoria (jerarquía, propiedades,
	atributos, señales, Clone/Destroy/PivotTo), Players, Heartbeat, raycast
	contra una isla plana, Random, task con reloj simulado y RemoteEvents.

	No simula colisiones ni gravedad: los enemigos se desplazan integrando
	LinearVelocity.PlaneVelocity, que es lo que decide la IA del servidor.
]]

local roblox = require("@lune/roblox")

local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame

local FakeEngine = {}

----------------------------------------------------------------- Reloj
local clock = 0
local scheduled: { { at: number, fn: (...any) -> (), args: { any } } } = {}

function FakeEngine.now(): number
	return clock
end

FakeEngine.task = {
	delay = function(seconds: number, fn, ...)
		table.insert(scheduled, { at = clock + (seconds or 0), fn = fn, args = { ... } })
	end,
	spawn = function(fn, ...)
		fn(...)
	end,
	defer = function(fn, ...)
		table.insert(scheduled, { at = clock, fn = fn, args = { ... } })
	end,
}

function FakeEngine.advanceClock(dt: number)
	clock += dt
	local index = 1
	while index <= #scheduled do
		local entry = scheduled[index]
		if entry.at <= clock then
			table.remove(scheduled, index)
			entry.fn(table.unpack(entry.args))
		else
			index += 1
		end
	end
end

FakeEngine.os = {
	clock = function()
		return clock
	end,
	time = os.time,
}

---------------------------------------------------------------- Señales
local function newSignal()
	local signal = { _handlers = {} }
	function signal.Connect(self, fn)
		local connection = { Connected = true }
		function connection.Disconnect(c)
			c.Connected = false
		end
		table.insert(self._handlers, { fn = fn, connection = connection })
		return connection
	end
	function signal.Fire(self, ...)
		for _, handler in table.clone(self._handlers) do
			if handler.connection.Connected then
				handler.fn(...)
			end
		end
	end
	function signal.DisconnectAll(self)
		for _, handler in self._handlers do
			handler.connection.Connected = false
		end
		table.clear(self._handlers)
	end
	return signal
end
FakeEngine.newSignal = newSignal

------------------------------------------------------------- Instancias
local BASEPART_CLASSES = {
	Part = true,
	WedgePart = true,
	SpawnLocation = true,
	MeshPart = true,
	CornerWedgePart = true,
}

local SIGNAL_NAMES = {
	Died = true,
	DescendantAdded = true,
	AncestryChanged = true,
	ChildAdded = true,
	ChildRemoved = true,
	PlayerAdded = true,
	PlayerRemoving = true,
	Heartbeat = true,
	OnServerEvent = true,
}

local Instance = {}
local InstanceMT = {}
local methods = {}

FakeEngine.stats = { created = 0, destroyed = 0 }

local function isA(self, className: string): boolean
	local own = rawget(self, "ClassName")
	if className == own or className == "Instance" then
		return true
	end
	if className == "BasePart" then
		return BASEPART_CLASSES[own] == true
	end
	if className == "PVInstance" then
		return BASEPART_CLASSES[own] == true or own == "Model"
	end
	return false
end

function Instance.new(className: string)
	FakeEngine.stats.created += 1
	local self = {
		ClassName = className,
		_name = className,
		_parent = nil,
		_children = {},
		_props = {},
		_attrs = {},
		_signals = {},
		_destroyed = false,
	}
	setmetatable(self, InstanceMT)
	if BASEPART_CLASSES[className] then
		self._props.CFrame = CFrame.new()
		self._props.Size = Vector3.new(4, 1, 2)
		self._props.Anchored = false
		self._props.CanCollide = true
		self._props.CollisionGroup = "Default"
		self._props.AssemblyLinearVelocity = Vector3.zero
	elseif className == "Humanoid" then
		self._props.Health = 100
		self._props.MaxHealth = 100
		self._props.WalkSpeed = 16
		self._props.CameraOffset = Vector3.zero
	end
	return self
end
FakeEngine.Instance = Instance

local function fireDescendantAdded(ancestor, descendant)
	local node = ancestor
	while node do
		local signal = rawget(node, "_signals").DescendantAdded
		if signal then
			signal:Fire(descendant)
		end
		node = rawget(node, "_parent")
	end
end

local function setParent(self, newParent)
	local old = rawget(self, "_parent")
	if old == newParent then
		return
	end
	if rawget(self, "_destroyed") and newParent ~= nil then
		error("No se puede cambiar el padre de una instancia destruida: " .. rawget(self, "_name"))
	end
	if old then
		local siblings = rawget(old, "_children")
		local index = table.find(siblings, self)
		if index then
			table.remove(siblings, index)
		end
		local removed = rawget(old, "_signals").ChildRemoved
		if removed then
			removed:Fire(self)
		end
	end
	rawset(self, "_parent", newParent)
	if newParent then
		table.insert(rawget(newParent, "_children"), self)
		local added = rawget(newParent, "_signals").ChildAdded
		if added then
			added:Fire(self)
		end
		fireDescendantAdded(newParent, self)
	end
	local ancestry = rawget(self, "_signals").AncestryChanged
	if ancestry then
		ancestry:Fire(self, newParent)
	end
end

InstanceMT.__index = function(self, key)
	if key == "Name" then
		return rawget(self, "_name")
	elseif key == "Parent" then
		return rawget(self, "_parent")
	end
	local method = methods[key]
	if method then
		return method
	end
	local props = rawget(self, "_props")
	if key == "Position" and props.CFrame then
		return props.CFrame.Position
	end
	local value = props[key]
	if value ~= nil then
		return value
	end
	if SIGNAL_NAMES[key] then
		local signals = rawget(self, "_signals")
		signals[key] = signals[key] or newSignal()
		return signals[key]
	end
	return methods.FindFirstChild(self, key)
end

InstanceMT.__newindex = function(self, key, value)
	if key == "Name" then
		rawset(self, "_name", value)
		return
	elseif key == "Parent" then
		setParent(self, value)
		return
	end
	local props = rawget(self, "_props")
	if key == "Position" then
		local current = props.CFrame or CFrame.new()
		props.CFrame = CFrame.new(value) * (current - current.Position)
		return
	end
	if key == "Health" and rawget(self, "ClassName") == "Humanoid" then
		local old = props.Health or 0
		local maxHealth = props.MaxHealth or 100
		value = math.clamp(value, 0, maxHealth)
		props.Health = value
		if old > 0 and value <= 0 then
			local died = rawget(self, "_signals").Died
			if died then
				died:Fire()
			end
		end
		return
	end
	if key == "MaxHealth" and rawget(self, "ClassName") == "Humanoid" then
		props.MaxHealth = value
		if (props.Health or 0) > value then
			props.Health = value
		end
		return
	end
	props[key] = value
end

InstanceMT.__tostring = function(self)
	return rawget(self, "_name")
end

function methods.IsA(self, className)
	return isA(self, className)
end

function methods.GetChildren(self)
	return table.clone(rawget(self, "_children"))
end

function methods.GetDescendants(self)
	local list = {}
	local function walk(node)
		for _, child in rawget(node, "_children") do
			table.insert(list, child)
			walk(child)
		end
	end
	walk(self)
	return list
end

function methods.FindFirstChild(self, name, recursive)
	for _, child in rawget(self, "_children") do
		if rawget(child, "_name") == name then
			return child
		end
	end
	if recursive then
		for _, child in rawget(self, "_children") do
			local found = methods.FindFirstChild(child, name, true)
			if found then
				return found
			end
		end
	end
	return nil
end

function methods.WaitForChild(self, name)
	local child = methods.FindFirstChild(self, name)
	assert(child, "WaitForChild: falta " .. tostring(name) .. " en " .. rawget(self, "_name"))
	return child
end

function methods.FindFirstChildOfClass(self, className)
	for _, child in rawget(self, "_children") do
		if rawget(child, "ClassName") == className then
			return child
		end
	end
	return nil
end

function methods.IsDescendantOf(self, ancestor)
	local node = rawget(self, "_parent")
	while node do
		if node == ancestor then
			return true
		end
		node = rawget(node, "_parent")
	end
	return false
end

function methods.GetFullName(self)
	local parts = {}
	local node = self
	while node do
		table.insert(parts, 1, rawget(node, "_name"))
		node = rawget(node, "_parent")
	end
	return table.concat(parts, ".")
end

function methods.SetAttribute(self, name, value)
	rawget(self, "_attrs")[name] = value
end

function methods.GetAttribute(self, name)
	return rawget(self, "_attrs")[name]
end

function methods.SetNetworkOwner(_self, _owner) end

function methods.Destroy(self)
	if rawget(self, "_destroyed") then
		return
	end
	FakeEngine.stats.destroyed += 1
	for _, child in table.clone(rawget(self, "_children")) do
		methods.Destroy(child)
	end
	setParent(self, nil)
	rawset(self, "_destroyed", true)
	for _, signal in rawget(self, "_signals") do
		signal:DisconnectAll()
	end
end

function methods.PivotTo(self, target)
	local own = rawget(self, "ClassName")
	if BASEPART_CLASSES[own] then
		rawget(self, "_props").CFrame = target
		return
	end
	local primary = rawget(self, "_props").PrimaryPart
	local pivot = if primary then primary.CFrame else CFrame.new()
	local delta = target * pivot:Inverse()
	for _, descendant in methods.GetDescendants(self) do
		if descendant:IsA("BasePart") then
			local props = rawget(descendant, "_props")
			props.CFrame = delta * props.CFrame
		end
	end
end

function methods.Clone(self)
	local mapping = {}
	local function copy(node)
		local clone = Instance.new(rawget(node, "ClassName"))
		rawset(clone, "_name", rawget(node, "_name"))
		for key, value in rawget(node, "_props") do
			rawget(clone, "_props")[key] = value
		end
		for key, value in rawget(node, "_attrs") do
			rawget(clone, "_attrs")[key] = value
		end
		mapping[node] = clone
		for _, child in rawget(node, "_children") do
			local childClone = copy(child)
			rawset(childClone, "_parent", clone)
			table.insert(rawget(clone, "_children"), childClone)
		end
		return clone
	end
	local root = copy(self)
	-- Remapea referencias internas (PrimaryPart, Part0/Part1, Attachment0...).
	for _, clone in mapping do
		local props = rawget(clone, "_props")
		for key, value in props do
			if type(value) == "table" and mapping[value] then
				props[key] = mapping[value]
			end
		end
	end
	return root
end

---------------------------------------------------------------- Mundo
function FakeEngine.createWorld(islandRadius: number)
	local world = {}
	world.Workspace = Instance.new("Workspace")
	world.Workspace.Name = "Workspace"
	local map = Instance.new("Folder")
	map.Name = "Map"
	map.Parent = world.Workspace
	local ground = Instance.new("Folder")
	ground.Name = "Ground"
	ground.Parent = map
	local props = Instance.new("Folder")
	props.Name = "Props"
	props.Parent = map
	local groundPart = Instance.new("Part")
	groundPart.Name = "IslandSurface"
	groundPart.Anchored = true
	groundPart.Parent = ground
	world.GroundPart = groundPart
	for _, name in { "ActiveEnemies", "ExperienceOrbs" } do
		local folder = Instance.new("Folder")
		folder.Name = name
		folder.Parent = world.Workspace
	end

	-- Raycast hacia abajo contra una isla circular plana en Y = 0.
	function methods.Raycast(_self, origin, direction, _params)
		local horizontal = math.sqrt(origin.X * origin.X + origin.Z * origin.Z)
		if horizontal > islandRadius or direction.Y >= 0 then
			return nil
		end
		if origin.Y < 0 or origin.Y + direction.Y > 0 then
			return nil
		end
		return {
			Instance = groundPart,
			Position = Vector3.new(origin.X, 0, origin.Z),
			Normal = Vector3.new(0, 1, 0),
		}
	end

	world.ServerStorage = Instance.new("ServerStorage")
	world.ServerStorage.Name = "ServerStorage"
	local models = Instance.new("Folder")
	models.Name = "EnemyModels"
	models.Parent = world.ServerStorage

	world.Players = Instance.new("Players")
	world.Players.Name = "Players"
	function methods.GetPlayers(self)
		if rawget(self, "ClassName") == "Players" then
			return methods.GetChildren(self)
		end
		return {}
	end

	world.RunService = Instance.new("RunService")
	world.RunService.Name = "RunService"
	world.RunService.IsStudio = function()
		return false
	end
	return world
end

function FakeEngine.createPlayer(world, name: string, spawnPosition: Vector3)
	local player = Instance.new("Player")
	player.Name = name
	player.UserId = 1
	player.LoadCharacter = function(self)
		local old = self.Character
		if old then
			old:Destroy()
		end
		local character = Instance.new("Model")
		character.Name = name
		local humanoid = Instance.new("Humanoid")
		humanoid.Parent = character
		local root = Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.Size = Vector3.new(2, 2, 1)
		root.CFrame = CFrame.new(spawnPosition)
		root.Parent = character
		local head = Instance.new("Part")
		head.Name = "Head"
		head.Parent = character
		character.PrimaryPart = root
		self.Character = character
		character.Parent = world.Workspace
	end
	player.Parent = world.Players
	return player
end

----------------------------------------------------------- Aleatorio
function FakeEngine.Random()
	return {
		new = function(seed: number?)
			local state = (seed or 12345) % 2147483647
			if state <= 0 then
				state += 2147483646
			end
			local rng = {}
			local function nextUnit()
				state = (state * 48271) % 2147483647
				return state / 2147483647
			end
			function rng.NextNumber(_self, min: number?, max: number?)
				local unit = nextUnit()
				if min and max then
					return min + (max - min) * unit
				end
				return unit
			end
			function rng.NextInteger(_self, min: number, max: number)
				return math.min(max, min + math.floor(nextUnit() * (max - min + 1)))
			end
			return rng
		end,
	}
end

FakeEngine.RaycastParams = {
	new = function()
		return {}
	end,
}

--------------------------------------------------------- RemoteEvents
-- Devuelve un sustituto de Shared/Net que registra todo lo enviado.
function FakeEngine.createNet(names: { string })
	local net = {}
	local log: { { name: string, args: { any } } } = {}
	local clientHandlers: { [string]: { (...any) -> () } } = {}
	for _, name in names do
		local remote = { OnServerEvent = newSignal() }
		function remote.FireClient(_self, _player, ...)
			table.insert(log, { name = name, args = { ... } })
			for _, handler in clientHandlers[name] or {} do
				handler(...)
			end
		end
		function remote.FireServer(self, player, ...)
			self.OnServerEvent:Fire(player, ...)
		end
		net[name] = remote
	end
	return net,
		log,
		function(name: string, handler)
			clientHandlers[name] = clientHandlers[name] or {}
			table.insert(clientHandlers[name], handler)
		end
end

return FakeEngine
