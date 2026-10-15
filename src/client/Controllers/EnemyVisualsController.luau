--[[
	EnemyVisualsController
	Animación de todos los enemigos a partir del estado que publica el
	servidor en cada modelo (State, StateAt, StateDuration, HopSeed). Solo
	presentación: nada de lo que ocurre aquí afecta al combate.

	Slimes (procedural, sobre BodyWeld.C0 y BodyMesh.Scale):
	  aparición (emergen del suelo), saltos sincronizados con el movimiento real
	  del servidor (mismo reloj y semilla), anticipación (se agachan y se tiñen),
	  salto de ataque, golpe en área del Rey (anillo de peligro), retroceso al
	  recibir un impacto y muerte (se aplastan, estallan y se desvanecen).
	Esqueletos (Animator + animaciones de Roblox):
	  reposo / andar / correr según la velocidad real, tajo sincronizado con la
	  anticipación, inclinación al recibir un impacto, aparición desde el suelo
	  y muerte desmontándose (piezas locales con física, como máximo MaxRagdolls).

	Un único RenderStepped recorre todos los enemigos.
]]

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local EnemyConfig = require(Shared.Config.EnemyConfig)
local Sfx = require(script.Parent.Parent.Util.Sfx)
local FxPool = require(script.Parent.Parent.Util.FxPool)

local EnemyVisualsController = {}

local TAU = math.pi * 2
local COMBAT = GameConfig.Combat
local FX = GameConfig.Effects
local ANIMS = GameConfig.Animations
local WARNING = Color3.fromRGB(255, 70, 90)
local player = Players.LocalPlayer

type Visual = {
	Model: Model,
	Def: any,
	Kind: string,
	Root: BasePart,
	Scale: number,
	State: string,
	StateAt: number,
	StateDuration: number,
	HopSeed: number,
	Bar: BillboardGui?,
	Fill: Frame?,
	FlashUntil: number,
	LastPosition: Vector3,
	Speed: number,
	Dying: boolean,
	DyingAt: number,
	Connections: { RBXScriptConnection },
	-- Slime
	Weld: Weld?,
	BaseC0: CFrame,
	Mesh: SpecialMesh?,
	Body: BasePart?,
	BodyColor: Color3,
	Extras: { BasePart }, -- ojos, núcleo, corona (se ocultan al aparecer/morir)
	Telegraph: Part?,
	-- Esqueleto
	RigWeld: Weld?,
	RigBaseC0: CFrame,
	Animator: Animator?,
	Tracks: { [string]: AnimationTrack },
	Loop: string?,
	Parts: { BasePart },
}

local visuals: { [Model]: Visual } = {}
local animations: { [string]: Animation } = {}
local ragdolls = 0

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function easeOutBack(t: number): number
	local c1, c3 = 1.70158, 2.70158
	return 1 + c3 * (t - 1) ^ 3 + c1 * (t - 1) ^ 2
end

local function animation(id: string): Animation
	local existing = animations[id]
	if existing then
		return existing
	end
	local anim = Instance.new("Animation")
	anim.AnimationId = id
	animations[id] = anim
	return anim
end

local function setLocalTransparency(parts: { BasePart }, value: number)
	for _, part in parts do
		part.LocalTransparencyModifier = value
	end
end

------------------------------------------------------------ Esqueletos
local function loadTracks(visual: Visual)
	local animator = visual.Animator
	if animator == nil or next(visual.Tracks) ~= nil then
		return
	end
	local function load(name: string, id: string, priority: Enum.AnimationPriority, looped: boolean)
		local ok, track = pcall(animator.LoadAnimation, animator, animation(id))
		if ok and track then
			track.Priority = priority
			track.Looped = looped
			visual.Tracks[name] = track
		end
	end
	load("Idle", ANIMS.SkeletonIdle, Enum.AnimationPriority.Idle, true)
	load("Walk", ANIMS.SkeletonWalk, Enum.AnimationPriority.Movement, true)
	load("Run", ANIMS.SkeletonRun, Enum.AnimationPriority.Movement, true)
	load("Attack", ANIMS.SkeletonAttack, Enum.AnimationPriority.Action, false)
end

local function playLoop(visual: Visual, name: string, speed: number)
	local track = visual.Tracks[name]
	if track == nil then
		return
	end
	if visual.Loop ~= name then
		local previous = visual.Loop and visual.Tracks[visual.Loop]
		if previous then
			previous:Stop(0.2)
		end
		track:Play(0.2)
		visual.Loop = name
	end
	track:AdjustSpeed(speed)
