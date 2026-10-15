--[[
	SpawnService
	Aparición controlada de enemigos alrededor del jugador:
	  • a una distancia entre MinRadius y MaxRadius (nunca encima del jugador),
	  • solo sobre suelo de la isla (raycast contra Map/Ground) y lejos del borde,
	  • respetando el límite de enemigos activos,
	  • con intervalo, tamaño de oleada y estadísticas que escalan con el tiempo,
	  • con un periodo de gracia al empezar y detenida fuera de Playing.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local ServerTypes = require(script.Parent.Parent.ServerTypes)

type Run = ServerTypes.Run

local SpawnService = {}

local services: ServerTypes.Services
local nextSpawnAt: { [Run]: number } = {}
local groundFolder: Instance
local raycastParams: RaycastParams

local TAU = math.pi * 2
local CFG = GameConfig.Spawn
local MAP = GameConfig.Map

function SpawnService.Init(allServices: ServerTypes.Services)
	services = allServices
	local map = workspace:WaitForChild("Map")
	groundFolder = map:WaitForChild("Ground")
	raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Include
	raycastParams.FilterDescendantsInstances = { groundFolder, map:WaitForChild("Props") }
	raycastParams.IgnoreWater = true
end

function SpawnService.Start() end

function SpawnService.SetupRun(run: Run)
	nextSpawnAt[run] = CFG.GracePeriod
end

function SpawnService.CleanupRun(run: Run)
	nextSpawnAt[run] = nil
end

-- Multiplicadores de dificultad según los minutos de partida.
function SpawnService.DifficultyAt(elapsed: number)
	local minutes = elapsed / 60
	local difficulty = GameConfig.Difficulty
	return {
		Health = 1 + difficulty.HealthPerMinute * minutes,
		Damage = 1 + difficulty.DamagePerMinute * minutes,
		Speed = math.min(difficulty.MaxSpeedMultiplier, 1 + difficulty.SpeedPerMinute * minutes),
	}
end

function SpawnService.IntervalAt(elapsed: number): number
	local minutes = elapsed / 60
	return math.max(CFG.MinInterval, CFG.InitialInterval * CFG.IntervalMultiplierPerMinute ^ minutes)
end

function SpawnService.BatchAt(elapsed: number): number
	local minutes = elapsed / 60
	return math.clamp(math.floor(CFG.InitialBatch + CFG.BatchGrowthPerMinute * minutes), 1, CFG.MaxBatch)
end

-- Busca una posición válida; devuelve nil si ningún intento es válido.
function SpawnService.FindSpawnPosition(run: Run): Vector3?
	local origin = run.Root.Position
	local maxRadius = MAP.PlayableRadius - CFG.EdgeMargin
	for _ = 1, CFG.Attempts do
		local angle = run.Rng:NextNumber() * TAU
		local distance = run.Rng:NextNumber(CFG.MinRadius, CFG.MaxRadius)
		local candidate = origin + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
		local dx, dz = candidate.X - MAP.Center.X, candidate.Z - MAP.Center.Z
		if dx * dx + dz * dz > maxRadius * maxRadius then
			continue
		end
		local rayOrigin = Vector3.new(candidate.X, MAP.SurfaceY + 60, candidate.Z)
		local result = workspace:Raycast(rayOrigin, Vector3.new(0, -120, 0), raycastParams)
		-- Debe caer sobre suelo (no sobre ruinas, árboles o rocas).
		if result and result.Instance:IsDescendantOf(groundFolder) then
			local position = result.Position + Vector3.new(0, 1.6, 0)
			local fromPlayer = Vector3.new(position.X - origin.X, 0, position.Z - origin.Z)
			if fromPlayer.Magnitude >= CFG.MinRadius * 0.9 then
				return position
			end
		end
	end
	return nil
end

function SpawnService.Step(run: Run)
	local state = run.State
	local scheduled = nextSpawnAt[run]
	if scheduled == nil or state.Phase ~= "Playing" or run.Humanoid.Health <= 0 then
		return
	end
	local now = state.Elapsed
	if now < scheduled then
		return
	end
	nextSpawnAt[run] = now + SpawnService.IntervalAt(now)

	local enemyService = services.EnemyService
	local multipliers = SpawnService.DifficultyAt(now)
	for _ = 1, SpawnService.BatchAt(now) do
		if enemyService.Count(run) >= CFG.MaxActiveEnemies then
			break
		end
		local position = SpawnService.FindSpawnPosition(run)
		if position == nil then
			break
		end
		local enemyType = CFG.EnemyTypes[run.Rng:NextInteger(1, #CFG.EnemyTypes)]
		enemyService.Spawn(run, enemyType, position, multipliers)
	end
end

return SpawnService
