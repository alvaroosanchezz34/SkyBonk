--[[
	Simulación de partidas completas con los servicios REALES del servidor
	sobre un motor emulado (tests/lib/FakeEngine):

	    lune run tests/simulation.luau

	Un "bot" mueve al jugador (recoge gemas y esquiva), elige mejoras y,
	pasado un tiempo, se queda quieto hasta morir. Después pide reiniciar.
	Se comprueban invariantes en cada frame y se envían peticiones
	manipuladas para verificar la seguridad. No sustituye a la prueba en
	Roblox Studio (no hay física real, red ni interfaz).
]]

local process = require("@lune/process")
local roblox = require("@lune/roblox")
local Harness = require("./lib/Harness")
local FakeEngine = require("./lib/FakeEngine")

local Vector3 = roblox.Vector3

local DT = 1 / 30
local REMOTE_NAMES = {
	"ClientReady",
	"ChooseUpgrade",
	"RequestRestart",
	"HudUpdate",
	"UpgradeOffer",
	"UpgradeResolved",
	"CombatFx",
	"EnemyDied",
	"GemCollected",
	"PlayerDamaged",
	"LevelUp",
	"GameOver",
}

------------------------------------------------------------- Montaje
local world = FakeEngine.createWorld(107)
local net, _log, onClient = FakeEngine.createNet(REMOTE_NAMES)

local harness = Harness.new({
	services = {
		Players = world.Players,
		RunService = world.RunService,
		ServerStorage = world.ServerStorage,
	},
	globals = {
		Instance = FakeEngine.Instance,
		workspace = world.Workspace,
		Random = FakeEngine.Random(),
		RaycastParams = FakeEngine.RaycastParams,
		task = FakeEngine.task,
		os = FakeEngine.os,
		warn = function(...)
			print("  [warn]", ...)
		end,
	},
	modules = { ["src/shared/Net.luau"] = net },
})

local GameConfig = harness.require(harness.path("src/shared/Config/GameConfig.luau"))
local UpgradeConfig = harness.require(harness.path("src/shared/Config/UpgradeConfig.luau"))
local StatSheet = harness.require(harness.path("src/server/Logic/StatSheet.luau"))
local WeaponConfig = harness.require(harness.path("src/shared/Config/WeaponConfig.luau"))

local servicesFolder = "src/server/Services/"
local services = {}
local START_ORDER = {
	"EnemyService",
	"ExperienceService",
	"SpawnService",
	"CombatService",
	"LevelService",
	"UpgradeService",
	"MatchService",
}
for _, name in START_ORDER do
	services[name] = harness.require(harness.path(servicesFolder .. name .. ".luau"))
end
services.EnemyService.EnsureTemplates(world.ServerStorage.EnemyModels)
for _, name in START_ORDER do
	services[name].Init(services)
end
for _, name in START_ORDER do
	services[name].Start()
end

---------------------------------------------------------- Aserciones
local failures = {}
local checks = 0
local function check(condition: any, message: string)
	checks += 1
	if not condition then
		table.insert(failures, message)
		print("  ✘ " .. message)
	else
		print("  ✔ " .. message)
	end
end
local function section(title: string)
	print("\n▶ " .. title)
end

------------------------------------------------------------ Registro
local counters = {
	spawned = 0,
	spawnTooClose = 0,
	spawnOutside = 0,
	maxEnemies = 0,
	gemsSpawned = 0,
	gemValueSpawned = 0,
	gemValueCollected = 0,
	enemyDiedEvents = 0,
	combatHits = 0,
	badDamage = 0,
	offers = 0,
	badOffers = 0,
	pauseViolations = 0,
	levelUps = 0,
	gameOvers = 0,
	playerDamaged = 0,
}

local player = FakeEngine.createPlayer(world, "Bot", GameConfig.Map.PlayerSpawn)
local function currentRun()
	return services.MatchService.GetRun(player)
end

world.Workspace.ActiveEnemies.ChildAdded:Connect(function(model)
	counters.spawned += 1
	local run = currentRun()
	local root = model.PrimaryPart
	if run and root then
		local offset = root.Position - run.Root.Position
		local flat = math.sqrt(offset.X * offset.X + offset.Z * offset.Z)
		if flat < GameConfig.Spawn.MinRadius * 0.9 then
			counters.spawnTooClose += 1
		end
		local fromCenter = math.sqrt(root.Position.X ^ 2 + root.Position.Z ^ 2)
		if fromCenter > GameConfig.Map.PlayableRadius - GameConfig.Spawn.EdgeMargin + 0.01 then
			counters.spawnOutside += 1
		end
	end
end)
world.Workspace.ExperienceOrbs.ChildAdded:Connect(function(part)
	counters.gemsSpawned += 1
	counters.gemValueSpawned += part:GetAttribute("Value") or 0
end)