end

-- El esqueleto se desmonta: copia local de sus huesos con física y se oculta el original.
local function ragdoll(visual: Visual)
	if ragdolls >= FX.MaxRagdolls then
		return false
	end
	ragdolls += 1
	local folder = FxPool.Folder()
	local pieces: { BasePart } = {}
	local origin = visual.Root.Position
	for _, part in visual.Parts do
		if part.Parent == nil then
			continue
		end
		local piece = part:Clone()
		for _, child in piece:GetChildren() do
			if not child:IsA("SpecialMesh") and not child:IsA("SurfaceAppearance") and not child:IsA("Decal") then
				child:Destroy()
			end
		end
		piece.CFrame = part.CFrame
		piece.Anchored = false
		piece.CanCollide = part.Size.Magnitude > 0.6
		piece.Massless = false
		piece.LocalTransparencyModifier = 0
		piece.CollisionGroup = "Default"
		piece.Parent = folder
		local away = piece.Position - origin
		local flatAway = Vector3.new(away.X, 0, away.Z)
		local push = if flatAway.Magnitude > 1e-3
			then flatAway.Unit
			else Vector3.new(math.random() - 0.5, 0, math.random() - 0.5).Unit
		piece.AssemblyLinearVelocity = push * (8 + math.random() * 8) + Vector3.new(0, 10 + math.random() * 10, 0)
		piece.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 14
		table.insert(pieces, piece)
	end
	setLocalTransparency(visual.Parts, 1)
	task.delay(1.1, function()
		for _, piece in pieces do
			TweenService:Create(piece, TweenInfo.new(0.5), { Transparency = 1 }):Play()
		end
		task.delay(0.55, function()
			for _, piece in pieces do
				piece:Destroy()
			end
			ragdolls -= 1
		end)
	end)
	return true
end

------------------------------------------------------------- Registro
local function readState(visual: Visual)
	local model = visual.Model
	visual.State = model:GetAttribute("State") or "Chase"
	visual.StateAt = model:GetAttribute("StateAt") or serverNow()
	visual.StateDuration = model:GetAttribute("StateDuration") or 0
end

local function onStateChanged(visual: Visual)
	local previous = visual.State
	readState(visual)
	local state = visual.State
	local def = visual.Def
	local position = visual.Root.Position
	if state == "Windup" then
		Sfx.PlayAt("EnemyWindup", position, if def.AttackKind == "Slam" then 0.7 else 1.1)
		if def.AttackKind == "Slam" then
			-- Zona de peligro del Rey: crece durante la anticipación.
			visual.Telegraph = FxPool.Ring(
				position - Vector3.new(0, visual.Root.Size.Y / 2 - 0.1, 0),
				1,
				def.HitRange * 2,
				visual.StateDuration,
				WARNING,
				0.55,
				0.12
			)
		elseif visual.Kind == "Skeleton" then
			local track = visual.Tracks.Attack
			if track then
				-- El tajo llega a su punto álgido (≈55 % de la animación) al terminar la anticipación.
				local speed = math.clamp(track.Length * 0.55 / math.max(visual.StateDuration, 0.05), 0.4, 2.5)
				track:Play(0.05, 1, if track.Length > 0 then speed else 1)
			end
		end
	elseif state == "Recover" and previous == "Windup" and def.AttackKind == "Slam" then
		local ground = position - Vector3.new(0, visual.Root.Size.Y / 2 - 0.2, 0)
		FxPool.Ring(ground, 2, def.HitRange * 2.3, 0.45, Color3.fromRGB(255, 160, 120), 0.2, 0.3)
		FxPool.Emit("Dust", ground, 26)
		Sfx.PlayAt("BossSlam", position, 1, 120)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and (root.Position - position).Magnitude < def.HitRange * 2 then
			EnemyVisualsController.Shake(0.5, 0.25)
		end
	elseif state == "Spawning" then
		FxPool.Ring(
			position - Vector3.new(0, visual.Root.Size.Y / 2 - 0.1, 0),
			1,
			7 * visual.Scale,
			0.5,
			def.Color,
			0.25
		)
	end
end

local function updateBar(visual: Visual)
	local model = visual.Model
	local health = model:GetAttribute("Health")
	local maxHealth = model:GetAttribute("MaxHealth")
	if visual.Fill and type(health) == "number" and type(maxHealth) == "number" and maxHealth > 0 then
		visual.Fill.Size = UDim2.fromScale(math.clamp(health / maxHealth, 0, 1), 1)
		if visual.Bar then
			-- La barra aparece al recibir el primer impacto (menos ruido con muchos enemigos).
			visual.Bar.Enabled = health < maxHealth and not visual.Dying
		end
	end
