-- Pruebas D, E y G (ofertas, aplicación de mejoras y validación de elecciones).
local Shared = game:GetService("ReplicatedStorage").Shared
local UpgradeConfig = require(Shared.Config.UpgradeConfig)
local WeaponConfig = require(Shared.Config.WeaponConfig)
local Logic = script.Parent.Parent.Logic
local RunState = require(Logic.RunState)
local StatSheet = require(Logic.StatSheet)
local UpgradeLogic = require(Logic.UpgradeLogic)

-- Generador determinista (LCG) con la interfaz de Random:NextNumber().
local function makeRng(seed: number)
	local state = seed
	return {
		NextNumber = function(_self)
			state = (state * 1103515245 + 12345) % 2147483648
			return state / 2147483648
		end,
	}
end

local function newRunWithLevels(levels: number)
	local state = RunState.new({ "GaleSword" })
	local total = 0
	for level = 1, levels do
		total += require(Shared.Progression).xpToNext(level)
	end
	RunState.grantXp(state, total)
	return state
end

return function(it, expect)
	it("todas las mejoras habilitadas tienen efectos reales y datos completos", function()
		for _, def in UpgradeConfig.List do
			expect.truthy(def.DisplayName ~= "" and def.Description ~= "", def.Id .. " sin textos")
			expect.truthy(UpgradeConfig.Rarities[def.Rarity] ~= nil, def.Id .. " rareza inválida")
			if def.Enabled ~= false then
				expect.truthy(#def.Effects > 0, def.Id .. " no hace nada")
			end
		end
		-- 14 mejoras (13 activas + Impulso Arcano desactivada) + el comodín.
		expect.equal(#UpgradeConfig.List, 15)
		for _, def in UpgradeConfig.List do
			expect.truthy(UpgradeConfig.Categories[def.Category] ~= nil, def.Id .. " sin categoría visual")
		end
	end)

	it("una oferta tiene tres opciones distintas y válidas (1000 tiradas)", function()
		local rng = makeRng(42)
		for _ = 1, 1000 do
			local state = RunState.new({ "GaleSword" })
			local options = UpgradeLogic.rollOptions({
				Stats = state.Stats,
				Weapons = state.Weapons,
				UpgradeLevels = state.UpgradeLevels,
			}, rng)
			expect.equal(#options, 3)
			local seen = {}
			for _, id in options do
				expect.falsy(seen[id], "opción repetida " .. id)
				seen[id] = true
				local def = UpgradeConfig.ById[id]
				expect.truthy(def and def.Enabled ~= false, "opción no seleccionable " .. id)
				expect.falsy(def.IsFallback, "no debe ofrecer comodines con opciones de sobra")
			end
		end
	end)

	it("Impulso Arcano (sin mecánica en Fase 1) nunca se ofrece", function()
		local rng = makeRng(7)
		local state = RunState.new({ "GaleSword" })
		for _ = 1, 2000 do
			local options = UpgradeLogic.rollOptions({
				Stats = state.Stats,
				Weapons = state.Weapons,
				UpgradeLevels = state.UpgradeLevels,
			}, rng)
			expect.falsy(table.find(options, "ArcaneImpulse"), "se ofreció ArcaneImpulse")
		end
	end)

	it("las mejoras al nivel máximo dejan de ofrecerse y se completa con el comodín", function()
		local state = RunState.new({ "GaleSword" })
		-- Agota todo menos dos mejoras.
		for _, def in UpgradeConfig.List do
			if def.MaxLevel and def.Id ~= "SharpEdge" and def.Id ~= "HawkSteps" then
				state.UpgradeLevels[def.Id] = def.MaxLevel
			end
		end
		local options = UpgradeLogic.rollOptions({
			Stats = state.Stats,
			Weapons = state.Weapons,
			UpgradeLevels = state.UpgradeLevels,
		}, makeRng(1))
		expect.equal(#options, 3)
		expect.truthy(table.find(options, "SharpEdge"))
		expect.truthy(table.find(options, "HawkSteps"))
		expect.truthy(table.find(options, "SkyBlessing"), "debe completarse con el comodín")
	end)

	it("Hoja Doble deja de ofrecerse cuando el arma alcanza su máximo de proyectiles", function()
		local state = RunState.new({ "GaleSword" })
		state.Stats.ExtraProjectiles = WeaponConfig.GaleSword.MaxProjectiles - 1
		local ctx = { Stats = state.Stats, Weapons = state.Weapons, UpgradeLevels = state.UpgradeLevels }
		expect.falsy(UpgradeLogic.isEligible(UpgradeConfig.ById.TwinBlade, ctx))
		state.Stats.ExtraProjectiles = 0
		expect.truthy(UpgradeLogic.isEligible(UpgradeConfig.ById.TwinBlade, ctx))
	end)

	it("la Suerte aumenta el peso de las rarezas Rara y Épica", function()
		local epic = UpgradeConfig.ById.TwinBlade
		local common = UpgradeConfig.ById.SharpEdge
		expect.truthy(UpgradeLogic.weightOf(epic, 3) > UpgradeLogic.weightOf(epic, 0))
		expect.equal(UpgradeLogic.weightOf(common, 3), UpgradeLogic.weightOf(common, 0))
	end)

	it("subir de nivel abre una oferta vinculada al nivel y pausa la partida", function()
		local state = newRunWithLevels(1)
		expect.equal(state.Progress.Level, 2)
		local offer = RunState.tryOpenOffer(state, makeRng(3))
		expect.truthy(offer, "debe abrirse una oferta")
		expect.equal(offer.Level, 2)
		expect.equal(state.Phase, "ChoosingUpgrade")
		-- No se superponen ofertas.
		expect.equal(RunState.tryOpenOffer(state, makeRng(3)), nil)
		-- El reloj de partida no avanza en pausa.
		RunState.advance(state, 5)
		expect.equal(state.Elapsed, 0)
	end)

	it("aplicar una mejora cambia realmente la estadística", function()
		local cases = {
			SharpEdge = function(s)
				return StatSheet.weaponStats(s, WeaponConfig.GaleSword).Damage
			end,
			SwiftStrike = function(s)
				return StatSheet.weaponStats(s, WeaponConfig.GaleSword).Cooldown
			end,
			AstralReach = function(s)
				return StatSheet.weaponStats(s, WeaponConfig.GaleSword).Range
			end,
			BasaltHeart = StatSheet.maxHealth,
			HawkSteps = StatSheet.walkSpeed,
			ConcentratedEssence = function(s)
				return StatSheet.xpGain(s, 10)
			end,
			StoneSkin = function(s)
				return StatSheet.damageTaken(s, 10)
			end,
			CelestialFortune = StatSheet.luckyGemChance,
			TwinBlade = function(s)
				return StatSheet.weaponStats(s, WeaponConfig.GaleSword).Projectiles
			end,
			StormEdge = function(s)
				return StatSheet.weaponStats(s, WeaponConfig.GaleSword).TargetsPerProjectile
			end,
			KeenStrike = function(s)
				return StatSheet.weaponStats(s, WeaponConfig.GaleSword).CritChance
			end,
			VitalSap = function(s)
				return s.HealthRegen
			end,
			CelestialMagnet = StatSheet.magnetRadius,
		}
		local expected = {
			SharpEdge = 15 * 1.2,
			SwiftStrike = 1.0 * 0.88,
			AstralReach = 30 * 1.2,
			BasaltHeart = 120,
			HawkSteps = 20 * 1.12,
			ConcentratedEssence = 12,
			StoneSkin = 9,
			TwinBlade = 2,
			StormEdge = 2,
			KeenStrike = 0.12,
			VitalSap = 1,
			CelestialMagnet = 11 * 1.35,
		}
		for id, measure in cases do
			local state = newRunWithLevels(1)
			local before = measure(state.Stats)
			local offer = RunState.tryOpenOffer(state, makeRng(9))
			-- Fuerza la opción a probar dentro de la oferta activa.
			offer.Options[1] = id
			local ok, result = RunState.choose(state, offer.Token, id)
			expect.truthy(ok, "elección rechazada: " .. id .. " " .. tostring(result))
			local after = measure(state.Stats)
			expect.truthy(after ~= before, id .. " no cambió la estadística")
			if expected[id] then
				expect.near(after, expected[id], 1e-6, id)
			end
			expect.equal(state.UpgradeLevels[id], 1)
			expect.equal(state.Phase, "Playing")
		end
	end)

	it("el comodín devuelve una curación del 30 %", function()
		local state = newRunWithLevels(1)
		local offer = RunState.tryOpenOffer(state, makeRng(5))
		offer.Options[1] = "SkyBlessing"
		local ok, result = RunState.choose(state, offer.Token, "SkyBlessing")
		expect.truthy(ok)
		expect.near(result.HealPct, 0.3)
	end)

	it("rechaza selecciones inventadas, fuera de tiempo y repetidas", function()
		local state = newRunWithLevels(2) -- dos niveles pendientes
		-- Fuera de tiempo: aún no hay oferta.
		state.Phase = "Playing"
		local ok, reason = RunState.choose(state, 1, "SharpEdge")
		expect.falsy(ok)
		expect.equal(reason, "NotChoosing")

		local offer = RunState.tryOpenOffer(state, makeRng(11))
		local notOffered
		for _, def in UpgradeConfig.List do
			if not table.find(offer.Options, def.Id) then
				notOffered = def.Id
				break
			end
		end

		ok, reason = RunState.choose(state, offer.Token, "HackDeLaMuerte")
		expect.falsy(ok)
		expect.equal(reason, "NotOffered")
		ok, reason = RunState.choose(state, offer.Token, notOffered)
		expect.falsy(ok)
		expect.equal(reason, "NotOffered")
		ok, reason = RunState.choose(state, offer.Token + 1, offer.Options[1])
		expect.falsy(ok)
		expect.equal(reason, "StaleToken")
		ok, reason = RunState.choose(state, tostring(offer.Token), offer.Options[1])
		expect.falsy(ok)
		ok, reason = RunState.choose(state, offer.Token, { offer.Options[1] })
		expect.falsy(ok)

		-- Elección válida.
		local chosen = offer.Options[1]
		ok = RunState.choose(state, offer.Token, chosen)
		expect.truthy(ok)
		expect.equal(state.UpgradeLevels[chosen], 1)

		-- Repetir la misma petición no duplica el efecto.
		ok, reason = RunState.choose(state, offer.Token, chosen)
		expect.falsy(ok)
		expect.equal(state.UpgradeLevels[chosen], 1)

		-- Segundo nivel pendiente: nueva oferta con token nuevo; el antiguo no sirve.
		local second = RunState.tryOpenOffer(state, makeRng(12))
		expect.truthy(second)
		expect.equal(second.Level, 3)
		expect.truthy(second.Token ~= offer.Token)
		ok, reason = RunState.choose(state, offer.Token, second.Options[1])
		expect.falsy(ok)
		expect.equal(reason, "StaleToken")
		expect.equal(RunState.tryOpenOffer(state, makeRng(13)), nil)
	end)

	it("tras la derrota no se conceden experiencia, muertes ni elecciones", function()
		local state = newRunWithLevels(1)
		local offer = RunState.tryOpenOffer(state, makeRng(2))
		expect.truthy(RunState.setGameOver(state))
		expect.falsy(RunState.setGameOver(state), "la derrota solo se procesa una vez")
		local ok = RunState.choose(state, offer.Token, offer.Options[1])
		expect.falsy(ok)
		expect.equal(RunState.grantXp(state, 100), 0)
		RunState.addKill(state)
		expect.equal(state.Kills, 0)
	end)
	it("hasta el nivel 4 cada oferta incluye al menos una mejora de Ataque", function()
		local rng = makeRng(7)
		for level = 2, 4 do
			for _ = 1, 300 do
				local state = RunState.new({ "GaleSword" })
				local options = UpgradeLogic.rollOptions({
					Stats = state.Stats,
					Weapons = state.Weapons,
					UpgradeLevels = state.UpgradeLevels,
				}, rng, nil, level)
				local attack = false
				for _, id in options do
					if UpgradeConfig.ById[id].Category == "Ataque" then
						attack = true
					end
				end
				expect.truthy(attack, "oferta del nivel " .. level .. " sin mejora de Ataque")
				expect.equal(#options, 3)
			end
		end
	end)
end