-------------------------------------------------------- Cliente bot
local pendingChoice = nil -- { token, id, at }
local lastOffer = nil
local pauseSnapshot = nil
local lastGameOver = nil
local lastHud = nil
local resolved = {}

onClient("UpgradeOffer", function(offer)
	counters.offers += 1
	lastOffer = offer
	local ids = {}
	local distinct = true
	for _, option in offer.Options do
		if ids[option.Id] then
			distinct = false
		end
		ids[option.Id] = true
		local def = UpgradeConfig.ById[option.Id]
		if def == nil or def.Enabled == false then
			distinct = false
		end
	end
	if #offer.Options ~= 3 or not distinct then
		counters.badOffers += 1
	end
	-- Prioriza el daño (como haría un jugador) y después la supervivencia.
	local preference = { "TwinBlade", "SharpEdge", "SwiftStrike", "BasaltHeart", "StoneSkin" }
	local choice = offer.Options[1].Id
	for _, preferred in preference do
		if ids[preferred] then
			choice = preferred
			break
		end
	end
	-- Espera 1 s simulado: así se comprueba que la pausa es real.
	pendingChoice = { token = offer.Token, id = choice, at = FakeEngine.now() + 1 }
	local run = currentRun()
	pauseSnapshot = {
		elapsed = run.State.Elapsed,
		enemies = services.EnemyService.Count(run),
	}
end)
onClient("UpgradeResolved", function(result)
	table.insert(resolved, result)
end)
onClient("CombatFx", function(attack)
	local run = currentRun()
	local expected = StatSheet.weaponStats(run.State.Stats, WeaponConfig.GaleSword).Damage
	for _, hit in attack.Hits do
		counters.combatHits += 1
		if hit.Damage > expected + 1e-6 or hit.Damage <= 0 then
			counters.badDamage += 1
		end
	end
end)
onClient("EnemyDied", function()
	counters.enemyDiedEvents += 1
end)
onClient("GemCollected", function(info)
	counters.gemValueCollected += info.Value
end)
local levelTimes = {}
onClient("LevelUp", function(info)
	counters.levelUps += 1
	local current = services.MatchService.GetRun(player)
	if current and #levelTimes < 12 then
		table.insert(levelTimes, string.format("Nv%d@%.0fs", info.Level, current.State.Elapsed))
	end
end)
onClient("GameOver", function(summary)
	counters.gameOvers += 1
	lastGameOver = summary
end)
onClient("HudUpdate", function(snapshot)
	lastHud = snapshot
end)
onClient("PlayerDamaged", function()
	counters.playerDamaged += 1
end)

-- Movimiento del bot, como un jugador básico: huye de los enemigos que se
-- acercan, recoge gemas cercanas y, si no hay peligro, se mueve despacio
-- para que los enemigos entren en el alcance del arma. Evita el borde.
local botMode = "play"
local function moveBot(run)
	if botMode ~= "play" or run.Root.Anchored or run.Humanoid.Health <= 0 then
		return
	end
	local position = run.Root.Position
	local speed = run.Humanoid.WalkSpeed
	local flee = Vector3.zero
	local threats = 0
	for _, enemy in services.EnemyService.GetEnemies(run) do
		local away = Vector3.new(position.X - enemy.Position.X, 0, position.Z - enemy.Position.Z)
		local distance = away.Magnitude
		if distance < 11 and distance > 0.01 then
			flee += away.Unit * (11 - distance)
			threats += 1
		end
	end
	local target, best = nil, 30
	for _, gem in world.Workspace.ExperienceOrbs:GetChildren() do
		local d = (gem.Position - position).Magnitude
		if d < best then
			best = d
			target = gem.Position
		end
	end
	local healthy = run.Humanoid.Health > run.Humanoid.MaxHealth * 0.5
	local direction
	if target and (threats == 0 or (healthy and best < 14)) then
		direction = Vector3.new(target.X - position.X, 0, target.Z - position.Z).Unit
	elseif threats > 0 then
		direction = flee.Unit
	else
		return -- quieto: deja que el arma trabaje
	end
	-- Cerca del borde, gira hacia dentro.
	local fromCenter = Vector3.new(position.X, 0, position.Z)
	if fromCenter.Magnitude > 70 then
		direction = (direction + (-fromCenter.Unit) * ((fromCenter.Magnitude - 70) / 10)).Unit
	end
	run.Root.CFrame = run.Root.CFrame + direction * speed * DT