end

local function track(model: Instance)
	if not model:IsA("Model") or visuals[model] then
		return
	end
	local root = model:WaitForChild("Root", 5) :: BasePart?
	local enemyId = model:GetAttribute("EnemyId")
	local def = enemyId and EnemyConfig[enemyId]
	if root == nil or def == nil or model.Parent == nil then
		return
	end
	local bar = root:FindFirstChild("HealthBar") :: BillboardGui?
	local back = bar and bar:FindFirstChild("Back")
	local visual: Visual = {
		Model = model,
		Def = def,
		Kind = def.Rig,
		Root = root,
		Scale = def.Scale,
		State = "Chase",
		StateAt = serverNow(),
		StateDuration = 0,
		HopSeed = model:GetAttribute("HopSeed") or math.random(),
		Bar = bar,
		Fill = back and back:FindFirstChild("Fill") :: Frame?,
		FlashUntil = 0,
		LastPosition = root.Position,
		Speed = 0,
		Dying = false,
		DyingAt = 0,
		Connections = {},
		Weld = nil,
		BaseC0 = CFrame.new(),
		Mesh = nil,
		Body = nil,
		BodyColor = def.Color,
		Extras = {},
		Telegraph = nil,
		RigWeld = nil,
		RigBaseC0 = CFrame.new(),
		Animator = nil,
		Tracks = {},
		Loop = nil,
		Parts = {},
	}
	if def.Rig == "Slime" then
		local body = model:FindFirstChild("Body") :: BasePart?
		visual.Body = body
		visual.Weld = body and body:FindFirstChild("BodyWeld") :: Weld?
		visual.BaseC0 = if visual.Weld then visual.Weld.C0 else CFrame.new()
		visual.Mesh = body and body:FindFirstChild("BodyMesh") :: SpecialMesh?
		visual.BodyColor = if body then body.Color else def.Color
		for _, child in model:GetChildren() do
			if child:IsA("BasePart") and child ~= body and child ~= root then
				table.insert(visual.Extras, child)
			end
		end
	else
		local rig = model:FindFirstChild("Rig")
		local hrp = rig and rig:FindFirstChild("HumanoidRootPart")
		visual.RigWeld = hrp and hrp:FindFirstChild("RigWeld") :: Weld?
		visual.RigBaseC0 = if visual.RigWeld then visual.RigWeld.C0 else CFrame.new()
		local controller = rig and rig:FindFirstChildOfClass("AnimationController")
		visual.Animator = controller and controller:FindFirstChildOfClass("Animator")
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("BasePart") and descendant ~= root then
				table.insert(visual.Parts, descendant)
			end
		end
		loadTracks(visual)
	end
	readState(visual)
	table.insert(
		visual.Connections,
		model:GetAttributeChangedSignal("State"):Connect(function()
			onStateChanged(visual)
		end)
	)
	table.insert(
		visual.Connections,
		model:GetAttributeChangedSignal("Health"):Connect(function()
			updateBar(visual)
		end)
	)
	visuals[model] = visual
	if visual.State == "Spawning" then
		visual.State = "" -- fuerza el efecto de aparición
		onStateChanged(visual)
		Sfx.PlayAt("EnemySpawn", root.Position, 1, 70)
	end
	updateBar(visual)
end

local function untrack(model: Instance)
	local visual = visuals[model :: Model]
	if visual == nil then
		return
	end
	for _, connection in visual.Connections do
		connection:Disconnect()
	end
	for _, t in visual.Tracks do
		t:Stop(0)
		t:Destroy()
	end
	visuals[model :: Model] = nil
end

------------------------------------------------------------ Público
local shakeFn: ((number, number) -> ())? = nil

function EnemyVisualsController.Shake(strength: number, duration: number)
	if shakeFn then
		shakeFn(strength, duration)
	end
end

-- Impacto confirmado por el servidor: destello y aplastamiento breve.
function EnemyVisualsController.OnHit(model: Model, crit: boolean)
	local visual = visuals[model]
	if visual == nil or visual.Dying then
		return
	end
	visual.FlashUntil = os.clock() + FX.HitFlashTime * (if crit then 1.6 else 1)
	if visual.Kind == "Slime" then
		if visual.Body then
			visual.Body.Color = Color3.new(1, 1, 1)
		end
	else
		FxPool.Flash(model, if crit then Color3.fromRGB(255, 190, 90) else Color3.new(1, 1, 1), FX.HitFlashTime)
	end
