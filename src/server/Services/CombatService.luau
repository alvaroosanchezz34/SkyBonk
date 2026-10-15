--[[
	CombatService
	Programación centralizada de los ataques automáticos. Cada partida tiene una
	lista de armas con su próximo instante de ataque y una cola de impactos
	pendientes (todo en tiempo de partida, así que la pausa también los detiene).

	Flujo de un tajo de la Espada del Vendaval:
	  1. El arma elige objetivos y el servidor envía CombatFx (qué hojas salen,
	     hacia quién y cuánto tardan) para que el cliente anime el tajo y las hojas.
	  2. Cada impacto se aplica cuando la hoja llega (anticipación + distancia /
	     velocidad). El daño, los críticos y los saltos de rayo se calculan aquí.
	  3. Los impactos aplicados se agrupan en un único CombatHits por paso.
	El cliente nunca decide el daño: si su animación falla, el combate es el mismo.

	Para añadir un arma con otro patrón: crea su entrada en WeaponConfig con un
	`Pattern` nuevo y añade el manejador correspondiente en `Patterns`.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local Net = require(Shared.Net)
local Types = require(Shared.Types)

local Logic = script.Parent.Parent.Logic
local StatSheet = require(Logic.StatSheet)
local Targeting = require(Logic.Targeting)
local ServerTypes = require(script.Parent.Parent.ServerTypes)

type Run = ServerTypes.Run
type Enemy = ServerTypes.Enemy

-- Impacto programado: se aplica en `At` (tiempo de partida).
type Impact = {
	At: number,
	Enemy: Enemy,
	Damage: number,
	Crit: boolean,
	Chain: boolean,
	From: Vector3,
}

export type Hit = {
	Model: Model,
	Position: Vector3,
	Damage: number,
	Killed: boolean,
	Crit: boolean,
	Chain: boolean,
}

-- Hoja enviada al cliente (solo presentación).
export type ShotFx = {
	Model: Model,
	Position: Vector3,
	Delay: number, -- segundos desde el tajo hasta el impacto
	Chain: { { Model: Model, Position: Vector3, Delay: number } },
}

local CombatService = {}

local services: ServerTypes.Services
local impactsByRun: { [Run]: { Impact } } = {}

-- Los saltos de rayo hacen menos daño que la hoja principal.
local CHAIN_DAMAGE = 0.7
local CHAIN_HOP_DELAY = 0.07

function CombatService.Init(allServices: ServerTypes.Services)
	services = allServices
end

function CombatService.Start() end

-- Objetivo válido: vivo, dentro del mapa y sin daño en vuelo suficiente para matarlo.
local function isValidTarget(enemy: Enemy): boolean
	return not enemy.Dead
		and enemy.Model.Parent ~= nil
		and enemy.State ~= "Spawning"
		and enemy.Health - enemy.PendingDamage > 0
		and not services.EnemyService.IsOutOfBounds(enemy.Position)
end

local function schedule(run: Run, impact: Impact)
	impact.Enemy.PendingDamage += impact.Damage
	table.insert(impactsByRun[run], impact)
end

local function rollDamage(run: Run, stats: Types.WeaponStats, scale: number): (number, boolean)
	local crit = run.Rng:NextNumber() < stats.CritChance
	local damage = stats.Damage * scale * (if crit then GameConfig.Combat.CritMultiplier else 1)
	return damage, crit
end

-- Patrones de ataque: programan impactos y devuelven la descripción visual (vacía si no hubo objetivo).
CombatService.Patterns = {
	--[[
		Hojas espectrales: cada hoja busca un enemigo distinto (el más cercano
		disponible). Con Filo de Tormenta, al impactar salta con un rayo a
		enemigos próximos a su objetivo.
	]]
	NearestTargets = function(run: Run, weapon: Types.WeaponState, stats: Types.WeaponStats): { ShotFx }
		local def = weapon.Def
		local now = run.State.Elapsed
		local enemies = services.EnemyService.GetEnemies(run)
		local origin = run.Root.Position
		local targets = Targeting.nearest(enemies, origin, stats.Range, stats.Projectiles, isValidTarget)
		local struck: { [Enemy]: boolean } = {}
		for _, target in targets do
			struck[target] = true
		end
		local shots: { ShotFx } = {}
		for _, target in targets do
			local distance = (target.Position - origin).Magnitude
			local delay = def.WindupTime + distance / def.ProjectileSpeed
			local damage, crit = rollDamage(run, stats, 1)
			schedule(
				run,
				{ At = now + delay, Enemy = target, Damage = damage, Crit = crit, Chain = false, From = origin }
			)
			local shot: ShotFx = { Model = target.Model, Position = target.Position, Delay = delay, Chain = {} }

			local hops = stats.TargetsPerProjectile - 1
			local previous = target
			local hopDelay = delay
			for _ = 1, hops do
				local nextTarget = Targeting.nearest(enemies, previous.Position, def.ChainRange, 1, function(candidate)
					return not struck[candidate] and isValidTarget(candidate)
				end)[1]
				if nextTarget == nil then
					break
				end
				struck[nextTarget] = true
				hopDelay += CHAIN_HOP_DELAY
				local chainDamage, chainCrit = rollDamage(run, stats, CHAIN_DAMAGE)
				schedule(run, {
					At = now + hopDelay,
					Enemy = nextTarget,
					Damage = chainDamage,
					Crit = chainCrit,
					Chain = true,
					From = previous.Position,
				})
				table.insert(shot.Chain, { Model = nextTarget.Model, Position = nextTarget.Position, Delay = hopDelay })
				previous = nextTarget
			end
			table.insert(shots, shot)
		end
		return shots
	end,
} :: { [string]: (Run, Types.WeaponState, Types.WeaponStats) -> { ShotFx } }

function CombatService.SetupRun(run: Run)
	impactsByRun[run] = {}
	for _, weapon in run.State.Weapons do
		weapon.NextAttackAt = 0
	end
end

-- Aplica los impactos cuyo instante ha llegado. Devuelve false si la fase ha cambiado.
local function resolveImpacts(run: Run, now: number): boolean
	local impacts = impactsByRun[run]
	if impacts == nil or #impacts == 0 then
		return true
	end
	local hits: { Hit } = {}
	local index = 1
	local stillPlaying = true
	while index <= #impacts do
		local impact = impacts[index]
		if impact.At > now then
			index += 1
			continue
		end
		table.remove(impacts, index)
		local enemy = impact.Enemy
		enemy.PendingDamage = math.max(0, enemy.PendingDamage - impact.Damage)
		local position = enemy.Position
		local model = enemy.Model
		local killed, dealt = services.EnemyService.Damage(enemy, impact.Damage, impact.From)
		if dealt > 0 then
			table.insert(hits, {
				Model = model,
				Position = position,
				Damage = dealt,
				Killed = killed,
				Crit = impact.Crit,
				Chain = impact.Chain,
			})
		end
		if run.State.Phase ~= "Playing" then
			stillPlaying = false
			break -- una muerte ha abierto la selección de mejoras (o la partida terminó)
		end
	end
	if #hits > 0 then
		Net.CombatHits:FireClient(run.Player, { Hits = hits })
	end
	return stillPlaying
end

function CombatService.Step(run: Run)
	local state = run.State
	if state.Phase ~= "Playing" or run.Root.Parent == nil or run.Humanoid.Health <= 0 then
		return
	end
	local now = state.Elapsed
	if not resolveImpacts(run, now) then
		return
	end
	for _, weapon in state.Weapons do
		if now < weapon.NextAttackAt then
			continue
		end
		local pattern = CombatService.Patterns[weapon.Def.Pattern]
		if pattern == nil then
			warn("[CombatService] Patrón desconocido:", weapon.Def.Pattern)
			weapon.NextAttackAt = math.huge
			continue
		end
		local weaponStats = StatSheet.weaponStats(state.Stats, weapon.Def)
		local origin = run.Root.Position
		local shots = pattern(run, weapon, weaponStats)
		if #shots == 0 then
			-- Sin objetivos: se vuelve a buscar en breve, no en cada frame.
			weapon.NextAttackAt = now + GameConfig.Combat.RetargetDelay
		else
			weapon.NextAttackAt = now + weaponStats.Cooldown
			Net.CombatFx:FireClient(run.Player, {
				WeaponId = weapon.Id,
				Origin = origin,
				Windup = weapon.Def.WindupTime,
				Cooldown = weaponStats.Cooldown,
				Shots = shots,
			})
		end
	end
end

function CombatService.CleanupRun(run: Run)
	local impacts = impactsByRun[run]
	if impacts then
		for _, impact in impacts do
			impact.Enemy.PendingDamage = 0
		end
	end
	impactsByRun[run] = nil
end

return CombatService