end

-- "Física": integra la velocidad plana de cada enemigo no anclado.
local function integrateEnemies()
	for _, model in world.Workspace.ActiveEnemies:GetChildren() do
		local root = model.PrimaryPart
		if root and not root.Anchored then
			local velocity = root.Mover.PlaneVelocity
			root.CFrame = root.CFrame + Vector3.new(velocity.X, 0, velocity.Y) * DT
		end
	end
end

local function frame()
	local run = currentRun()
	FakeEngine.advanceClock(DT)
	world.RunService.Heartbeat:Fire(DT)
	if run and run.Active then
		moveBot(run)
		integrateEnemies()
		counters.maxEnemies = math.max(counters.maxEnemies, services.EnemyService.Count(run))
		if run.State.Phase == "ChoosingUpgrade" and pauseSnapshot then
			if
				run.State.Elapsed ~= pauseSnapshot.elapsed
				or services.EnemyService.Count(run) ~= pauseSnapshot.enemies
				or not run.Root.Anchored
			then
				counters.pauseViolations += 1
			end
			for _, enemy in services.EnemyService.GetEnemies(run) do
				if not enemy.Root.Anchored then
					counters.pauseViolations += 1
				end
			end
		end
	end
	if pendingChoice and FakeEngine.now() >= pendingChoice.at then
		local choice = pendingChoice
		pendingChoice = nil
		net.ChooseUpgrade:FireServer(player, choice.token, choice.id)
	end
end

local function runFor(seconds: number, stopWhen: (() -> boolean)?)
	local frames = math.floor(seconds / DT)
	for _ = 1, frames do
		frame()
		if stopWhen and stopWhen() then
			return
		end
	end
end

----------------------------------------------------------- Prueba A
section("A · Inicio")
world.Players.PlayerAdded:Fire(player)
net.ClientReady:FireServer(player)
local run = currentRun()
check(run ~= nil, "la partida empieza al recibir ClientReady")
check(run and run.State.Phase == "Playing", "estado inicial Playing")
check(run and run.Humanoid.MaxHealth == 100 and run.Humanoid.Health == 100, "vida inicial 100/100")
check(run and math.abs(run.Humanoid.WalkSpeed - 18) < 1e-6, "velocidad base 18")
check(lastHud and lastHud.Level == 1 and lastHud.XpToNext == 5, "HUD inicial (nivel 1, 0/5 XP)")
net.ClientReady:FireServer(player)
check(currentRun() == run, "un segundo ClientReady no reinicia la partida")

runFor(GameConfig.Spawn.GracePeriod - 0.2)
check(services.EnemyService.Count(run) == 0, "periodo de gracia: sin enemigos los primeros segundos")

----------------------------------------------------------- Prueba B-E
section("B-E · Combate, experiencia, niveles y mejoras")
-- Seguridad antes de la primera oferta: elección fuera de tiempo.
net.ChooseUpgrade:FireServer(player, 1, "SharpEdge")
check(#resolved == 1 and resolved[1].Accepted == false and resolved[1].Reason == "NotChoosing",
	"elección fuera de tiempo rechazada")

