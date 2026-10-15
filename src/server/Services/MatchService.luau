--[[
	MatchService  (el "RunService" del diseño; renombrado para no confundirlo
	con game:GetService("RunService") de Roblox)

	Responsabilidades:
	  • Crear, pausar, terminar y reiniciar partidas (una por jugador).
	  • Bucle centralizado del servidor: un único Heartbeat que avanza todas
	    las partidas y llama a Combat/Enemy/Spawn/Experience.
	  • Vida del jugador: daño recibido, caída al vacío y derrota.
	  • Envío del HUD al cliente (agrupado y limitado en frecuencia).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local Progression = require(Shared.Progression)
local Net = require(Shared.Net)
local Types = require(Shared.Types)

local Logic = script.Parent.Parent.Logic
local RunState = require(Logic.RunState)
local StatSheet = require(Logic.StatSheet)
local RateLimiter = require(Logic.RateLimiter)
local ServerTypes = require(script.Parent.Parent.ServerTypes)

type Run = ServerTypes.Run

local MatchService = {}

local services: ServerTypes.Services
local runs: { [Player]: Run } = {}
local starting: { [Player]: boolean } = {}
local readyLimiter = RateLimiter.new(GameConfig.RateLimits.ClientReady.Max, GameConfig.RateLimits.ClientReady.Window)
local restartLimiter = RateLimiter.new(GameConfig.RateLimits.RequestRestart.Max, GameConfig.RateLimits.RequestRestart.Window)

local function disconnectAll(connections: { RBXScriptConnection })
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
end

local function setCharacterCollisionGroup(character: Model)
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = "Players"
		end
	end
end

function MatchService.Init(allServices: ServerTypes.Services)
	services = allServices
end

function MatchService.GetRun(player: Player): Run?
	return runs[player]
end

function MatchService.MarkHudDirty(run: Run)
	run.HudDirty = true
end

function MatchService.BuildHudSnapshot(run: Run): Types.HudSnapshot
	local state = run.State
	local humanoid = run.Humanoid
	local primary = state.Weapons[1]
	return {
		Phase = state.Phase,
		Level = state.Progress.Level,
		Xp = state.Progress.Xp,
		XpToNext = Progression.xpToNext(state.Progress.Level),
		Health = humanoid.Health,
		MaxHealth = humanoid.MaxHealth,
		Kills = state.Kills,
		Elapsed = state.Elapsed,
		Stats = StatSheet.summary(state.Stats, primary and primary.Def),
	}
end

local function sendHud(run: Run)
	run.HudDirty = false
	run.LastHudSentAt = os.clock()
	Net.HudUpdate:FireClient(run.Player, MatchService.BuildHudSnapshot(run))
end

--[[
	Aplica al personaje las estadísticas derivadas (vida máxima y velocidad).
	Si la vida máxima sube, cura la diferencia; `healPct` cura además un
	porcentaje de la vida máxima (mejora Bendición del Cielo).
]]
function MatchService.ApplyStats(run: Run, healPct: number?)
	local humanoid = run.Humanoid
	if humanoid.Health <= 0 then
		return
	end
	local stats = run.State.Stats
	local newMax = StatSheet.maxHealth(stats)
	local oldMax = humanoid.MaxHealth
	local health = humanoid.Health
	humanoid.MaxHealth = newMax
	if newMax > oldMax then
		health += newMax - oldMax
	end
	if healPct and healPct > 0 then
		health += newMax * healPct
	end
	humanoid.Health = math.clamp(health, 1, newMax)
	humanoid.WalkSpeed = StatSheet.walkSpeed(stats)
	run.HudDirty = true
end

-- Pausa lógica real: congela al jugador, a los enemigos, la aparición y el reloj.
function MatchService.SetPaused(run: Run, paused: boolean)
	if run.Paused == paused then
		return
	end
	run.Paused = paused
	if run.Root.Parent and run.Humanoid.Health > 0 then
		run.Root.Anchored = paused
	end
	services.EnemyService.SetFrozen(run, paused)
end

--[[
	Daño al jugador. Solo el servidor lo llama (contacto de enemigos o caídas);
	aplica la reducción de Piel de Piedra salvo que `ignoreReduction` sea true.
]]
function MatchService.DamagePlayer(run: Run, rawDamage: number, ignoreReduction: boolean?): boolean
	if not run.Active or run.State.Phase ~= "Playing" then
		return false
	end
	local humanoid = run.Humanoid
	if humanoid.Health <= 0 then
		return false
	end
	if not ignoreReduction and run.State.Elapsed < run.InvulnerableUntil then
		return false
	end
	local amount = if ignoreReduction then rawDamage else StatSheet.damageTaken(run.State.Stats, rawDamage)
	if amount <= 0 then
		return false
	end
	humanoid.Health = math.max(0, humanoid.Health - amount)
	Net.PlayerDamaged:FireClient(run.Player, {
		Amount = amount,
		Health = humanoid.Health,
		MaxHealth = humanoid.MaxHealth,
	})
	run.HudDirty = true
	return true
end

local function cleanupRun(run: Run)
	if not run.Active then
		return
	end
	run.Active = false
	disconnectAll(run.Connections)
	services.CombatService.CleanupRun(run)
	services.SpawnService.CleanupRun(run)
	services.EnemyService.CleanupRun(run)
	services.ExperienceService.CleanupRun(run)
end

-- Termina la partida (derrota). Idempotente: una muerte solo se procesa una vez.
function MatchService.EndRun(run: Run, reason: string)
	if not RunState.setGameOver(run.State) then
		return
	end
	run.EndedAt = os.clock()
	if run.Paused then
		run.Paused = false
		if run.Root.Parent then
			run.Root.Anchored = false
		end
	end
	-- Los enemigos quedan congelados detrás de la pantalla de derrota.
	services.EnemyService.SetFrozen(run, true)
	sendHud(run)
	Net.GameOver:FireClient(run.Player, {
		Elapsed = run.State.Elapsed,
		Kills = run.State.Kills,
		Level = run.State.Progress.Level,
		Reason = reason,
	})
	task.delay(GameConfig.Match.CleanupDelay, function()
		if runs[run.Player] == run then
			cleanupRun(run)
		end
	end)
end

function MatchService.StartRun(player: Player)
	if starting[player] or player.Parent ~= Players then
		return
	end
	starting[player] = true

	local previous = runs[player]
	if previous then
		cleanupRun(previous)
		runs[player] = nil
	end

	local ok, err = pcall(function()
		player:LoadCharacter()
	end)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not ok or not character or not humanoid or not root or player.Parent ~= Players then
		warn("[MatchService] No se pudo cargar el personaje de", player.Name, err)
		starting[player] = nil
		return
	end

	local run: Run = {
		Player = player,
		State = RunState.new(GameConfig.Player.StartingWeapons),
		Active = true,
		Character = character,
		Humanoid = humanoid,
		Root = root :: BasePart,
		Connections = {},
		Rng = Random.new(),
		Paused = false,
		InvulnerableUntil = 0,
		HudDirty = true,
		LastHudSentAt = 0,
		NextFallCheckAt = 0,
		EndedAt = nil,
	}

	humanoid.MaxHealth = StatSheet.maxHealth(run.State.Stats)
	humanoid.Health = humanoid.MaxHealth
	humanoid.WalkSpeed = StatSheet.walkSpeed(run.State.Stats)
	setCharacterCollisionGroup(character)

	table.insert(run.Connections, humanoid.Died:Connect(function()
		MatchService.EndRun(run, "Died")
	end))
	table.insert(run.Connections, character.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = "Players"
		end
	end))
	table.insert(run.Connections, character.AncestryChanged:Connect(function(_, parent)
		-- El personaje ha desaparecido (p. ej. destruido por el motor): derrota.
		if parent == nil and run.State.Phase ~= "GameOver" then
			MatchService.EndRun(run, "CharacterRemoved")
		end
	end))

	runs[player] = run
	services.SpawnService.SetupRun(run)
	services.EnemyService.SetupRun(run)
	services.ExperienceService.SetupRun(run)
	services.CombatService.SetupRun(run)
	starting[player] = nil
	sendHud(run)
end

-- Caída fuera del mapa: reaparición controlada con penalización de vida.
local function checkFall(run: Run)
	if run.State.Elapsed < run.NextFallCheckAt then
		return
	end
	run.NextFallCheckAt = run.State.Elapsed + GameConfig.Match.FallCheckInterval
	local root = run.Root
	if root.Parent == nil or run.Humanoid.Health <= 0 then
		return
	end
	if root.Position.Y >= GameConfig.Map.KillY then
		return
	end
	local spawnPosition = GameConfig.Map.PlayerSpawn + Vector3.new(0, 3, 0)
	run.Character:PivotTo(CFrame.new(spawnPosition))
	root.AssemblyLinearVelocity = Vector3.zero
	MatchService.DamagePlayer(run, run.Humanoid.MaxHealth * GameConfig.Player.FallDamagePct, true)
	run.InvulnerableUntil = run.State.Elapsed + GameConfig.Player.FallInvulnerability
end

local function step(dt: number)
	local now = os.clock()
	for _, run in runs do
		if not run.Active then
			continue
		end
		local state = run.State
		if state.Phase == "Playing" then
			RunState.advance(state, dt)
			services.CombatService.Step(run)
			services.SpawnService.Step(run)
			services.EnemyService.Step(run)
			services.ExperienceService.Step(run)
			if state.Phase == "Playing" then
				checkFall(run)
			end
			-- El tiempo cambia en cada frame; el HUD lo extrapola en el cliente.
		end
		if run.Active and run.HudDirty and now - run.LastHudSentAt >= GameConfig.Match.HudSendInterval then
			sendHud(run)
		end
	end
end

local function onPlayerAdded(player: Player)
	-- Si el cliente no avisa a tiempo, la partida empieza igualmente.
	task.delay(GameConfig.Match.ClientReadyTimeout, function()
		if player.Parent == Players and runs[player] == nil then
			MatchService.StartRun(player)
		end
	end)
end

local function onPlayerRemoving(player: Player)
	local run = runs[player]
	if run then
		cleanupRun(run)
		runs[player] = nil
	end
	starting[player] = nil
	readyLimiter:Forget(player)
	restartLimiter:Forget(player)
	services.UpgradeService.ForgetPlayer(player)
end

function MatchService.Start()
	Players.CharacterAutoLoads = false

	Net.ClientReady.OnServerEvent:Connect(function(player: Player)
		if not readyLimiter:Allow(player) then
			return
		end
		local run = runs[player]
		if run == nil then
			MatchService.StartRun(player)
		elseif run.Active then
			-- Resincroniza la interfaz (p. ej. si el cliente se recargó).
			sendHud(run)
			services.UpgradeService.ResendOffer(run)
		end
	end)

	Net.RequestRestart.OnServerEvent:Connect(function(player: Player)
		if not restartLimiter:Allow(player) then
			return
		end
		local run = runs[player]
		if run ~= nil then
			if run.State.Phase ~= "GameOver" then
				return -- no se puede reiniciar una partida en curso
			end
			if os.clock() - (run.EndedAt or 0) < GameConfig.Match.RestartCooldown then
				return
			end
		end
		MatchService.StartRun(player)
	end)

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	RunService.Heartbeat:Connect(step)
end

return MatchService
