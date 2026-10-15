--!strict
--[[
	UpgradeLogic
	Elegibilidad, tirada aleatoria ponderada (sin repeticiones) y validación
	de elecciones de mejoras. Lógica pura: el generador aleatorio se inyecta.
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Types = require(Shared.Types)
local UpgradeConfig = require(Shared.Config.UpgradeConfig)
local StatSheet = require(script.Parent.StatSheet)

export type Rng = { NextNumber: (self: any) -> number }

export type Context = {
	Stats: Types.Stats,
	Weapons: { Types.WeaponState },
	UpgradeLevels: { [string]: number },
}

local UpgradeLogic = {}

-- Requisitos con nombre referenciados desde UpgradeConfig.Requires.
UpgradeLogic.Requirements = {
	WeaponAcceptsExtraProjectile = function(ctx: Context): boolean
		for _, weapon in ctx.Weapons do
			if StatSheet.projectilesFor(ctx.Stats, weapon.Def) < weapon.Def.MaxProjectiles then
				return true
			end
		end
		return false
	end,
	WeaponAcceptsExtraChain = function(ctx: Context): boolean
		for _, weapon in ctx.Weapons do
			if StatSheet.targetsFor(ctx.Stats, weapon.Def) < weapon.Def.MaxTargetsPerProjectile then
				return true
			end
		end
		return false
	end,
} :: { [string]: (Context) -> boolean }

local function levelOf(ctx: Context, id: string): number
	return ctx.UpgradeLevels[id] or 0
end

-- ¿Puede ofrecerse esta mejora ahora mismo? (los comodines se tratan aparte)
function UpgradeLogic.isEligible(def: Types.UpgradeDef, ctx: Context): boolean
	if def.Enabled == false or def.IsFallback then
		return false
	end
	if #def.Effects == 0 then
		return false -- nunca mostrar mejoras que no hacen nada
	end
	if def.MaxLevel ~= nil and levelOf(ctx, def.Id) >= def.MaxLevel then
		return false
	end
	if def.Requires ~= nil then
		local check = UpgradeLogic.Requirements[def.Requires]
		if check == nil then
			warn("[UpgradeLogic] Requisito desconocido:", def.Requires)
			return false
		end
		if not check(ctx) then
			return false
		end
	end
	return true
end

function UpgradeLogic.weightOf(def: Types.UpgradeDef, luck: number): number
	local rarity = UpgradeConfig.Rarities[def.Rarity]
	local weight = (rarity and rarity.Weight or 1) * (def.Weight or 1)
	if def.Rarity ~= "Common" then
		weight *= 1 + math.max(0, luck) * UpgradeConfig.LuckRarityBonus
	end
	return math.max(weight, 0)
end

-- Devuelve hasta `size` ids distintos. Si hay menos mejoras válidas que
-- `size`, completa con comodines (IsFallback) para no bloquear la partida.
-- `level` (opcional) activa la garantía de UpgradeConfig.EarlyGuarantee.
function UpgradeLogic.rollOptions(ctx: Context, rng: Rng, size: number?, level: number?): { string }
	local offerSize = size or UpgradeConfig.OfferSize
	local pool: { Types.UpgradeDef } = {}
	for _, def in UpgradeConfig.List do
		if UpgradeLogic.isEligible(def, ctx) then
			table.insert(pool, def)
		end
	end

	local result: { string } = {}
	while #result < offerSize and #pool > 0 do
		local total = 0
		for _, def in pool do
			total += UpgradeLogic.weightOf(def, ctx.Stats.Luck)
		end
		local pickIndex = #pool
		if total > 0 then
			local roll = rng:NextNumber() * total
			for index, def in pool do
				roll -= UpgradeLogic.weightOf(def, ctx.Stats.Luck)
				if roll < 0 then
					pickIndex = index
					break
				end
			end
		end
		table.insert(result, pool[pickIndex].Id)
		table.remove(pool, pickIndex)
	end

	-- Garantía de los primeros niveles: al menos una opción de la categoría indicada.
	local guarantee = UpgradeConfig.EarlyGuarantee
	if guarantee and level and level <= guarantee.UntilLevel and #result > 0 then
		local hasCategory = false
		for _, id in result do
			if UpgradeConfig.ById[id].Category == guarantee.Category then
				hasCategory = true
			end
		end
		if not hasCategory then
			local candidates: { Types.UpgradeDef } = {}
			for _, def in pool do
				if def.Category == guarantee.Category then
					table.insert(candidates, def)
				end
			end
			if #candidates > 0 then
				local pick = candidates[math.clamp(math.floor(rng:NextNumber() * #candidates) + 1, 1, #candidates)]
				result[#result] = pick.Id
			end
		end
	end

	if #result < offerSize then
		for _, def in UpgradeConfig.List do
			if #result >= offerSize then
				break
			end
			if def.IsFallback and def.Enabled ~= false and not table.find(result, def.Id) then
				table.insert(result, def.Id)
			end
		end
	end

	return result
end

-- Comprueba que (token, id) corresponde a la oferta activa y no consumida.
function UpgradeLogic.validateChoice(offer: Types.Offer?, token: any, upgradeId: any): (boolean, string?)
	if offer == nil then
		return false, "NoActiveOffer"
	end
	if type(token) ~= "number" or token ~= offer.Token then
		return false, "StaleToken"
	end
	if offer.Consumed then
		return false, "AlreadyConsumed"
	end
	if type(upgradeId) ~= "string" or table.find(offer.Options, upgradeId) == nil then
		return false, "NotOffered"
	end
	if UpgradeConfig.ById[upgradeId] == nil then
		return false, "UnknownUpgrade"
	end
	return true, nil
end

return UpgradeLogic
