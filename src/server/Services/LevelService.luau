--[[
	LevelService
	Punto único para conceder experiencia. Aplica el bonus de XP, procesa
	subidas de nivel múltiples y pide a UpgradeService que abra la oferta.
	El cliente nunca indica cuánta experiencia ha obtenido.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage.Shared.Net)
local RunState = require(script.Parent.Parent.Logic.RunState)
local ServerTypes = require(script.Parent.Parent.ServerTypes)

type Run = ServerTypes.Run

local LevelService = {}

local services: ServerTypes.Services

function LevelService.Init(allServices: ServerTypes.Services)
	services = allServices
end

function LevelService.Start() end

-- `baseAmount` lo calcula siempre el servidor (valor de las gemas recogidas).
function LevelService.GrantExperience(run: Run, baseAmount: number)
	if not run.Active then
		return
	end
	local gained = RunState.grantXp(run.State, baseAmount)
	services.MatchService.MarkHudDirty(run)
	if gained > 0 then
		Net.LevelUp:FireClient(run.Player, {
			Level = run.State.Progress.Level,
			Gained = gained,
		})
		services.UpgradeService.TryOpenOffer(run)
	end
end

return LevelService
