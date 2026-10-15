--[[
	EnemyService
	Ciclo de vida de los enemigos: aparición, IA centralizada (persecución,
	rodeo de obstáculos, ataque por contacto), daño, muerte y limpieza.

	Un único tick de IA (GameConfig.Combat.EnemyAiInterval) recorre todos los
	enemigos de cada partida; no hay scripts ni bucles por enemigo. El
	movimiento es físico (LinearVelocity en el plano XZ), por lo que los
	enemigos chocan con paredes y rocas y no las atraviesan.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local EnemyConfig = require(Shared.Config.EnemyConfig)
local Net = require(Shared.Net)
local Types = require(Shared.Types)

local RunState = require(script.Parent.Parent.Logic.RunState)
local ModelFactory = require(script.Parent.Parent.World.ModelFactory)
local ServerTypes = require(script.Parent.Parent.ServerTypes)

type Run = ServerTypes.Run
type Enemy = ServerTypes.Enemy

type RunEnemies = {
	List: { Enemy },
	Frozen: boolean,
	NextAiAt: number,
}

export type Multipliers = { Health: number, Damage: number, Speed: number }

local EnemyService = {}

local services: ServerTypes.Services
local byRun: { [Run]: RunEnemies } = {}
local nextEnemyId = 0
local activeFolder: Folder
local templatesFolder: Folder
local EMPTY: { Enemy } = {}

local MAP_CENTER = GameConfig.Map.Center
local EDGE_RADIUS = GameConfig.Map.PlayableRadius + 4
local BOUNDS_RADIUS = GameConfig.Map.BoundsRadius
local KILL_Y = GameConfig.Map.KillY

function EnemyService.Init(allServices: ServerTypes.Services)
	services = allServices
	activeFolder = workspace:WaitForChild("ActiveEnemies") :: Folder
	templatesFolder = ServerStorage:WaitForChild("EnemyModels") :: Folder
end

function EnemyService.Start() end

-- Crea (una sola vez) las plantillas que falten en ServerStorage/EnemyModels.
function EnemyService.EnsureTemplates(folder: Folder)
	for _, def in EnemyConfig do
		if folder:FindFirstChild(def.ModelName) == nil then
			local builder = ModelFactory.Builders[def.ModelName]
			assert(builder, "No hay modelo ni constructor para " .. def.ModelName)
			builder(def).Parent = folder
		end
	end
end

function EnemyService.SetupRun(run: Run)
	byRun[run] = { List = {}, Frozen = false, NextAiAt = 0 }
end

function EnemyService.GetEnemies(run: Run): { Enemy }
	local data = byRun[run]
	return if data then data.List else EMPTY
end

function EnemyService.Count(run: Run): number
	local data = byRun[run]
	return if data then #data.List else 0
end

local function removeFromList(list: { Enemy }, enemy: Enemy)
	local index = table.find(list, enemy)
	if index then
		-- Intercambio con el último: O(1) y sin huecos.
		list[index] = list[#list]
		list[#list] = nil
	end
end

local function despawn(enemy: Enemy)
	enemy.Dead = true
	local data = byRun[enemy.Run]
	if data then
		removeFromList(data.List, enemy)
	end
	enemy.Model:Destroy()
end

local function isOutOfBounds(position: Vector3): boolean
	if position.Y < KILL_Y then
		return true
	end
	local dx, dz = position.X - MAP_CENTER.X, position.Z - MAP_CENTER.Z
	return dx * dx + dz * dz > BOUNDS_RADIUS * BOUNDS_RADIUS
end
EnemyService.IsOutOfBounds = isOutOfBounds

function EnemyService.Spawn(run: Run, enemyId: string, position: Vector3, multipliers: Multipliers): Enemy?
	local data = byRun[run]
	local def: Types.EnemyDef? = EnemyConfig[enemyId]
	if data == nil or def == nil or not run.Active then
		return nil
	end
	local template = templatesFolder:FindFirstChild(def.ModelName)
	if template == nil then
		warn("[EnemyService] Falta la plantilla", def.ModelName)
		return nil
	end

	local model = template:Clone() :: Model
	local root = model.PrimaryPart :: BasePart
	local mover = root:FindFirstChild("Mover") :: LinearVelocity
	local facing = root:FindFirstChild("Facing") :: AlignOrientation
	if not (root and mover and facing) then
		warn("[EnemyService] Plantilla incompleta", def.ModelName)
		model:Destroy()
		return nil
	end

	nextEnemyId += 1
	local maxHealth = def.MaxHealth * multipliers.Health
	model:PivotTo(CFrame.new(position))
	model:SetAttribute("EnemyId", def.Id)
	model:SetAttribute("Health", maxHealth)
	model:SetAttribute("MaxHealth", maxHealth)
	root.CollisionGroup = "Enemies"
	root.Anchored = data.Frozen
	model.Parent = activeFolder
	if not data.Frozen then
		-- El servidor es dueño de la física: el cliente no puede empujarlos.
		pcall(root.SetNetworkOwner, root, nil)
	end

	local now = run.State.Elapsed
	local enemy: Enemy = {
		Id = nextEnemyId,
		Def = def,
		Run = run,
		Model = model,
		Root = root,
		Mover = mover,
		Facing = facing,
		Health = maxHealth,
		MaxHealth = maxHealth,
		Damage = def.ContactDamage * multipliers.Damage,
		Speed = def.MoveSpeed * multipliers.Speed,
		Dead = false,
		Position = position,
		-- Pequeño margen para que un enemigo recién aparecido no golpee al instante.
		NextAttackAt = now + 0.5,
		LastProgressPosition = position,
		LastProgressAt = now,
		SidestepUntil = 0,
		SidestepSign = 1,
	}
	table.insert(data.List, enemy)
	return enemy
end

local function kill(enemy: Enemy)
	-- `Dead` se marca antes que nada: una muerte solo genera una recompensa.
	enemy.Dead = true
	local run = enemy.Run
	local position = enemy.Root.Position
	local data = byRun[run]
	if data then
		removeFromList(data.List, enemy)
	end
	enemy.Model:Destroy()

	RunState.addKill(run.State)
	Net.EnemyDied:FireClient(run.Player, { Position = position, Color = enemy.Def.Color })
	services.ExperienceService.SpawnGem(run, position, enemy.Def.XpReward)
	services.MatchService.MarkHudDirty(run)
end

-- Aplica daño calculado por el servidor. Devuelve (murió, daño aplicado).
function EnemyService.Damage(enemy: Enemy, amount: number): (boolean, number)
	if enemy.Dead or enemy.Model.Parent == nil or not enemy.Run.Active then
		return false, 0
	end
	if type(amount) ~= "number" or amount ~= amount or amount <= 0 then
		return false, 0
	end
	local dealt = math.min(amount, enemy.Health)
	enemy.Health -= dealt
	enemy.Model:SetAttribute("Health", enemy.Health)
	if enemy.Health <= 0 then
		kill(enemy)
		return true, dealt
	end
	return false, dealt
end

function EnemyService.SetFrozen(run: Run, frozen: boolean)
	local data = byRun[run]
	if data == nil or data.Frozen == frozen then
		return
	end
	data.Frozen = frozen
	for _, enemy in data.List do
		enemy.Mover.PlaneVelocity = Vector2.zero
		enemy.Root.Anchored = frozen
		if not frozen then
			pcall(enemy.Root.SetNetworkOwner, enemy.Root, nil)
		end
	end
end

-- Dirección horizontal hacia el jugador con rodeo de obstáculos y sin salir de la isla.
local function steer(enemy: Enemy, toTarget: Vector3, now: number): Vector3
	local direction = toTarget.Unit
	if now < enemy.SidestepUntil then
		local perpendicular = Vector3.new(-direction.Z, 0, direction.X) * enemy.SidestepSign
		direction = (direction * 0.35 + perpendicular).Unit
	end
	-- No avanzar hacia el vacío: elimina la componente radial hacia fuera cerca del borde.
	local position = enemy.Position
	local radial = Vector3.new(position.X - MAP_CENTER.X, 0, position.Z - MAP_CENTER.Z)
	if radial.Magnitude > EDGE_RADIUS - 3 then
		local outward = radial.Unit
		local outwardSpeed = direction:Dot(outward)
		if outwardSpeed > 0 then
			direction -= outward * outwardSpeed
		end
	end
	return direction
end

function EnemyService.Step(run: Run)
	local data = byRun[run]
	if data == nil or data.Frozen or run.State.Phase ~= "Playing" then
		return
	end
	local now = run.State.Elapsed
	if now < data.NextAiAt then
		return
	end
	data.NextAiAt = now + GameConfig.Combat.EnemyAiInterval

	local playerAlive = run.Root.Parent ~= nil and run.Humanoid.Health > 0
	local playerPosition = run.Root.Position
	local combat = GameConfig.Combat
	local list = data.List

	for index = #list, 1, -1 do
		local enemy = list[index]
		if enemy == nil or enemy.Dead then
			continue
		end
		if enemy.Model.Parent == nil then
			despawn(enemy)
			continue
		end
		local position = enemy.Root.Position
		enemy.Position = position
		if isOutOfBounds(position) then
			-- Se cayó o salió del mapa: se elimina sin recompensa.
			despawn(enemy)
			continue
		end
		if not playerAlive then
			enemy.Mover.PlaneVelocity = Vector2.zero
			continue
		end

		local offset = playerPosition - position
		local flat = Vector3.new(offset.X, 0, offset.Z)
		local distance = flat.Magnitude

		-- Ataque por contacto con enfriamiento propio de cada enemigo.
		if distance <= enemy.Def.AttackRange and math.abs(offset.Y) < 6 and now >= enemy.NextAttackAt then
			enemy.NextAttackAt = now + enemy.Def.AttackCooldown
			services.MatchService.DamagePlayer(run, enemy.Damage)
			if run.State.Phase ~= "Playing" then
				return -- el golpe ha terminado la partida
			end
		end

		-- Detección de atasco: si apenas avanza, rodea el obstáculo un momento.
		if
			(position - enemy.LastProgressPosition).Magnitude > combat.StuckDistance
			or distance <= enemy.Def.AttackRange
		then
			enemy.LastProgressPosition = position
			enemy.LastProgressAt = now
		elseif now - enemy.LastProgressAt > combat.StuckWindow then
			enemy.SidestepUntil = now + combat.SidestepDuration
			enemy.SidestepSign = if run.Rng:NextNumber() < 0.5 then -1 else 1
			enemy.LastProgressAt = now
			enemy.LastProgressPosition = position
		end

		if distance > enemy.Def.AttackRange * 0.5 then
			local direction = steer(enemy, flat, now)
			local velocity = direction * enemy.Speed
			enemy.Mover.PlaneVelocity = Vector2.new(velocity.X, velocity.Z)
			enemy.Facing.CFrame = CFrame.lookAt(Vector3.zero, flat.Unit)
		else
			enemy.Mover.PlaneVelocity = Vector2.zero
		end
	end
end

function EnemyService.CleanupRun(run: Run)
	local data = byRun[run]
	if data == nil then
		return
	end
	byRun[run] = nil
	for _, enemy in data.List do
		enemy.Dead = true
		enemy.Model:Destroy()
	end
	table.clear(data.List)
end

return EnemyService