end

function EnemyVisualsController.OnDied(model: Model?, position: Vector3, color: Color3, enemyId: string?)
	local def = enemyId and EnemyConfig[enemyId]
	local big = def and def.Scale > 1.5
	FxPool.Emit("DeathBurst", position, if big then 40 else FX.DeathBurstParticles, color)
	Sfx.PlayAt("EnemyDeath", position, if big then 0.7 else 0.9 + math.random() * 0.25, 110)
	if big then
		FxPool.Ring(position - Vector3.new(0, 2, 0), 4, 26, 0.6, color, 0.3, 0.3)
		EnemyVisualsController.Shake(0.4, 0.2)
	end
	local visual = model and visuals[model]
	if visual == nil or visual.Dying then
		return
	end
	visual.Dying = true
	visual.DyingAt = os.clock()
	if visual.Bar then
		visual.Bar.Enabled = false
	end
	if visual.Telegraph then
		visual.Telegraph.Transparency = 1
	end
	if visual.Kind == "Skeleton" then
		for _, t in visual.Tracks do
			t:Stop(0.1)
		end
		if not ragdoll(visual) then
			-- Sin cupo de piezas con física: se hunde y se desvanece.
			for _, part in visual.Parts do
				TweenService:Create(part, TweenInfo.new(0.4), { LocalTransparencyModifier = 1 }):Play()
			end
		end
	end
end

------------------------------------------------------------- Bucle
local function updateSlime(visual: Visual, now: number, sNow: number, dt: number)
	local weld, mesh, body = visual.Weld, visual.Mesh, visual.Body
	if weld == nil or mesh == nil or body == nil then
		return
	end
	local s = visual.Scale
	local halfHeight = 1.5 * s
	local sx, sy, offsetY = 1, 1, 0
	local tint: Color3? = nil
	local elapsed = sNow - visual.StateAt
	local duration = math.max(visual.StateDuration, 0.01)
	local p = math.clamp(elapsed / duration, 0, 1)
	local state = visual.State
	local def = visual.Def
	local extrasAlpha = 0

	if visual.Dying then
		local t = math.clamp((now - visual.DyingAt) / 0.35, 0, 1)
		sx = 1 + 0.6 * t
		sy = math.max(0.05, 1 - 0.95 * t)
		extrasAlpha = t
		body.LocalTransparencyModifier = t * t
	elseif state == "Spawning" then
		local e = easeOutBack(p)
		sx, sy = 0.05 + 0.95 * e, 0.05 + 0.95 * e
		offsetY = -halfHeight * (1 - p)
		extrasAlpha = 1 - p
	elseif state == "Windup" then
		local crouch = p * p
		sy = 1 - 0.32 * crouch
		sx = 1 + 0.22 * crouch
		offsetY = math.sin(now * 60) * 0.06 * crouch * s
		tint = WARNING:Lerp(visual.BodyColor, 1 - 0.65 * crouch)
	elseif state == "Recover" and def.AttackKind == "Lunge" then
		local jump = elapsed / (COMBAT.RecoverTime * 0.45)
		if jump < 1 then
			offsetY = math.sin(jump * math.pi) * 1.9 * s
			sy = 1 + 0.25 * math.sin(jump * math.pi)
			sx = 1 - 0.12 * math.sin(jump * math.pi)
		else
			local land = math.clamp((jump - 1) * 3, 0, 1)
			sy = 1 - 0.2 * (1 - land)
			sx = 1 + 0.14 * (1 - land)
		end
	elseif state == "Recover" and def.AttackKind == "Slam" then
		local slam = math.clamp(elapsed / 0.25, 0, 1)
		sy = 0.55 + 0.45 * slam
		sx = 1.35 - 0.35 * slam
	elseif state == "Stagger" then
		sx = 1.22 - 0.22 * p
		sy = 0.82 + 0.18 * p
	else
		local moving = visual.Speed > 1 and not visual.Root.Anchored
		local frequency = def.HopFrequency
		if moving and frequency then
			-- Mismo reloj y semilla que el servidor: el salto coincide con el avance real.
			local wave = math.sin(TAU * (sNow * frequency + visual.HopSeed))
			if wave > 0 then
				offsetY = wave * 1.05 * s
				sy = 1 + 0.12 * wave
				sx = 1 - 0.06 * wave
			else
				local land = -wave
				sy = 1 - 0.17 * land
				sx = 1 + 0.1 * land
			end
		else
			local breathe = math.sin(now * 3 + visual.HopSeed * TAU)
			sy = 1 + 0.04 * breathe
			sx = 1 - 0.02 * breathe
		end
	end

	-- El cuerpo se escala desde su centro: se corrige la altura para que apoye en el suelo.
	offsetY -= (1 - sy) * halfHeight
	weld.C0 = visual.BaseC0 * CFrame.new(0, offsetY, 0)
	mesh.Scale = Vector3.new(sx, sy, sx)
	if extrasAlpha > 0 or visual.Extras[1] and visual.Extras[1].LocalTransparencyModifier > 0 then
		setLocalTransparency(visual.Extras, extrasAlpha)
	end
	if visual.FlashUntil > now then
		body.Color = Color3.new(1, 1, 1)
	elseif tint then
		body.Color = tint
	elseif body.Color ~= visual.BodyColor then
		body.Color = visual.BodyColor
	end
	local telegraph = visual.Telegraph
	if telegraph and (state ~= "Windup" or visual.Dying) then
		visual.Telegraph = nil
	end
	local _ = dt
