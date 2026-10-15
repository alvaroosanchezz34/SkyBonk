--[[
	UpgradeService
	Abre las ofertas de mejoras (una por nivel pendiente, sin superponerse),
	valida las elecciones del cliente y aplica sus efectos.

	Protocolo:
	  1. Servidor -> UpgradeOffer { Token, Level, Options = { {Id, CurrentLevel, NextLevel} } }
	  2. Cliente  -> ChooseUpgrade(Token, Id)      (solo identificadores)
	  3. Servidor valida tipo, frecuencia, estado de la partida, token y opción.
	  4. Servidor aplica la mejora, cierra la oferta y responde UpgradeResolved.
	  5. Si quedan niveles pendientes se abre la siguiente oferta; si no, se
	     reanuda la partida.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local Net = require(Shared.Net)

local Logic = script.Parent.Parent.Logic
local RunState = require(Logic.RunState)
local RateLimiter = require(Logic.RateLimiter)
local Validation = require(Logic.Validation)
local ServerTypes = require(script.Parent.Parent.ServerTypes)

type Run = ServerTypes.Run

local UpgradeService = {}

local services: ServerTypes.Services
local chooseLimiter = RateLimiter.new(GameConfig.RateLimits.ChooseUpgrade.Max, GameConfig.RateLimits.ChooseUpgrade.Window)

function UpgradeService.Init(allServices: ServerTypes.Services)
	services = allServices
end

-- Abre la siguiente oferta si procede. Devuelve true si hay una oferta abierta.
function UpgradeService.TryOpenOffer(run: Run): boolean
	if not run.Active then
		return false
	end
	local offer = RunState.tryOpenOffer(run.State, run.Rng)
	if offer == nil then
		return run.State.ActiveOffer ~= nil
	end
	services.MatchService.SetPaused(run, true)
	Net.UpgradeOffer:FireClient(run.Player, RunState.offerPayload(run.State, offer))
	services.MatchService.MarkHudDirty(run)
	return true
end

-- Reenvía la oferta activa (si el cliente recargó su interfaz).
function UpgradeService.ResendOffer(run: Run)
	local offer = run.State.ActiveOffer
	if offer and not offer.Consumed then
		Net.UpgradeOffer:FireClient(run.Player, RunState.offerPayload(run.State, offer))
	end
end

function UpgradeService.ForgetPlayer(player: Player)
	chooseLimiter:Forget(player)
end

local function onChooseUpgrade(player: Player, token: any, upgradeId: any)
	if not chooseLimiter:Allow(player) then
		return
	end
	-- Tipos inválidos: petición manipulada, se ignora sin respuesta.
	if not Validation.isPositiveInteger(token) or not Validation.isIdentifier(upgradeId, 40) then
		warn(string.format("[UpgradeService] Elección malformada de %s rechazada", player.Name))
		return
	end
	local run = services.MatchService.GetRun(player)
	if run == nil or not run.Active then
		return
	end

	local ok, result = RunState.choose(run.State, token, upgradeId)
	if not ok then
		Net.UpgradeResolved:FireClient(player, { Token = token, Accepted = false, Reason = result })
		return
	end

	services.MatchService.ApplyStats(run, result.HealPct)
	Net.UpgradeResolved:FireClient(player, {
		Token = token,
		Accepted = true,
		UpgradeId = upgradeId,
		NewLevel = run.State.UpgradeLevels[upgradeId],
	})

	-- Encadena la siguiente oferta si se ganaron varios niveles a la vez.
	if not UpgradeService.TryOpenOffer(run) then
		services.MatchService.SetPaused(run, false)
	end
	services.MatchService.MarkHudDirty(run)
end

function UpgradeService.Start()
	Net.ChooseUpgrade.OnServerEvent:Connect(onChooseUpgrade)
end

return UpgradeService
