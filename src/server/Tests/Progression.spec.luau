-- Prueba D (curva y niveles): experiencia sobrante, varios niveles, sin duplicados.
local Shared = game:GetService("ReplicatedStorage").Shared
local Progression = require(Shared.Progression)
local LevelLogic = require(script.Parent.Parent.Logic.LevelLogic)

return function(it, expect)
	it("la curva inicial es 5, 8, 12 y sigue creciendo", function()
		expect.equal(Progression.xpToNext(1), 5)
		expect.equal(Progression.xpToNext(2), 8)
		expect.equal(Progression.xpToNext(3), 12)
		local previous = Progression.xpToNext(3)
		for level = 4, 60 do
			local required = Progression.xpToNext(level)
			expect.truthy(required > previous, "la curva debe crecer en el nivel " .. level)
			previous = required
		end
	end)

	it("sube de nivel al alcanzar el umbral y conserva la experiencia sobrante", function()
		local progress = LevelLogic.new()
		expect.equal(LevelLogic.addXp(progress, 4), 0)
		expect.equal(progress.Level, 1)
		expect.equal(LevelLogic.addXp(progress, 3), 1) -- 7 XP: 5 para subir, sobran 2
		expect.equal(progress.Level, 2)
		expect.equal(progress.Xp, 2)
		expect.equal(#progress.PendingLevels, 1)
		expect.equal(progress.PendingLevels[1], 2)
	end)

	it("procesa varios niveles con una sola concesión grande", function()
		local progress = LevelLogic.new()
		-- 5 + 8 + 12 = 25 -> nivel 4 con 1 de sobra
		expect.equal(LevelLogic.addXp(progress, 26), 3)
		expect.equal(progress.Level, 4)
		expect.equal(progress.Xp, 1)
		expect.equal(#progress.PendingLevels, 3)
		expect.equal(LevelLogic.popPendingLevel(progress), 2)
		expect.equal(LevelLogic.popPendingLevel(progress), 3)
		expect.equal(LevelLogic.popPendingLevel(progress), 4)
		expect.equal(LevelLogic.popPendingLevel(progress), nil)
	end)

	it("rechaza cantidades inválidas (negativas, NaN, infinito)", function()
		local progress = LevelLogic.new()
		expect.equal(LevelLogic.addXp(progress, -10), 0)
		expect.equal(LevelLogic.addXp(progress, 0 / 0), 0)
		expect.equal(LevelLogic.addXp(progress, 0), 0)
		expect.equal(progress.Xp, 0)
		-- math.huge se acota a MaxXpPerGrant en lugar de bloquear el servidor.
		LevelLogic.addXp(progress, math.huge)
		expect.truthy(progress.Level > 1 and progress.Level < 1000, "nivel acotado")
	end)
end
