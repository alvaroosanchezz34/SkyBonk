--[[
	SpawnService
	Aparición controlada de enemigos alrededor del jugador:
	  • a una distancia entre MinRadius y MaxRadius (nunca encima del jugador),
	  • solo sobre suelo de la isla (raycast contra Map/Ground) y lejos del borde
	    (World/MapLayout), incluidos mesetas, puente y santuario,
	  • respetando el límite de enemigos activos y el de cada tipo,
	  • con intervalo, tamaño de oleada, tipos y estadísticas que escalan con el tiempo,
	  • con un periodo de gracia corto, una primera oleada para entrar en acción
	    enseguida, y detenida fuera de Playing.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local ServerTypes = require(script.Parent.Parent.ServerTypes)
local MapLayout = require(script.Parent.Parent.World.MapLayout)

type Run = ServerTypes.Run

local SpawnService = {}

local services: ServerTypes.Services
local nextSpawnAt: { [Run]: number } = {}
local openingDone: { [Run]: boolean } = {}
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
	openingDone[run] = false
end

function SpawnService.CleanupRun(run: Run)
	nextSpawnAt[run] = nil
	openingDone[run] = nil
end

-- Multiplicadores de dificultad según los minutos de partida.
function SpawnService.DifficultyAt(elapsed: number)
	local m = elapsed / 60
	local difficulty = GameConfig.Difficulty
	return {
		Health = 1 + difficulty.HealthLinear * m + difficulty.HealthQuadratic * m * m,
		Damage = 1 + difficulty.DamageLinear * m + difficulty.DamageQuadratic * m * m,
		Speed = math.min(difficulty.MaxSpeedMultiplier, 1 + difficulty.SpeedPerMinute * m),
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

-- Tipo de enemigo según el minuto de partida (pesos de GameConfig.Spawn.EnemyTypes).
function SpawnService.PickEnemyType(run: Run, elapsed: number): string?
	local minutes = elapsed / 60
	local total = 0
	local weights: { number } = {}
	for index, entry in CFG.EnemyTypes do
		local weight = 0
		if minutes >= entry.FromMinute then
			local alive = services.EnemyService.CountOfType(run, entry.Id)
			if entry.MaxAlive == nil or alive < entry.MaxAlive then
				weight = entry.Weight + entry.WeightPerMinute * (minutes - entry.FromMinute)
			end
		end
		weights[index] = weight
		total += weight
	end
	if total <= 0 then
		return nil
	end
	local roll = run.Rng:NextNumber() * total
	for index, entry in CFG.EnemyTypes do
		roll -= weights[index]
		if roll < 0 then
			return entry.Id
		end
	end
	return CFG.EnemyTypes[1].Id
end

-- Busca un punto del suelo válido; devuelve nil si ningún intento es válido.
-- Si alrededor casi todo es vacío (santuario, puente), lo intenta más cerca.
function SpawnService.FindSpawnPosition(run: Run): Vector3?
	return SpawnService.TrySpawnPosition(run, CFG.MinRadius, CFG.MaxRadius)
		or SpawnService.TrySpawnPosition(run, CFG.MinRadius * 0.55, CFG.MinRadius)
end

function SpawnService.TrySpawnPosition(run: Run, minRadius: number, maxRadius: number): Vector3?
	local origin = run.Root.Position
	for _ = 1, CFG.Attempts do
		local angle = run.Rng:NextNumber() * TAU
		local distance = run.Rng:NextNumber(minRadius, maxRadius)
		local candidate = origin + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
		local dx, dz = candidate.X - MAP.Center.X, candidate.Z - MAP.Center.Z
		if dx * dx + dz * dz > MAP.BoundsRadius * MAP.BoundsRadius then
			continue
		end
		if not MapLayout.isWalkable(candidate, CFG.EdgeMargin) then
			continue
		end
		local rayOrigin = Vector3.new(candidate.X, MAP.SurfaceY + 60, candidate.Z)
		local result = workspace:Raycast(rayOrigin, Vector3.new(0, -120, 0), raycastParams)
		-- Debe caer sobre suelo (no sobre ruinas, árboles o rocas).
		if result and result.Instance:IsDescendantOf(groundFolder) then
			local position = result.Position
			local fromPlayer = Vector3.new(position.X - origin.X, 0, position.Z - origin.Z)
			if fromPlayer.Magnitude >= minRadius * 0.9 then
				return position
			end
		end
	end
	return nil
end

-- Tope de enemigos activos en este momento de la partida.
function SpawnService.CapAt(elapsed: number): number
	return math.min(CFG.MaxActiveEnemies, math.floor(CFG.MaxActiveStart + CFG.MaxActivePerMinute * elapsed / 60))
end

local function spawnBatch(run: Run, count: number, now: number)
	local enemyService = services.EnemyService
	local multipliers = SpawnService.DifficultyAt(now)
	local cap = SpawnService.CapAt(now)
	for _ = 1, count do
		if enemyService.Count(run) >= cap then
			break
		end
		local enemyType = SpawnService.PickEnemyType(run, now)
		local position = enemyType and SpawnService.FindSpawnPosition(run)
		if enemyType == nil or position == nil then
			break
		end
		enemyService.Spawn(run, enemyType, position, multipliers)
	end
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
	local count = SpawnService.BatchAt(now)
	if not openingDone[run] then
		openingDone[run] = true
		count = math.max(count, CFG.OpeningWave)
	end
	spawnBatch(run, count, now)
end

return SpawnService
