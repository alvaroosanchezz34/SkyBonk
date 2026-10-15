--!strict
--[[
	RunState
	Estado autoritativo de una partida y su máquina de estados:

	  Playing ──(nivel pendiente)──► ChoosingUpgrade ──(elección válida)──► Playing
	     │                                   │
	     └──────────────(muerte)─────────────┴──────────────────────────► GameOver

	Es lógica pura (sin instancias), por lo que se prueba fuera de Roblox.
	Los servicios del servidor la envuelven con personajes, enemigos y remotes.
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Types = require(Shared.Types)
local WeaponConfig = require(Shared.Config.WeaponConfig)
local UpgradeConfig = require(Shared.Config.UpgradeConfig)
local StatSheet = require(script.Parent.StatSheet)
local LevelLogic = require(script.Parent.LevelLogic)
local UpgradeLogic = require(script.Parent.UpgradeLogic)

export type RunState = {
	Phase: Types.GamePhase,
	Elapsed: number, -- reloj de partida: solo avanza en Playing
	Kills: number,
	Progress: Types.Progress,
	Stats: Types.Stats,
	UpgradeLevels: { [string]: number },
	Weapons: { Types.WeaponState },
	ActiveOffer: Types.Offer?,
	NextOfferToken: number,
}

export type ChoiceResult = {
	Def: Types.UpgradeDef,
	HealPct: number,
}

local RunState = {}

function RunState.new(weaponIds: { string }): RunState
	local weapons: { Types.WeaponState } = {}
	for _, id in weaponIds do
		local def = WeaponConfig[id]
		assert(def ~= nil, "Arma desconocida: " .. id)
		table.insert(weapons, { Id = id, Def = def, NextAttackAt = 0 })
	end
	return {
		Phase = "Playing",
		Elapsed = 0,
		Kills = 0,
		Progress = LevelLogic.new(),
		Stats = StatSheet.new(),
		UpgradeLevels = {},
		Weapons = weapons,
		ActiveOffer = nil,
		NextOfferToken = 0,
	}
end

function RunState.isPlaying(state: RunState): boolean
	return state.Phase == "Playing"
end

function RunState.advance(state: RunState, dt: number)
	if state.Phase == "Playing" and dt > 0 then
		state.Elapsed += dt
	end
end

function RunState.addKill(state: RunState)
	if state.Phase ~= "GameOver" then
		state.Kills += 1
	end
end

-- Concede experiencia base (aplica el bonus de XP). Devuelve niveles ganados.
function RunState.grantXp(state: RunState, baseAmount: number): number
	if state.Phase == "GameOver" then
		return 0
	end
	return LevelLogic.addXp(state.Progress, StatSheet.xpGain(state.Stats, baseAmount))
end

local function contextOf(state: RunState): UpgradeLogic.Context
	return {
		Stats = state.Stats,
		Weapons = state.Weapons,
		UpgradeLevels = state.UpgradeLevels,
	}
end

--[[
	Abre una oferta si la partida está en Playing y hay niveles pendientes.
	Devuelve la oferta nueva o nil (no se superponen ofertas).
]]
function RunState.tryOpenOffer(state: RunState, rng: UpgradeLogic.Rng): Types.Offer?
	if state.Phase ~= "Playing" or state.ActiveOffer ~= nil then
		return nil
	end
	local level = LevelLogic.popPendingLevel(state.Progress)
	if level == nil then
		return nil
	end
	local options = UpgradeLogic.rollOptions(contextOf(state), rng, nil, level)
	if #options == 0 then
		-- Sin opciones ni comodines: el nivel se considera resuelto.
		return nil
	end
	state.NextOfferToken += 1
	local offer: Types.Offer = {
		Token = state.NextOfferToken,
		Level = level,
		Options = options,
		Consumed = false,
	}
	state.ActiveOffer = offer
	state.Phase = "ChoosingUpgrade"
	return offer
end

--[[
	Valida y aplica una elección. Solo se acepta si la partida está esperando
	una elección y (token, id) corresponde a la oferta activa no consumida.
]]
function RunState.choose(state: RunState, token: any, upgradeId: any): (boolean, string? | ChoiceResult)
	if state.Phase ~= "ChoosingUpgrade" then
		return false, "NotChoosing"
	end
	local ok, reason = UpgradeLogic.validateChoice(state.ActiveOffer, token, upgradeId)
	if not ok then
		return false, reason
	end

	local offer = state.ActiveOffer :: Types.Offer
	local def = UpgradeConfig.ById[upgradeId :: string]
	offer.Consumed = true
	state.ActiveOffer = nil
	state.Phase = "Playing"

	local healPct = StatSheet.applyEffects(state.Stats, def.Effects)
	state.UpgradeLevels[def.Id] = (state.UpgradeLevels[def.Id] or 0) + 1

	local result: ChoiceResult = { Def = def, HealPct = healPct }
	return true, result
end

function RunState.setGameOver(state: RunState): boolean
	if state.Phase == "GameOver" then
		return false
	end
	state.Phase = "GameOver"
	if state.ActiveOffer then
		state.ActiveOffer.Consumed = true
		state.ActiveOffer = nil
	end
	return true
end

function RunState.offerPayload(state: RunState, offer: Types.Offer): Types.OfferPayload
	local options: { Types.OfferOptionPayload } = {}
	for _, id in offer.Options do
		local current = state.UpgradeLevels[id] or 0
		table.insert(options, { Id = id, CurrentLevel = current, NextLevel = current + 1 })
	end
	return { Token = offer.Token, Level = offer.Level, Options = options }
end

return RunState