local firstOfferChecked = false
local damageBefore = nil
runFor(300, function()
	-- Pruebas de seguridad sobre la primera oferta abierta.
	if not firstOfferChecked and lastOffer and run.State.Phase == "ChoosingUpgrade" then
		firstOfferChecked = true
		local token = lastOffer.Token
		local before = #resolved
		net.ChooseUpgrade:FireServer(player, token, "HackInfinito")
		check(resolved[before + 1] and resolved[before + 1].Reason == "NotOffered", "id inventado rechazado")
		net.ChooseUpgrade:FireServer(player, "1", lastOffer.Options[1].Id)
		net.ChooseUpgrade:FireServer(player, token, { "tabla" })
		net.ChooseUpgrade:FireServer(player, 0 / 0, lastOffer.Options[1].Id)
		check(#resolved == before + 1, "argumentos de tipo inválido ignorados")
		net.ChooseUpgrade:FireServer(player, token + 7, lastOffer.Options[1].Id)
		check(resolved[#resolved].Reason == "StaleToken", "token de otra oferta rechazado")
		check(run.State.Phase == "ChoosingUpgrade", "la oferta sigue abierta tras peticiones inválidas")
		-- Aún no se ha aplicado ninguna mejora.
		local applied = 0
		for _ in run.State.UpgradeLevels do
			applied += 1
		end
		check(applied == 0, "las peticiones inválidas no aplican mejoras")
		damageBefore = StatSheet.weaponStats(run.State.Stats, WeaponConfig.GaleSword)
	end
	return run.State.Progress.Level >= 5 and run.State.Phase == "Playing"
end)

check(counters.spawned > 0, "aparecen enemigos")
check(counters.spawnTooClose == 0, "ningún enemigo aparece encima del jugador (" .. counters.spawnTooClose .. ")")
check(counters.spawnOutside == 0, "ningún enemigo aparece fuera de la zona válida")
check(counters.maxEnemies <= GameConfig.Spawn.MaxActiveEnemies, "se respeta el máximo de enemigos activos")
check(counters.combatHits > 0, "el arma encuentra objetivos y golpea")
check(counters.badDamage == 0, "el daño de cada golpe es el calculado por el servidor")
check(run.State.Kills > 0, "los enemigos mueren")
check(counters.enemyDiedEvents == run.State.Kills, "una muerte = un evento (sin duplicados)")
check(counters.gemsSpawned == run.State.Kills, "cada muerte genera exactamente una gema")
check(counters.gemValueCollected > 0, "las gemas se recogen")
check(counters.gemValueCollected <= counters.gemValueSpawned, "no se recoge más XP de la generada")
check(run.State.Progress.Level >= 5, "se suben varios niveles (nivel " .. run.State.Progress.Level .. ")")
check(counters.offers == run.State.Progress.Level - 1, "una oferta por nivel ganado")
check(counters.badOffers == 0, "todas las ofertas tienen 3 opciones distintas y válidas")
check(counters.pauseViolations == 0, "pausa real durante la selección (" .. counters.pauseViolations .. " violaciones)")
local totalUpgrades = 0
for _, level in run.State.UpgradeLevels do
	totalUpgrades += level
end
check(totalUpgrades == run.State.Progress.Level - 1, "una mejora aplicada por nivel")
local damageAfter = StatSheet.weaponStats(run.State.Stats, WeaponConfig.GaleSword)
check(
	damageBefore
		and (
			damageAfter.Damage ~= damageBefore.Damage
			or damageAfter.Cooldown ~= damageBefore.Cooldown
			or damageAfter.Projectiles ~= damageBefore.Projectiles
			or run.Humanoid.MaxHealth ~= 100
			or run.State.Stats.DamageTakenMult ~= 1
			or run.State.Stats.Luck ~= 0
			or run.State.Stats.XpGainPct ~= 0
			or run.Humanoid.WalkSpeed ~= 18
			or run.State.Stats.RangePct ~= 0
		),
	"las mejoras elegidas cambian estadísticas reales"
)
check(run.Humanoid.MaxHealth == StatSheet.maxHealth(run.State.Stats), "vida máxima sincronizada con las mejoras")
check(math.abs(run.Humanoid.WalkSpeed - StatSheet.walkSpeed(run.State.Stats)) < 1e-6, "velocidad sincronizada")

-- Repetir la última elección ya consumida no duplica efectos.
local levelsBefore = table.clone(run.State.UpgradeLevels)
local lastAccepted
for index = #resolved, 1, -1 do
	if resolved[index].Accepted then
		lastAccepted = resolved[index]
		break
	end
end
check(lastAccepted ~= nil, "hay al menos una elección aceptada")
lastAccepted = lastAccepted or { Token = 1, UpgradeId = "SharpEdge" }
net.ChooseUpgrade:FireServer(player, lastAccepted.Token, lastAccepted.UpgradeId)
local sameLevels = true
for id, level in run.State.UpgradeLevels do
	if levelsBefore[id] ~= level then
		sameLevels = false
	end
end
check(sameLevels and resolved[#resolved].Accepted == false, "repetir una elección consumida no duplica el efecto")

-- Límite de frecuencia de ChooseUpgrade.
local beforeSpam = #resolved
for _ = 1, 30 do
	net.ChooseUpgrade:FireServer(player, 999, "SharpEdge")
end
check(#resolved - beforeSpam <= GameConfig.RateLimits.ChooseUpgrade.Max, "spam de ChooseUpgrade limitado")
runFor(1.2)

print(string.format(
	"  · %0.1f s de partida | nivel %d | %d muertes | %d golpes | máx. %d enemigos simultáneos | %d golpes recibidos",
	run.State.Elapsed,
	run.State.Progress.Level,
	run.State.Kills,
	counters.combatHits,
	counters.maxEnemies,
	counters.playerDamaged
))

print("  · ritmo de niveles: " .. table.concat(levelTimes, ", "))

-- Varios niveles con una sola concesión: ofertas encadenadas sin solaparse.
section("D · Varios niveles de golpe")
local offersBefore = counters.offers
local levelBefore = run.State.Progress.Level
services.LevelService.GrantExperience(run, 200)
local gainedLevels = run.State.Progress.Level - levelBefore
check(gainedLevels >= 2, "200 XP otorgan varios niveles (" .. gainedLevels .. ")")
check(counters.offers == offersBefore + 1, "solo se abre una oferta a la vez")
check(#run.State.Progress.PendingLevels == gainedLevels - 1, "el resto de niveles queda en cola")
runFor(1.1 * gainedLevels + 1, function()
	return run.State.Phase == "Playing" and #run.State.Progress.PendingLevels == 0
end)
check(counters.offers == offersBefore + gainedLevels, "se encadenan las ofertas pendientes")
check(run.State.Phase == "Playing", "la partida continúa tras elegir")

-------------------------------------------------------------- Caída
section("Caída fuera del mapa")
local healthBefore = run.Humanoid.Health
run.Root.CFrame = run.Root.CFrame + Vector3.new(0, GameConfig.Map.KillY - 20 - run.Root.Position.Y, 0)
runFor(0.5)
check(run.Root.Position.Y > GameConfig.Map.KillY, "el jugador reaparece de forma controlada")
check(run.Humanoid.Health < healthBefore or run.State.Phase == "GameOver", "la caída penaliza la vida")

------------------------------------------------------- Prueba F y G
section("F · Derrota y reinicio")
botMode = "idle" -- se queda quieto hasta morir
runFor(600, function()
	return run.State.Phase == "GameOver"
end)
check(run.State.Phase == "GameOver", "el jugador puede morir")
check(counters.gameOvers == 1, "la derrota se procesa una sola vez")
check(lastGameOver and lastGameOver.Level == run.State.Progress.Level and lastGameOver.Kills == run.State.Kills,
	"resumen de derrota correcto")
local killsAtDeath = run.State.Kills
local elapsedAtDeath = run.State.Elapsed
services.LevelService.GrantExperience(run, 50)
check(run.State.Progress.Level == lastGameOver.Level, "no se gana XP tras la derrota")
runFor(0.5)
check(run.State.Elapsed == elapsedAtDeath and run.State.Kills == killsAtDeath, "el reloj y las muertes se detienen")

net.RequestRestart:FireServer(player)
check(currentRun() == run, "reinicio antes del enfriamiento rechazado")
runFor(GameConfig.Match.CleanupDelay + 0.2)
check(#world.Workspace.ActiveEnemies:GetChildren() == 0, "enemigos limpiados tras la derrota")
check(#world.Workspace.ExperienceOrbs:GetChildren() == 0, "gemas limpiadas tras la derrota")
check(not run.Active, "la partida anterior queda inactiva")

local oldCharacter = run.Character
botMode = "play"
net.RequestRestart:FireServer(player)
local newRun = currentRun()
check(newRun ~= nil and newRun ~= run, "nueva partida tras pedir reinicio")
check(newRun and newRun.State.Phase == "Playing" and newRun.State.Progress.Level == 1, "nueva partida en nivel 1")
check(newRun and newRun.State.Kills == 0 and newRun.State.Elapsed == 0, "contadores reiniciados")
check(newRun and newRun.Humanoid.Health == 100 and newRun.Humanoid.MaxHealth == 100, "vida restablecida")
check(newRun and newRun.Character ~= oldCharacter and oldCharacter.Parent == nil, "personaje nuevo")
check(lastHud and lastHud.Phase == "Playing" and lastHud.Level == 1, "HUD de la nueva partida")
net.RequestRestart:FireServer(player)
check(currentRun() == newRun, "no se puede reiniciar una partida en curso")
runFor(20)
check(services.EnemyService.Count(newRun) > 0, "la nueva partida genera enemigos")
check(newRun.State.Elapsed > 15, "la nueva partida avanza")

section("Salida del jugador")
world.Players.PlayerRemoving:Fire(player)
check(currentRun() == nil, "la partida se elimina al salir")
check(#world.Workspace.ActiveEnemies:GetChildren() == 0, "enemigos eliminados al salir")

----------------------------------------------------------- Resumen
print(string.format("\n[SkyBonk Simulación] %d comprobaciones, %d fallidas", checks, #failures))
if #failures > 0 then
	process.exit(1)
end
