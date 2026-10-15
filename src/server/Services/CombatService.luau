--[[
	CombatService
	Programación centralizada de los ataques automáticos. Cada partida tiene una
	lista de armas con su próximo instante de ataque (en tiempo de partida, así
	que la pausa también detiene el combate). El daño se calcula y aplica aquí;
	el cliente solo recibe la descripción visual del ataque (CombatFx).

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

export type Hit = {
	Model: Model,
	Position: Vector3,
	Damage: number,
	Killed: boolean,
}

local CombatService = {}

local services: ServerTypes.Services

function CombatService.Init(allServices: ServerTypes.Services)
	services = allServices
end

function CombatService.Start() end

local function isValidTarget(enemy: Enemy): boolean
	return not enemy.Dead and enemy.Model.Parent ~= nil and not services.EnemyService.IsOutOfBounds(enemy.Position)
end

local function strike(enemy: Enemy, damage: number, hits: { Hit })
	local position = enemy.Position
	local model = enemy.Model
	local killed, dealt = services.EnemyService.Damage(enemy, damage)
	if dealt > 0 then
		table.insert(hits, { Model = model, Position = position, Damage = dealt, Killed = killed })
	end
end

-- Patrones de ataque: devuelven la lista de impactos (vacía si no hubo objetivo).
CombatService.Patterns = {
	-- Hojas espectrales: cada proyectil busca un enemigo distinto (el más cercano
	-- disponible). Con TargetsPerProjectile > 1 la hoja encadena a enemigos
	-- próximos a su objetivo.
	NearestTargets = function(run: Run, _weapon: Types.WeaponState, stats: Types.WeaponStats): { Hit }
		local hits: { Hit } = {}
		local enemies = services.EnemyService.GetEnemies(run)
		local origin = run.Root.Position
		local targets = Targeting.nearest(enemies, origin, stats.Range, stats.Projectiles, isValidTarget)
		local struck: { [Enemy]: boolean } = {}
		for _, target in targets do
			struck[target] = true
		end
		for _, target in targets do
			strike(target, stats.Damage, hits)
			local extra = stats.TargetsPerProjectile - 1
			if extra > 0 then
				local chained = Targeting.nearest(enemies, target.Position, stats.Range * 0.35, extra, function(candidate)
					return not struck[candidate] and isValidTarget(candidate)
				end)
				for _, other in chained do
					struck[other] = true
					strike(other, stats.Damage, hits)
				end
			end
		end
		return hits
	end,
} :: { [string]: (Run, Types.WeaponState, Types.WeaponStats) -> { Hit } }

function CombatService.SetupRun(run: Run)
	for _, weapon in run.State.Weapons do
		weapon.NextAttackAt = 0
	end
end

function CombatService.Step(run: Run)
	local state = run.State
	if state.Phase ~= "Playing" or run.Root.Parent == nil or run.Humanoid.Health <= 0 then
		return
	end
	local now = state.Elapsed
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
		local hits = pattern(run, weapon, weaponStats)
		if #hits == 0 then
			-- Sin objetivos: se vuelve a buscar en breve, no en cada frame.
			weapon.NextAttackAt = now + GameConfig.Combat.RetargetDelay
		else
			weapon.NextAttackAt = now + weaponStats.Cooldown
			Net.CombatFx:FireClient(run.Player, {
				WeaponId = weapon.Id,
				Origin = origin,
				Hits = hits,
			})
		end
		if state.Phase ~= "Playing" then
			return -- una muerte ha abierto la selección de mejoras
		end
	end
end

function CombatService.CleanupRun(_run: Run)
	-- El estado de las armas vive en RunState y se descarta con la partida.
end

return CombatService
