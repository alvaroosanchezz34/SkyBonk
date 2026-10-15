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
-- Instante (tiempo de partida) de cada subida de nivel: lo usa el informe de depuración.
local levelTimes: { [Run]: { string } } = setmetatable({}, { __mode = "k" }) :: any

function LevelService.GetLevelTimes(run: Run): { string }
	return levelTimes[run] or {}
end

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
		local times = levelTimes[run] or {}
		levelTimes[run] = times
		table.insert(times, string.format("Nv%d@%.0fs", run.State.Progress.Level, run.State.Elapsed))
		Net.LevelUp:FireClient(run.Player, {
			Level = run.State.Progress.Level,
			Gained = gained,
		})
		services.UpgradeService.TryOpenOffer(run)
	end
end

return LevelService
