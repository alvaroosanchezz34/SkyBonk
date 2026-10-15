--[[
	ExperienceService
	Gemas de experiencia: creación al morir un enemigo, comprobación de
	proximidad centralizada (una sola pasada por partida a frecuencia
	reducida, sin bucles ni Touched por gema), recogida única, caducidad
	y límite de gemas simultáneas.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local Net = require(Shared.Net)

local StatSheet = require(script.Parent.Parent.Logic.StatSheet)
local ServerTypes = require(script.Parent.Parent.ServerTypes)

type Run = ServerTypes.Run
type Gem = ServerTypes.Gem

type RunGems = {
	Gems: { Gem },
	NextCheckAt: number,
}

local ExperienceService = {}

local services: ServerTypes.Services
local byRun: { [Run]: RunGems } = {}
local orbsFolder: Folder
local groundParams: RaycastParams

local CFG = GameConfig.Experience
local MAP = GameConfig.Map
local NORMAL_COLOR = Color3.fromRGB(80, 240, 255)
local LUCKY_COLOR = Color3.fromRGB(255, 214, 90)

function ExperienceService.Init(allServices: ServerTypes.Services)
	services = allServices
	orbsFolder = workspace:WaitForChild("ExperienceOrbs") :: Folder
	groundParams = RaycastParams.new()
	groundParams.FilterType = Enum.RaycastFilterType.Include
	groundParams.FilterDescendantsInstances = { workspace:WaitForChild("Map"):WaitForChild("Ground") }
end

function ExperienceService.Start() end

function ExperienceService.SetupRun(run: Run)
	byRun[run] = { Gems = {}, NextCheckAt = 0 }
end

-- Posición alcanzable: sobre el suelo y dentro de la isla.
local function groundedPosition(position: Vector3): Vector3
	local flat = Vector3.new(position.X - MAP.Center.X, 0, position.Z - MAP.Center.Z)
	local limit = MAP.PlayableRadius - 2
	if flat.Magnitude > limit then
		flat = flat.Unit * limit
		position = Vector3.new(MAP.Center.X + flat.X, position.Y, MAP.Center.Z + flat.Z)
	end
	local result = workspace:Raycast(position + Vector3.new(0, 6, 0), Vector3.new(0, -40, 0), groundParams)
	if result then
		return result.Position + Vector3.new(0, 1.4, 0)
	end
	return Vector3.new(position.X, MAP.SurfaceY + 1.4, position.Z)
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
	local part = Instance.new("Part")
	part.Name = if lucky then "XpGemLucky" else "XpGem"
	part.Size = if lucky then Vector3.new(1.2, 1.7, 1.2) else Vector3.new(0.8, 1.2, 0.8)
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
		ExpiresAt = run.State.Elapsed + CFG.GemLifetime,
		Collected = false,
	})
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
	data.NextCheckAt = now + CFG.PickupCheckInterval
	if run.Root.Parent == nil or run.Humanoid.Health <= 0 then
		return
	end

	local playerPosition = run.Root.Position
	local radius = GameConfig.Player.PickupRadius
	local radiusSq = radius * radius
	local gems = data.Gems
	local collectedValue = 0
	local collectedPositions: { Vector3 } = {}

	for index = #gems, 1, -1 do
		local gem = gems[index]
		if gem.Collected or gem.Part.Parent == nil then
			table.remove(gems, index)
		elseif now >= gem.ExpiresAt then
			destroyGem(gem)
			table.remove(gems, index)
		else
			local offset = gem.Position - playerPosition
			if offset.X * offset.X + offset.Y * offset.Y + offset.Z * offset.Z <= radiusSq then
				-- Se marca y elimina antes de conceder: una gema = una concesión.
				destroyGem(gem)
				table.remove(gems, index)
				collectedValue += gem.Value
				table.insert(collectedPositions, gem.Position)
			end
		end
	end

	if collectedValue > 0 then
		Net.GemCollected:FireClient(run.Player, { Positions = collectedPositions, Value = collectedValue })
		services.LevelService.GrantExperience(run, collectedValue)
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