end

local function updateSkeleton(visual: Visual, _now: number, sNow: number)
	local weld = visual.RigWeld
	if weld == nil or visual.Dying then
		return
	end
	if next(visual.Tracks) == nil then
		loadTracks(visual)
	end
	local elapsed = sNow - visual.StateAt
	local duration = math.max(visual.StateDuration, 0.01)
	local p = math.clamp(elapsed / duration, 0, 1)
	local state = visual.State
	local offset = CFrame.new()
	if state == "Spawning" then
		-- Emerge del suelo.
		offset = CFrame.new(0, -5.2 * visual.Scale * (1 - easeOutBack(p) ^ 0.7), 0)
		setLocalTransparency(visual.Parts, (1 - p) * 0.6)
	elseif state == "Stagger" then
		offset = CFrame.Angles(math.sin(p * math.pi) * 0.32, 0, 0)
	elseif visual.Parts[1] and visual.Parts[1].LocalTransparencyModifier > 0 then
		setLocalTransparency(visual.Parts, 0)
	end
	weld.C0 = visual.RigBaseC0 * offset

	if state == "Chase" or state == "Recover" or state == "Stagger" then
		local speed = visual.Speed
		if speed > 13 then
			playLoop(visual, "Run", math.clamp(speed / 16, 0.7, 1.5))
		elseif speed > 0.8 then
			playLoop(visual, "Walk", math.clamp(speed / 8.5, 0.5, 1.8))
		else
			playLoop(visual, "Idle", 1)
		end
	elseif state == "Windup" or state == "Spawning" then
		playLoop(visual, "Idle", 1)
	end
end

local function update(dt: number)
	debug.profilebegin("SkyBonk.EnemyVisuals")
	local now = os.clock()
	local sNow = serverNow()
	for model, visual in visuals do
		if model.Parent == nil then
			untrack(model)
			continue
		end
		-- Velocidad horizontal medida (suavizada) para decidir la animación.
		local position = visual.Root.Position
		local delta = position - visual.LastPosition
		visual.LastPosition = position
		if dt > 0 then
			local instant = Vector3.new(delta.X, 0, delta.Z).Magnitude / dt
			visual.Speed += (instant - visual.Speed) * math.min(1, dt * 10)
		end
		if visual.Kind == "Slime" then
			updateSlime(visual, now, sNow, dt)
		else
			updateSkeleton(visual, now, sNow)
		end
	end
	debug.profileend()
end

function EnemyVisualsController.Init(controllers)
	shakeFn = controllers.CameraController.Shake
end

function EnemyVisualsController.Start()
	task.spawn(function()
		local list = {}
		for _, id in { ANIMS.SkeletonIdle, ANIMS.SkeletonWalk, ANIMS.SkeletonRun, ANIMS.SkeletonAttack } do
			table.insert(list, animation(id))
		end
		pcall(ContentProvider.PreloadAsync, ContentProvider, list)
	end)
	local enemies = Workspace:WaitForChild("ActiveEnemies")
	enemies.ChildAdded:Connect(function(child)
		task.spawn(track, child)
	end)
	enemies.ChildRemoved:Connect(untrack)
	for _, child in enemies:GetChildren() do
		task.spawn(track, child)
	end
	RunService.RenderStepped:Connect(update)
end

return EnemyVisualsController
