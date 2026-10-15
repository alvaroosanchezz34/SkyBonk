--!strict
--[[
	Progression
	Función centralizada de la curva de experiencia (servidor y HUD).
]]

local GameConfig = require(script.Parent.Config.GameConfig)

local Progression = {}

-- Experiencia necesaria para pasar de `level` a `level + 1`.
function Progression.xpToNext(level: number): number
	local curve = GameConfig.Progression
	local n = math.max(math.floor(level), 1) - 1
	local required = curve.BaseXp + curve.LinearXp * n + curve.QuadraticXp * n * n
	return math.max(1, math.floor(required + 1e-6))
end

return Progression
