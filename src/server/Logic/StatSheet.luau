--!strict
--[[
	StatSheet
	Estadísticas del jugador durante una partida y cálculo de los valores
	derivados (daño de arma, vida máxima, velocidad...). Lógica pura y
	determinista: no toca instancias de Roblox.
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Types = require(Shared.Types)
local GameConfig = require(Shared.Config.GameConfig)

type Stats = Types.Stats

local StatSheet = {}

function StatSheet.new(): Stats
	return {
		DamagePct = 0,
		CooldownMult = 1,
		RangePct = 0,
		MaxHealthPct = 0,
		MoveSpeedPct = 0,
		XpGainPct = 0,
		DamageTakenMult = 1,
		Luck = 0,
		ExtraProjectiles = 0,
	}
end

--[[
	Aplica los efectos de una mejora. Devuelve el porcentaje de curación
	instantánea solicitado (efectos "HealPct"), que aplica quien llama porque
	depende del Humanoid.
]]
function StatSheet.applyEffects(stats: Stats, effects: { Types.UpgradeEffect }): number
	local healPct = 0
	for _, effect in effects do
		if effect.Op == "HealPct" then
			healPct += effect.Value
		else
			local statName = effect.Stat
			assert(statName ~= nil, "Efecto sin estadística")
			local current = (stats :: any)[statName]
			assert(type(current) == "number", "Estadística desconocida: " .. tostring(statName))
			if effect.Op == "Add" then
				(stats :: any)[statName] = current + effect.Value
			elseif effect.Op == "Mul" then
				(stats :: any)[statName] = current * effect.Value
			else
				error("Operación de efecto desconocida: " .. tostring(effect.Op))
			end
		end
	end
	return healPct
end

function StatSheet.projectilesFor(stats: Stats, def: Types.WeaponDef): number
	return math.clamp(def.Projectiles + stats.ExtraProjectiles, 1, def.MaxProjectiles)
end

function StatSheet.weaponStats(stats: Stats, def: Types.WeaponDef): Types.WeaponStats
	return {
		Damage = def.Damage * (1 + stats.DamagePct),
		Cooldown = math.max(def.MinCooldown, def.Cooldown * stats.CooldownMult),
		Range = def.Range * (1 + stats.RangePct),
		Projectiles = StatSheet.projectilesFor(stats, def),
		TargetsPerProjectile = def.TargetsPerProjectile,
	}
end

function StatSheet.maxHealth(stats: Stats): number
	return math.floor(GameConfig.Player.BaseMaxHealth * (1 + stats.MaxHealthPct) + 0.5)
end

function StatSheet.walkSpeed(stats: Stats): number
	return GameConfig.Player.BaseWalkSpeed * (1 + stats.MoveSpeedPct)
end

function StatSheet.xpGain(stats: Stats, baseAmount: number): number
	return baseAmount * (1 + stats.XpGainPct)
end

function StatSheet.damageTaken(stats: Stats, rawDamage: number): number
	return math.max(0, rawDamage * stats.DamageTakenMult)
end

function StatSheet.luckyGemChance(stats: Stats): number
	local cfg = GameConfig.Experience
	return math.clamp(cfg.LuckyGemBaseChance + cfg.LuckyGemChancePerLuck * stats.Luck, 0, 1)
end

function StatSheet.summary(stats: Stats, primaryWeapon: Types.WeaponDef?): Types.StatSummary
	local weapon = primaryWeapon and StatSheet.weaponStats(stats, primaryWeapon)
	return {
		Damage = weapon and weapon.Damage or 0,
		Cooldown = weapon and weapon.Cooldown or 0,
		Range = weapon and weapon.Range or 0,
		Projectiles = weapon and weapon.Projectiles or 0,
		MoveSpeed = StatSheet.walkSpeed(stats),
		DamageReductionPct = (1 - stats.DamageTakenMult) * 100,
		XpBonusPct = stats.XpGainPct * 100,
		Luck = stats.Luck,
	}
end

return StatSheet
