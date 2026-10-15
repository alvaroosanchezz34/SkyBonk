--[[
	ExperienceService
	Fuentes de experiencia del mapa y su recogida:

	• Gemas: aparecen donde muere un enemigo (siempre sobre suelo alcanzable).
	  Una pasada centralizada por partida (PickupCheckInterval) decide:
	    - dentro del radio de imán → la gema empieza a volar hacia el jugador
	      (atributo "Attracting" para que el cliente anime el vuelo),
	    - al llegar (PickupRadius) → se recoge una sola vez y se concede su XP.
	  No caducan; si hay demasiadas, la más antigua se funde en la nueva.
	• Cristales de Esencia (Map/Interactables): se rompen al tocarlos, sueltan
	  varias gemas y vuelven a crecer pasado un tiempo. Premian la exploración.

	Sin Touched ni bucles por gema o cristal.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local Net = require(Shared.Net)

local StatSheet = require(script.Parent.Parent.Logic.StatSheet)
local MapLayout = require(script.Parent.Parent.World.MapLayout)
local ServerTypes = require(script.Parent.Parent.ServerTypes)

type Run = ServerTypes.Run
type Gem = ServerTypes.Gem

type RunGems = {
	Gems: { Gem },
	NextCheckAt: number,
}

type Crystal = {
	Model: Model,
	Position: Vector3,
	Ready: boolean,
	RespawnAt: number, -- os.clock()
}

local ExperienceService = {}

local services: ServerTypes.Services
local byRun: { [Run]: RunGems } = {}
local crystals: { Crystal } = {}
local orbsFolder: Folder
local groundParams: RaycastParams

local CFG = GameConfig.Experience
local MAP = GameConfig.Map
local NORMAL_COLOR = Color3.fromRGB(80, 240, 255)
local LUCKY_COLOR = Color3.fromRGB(255, 214, 90)
local TAU = math.pi * 2

local function setCrystalVisible(crystal: Crystal, visible: boolean)
	for _, descendant in crystal.Model:GetDescendants() do
		if descendant:IsA("BasePart") then
			local base = descendant:GetAttribute("BaseTransparency")
			if base == nil then
				base = descendant.Transparency
				descendant:SetAttribute("BaseTransparency", base)
			end
			descendant.Transparency = if visible then base else 1
		elseif descendant:IsA("PointLight") then
			descendant.Enabled = visible
		end
	end
	crystal.Model:SetAttribute("Broken", not visible)
end

function ExperienceService.Init(allServices: ServerTypes.Services)
	services = allServices
	orbsFolder = workspace:WaitForChild("ExperienceOrbs") :: Folder
	local map = workspace:WaitForChild("Map")
	groundParams = RaycastParams.new()
	groundParams.FilterType = Enum.RaycastFilterType.Include
	groundParams.FilterDescendantsInstances = { map:WaitForChild("Ground") }

	local interactables = map:FindFirstChild("Interactables")
	if interactables then
		for _, model in interactables:GetChildren() do
			if model:IsA("Model") and model:GetAttribute("EssenceCrystal") then
				table.insert(crystals, {
					Model = model,
					Position = model:GetPivot().Position,
					Ready = true,
					RespawnAt = 0,
				})
			end
		end
	end
end

function ExperienceService.Start() end

function ExperienceService.SetupRun(run: Run)
	byRun[run] = { Gems = {}, NextCheckAt = 0 }
end

local function raycastGround(position: Vector3): Vector3?
	local result = workspace:Raycast(position + Vector3.new(0, 8, 0), Vector3.new(0, -40, 0), groundParams)
	return result and result.Position
end

-- Posición alcanzable: sobre el suelo de la isla (nunca en el vacío ni dentro de rocas).
local function groundedPosition(position: Vector3): Vector3
	local hit = MapLayout.isWalkable(position, 1) and raycastGround(position)
	if hit then
		return hit + Vector3.new(0, 1.4, 0)
	end
	-- Fuera del suelo: se acerca al centro de la isla hasta encontrarlo.
	local toCenter = Vector3.new(MAP.Center.X - position.X, 0, MAP.Center.Z - position.Z)
	local distance = toCenter.Magnitude
	local direction = if distance > 1e-3 then toCenter.Unit else Vector3.zero
	for step = 4, math.max(4, distance), 4 do
		local candidate = position + direction * step
		if MapLayout.isWalkable(candidate, 1) then
			local found = raycastGround(Vector3.new(candidate.X, MAP.SurfaceY + 10, candidate.Z))
			if found then
				return found + Vector3.new(0, 1.4, 0)
			end
		end
	end
	return Vector3.new(MAP.PlayerSpawn.X, MAP.SurfaceY + 1.4, MAP.PlayerSpawn.Z)
end

local function destroyGem(gem: Gem)
	gem.Collected = true
	gem.Part:Destroy()
end

function ExperienceService.SpawnGem(run: Run, position: Vector3, baseXp: number)
	local data = byRun[run]
	if data == nil or run.State.Phase == "GameOver" then
		return
	end
	local lucky = run.Rng:NextNumber() < StatSheet.luckyGemChance(run.State.Stats)
	local value = baseXp * (if lucky then CFG.LuckyGemMultiplier else 1)

	-- Límite de gemas: la más antigua se funde en la nueva (no se pierde XP).
	if #data.Gems >= CFG.MaxGemsPerRun then
		local oldest = table.remove(data.Gems, 1)
		if oldest then
			value += oldest.Value
			destroyGem(oldest)
		end
	end

	local gemPosition = groundedPosition(position)
	local big = lucky or value >= 3
	local part = Instance.new("Part")
	part.Name = if lucky then "XpGemLucky" else "XpGem"
	part.Size = if big then Vector3.new(1.3, 1.8, 1.3) else Vector3.new(0.9, 1.3, 0.9)
	part.CFrame = CFrame.new(gemPosition) * CFrame.Angles(0, math.rad(45), math.rad(45))
	part.Color = if lucky then LUCKY_COLOR else NORMAL_COLOR
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part:SetAttribute("Value", value)
	part.Parent = orbsFolder

	table.insert(data.Gems, {
		Part = part,
		Position = gemPosition,
		Value = value,
		ExpiresAt = if CFG.GemLifetime > 0 then run.State.Elapsed + CFG.GemLifetime else math.huge,
		Collected = false,
		AttractStart = nil,
	})
end

-- Cristales de Esencia: rotura al tocarlos y regeneración.
local function stepCrystals(run: Run, playerPosition: Vector3)
	local cfg = CFG.EssenceCrystal
	local clock = os.clock()
	local radiusSq = cfg.TouchRadius * cfg.TouchRadius
	for _, crystal in crystals do
		if not crystal.Ready then
			if clock >= crystal.RespawnAt then
				crystal.Ready = true
				setCrystalVisible(crystal, true)
			end
			continue
		end
		local offset = crystal.Position - playerPosition
		if offset.X * offset.X + offset.Y * offset.Y + offset.Z * offset.Z > radiusSq then
			continue
		end
		crystal.Ready = false
		crystal.RespawnAt = clock + cfg.RespawnTime
		setCrystalVisible(crystal, false)
		Net.WorldFx:FireAllClients({ Kind = "CrystalBreak", Position = crystal.Position })
		for index = 1, cfg.Gems do
			local angle = (index / cfg.Gems) * TAU + run.Rng:NextNumber() * 0.5
			local distance = 2.5 + run.Rng:NextNumber() * 2.5
			local spot = crystal.Position + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
			ExperienceService.SpawnGem(run, spot, cfg.XpPerGem)
		end
	end
end

function ExperienceService.Step(run: Run)
	local data = byRun[run]
	local state = run.State
	if data == nil or state.Phase ~= "Playing" then
		return
	end
	local now = state.Elapsed
	if now < data.NextCheckAt then
		return
	end
	local dt = CFG.PickupCheckInterval + math.max(0, now - data.NextCheckAt)
	data.NextCheckAt = now + CFG.PickupCheckInterval
	if run.Root.Parent == nil or run.Humanoid.Health <= 0 then
		return
	end

	local playerPosition = run.Root.Position
	local pickupSq = GameConfig.Player.PickupRadius ^ 2
	local magnetSq = StatSheet.magnetRadius(state.Stats) ^ 2
	local gems = data.Gems
	local collectedValue = 0
	local collectedPositions: { Vector3 } = {}

	for index = #gems, 1, -1 do
		local gem = gems[index]
		if gem.Collected or gem.Part.Parent == nil then
			table.remove(gems, index)
			continue
		elseif now >= gem.ExpiresAt then
			destroyGem(gem)
			table.remove(gems, index)
			continue
		end
		local offset = playerPosition - gem.Position
		local distSq = offset.X * offset.X + offset.Y * offset.Y + offset.Z * offset.Z
		if gem.AttractStart == nil and distSq <= magnetSq then
			-- Empieza a volar hacia el jugador (el cliente anima el vuelo).
			gem.AttractStart = now
			gem.Part:SetAttribute("Attracting", true)
		end
		local attractStart = gem.AttractStart
		if attractStart then
			local t = now - attractStart
			local speed = CFG.AttractSpeed + CFG.AttractAcceleration * t
			local distance = math.sqrt(distSq)
			local advance = math.min(distance, speed * dt)
			if distance > 1e-3 then
				gem.Position += offset / distance * advance
			end
			offset = playerPosition - gem.Position
			distSq = offset.X * offset.X + offset.Y * offset.Y + offset.Z * offset.Z
		end
		if distSq <= pickupSq then
			-- Se marca y elimina antes de conceder: una gema = una concesión.
			destroyGem(gem)
			table.remove(gems, index)
			collectedValue += gem.Value
			table.insert(collectedPositions, gem.Position)
		end
	end

	if collectedValue > 0 then
		Net.GemCollected:FireClient(run.Player, { Positions = collectedPositions, Value = collectedValue })
		services.LevelService.GrantExperience(run, collectedValue)
	end
	if #crystals > 0 and state.Phase == "Playing" then
		stepCrystals(run, playerPosition)
	end
end

function ExperienceService.CleanupRun(run: Run)
	local data = byRun[run]
	if data == nil then
		return
	end
	byRun[run] = nil
	for _, gem in data.Gems do
		destroyGem(gem)
	end
	table.clear(data.Gems)
end

return ExperienceService
