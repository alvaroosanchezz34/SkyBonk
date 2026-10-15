--[[
	EnemyService
	Ciclo de vida de los enemigos y su IA centralizada:

	  Spawning ─► Chase ─► Windup ─► Recover ─► Chase ...
	                 ▲        │ (impacto sin aplomo)
	                 └─ Stagger ◄┘
	  (cualquier estado) ─► muerte: el modelo queda DeathDuration sin colisión
	                        para la animación del cliente y después se destruye.

	• Un único tick de IA (GameConfig.Combat.EnemyAiInterval) recorre todos los
	  enemigos de cada partida; no hay scripts ni bucles por enemigo.
	• El movimiento es físico (LinearVelocity en el plano XZ + gravedad).
	• El daño al jugador se aplica AL TERMINAR la anticipación (AttackWindup) y
	  solo si sigue al alcance: los ataques se ven venir y se pueden esquivar.
	• El cliente anima a partir de los atributos del modelo (State, StateAt,
	  StateDuration, HopSeed); nada de lo que haga el cliente decide el daño.
	• La navegación usa World/MapLayout: no camina hacia el vacío y sube a las
	  mesetas o cruza el puente por sus accesos.
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
local MapLayout = require(script.Parent.Parent.World.MapLayout)
local ServerTypes = require(script.Parent.Parent.ServerTypes)

type Run = ServerTypes.Run
type Enemy = ServerTypes.Enemy

type RunEnemies = {
	List: { Enemy },
	Dying: { { Model: Model, RemoveAt: number } },
	Frozen: boolean,
	NextAiAt: number,
	CountByType: { [string]: number },
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
local BOUNDS_RADIUS = GameConfig.Map.BoundsRadius
local KILL_Y = GameConfig.Map.KillY
local COMBAT = GameConfig.Combat
local TAU = math.pi * 2
-- Giros que se prueban, en orden, cuando la dirección deseada lleva al vacío.
local AVOID_ANGLES = { math.rad(35), -math.rad(35), math.rad(70), -math.rad(70), math.rad(110), -math.rad(110) }

-- Tiempo común servidor/cliente para sincronizar los saltos de los slimes.
local function serverTime(): number
	local getter = (workspace :: any).GetServerTimeNow
	if getter then
		return getter(workspace)
	end
	return os.clock()
end

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
			local builder = ModelFactory.Builders[def.Rig]
			assert(builder, "No hay constructor para el rig " .. def.Rig)
			local model = builder(def)
			model.Name = def.ModelName
			model.Parent = folder
		end
	end
end

function EnemyService.SetupRun(run: Run)
	byRun[run] = { List = {}, Dying = {}, Frozen = false, NextAiAt = 0, CountByType = {} }
end

function EnemyService.GetEnemies(run: Run): { Enemy }
	local data = byRun[run]
	return if data then data.List else EMPTY
end

function EnemyService.Count(run: Run): number
	local data = byRun[run]
	return if data then #data.List else 0
end

function EnemyService.CountOfType(run: Run, enemyId: string): number
	local data = byRun[run]
	return if data then data.CountByType[enemyId] or 0 else 0
end

local function removeFromList(data: RunEnemies, enemy: Enemy)
	local list = data.List
	local index = table.find(list, enemy)
	if index then
		-- Intercambio con el último: O(1) y sin huecos.
		list[index] = list[#list]
		list[#list] = nil
		data.CountByType[enemy.Def.Id] = math.max(0, (data.CountByType[enemy.Def.Id] or 1) - 1)
	end
end

local function despawn(enemy: Enemy)
	enemy.Dead = true
	local data = byRun[enemy.Run]
	if data then
		removeFromList(data, enemy)
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

-- Cambia de estado y lo publica en el modelo (el cliente anima a partir de esto).
local function setState(enemy: Enemy, state: string, duration: number)
	local now = enemy.Run.State.Elapsed
	enemy.State = state
	enemy.StateUntil = now + duration
	local model = enemy.Model
	-- State va al final: el cliente reacciona a su cambio y lee los otros dos.
	model:SetAttribute("StateAt", serverTime())
	model:SetAttribute("StateDuration", duration)
	model:SetAttribute("State", state)
end

local function setVelocity(enemy: Enemy, velocity: Vector3)
	enemy.Mover.PlaneVelocity = Vector2.new(velocity.X, velocity.Z)
end

local function face(enemy: Enemy, direction: Vector3)
	if direction.Magnitude > 1e-3 then
		enemy.Facing.CFrame = CFrame.lookAt(Vector3.zero, Vector3.new(direction.X, 0, direction.Z).Unit)
	end
end

--[[
	Crea un enemigo apoyado sobre `groundPosition` (punto del suelo). Emerge
	durante SpawnDuration (anclado, sin atacar) y después persigue al jugador.
]]
function EnemyService.Spawn(run: Run, enemyId: string, groundPosition: Vector3, multipliers: Multipliers): Enemy?
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
	local mover = root and root:FindFirstChild("Mover") :: LinearVelocity
	local facing = root and root:FindFirstChild("Facing") :: AlignOrientation
	if not (root and mover and facing) then
		warn("[EnemyService] Plantilla incompleta", def.ModelName)
		model:Destroy()
		return nil
	end

	nextEnemyId += 1
	local now = run.State.Elapsed
	local maxHealth = def.MaxHealth * multipliers.Health
	local position = groundPosition + Vector3.new(0, root.Size.Y / 2 + 0.05, 0)
	local towardPlayer = run.Root.Position - position
	local yaw = math.atan2(-towardPlayer.X, -towardPlayer.Z)
	model:PivotTo(CFrame.new(position) * CFrame.Angles(0, yaw, 0))
	model:SetAttribute("EnemyId", def.Id)
	model:SetAttribute("Health", maxHealth)
	model:SetAttribute("MaxHealth", maxHealth)
	model:SetAttribute("HopSeed", run.Rng:NextNumber())
	root.CollisionGroup = "Enemies"
	root.Anchored = true -- emerge anclado; se libera al terminar la aparición
	model.Parent = activeFolder

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
		PendingDamage = 0,
		Damage = def.ContactDamage * multipliers.Damage,
		Speed = def.MoveSpeed * multipliers.Speed,
		Dead = false,
		Position = position,
		State = "Spawning",
		StateUntil = now,
		NextAttackAt = now + COMBAT.SpawnDuration + 0.25,
		AttackDir = Vector3.new(0, 0, -1),
		PendingHitAt = nil,
		KnockDir = Vector3.zero,
		HopSeed = model:GetAttribute("HopSeed") :: number,
		LinkExit = nil,
		LastProgressPosition = position,
		LastProgressAt = now,
		SidestepUntil = 0,
		SidestepSign = 1,
	}
	setState(enemy, "Spawning", COMBAT.SpawnDuration)
	face(enemy, towardPlayer)
	table.insert(data.List, enemy)
	data.CountByType[def.Id] = (data.CountByType[def.Id] or 0) + 1
	return enemy
end

local function kill(enemy: Enemy)
	-- `Dead` se marca antes que nada: una muerte solo genera una recompensa.
	enemy.Dead = true
	local run = enemy.Run
	local root = enemy.Root
	local position = root.Position
	local data = byRun[run]
	setVelocity(enemy, Vector3.zero)
	root.Anchored = true
	root.CanCollide = false
	enemy.Model:SetAttribute("Dead", true)
	setState(enemy, "Dead", COMBAT.DeathDuration)
	if data then
		removeFromList(data, enemy)
		-- El modelo se queda para la animación de muerte y se retira después.
		table.insert(data.Dying, { Model = enemy.Model, RemoveAt = run.State.Elapsed + COMBAT.DeathDuration })
	else
		enemy.Model:Destroy()
	end

	RunState.addKill(run.State)
	Net.EnemyDied:FireClient(run.Player, {
		Position = position,
		Color = enemy.Def.Color,
		Model = enemy.Model,
		EnemyId = enemy.Def.Id,
	})
	services.ExperienceService.SpawnGem(run, position, enemy.Def.XpReward)
	services.MatchService.MarkHudDirty(run)
end

--[[
	Aplica daño calculado por el servidor. `fromPosition` (opcional) orienta
	el retroceso. Devuelve (murió, daño aplicado).
]]
function EnemyService.Damage(enemy: Enemy, amount: number, fromPosition: Vector3?): (boolean, number)
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
	-- Reacción al impacto: retroceso breve. Los enemigos con aplomo no se interrumpen.
	local interruptible = enemy.State == "Chase"
		or enemy.State == "Recover"
		or (enemy.State == "Windup" and not enemy.Def.Poise)
	if interruptible and enemy.Def.Knockback > 0 then
		local away = enemy.Position - (fromPosition or enemy.Run.Root.Position)
		local flat = Vector3.new(away.X, 0, away.Z)
		enemy.KnockDir = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.zero
		if enemy.State == "Windup" then
			-- Ataque cancelado: no vuelve a cargarlo al instante.
			enemy.NextAttackAt = math.max(enemy.NextAttackAt, enemy.Run.State.Elapsed + 0.45)
		end
		enemy.PendingHitAt = nil -- un salto interrumpido no golpea
		setState(enemy, "Stagger", COMBAT.StaggerTime)
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
		setVelocity(enemy, Vector3.zero)
		-- Los que están emergiendo siguen anclados hasta terminar su aparición.
		enemy.Root.Anchored = frozen or enemy.State == "Spawning"
		if not enemy.Root.Anchored then
			pcall(enemy.Root.SetNetworkOwner, enemy.Root, nil)
		end
	end
end

-- ¿La dirección lleva al vacío? Si es así, prueba a girarla a lo largo del borde.
local function avoidVoid(position: Vector3, direction: Vector3): Vector3
	if direction.Magnitude < 1e-3 then
		return direction
	end
	local lookAhead = 4
	if MapLayout.isWalkable(position + direction * lookAhead, 1) then
		return direction
	end
	for _, angle in AVOID_ANGLES do
		local rotated = (CFrame.Angles(0, angle, 0) * direction)
		if MapLayout.isWalkable(position + rotated * lookAhead, 1) then
			return rotated
		end
	end
	return Vector3.zero
end

local function flatDistance(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

-- Punto hacia el que caminar: el jugador, o el acceso a su zona si está en otra.
local function navigationTarget(enemy: Enemy, playerPosition: Vector3, playerArea: string): Vector3
	local position = enemy.Position
	local exit = enemy.LinkExit
	if exit then
		if flatDistance(position, exit) < 3 or MapLayout.areaAt(position) == playerArea then
			enemy.LinkExit = nil
		else
			return exit
		end
	end
	local entry, linkExit = MapLayout.route(MapLayout.areaAt(position), playerArea)
	if entry and linkExit then
		-- Ya está sobre el acceso (p. ej. apareció en el puente): sigue hacia la salida.
		if flatDistance(position, entry) < 3 or MapLayout.onLink(position, entry, linkExit, MapLayout.linkWidth(entry)) then
			enemy.LinkExit = linkExit
			return linkExit
		end
		return entry
	end
	return playerPosition
end

-- Factor de velocidad del salto de los slimes (0,35 en el suelo, hasta 1,55 en el aire).
local function hopFactor(enemy: Enemy, now: number): number
	local frequency = enemy.Def.HopFrequency
	if frequency == nil then
		return 1
	end
	local wave = math.sin(TAU * (now * frequency + enemy.HopSeed))
	return 0.35 + 1.2 * math.max(0, wave)
end

local function resolveAttack(enemy: Enemy, playerAlive: boolean, playerPosition: Vector3)
	local run = enemy.Run
	if not playerAlive then
		return
	end
	local offset = playerPosition - enemy.Root.Position
	local flat = Vector3.new(offset.X, 0, offset.Z).Magnitude
	local reach = enemy.Def.HitRange + COMBAT.HitTolerance
	if flat <= reach and math.abs(offset.Y) < COMBAT.MeleeVerticalReach * enemy.Def.Scale then
		services.MatchService.DamagePlayer(run, enemy.Damage)
	end
end

local function stepEnemy(
	enemy: Enemy,
	now: number,
	sNow: number,
	playerAlive: boolean,
	playerPosition: Vector3,
	playerArea: string
)
	local def = enemy.Def
	local position = enemy.Position
	local state = enemy.State

	if state == "Spawning" then
		if now >= enemy.StateUntil then
			enemy.Root.Anchored = false
			pcall(enemy.Root.SetNetworkOwner, enemy.Root, nil)
			setState(enemy, "Chase", 0)
		end
		return
	end
	if not playerAlive then
		setVelocity(enemy, Vector3.zero)
		return
	end

	local offset = playerPosition - position
	local flat = Vector3.new(offset.X, 0, offset.Z)
	local distance = flat.Magnitude

	if state == "Windup" then
		setVelocity(enemy, Vector3.zero)
		if def.AttackKind ~= "Slam" and now < enemy.StateUntil - def.AttackWindup * 0.35 then
			-- Sigue al jugador con la mirada hasta poco antes del golpe.
			enemy.AttackDir = if distance > 1e-3 then flat.Unit else enemy.AttackDir
			face(enemy, enemy.AttackDir)
		end
		if now >= enemy.StateUntil then
			enemy.NextAttackAt = now + def.AttackCooldown
			if def.AttackKind == "Lunge" then
				-- El slime salta primero; el golpe se comprueba al final del salto.
				enemy.PendingHitAt = now + COMBAT.RecoverTime * 0.45
			else
				resolveAttack(enemy, playerAlive, playerPosition)
			end
			setState(enemy, "Recover", COMBAT.RecoverTime)
		end
		return
	end

	if state == "Stagger" then
		local remaining = math.max(0, enemy.StateUntil - now) / COMBAT.StaggerTime
		setVelocity(enemy, avoidVoid(position, enemy.KnockDir) * def.Knockback * remaining)
		if now >= enemy.StateUntil then
			setState(enemy, "Chase", 0)
		end
		return
	end

	-- Ataque: se inicia la anticipación si el jugador está al alcance.
	if
		state == "Chase"
		and distance <= def.AttackRange
		and math.abs(offset.Y) < COMBAT.MeleeVerticalReach * def.Scale
		and now >= enemy.NextAttackAt
	then
		enemy.AttackDir = if distance > 1e-3 then flat.Unit else enemy.AttackDir
		face(enemy, enemy.AttackDir)
		setVelocity(enemy, Vector3.zero)
		setState(enemy, "Windup", def.AttackWindup)
		return
	end

	local speed = enemy.Speed
	if state == "Recover" then
		local pendingHit = enemy.PendingHitAt
		if pendingHit and now >= pendingHit then
			enemy.PendingHitAt = nil
			resolveAttack(enemy, playerAlive, playerPosition)
		end
		if now >= enemy.StateUntil then
			setState(enemy, "Chase", 0)
		elseif enemy.PendingHitAt then
			-- Salto de ataque del slime: impulso corto en la dirección fijada.
			setVelocity(enemy, avoidVoid(position, enemy.AttackDir) * enemy.Speed * 1.6)
			return
		else
			speed *= COMBAT.RecoverSpeedMultiplier
		end
	end

	-- Persecución con detección de atasco (rodea el obstáculo un momento).
	if (position - enemy.LastProgressPosition).Magnitude > COMBAT.StuckDistance or distance <= def.AttackRange then
		enemy.LastProgressPosition = position
		enemy.LastProgressAt = now
	elseif now - enemy.LastProgressAt > COMBAT.StuckWindow then
		enemy.SidestepUntil = now + COMBAT.SidestepDuration
		enemy.SidestepSign = if enemy.Run.Rng:NextNumber() < 0.5 then -1 else 1
		enemy.LastProgressAt = now
		enemy.LastProgressPosition = position
	end

	if distance <= def.AttackRange * 0.4 then
		setVelocity(enemy, Vector3.zero)
		face(enemy, flat)
		return
	end
	local target = navigationTarget(enemy, playerPosition, playerArea)
	local toTarget = Vector3.new(target.X - position.X, 0, target.Z - position.Z)
	local direction = if toTarget.Magnitude > 1e-3 then toTarget.Unit else Vector3.zero
	if now < enemy.SidestepUntil and direction.Magnitude > 0 then
		local perpendicular = Vector3.new(-direction.Z, 0, direction.X) * enemy.SidestepSign
		direction = (direction * 0.35 + perpendicular).Unit
	end
	direction = avoidVoid(position, direction)
	setVelocity(enemy, direction * speed * hopFactor(enemy, sNow))
	face(enemy, if direction.Magnitude > 0 then direction else flat)
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
	data.NextAiAt = now + COMBAT.EnemyAiInterval

	-- Retira los cadáveres cuya animación de muerte ha terminado.
	local dying = data.Dying
	for index = #dying, 1, -1 do
		if now >= dying[index].RemoveAt then
			dying[index].Model:Destroy()
			table.remove(dying, index)
		end
	end

	local playerAlive = run.Root.Parent ~= nil and run.Humanoid.Health > 0
	local playerPosition = run.Root.Position
	local playerArea = MapLayout.areaAt(playerPosition)
	local sNow = serverTime()
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
		enemy.Position = enemy.Root.Position
		if isOutOfBounds(enemy.Position) then
			-- Se cayó o salió del mapa: se elimina sin recompensa.
			despawn(enemy)
			continue
		end
		stepEnemy(enemy, now, sNow, playerAlive, playerPosition, playerArea)
		if run.State.Phase ~= "Playing" then
			return -- un golpe ha terminado la partida
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
	for _, corpse in data.Dying do
		corpse.Model:Destroy()
	end
	table.clear(data.List)
	table.clear(data.Dying)
end

return EnemyService
