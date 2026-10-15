--[[
	CombatEffectsController
	Presentación local de todo lo que calcula el servidor. Nada de lo que
	ocurre aquí afecta al resultado de la partida.

	  • Hojas de la Espada del Vendaval (proyectil visual con estela).
	  • Números de daño, destello de impacto y chispas.
	  • Explosión al morir un enemigo.
	  • Gemas que vuelan hacia el jugador al recogerlas.
	  • Aura y anillo al subir de nivel; resalte rojo al recibir daño.
	  • Animación de rebote de los slimes, barras de vida y giro de las gemas.

	Todo se anima desde un único RenderStepped y los objetos temporales
	(hojas y números de daño) se reutilizan mediante pools.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local WeaponConfig = require(Shared.Config.WeaponConfig)
local Net = require(Shared.Net)
local Sfx = require(script.Parent.Parent.Util.Sfx)

local CombatEffectsController = {}

local FX = GameConfig.Effects
local player = Players.LocalPlayer

local effectsFolder: Folder
local anchorPart: Part -- se mueve a cada posición antes de emitir partículas
local numbersAnchor: Part -- fijo en el origen; sostiene los adjuntos de los números
local hitEmitter: ParticleEmitter
local burstEmitter: ParticleEmitter
local sparkleEmitter: ParticleEmitter
local damageHighlight: Highlight

-- Animaciones activas (una sola actualización por frame para todas).
type Blade = { Part: BasePart, Trail: Trail, From: Vector3, To: Vector3, Start: number, Hit: any, Spin: number }
type FlyingGem = { Part: BasePart, From: Vector3, Start: number }
type EnemyVisual = {
	Model: Model,
	Weld: Weld?,
	BaseC0: CFrame,
	Mesh: SpecialMesh?,
	Body: BasePart?,
	BodyColor: Color3,
	Fill: Frame?,
	Phase: number,
	FlashUntil: number,
	Connection: RBXScriptConnection?,
}
type GemVisual = { Part: BasePart, Base: CFrame, Phase: number }

local blades: { Blade } = {}
local flyingGems: { FlyingGem } = {}
local enemyVisuals: { [Model]: EnemyVisual } = {}
local gemVisuals: { [BasePart]: GemVisual } = {}

local bladePool: { Blade } = {}
local numberPool: { { Attachment: Attachment, Gui: BillboardGui, Label: TextLabel } } = {}
local gemComboUntil = 0
local gemCombo = 0

local function rootPosition(): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return root and (root :: BasePart).Position
end

local function makeEmitter(name: string, props: { [string]: any }): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = name
	emitter.Enabled = false
	emitter.LightEmission = 0.8
	emitter.LockedToPart = false
	for key, value in props do
		(emitter :: any)[key] = value
	end
	emitter.Parent = anchorPart
	return emitter
end

local function emitAt(emitter: ParticleEmitter, position: Vector3, count: number, color: Color3?)
	anchorPart.CFrame = CFrame.new(position)
	if color then
		emitter.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	end
	emitter:Emit(count)
end

------------------------------------------------------------------ Números
local function acquireNumber()
	local entry = table.remove(numberPool)
	if entry then
		return entry
	end
	local attachment = Instance.new("Attachment")
	attachment.Parent = numbersAnchor
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(90, 40)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 140
	gui.Adornee = attachment
	gui.Parent = attachment
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextSize = 26
	label.TextStrokeTransparency = 0.2
	label.Parent = gui
	return { Attachment = attachment, Gui = gui, Label = label }
end

local function showDamageNumber(position: Vector3, amount: number, killed: boolean)
	local entry = acquireNumber()
	entry.Attachment.WorldPosition = position + Vector3.new((math.random() - 0.5) * 1.5, 2.5, 0)
	entry.Label.Text = tostring(math.max(1, math.floor(amount + 0.5)))
	entry.Label.TextColor3 = if killed then Color3.fromRGB(255, 214, 90) else Color3.fromRGB(255, 255, 255)
	entry.Label.TextSize = if killed then 30 else 24
	entry.Label.TextTransparency = 0
	entry.Label.TextStrokeTransparency = 0.2
	entry.Gui.StudsOffset = Vector3.zero
	entry.Gui.Enabled = true
	local info = TweenInfo.new(FX.DamageNumberLifetime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(entry.Gui, info, { StudsOffset = Vector3.new(0, 2.2, 0) }):Play()
	TweenService:Create(entry.Label, info, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	task.delay(FX.DamageNumberLifetime, function()
		entry.Gui.Enabled = false
		table.insert(numberPool, entry)
	end)
end

------------------------------------------------------------------- Hojas
local function acquireBlade(color: Color3): Blade
	local blade = table.remove(bladePool)
	if blade == nil then
		local part = Instance.new("Part")
		part.Name = "GaleBlade"
		part.Size = Vector3.new(0.25, 0.25, 2.8)
		part.Material = Enum.Material.Neon
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(0, 0, -1.3)
		a0.Parent = part
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(0, 0, 1.3)
		a1.Parent = part
		local trail = Instance.new("Trail")
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.Lifetime = 0.16
		trail.LightEmission = 1
		trail.FaceCamera = true
		trail.Transparency = NumberSequence.new(0.2, 1)
		trail.Parent = part
		blade = { Part = part, Trail = trail, From = Vector3.zero, To = Vector3.zero, Start = 0, Hit = nil, Spin = 0 }
	end
	local b = blade :: Blade
	b.Part.Color = color
	b.Trail.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	return b
end

local function releaseBlade(blade: Blade)
	blade.Trail.Enabled = false
	blade.Part.Parent = nil
	blade.Hit = nil
	table.insert(bladePool, blade)
end

local function onBladeArrived(blade: Blade)
	local hit = blade.Hit
	if hit == nil then
		return
	end
	emitAt(hitEmitter, blade.To, 6)
	showDamageNumber(blade.To, hit.Damage, hit.Killed)
	local visual = hit.Model and enemyVisuals[hit.Model]
	if visual and visual.Body then
		visual.FlashUntil = os.clock() + FX.HitFlashTime
		visual.Body.Color = Color3.new(1, 1, 1)
	end
end

local function onCombatFx(attack)
	if type(attack) ~= "table" or type(attack.Hits) ~= "table" or typeof(attack.Origin) ~= "Vector3" then
		return
	end
	local weapon = WeaponConfig[attack.WeaponId]
	local color = weapon and weapon.Color or Color3.new(1, 1, 1)
	local origin = (rootPosition() or attack.Origin) + Vector3.new(0, 1.2, 0)
	Sfx.Play("Attack", 0.95 + math.random() * 0.15)
	for index, hit in attack.Hits do
		if typeof(hit.Position) ~= "Vector3" then
			continue
		end
		local blade = acquireBlade(color)
		blade.From = origin
		blade.To = hit.Position + Vector3.new(0, 0.8, 0)
		blade.Start = os.clock() + (index - 1) * 0.04
		blade.Hit = hit
		blade.Spin = math.random() * math.pi
		blade.Part.CFrame = CFrame.lookAt(blade.From, blade.To)
		blade.Part.Parent = effectsFolder
		blade.Trail:Clear()
		blade.Trail.Enabled = true
		table.insert(blades, blade)
	end
	task.delay(FX.BladeTravelTime, function()
		Sfx.Play("Hit", 0.9 + math.random() * 0.2)
	end)
end

------------------------------------------------------------- Enemigos
local function trackEnemy(model: Instance)
	if not model:IsA("Model") or enemyVisuals[model] then
		return
	end
	local body = model:FindFirstChild("Body") :: BasePart?
	local weld = body and body:FindFirstChild("BodyWeld") :: Weld?
	local mesh = body and body:FindFirstChild("BodyMesh") :: SpecialMesh?
	local root = model:FindFirstChild("Root")
	local bar = root and root:FindFirstChild("HealthBar")
	local fill = bar and bar:FindFirstChild("Back") and bar.Back:FindFirstChild("Fill") :: Frame?

	local visual: EnemyVisual = {
		Model = model,
		Weld = weld,
		BaseC0 = weld and weld.C0 or CFrame.new(),
		Mesh = mesh,
		Body = body,
		BodyColor = body and body.Color or Color3.new(1, 1, 1),
		Fill = fill,
		Phase = math.random() * math.pi * 2,
		FlashUntil = 0,
		Connection = nil,
	}
	local function updateBar()
		local health = model:GetAttribute("Health")
		local maxHealth = model:GetAttribute("MaxHealth")
		if fill and type(health) == "number" and type(maxHealth) == "number" and maxHealth > 0 then
			fill.Size = UDim2.fromScale(math.clamp(health / maxHealth, 0, 1), 1)
		end
	end
	visual.Connection = model:GetAttributeChangedSignal("Health"):Connect(updateBar)
	updateBar()
	enemyVisuals[model] = visual
end

local function untrackEnemy(model: Instance)
	local visual = enemyVisuals[model :: Model]
	if visual then
		if visual.Connection then
			visual.Connection:Disconnect()
		end
		enemyVisuals[model :: Model] = nil
	end
end

local function onEnemyDied(info)
	if type(info) ~= "table" or typeof(info.Position) ~= "Vector3" then
		return
	end
	local color = if typeof(info.Color) == "Color3" then info.Color else Color3.fromRGB(150, 80, 230)
	emitAt(burstEmitter, info.Position, FX.DeathBurstParticles, color)
	Sfx.Play("EnemyDeath", 0.9 + math.random() * 0.25)
end

------------------------------------------------------------------- Gemas
local function trackGem(part: Instance)
	if part:IsA("BasePart") and not gemVisuals[part] then
		gemVisuals[part] = { Part = part, Base = part.CFrame, Phase = math.random() * math.pi * 2 }
	end
end

local function untrackGem(part: Instance)
	gemVisuals[part :: BasePart] = nil
end

local function onGemCollected(info)
	if type(info) ~= "table" or type(info.Positions) ~= "table" then
		return
	end
	local now = os.clock()
	gemCombo = if now < gemComboUntil then math.min(gemCombo + 1, 12) else 0
	gemComboUntil = now + 0.6
	Sfx.Play("GemPickup", 1 + gemCombo * 0.05)
	for index, position in info.Positions do
		if typeof(position) ~= "Vector3" or index > 12 then
			continue
		end
		local part = Instance.new("Part")
		part.Size = Vector3.new(0.6, 0.9, 0.6)
		part.Material = Enum.Material.Neon
		part.Color = Color3.fromRGB(80, 240, 255)
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.CFrame = CFrame.new(position)
		part.Parent = effectsFolder
		table.insert(flyingGems, { Part = part, From = position, Start = now })
	end
end

-------------------------------------------------------------- Jugador
local function onLevelUp()
	local position = rootPosition()
	Sfx.Play("LevelUp")
	if position == nil then
		return
	end
	emitAt(sparkleEmitter, position, 40)
	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.3, 4, 4)
	ring.CFrame = CFrame.new(position - Vector3.new(0, 2.5, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(255, 214, 90)
	ring.Transparency = 0.2
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Parent = effectsFolder
	TweenService:Create(ring, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.3, 26, 26),
		Transparency = 1,
	}):Play()
	task.delay(0.65, function()
		ring:Destroy()
	end)
end

local highlightToken = 0
local function onPlayerDamaged()
	Sfx.Play("PlayerHurt", 0.95 + math.random() * 0.1)
	local character = player.Character
	if character == nil then
		return
	end
	highlightToken += 1
	local token = highlightToken
	damageHighlight.Adornee = character
	damageHighlight.Enabled = true
	task.delay(0.15, function()
		if token == highlightToken then
			damageHighlight.Enabled = false
		end
	end)
end

--------------------------------------------------------- Bucle visual
local function update()
	local now = os.clock()

	-- Hojas en vuelo (arco ligero + giro).
	for index = #blades, 1, -1 do
		local blade = blades[index]
		local t = (now - blade.Start) / FX.BladeTravelTime
		if t >= 1 then
			table.remove(blades, index)
			onBladeArrived(blade)
			releaseBlade(blade)
		elseif t >= 0 then
			local position = blade.From:Lerp(blade.To, t) + Vector3.new(0, math.sin(t * math.pi) * 1.5, 0)
			blade.Part.CFrame = CFrame.lookAt(position, blade.To) * CFrame.Angles(0, 0, blade.Spin + t * 8)
		end
	end

	-- Gemas recogidas volando hacia el jugador.
	local target = rootPosition()
	for index = #flyingGems, 1, -1 do
		local gem = flyingGems[index]
		local t = (now - gem.Start) / FX.GemFlyTime
		if t >= 1 or target == nil then
			gem.Part:Destroy()
			table.remove(flyingGems, index)
		else
			gem.Part.CFrame = CFrame.new(gem.From:Lerp(target :: Vector3, t * t)) * CFrame.Angles(0, t * 10, 0)
			gem.Part.Size = Vector3.new(0.6, 0.9, 0.6) * (1 - t * 0.6)
		end
	end

	-- Rebote de los slimes (solo visual, sobre la soldadura del cuerpo).
	for model, visual in enemyVisuals do
		if model.Parent == nil then
			untrackEnemy(model)
			continue
		end
		local wave = math.sin(now * 7 + visual.Phase)
		if visual.Weld then
			visual.Weld.C0 = visual.BaseC0 * CFrame.new(0, math.abs(wave) * 0.45, 0)
		end
		if visual.Mesh then
			local squash = wave * 0.08
			visual.Mesh.Scale = Vector3.new(1 + squash, 1 - squash, 1 + squash)
		end
		if visual.Body and visual.FlashUntil > 0 and now >= visual.FlashUntil then
			visual.FlashUntil = 0
			visual.Body.Color = visual.BodyColor
		end
	end

	-- Gemas en el suelo: giro y flotación.
	for part, visual in gemVisuals do
		if part.Parent == nil then
			gemVisuals[part] = nil
			continue
		end
		part.CFrame = visual.Base
			* CFrame.new(0, math.sin(now * 3 + visual.Phase) * 0.25, 0)
			* CFrame.Angles(0, now * 2.5, 0)
	end
end

function CombatEffectsController.Init(_controllers) end

function CombatEffectsController.Start()
	effectsFolder = Instance.new("Folder")
	effectsFolder.Name = "ClientEffects"
	effectsFolder.Parent = Workspace

	anchorPart = Instance.new("Part")
	anchorPart.Name = "FxAnchor"
	anchorPart.Size = Vector3.new(0.2, 0.2, 0.2)
	anchorPart.Transparency = 1
	anchorPart.Anchored = true
	anchorPart.CanCollide = false
	anchorPart.CanQuery = false
	anchorPart.CanTouch = false
	anchorPart.Parent = effectsFolder
	numbersAnchor = anchorPart:Clone()
	numbersAnchor.Name = "NumbersAnchor"
	numbersAnchor.CFrame = CFrame.new()
	numbersAnchor.Parent = effectsFolder

	hitEmitter = makeEmitter("HitSparks", {
		Color = ColorSequence.new(Color3.fromRGB(180, 250, 255), Color3.new(1, 1, 1)),
		Size = NumberSequence.new(0.6, 0),
		Lifetime = NumberRange.new(0.2, 0.35),
		Speed = NumberRange.new(12, 20),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 6,
	})
	burstEmitter = makeEmitter("DeathBurst", {
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.1), NumberSequenceKeypoint.new(1, 0) }),
		Lifetime = NumberRange.new(0.35, 0.6),
		Speed = NumberRange.new(10, 18),
		SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0, -30, 0),
		Drag = 3,
	})
	sparkleEmitter = makeEmitter("LevelSparkles", {
		Color = ColorSequence.new(Color3.fromRGB(255, 220, 110), Color3.fromRGB(120, 240, 255)),
		Size = NumberSequence.new(0.8, 0),
		Lifetime = NumberRange.new(0.6, 1),
		Speed = NumberRange.new(6, 14),
		SpreadAngle = Vector2.new(60, 60),
		EmissionDirection = Enum.NormalId.Top,
		Acceleration = Vector3.new(0, 8, 0),
	})

	damageHighlight = Instance.new("Highlight")
	damageHighlight.Name = "DamageHighlight"
	damageHighlight.FillColor = Color3.fromRGB(255, 60, 60)
	damageHighlight.FillTransparency = 0.45
	damageHighlight.OutlineTransparency = 1
	damageHighlight.DepthMode = Enum.HighlightDepthMode.Occluded
	damageHighlight.Enabled = false
	damageHighlight.Parent = effectsFolder

	Sfx.Preload()

	local enemies = Workspace:WaitForChild("ActiveEnemies")
	enemies.ChildAdded:Connect(trackEnemy)
	enemies.ChildRemoved:Connect(untrackEnemy)
	for _, child in enemies:GetChildren() do
		trackEnemy(child)
	end
	local orbs = Workspace:WaitForChild("ExperienceOrbs")
	orbs.ChildAdded:Connect(trackGem)
	orbs.ChildRemoved:Connect(untrackGem)
	for _, child in orbs:GetChildren() do
		trackGem(child)
	end

	Net.CombatFx.OnClientEvent:Connect(onCombatFx)
	Net.EnemyDied.OnClientEvent:Connect(onEnemyDied)
	Net.GemCollected.OnClientEvent:Connect(onGemCollected)
	Net.LevelUp.OnClientEvent:Connect(onLevelUp)
	Net.PlayerDamaged.OnClientEvent:Connect(onPlayerDamaged)

	RunService.RenderStepped:Connect(update)
end

return CombatEffectsController
