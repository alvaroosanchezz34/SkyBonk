--!strict
--[[
	LevelLogic
	Experiencia y niveles. Cada nivel alcanzado se encola una sola vez en
	PendingLevels; la experiencia sobrante se conserva.
]]

local Shared = game:GetService("ReplicatedStorage").Shared
local Types = require(Shared.Types)
local Progression = require(Shared.Progression)
local GameConfig = require(Shared.Config.GameConfig)

type Progress = Types.Progress

local LevelLogic = {}

function LevelLogic.new(): Progress
	return {
		Level = 1,
		Xp = 0,
		TotalXp = 0,
		PendingLevels = {},
	}
end

-- Añade experiencia (ya multiplicada) y devuelve cuántos niveles se han ganado.
function LevelLogic.addXp(progress: Progress, amount: number): number
	-- Rechaza NaN, infinitos, negativos y cantidades absurdas.
	if type(amount) ~= "number" or amount ~= amount or amount <= 0 then
		return 0
	end
	amount = math.min(amount, GameConfig.Experience.MaxXpPerGrant)

	progress.Xp += amount
	progress.TotalXp += amount

	local gained = 0
	local required = Progression.xpToNext(progress.Level)
	while progress.Xp >= required do
		progress.Xp -= required
		progress.Level += 1
		table.insert(progress.PendingLevels, progress.Level)
		gained += 1
		required = Progression.xpToNext(progress.Level)
	end
	return gained
end

-- Extrae el siguiente nivel pendiente de elegir mejora (FIFO).
function LevelLogic.popPendingLevel(progress: Progress): number?
	if #progress.PendingLevels == 0 then
		return nil
	end
	return table.remove(progress.PendingLevels, 1)
end

return LevelLogic
