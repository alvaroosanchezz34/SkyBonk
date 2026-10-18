--[[
	CombatEffectsController
	Presentación local de lo que calcula el servidor. Nada de lo que ocurre
	aquí afecta al resultado de la partida.

	  • Espada del Vendaval: tajo (animación de Roblox "R15 Sword Slash") con
	    estela; la velocidad del tajo sigue al enfriamiento real sin pasar de
	    MaxSlashSpeed. Las hojas salen al final de la anticipación y llegan a su
	    objetivo cuando el servidor aplica el impacto (CombatHits).
	  • Filo de Tormenta: rayos entre los objetivos encadenados.
	  • Impactos confirmados: chispas, números de daño (críticos destacados),
	    sonido y reacción del enemigo (EnemyVisualsController).
	  • Gemas: aparición con salto, flotación, vuelo hacia el jugador mientras
	    el servidor las atrae, y destello al recogerlas.
	  • Subida de nivel, rotura de Cristales de Esencia y daño recibido.
	  • La espada brilla más con cada hoja extra y chispea con Filo de Tormenta.

	Todo se anima desde un único RenderStepped; hojas, rayos y números de daño
	se reutilizan mediante pools.
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
local VisualConfig = require(Shared.Config.VisualConfig)
local Sfx = require(script.Parent.Parent.Util.Sfx)
local FxPool = require(script.Parent.Parent.Util.FxPool)

local CombatEffectsController = {}

local FX = GameConfig.Effects
local EXP = GameConfig.Experience
local player = Players.LocalPlayer

local controllers
local effectsFolder: Folder
local numbersAnchor: Part
local damageHighlight: Highlight

type Blade = {
	Part: BasePart,
	Trail: Trail,
	From: Vector3,
	Target: Model?,
	Fallback: Vector3,
	Start: number,
	Duration: number,
	Windup: number,
	Spin: number,
	Chain: { any },
}
type Bolt = { Parts: { BasePart }, Until: number }
type GemVisual = { Part: BasePart, Base: CFrame, Phase: number, Born: number, Speed: number, Flying: boolean }
type NumberEntry = { Attachment: Attachment, Gui: BillboardGui, Label: TextLabel, Busy: boolean }

local blades: { Blade } = {}
local bladePool: { Blade } = {}
local bolts: { Bolt } = {}
local boltPool: { BasePart } = {}
local gemVisuals: { [BasePart]: GemVisual } = {}
local numberPool: { NumberEntry } = {}
local numbersInUse = 0
local gemComboUntil = 0
local gemCombo = 0

-- Animación del tajo del jugador.
local slashAnimations: { Animation } = {}
local slashTracks: { AnimationTrack } = {}
local slashIndex = 0
local swordTrail: Trail? = nil
local swordTrailUntil = 0
local swordGlow = 0
local slashSide = 1 -- alterna tajos de izquierda a derecha y al revés
local lastCritKickAt = 0
local SWORD = VisualConfig.Weapons.GaleSword

local function character(): Model?
	return player.Character
end

local function rootPart(): BasePart?
	local c = character()
	return c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function modelPosition(model: Model?): Vector3?
	if model == nil or model.Parent == nil then
		return nil
	end
	local root = model.PrimaryPart
	return root and root.Position
end

------------------------------------------------------------------ Números
local function acquireNumber(): NumberEntry?
	if numbersInUse >= FX.MaxDamageNumbers then
		return nil -- demasiados a la vez: se omite (no se tapa el combate)
	end
	local entry = table.remove(numberPool)
	if entry == nil then
		local attachment = Instance.new("Attachment")
		attachment.Parent = numbersAnchor
		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.fromOffset(110, 44)
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
		entry = { Attachment = attachment, Gui = gui, Label = label, Busy = false }
	end
	numbersInUse += 1
	return entry
end

local function showDamageNumber(position: Vector3, amount: number, killed: boolean, crit: boolean, chain: boolean)
	local entry = acquireNumber()
	if entry == nil then
		return
	end
	entry.Attachment.WorldPosition = position
		+ Vector3.new((math.random() - 0.5) * 1.6, 2.6, (math.random() - 0.5) * 1.6)
	local text = tostring(math.max(1, math.floor(amount + 0.5)))
	entry.Label.Text = if crit then text .. "!" else text
	entry.Label.TextColor3 = if crit
		then Color3.fromRGB(255, 150, 60)
		elseif killed then Color3.fromRGB(255, 214, 90)
		elseif chain then Color3.fromRGB(170, 190, 255)
		else Color3.fromRGB(255, 255, 255)
	local size = if crit then 36 elseif killed then 29 elseif chain then 21 else 24
	entry.Label.TextSize = size * 0.6
	entry.Label.TextTransparency = 0
	entry.Label.TextStrokeTransparency = 0.2
	entry.Gui.StudsOffset = Vector3.zero
	entry.Gui.Enabled = true
	local life = FX.DamageNumberLifetime * (if crit then 1.3 else 1)
	TweenService
		:Create(entry.Label, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { TextSize = size })
		:Play()
	local info = TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(entry.Gui, info, { StudsOffset = Vector3.new(0, 2.4, 0) }):Play()
	TweenService:Create(
		entry.Label,
		TweenInfo.new(life * 0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, life * 0.5),
		{
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		}
	):Play()
	task.delay(life, function()
		entry.Gui.Enabled = false
		numbersInUse -= 1
		table.insert(numberPool, entry)
	end)
end

------------------------------------------------------------------- Hojas
local function acquireBlade(color: Color3, scale: number): Blade
	local blade = table.remove(bladePool)
	if blade == nil then
		local part = Instance.new("Part")
		part.Name = "GaleBlade"
		part.Material = Enum.Material.Neon
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = part
		local a0 = Instance.new("Attachment")
		a0.Name = "A0"
		a0.Parent = part
		local a1 = Instance.new("Attachment")
		a1.Name = "A1"
		a1.Parent = part
		local trail = Instance.new("Trail")
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.Lifetime = 0.18
		trail.LightEmission = 1
		trail.FaceCamera = true
		trail.Transparency = NumberSequence.new(0.1, 1)
		trail.WidthScale = NumberSequence.new(1, 0.2)
		trail.Parent = part
		blade = {
			Part = part,
			Trail = trail,
			From = Vector3.zero,
			Target = nil,
			Fallback = Vector3.zero,
			Start = 0,
			Duration = 0.2,
			Windup = 0.1,
			Spin = 0,
			Chain = {},
		}
	end
	local b = blade :: Blade
	-- Hoja en forma de media luna: ancha y plana (se lee como un corte de viento).
	b.Part.Size = Vector3.new(2.6 * scale, 0.2, 0.9 * scale)
	local a0 = b.Part:FindFirstChild("A0") :: Attachment
	local a1 = b.Part:FindFirstChild("A1") :: Attachment
	a0.Position = Vector3.new(-1.2 * scale, 0, 0)
	a1.Position = Vector3.new(1.2 * scale, 0, 0)
	b.Part.Color = color
	b.Trail.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	return b
end

local function releaseBlade(blade: Blade)
	blade.Trail.Enabled = false
	blade.Part.Parent = nil
	blade.Target = nil
	blade.Chain = {}
	table.insert(bladePool, blade)
end

-- Rayo quebrado entre dos puntos (Filo de Tormenta).
local function drawBolt(from: Vector3, to: Vector3)
	local parts: { BasePart } = {}
	local segments = 4
	local previous = from
	for i = 1, segments do
		local t = i / segments
		local point = from:Lerp(to, t)
		if i < segments then
			point += Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 1.6
		end
		local part = table.remove(boltPool)
		if part == nil then
			local created = Instance.new("Part")
			created.Name = "Bolt"
			created.Material = Enum.Material.Neon
			created.Color = Color3.fromRGB(190, 200, 255)
			created.Anchored = true
			created.CanCollide = false
			created.CanQuery = false
			created.CanTouch = false
			created.CastShadow = false
			part = created
		end
		local p = part :: BasePart
		local length = (point - previous).Magnitude
		p.Size = Vector3.new(0.18, 0.18, length)
		p.CFrame = CFrame.lookAt((previous + point) / 2, point)
		p.Transparency = 0
		p.Parent = effectsFolder
		table.insert(parts, p)
		previous = point
	end
	table.insert(bolts, { Parts = parts, Until = os.clock() + 0.12 })
	FxPool.Emit("Spark", to, 6)
end

-- La hoja ha llegado: chispa y rayos (el daño y el número llegan con CombatHits).
local function onBladeArrived(blade: Blade, position: Vector3)
	FxPool.Emit("HitSparks", position, 5)
	local previous = position
	for _, link in blade.Chain do
		local delay = math.max(0, link.Delay - blade.Duration - blade.Windup)
		local fromPoint = previous
		task.delay(delay, function()
			local target = modelPosition(link.Model) or link.Position
			drawBolt(fromPoint + Vector3.new(0, 0.6, 0), target + Vector3.new(0, 0.6, 0))
			Sfx.PlayAt("Chain", target, 1.1)
		end)
		previous = modelPosition(link.Model) or link.Position
	end
end

------------------------------------------------------------ Tajo jugador
local function swordOf(c: Model?): Model?
	return c and c:FindFirstChild("GaleSword") :: Model?
end

local function ensureSwordTrail(): Trail?
	local sword = swordOf(character())
	local blade = sword and sword:FindFirstChild("Blade")
	if blade == nil then
		return nil
	end
	local existing = blade:FindFirstChild("SlashTrail") :: Trail?
	if existing then
		return existing
	end
	local trail = Instance.new("Trail")
	trail.Name = "SlashTrail"
	trail.Attachment0 = blade:FindFirstChild("TrailBase") :: Attachment
	trail.Attachment1 = blade:FindFirstChild("TrailTip") :: Attachment
	trail.Lifetime = 0.16
	trail.LightEmission = 1
	trail.Color = ColorSequence.new(Color3.fromRGB(150, 240, 255), Color3.new(1, 1, 1))
	trail.Transparency = NumberSequence.new(0.15, 1)
	trail.Enabled = false
	trail.Parent = blade
	return trail
end

local function loadSlashTracks()
	table.clear(slashTracks)
	local c = character()
	local humanoid = c and c:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if humanoid == nil or animator == nil or humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		return -- R6: la espada y las hojas siguen funcionando, sin animación de brazo
	end
	for _, anim in slashAnimations do
		local ok, t = pcall(animator.LoadAnimation, animator, anim)
		if ok and t then
			t.Priority = Enum.AnimationPriority.Action
			t.Looped = false
			table.insert(slashTracks, t)
		end
	end
end

local function playSlash(cooldown: number)
	if #slashTracks == 0 then
		loadSlashTracks()
	end
	slashIndex = slashIndex % math.max(1, #slashTracks) + 1
	local t = slashTracks[slashIndex]
	if t then
		-- El tajo ocupa como mucho el 85 % del enfriamiento y nunca va más rápido de MaxSlashSpeed.
		local length = if t.Length > 0 then t.Length else 0.6
		local speed = math.clamp(length / math.max(0.15, cooldown * 0.85), 1, FX.MaxSlashSpeed)
		t:Play(0.05, 1, speed)
	end
	swordTrail = swordTrail or ensureSwordTrail()
	if swordTrail and swordTrail.Parent then
		swordTrail.Enabled = true
		swordTrailUntil = os.clock() + 0.28
	else
		swordTrail = nil
	end
end

local function swordTip(): Vector3?
	local sword = swordOf(character())
	local blade = sword and sword:FindFirstChild("Blade") :: BasePart?
	return blade and (blade.CFrame * CFrame.new(0, 0, -1.2)).Position
end

local function onCombatFx(attack)
	if type(attack) ~= "table" or type(attack.Shots) ~= "table" or typeof(attack.Origin) ~= "Vector3" then
		return
	end
	local weapon = WeaponConfig[attack.WeaponId]
	local color = weapon and weapon.Color or Color3.new(1, 1, 1)
	local windup = if type(attack.Windup) == "number" then attack.Windup else 0.1
	local cooldown = if type(attack.Cooldown) == "number" then attack.Cooldown else 1
	playSlash(cooldown)
	task.delay(windup * 0.6, function()
		Sfx.Play("Attack", 1 + (#attack.Shots - 1) * 0.04)
	end)
	-- Corte en media luna en el instante del tajo, orientado al primer objetivo.
	local firstShot = attack.Shots[1]
	task.delay(windup * 0.8, function()
		local root = rootPart()
		if root == nil or firstShot == nil or typeof(firstShot.Position) ~= "Vector3" then
			return
		end
		local chest = root.Position + Vector3.new(0, 1.1, 0)
		local target = Vector3.new(firstShot.Position.X, chest.Y, firstShot.Position.Z)
		if (target - chest).Magnitude < 0.5 then
			return
		end
		local facing = CFrame.lookAt(chest, target)
		slashSide = -slashSide
		local radius = 3.2 * (1 + swordGlow * 0.1)
		FxPool.Slash(
			facing * CFrame.new(0, 0, -2.4),
			radius,
			SWORD.Slash,
			slashSide * (0.3 + math.random() * 0.25),
			0.2
		)
	end)
	local now = os.clock()
	local scale = 1 + swordGlow * 0.08
	for index, shot in attack.Shots do
		if typeof(shot.Position) ~= "Vector3" or type(shot.Delay) ~= "number" then
			continue
		end
		local blade = acquireBlade(color, scale)
		local origin = (rootPart() and (rootPart() :: BasePart).Position or attack.Origin) + Vector3.new(0, 1.4, 0)
		blade.From = origin
		blade.Target = if typeof(shot.Model) == "Instance" then shot.Model else nil
		blade.Fallback = shot.Position
		blade.Start = now + windup + (index - 1) * 0.015
		blade.Duration = math.max(0.06, shot.Delay - windup)
		blade.Spin = math.random() * math.pi
		blade.Chain = if type(shot.Chain) == "table" then shot.Chain else {}
		blade.Windup = windup
		blade.Part.CFrame = CFrame.lookAt(origin, shot.Position)
		blade.Part.Parent = effectsFolder
		blade.Trail:Clear()
		blade.Trail.Enabled = false
		table.insert(blades, blade)
	end
end

local function onCombatHits(payload)
	if type(payload) ~= "table" or type(payload.Hits) ~= "table" then
		return
	end
	local anyCrit, anyKill = false, false
	for _, hit in payload.Hits do
		if typeof(hit.Position) ~= "Vector3" or type(hit.Damage) ~= "number" then
			continue
		end
		local model = if typeof(hit.Model) == "Instance" then hit.Model else nil
		local position = modelPosition(model) or hit.Position
		showDamageNumber(position, hit.Damage, hit.Killed == true, hit.Crit == true, hit.Chain == true)
		local impact = position + Vector3.new(0, 1, 0)
		if hit.Crit then
			-- Crítico: estrella dorada, destello mayor y un pequeño golpe de FOV.
			anyCrit = true
			FxPool.Emit("CritSparks", impact, 10)
			FxPool.Star(impact, SWORD.SlashCrit, 6)
			FxPool.ImpactFlash(impact, SWORD.SlashCrit, 3)
			local now = os.clock()
			if now - lastCritKickAt > 0.4 then
				lastCritKickAt = now
				controllers.CameraController.FovKick(VisualConfig.Camera.CritFovKick, 0.25)
			end
		elseif hit.Chain then
			FxPool.ImpactFlash(impact, Color3.fromRGB(190, 200, 255), 1.6)
		else
			FxPool.ImpactFlash(impact, Color3.new(1, 1, 1), 1.4 + math.random() * 0.8)
		end
		if hit.Killed then
			anyKill = true
			FxPool.Ring(position - Vector3.new(0, 1.3, 0), 1, 6, 0.25, SWORD.Edge, 0.35, 0.12)
		end
		if model then
			controllers.EnemyVisualsController.OnHit(model, hit.Crit == true)
		end
	end
	if anyCrit then
		Sfx.Play("Crit", 1)
	elseif anyKill then
		Sfx.Play("HitHeavy", 0.95 + math.random() * 0.1)
	else
		Sfx.Play("Hit", 1)
	end
end

------------------------------------------------------------------- Gemas
local function trackGem(part: Instance)
	if part:IsA("BasePart") and not gemVisuals[part] then
		gemVisuals[part] = {
			Part = part,
			Base = part.CFrame,
			Phase = math.random() * math.pi * 2,
			Born = os.clock(),
			Speed = EXP.AttractSpeed,
			Flying = false,
		}
		if part.Name == "XpGemLucky" then
			local sparkle = Instance.new("Sparkles")
			sparkle.SparkleColor = Color3.fromRGB(255, 220, 120)
			sparkle.Parent = part
		end
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
	gemCombo = if now < gemComboUntil then math.min(gemCombo + 1, 14) else 0
	gemComboUntil = now + 0.7
	-- La escala sube con las recogidas seguidas: recompensa sonora sin saturar.
	Sfx.Play("GemPickup", 1 + gemCombo * 0.045)
	local root = rootPart()
	if root then
		FxPool.Emit("GemPop", root.Position + Vector3.new(0, 0.5, 0), math.min(4 + #info.Positions * 2, 14))
	end
end

-------------------------------------------------------------- Mundo y jugador
local function onWorldFx(event)
	if type(event) ~= "table" or typeof(event.Position) ~= "Vector3" then
		return
	end
	if event.Kind == "CrystalBreak" then
		local gold = Color3.fromRGB(255, 196, 92)
		FxPool.Emit("DeathBurst", event.Position + Vector3.new(0, 3, 0), 30, gold)
		FxPool.Emit("Sparkles", event.Position + Vector3.new(0, 2, 0), 24)
		FxPool.Ring(event.Position + Vector3.new(0, 0.3, 0), 2, 16, 0.5, gold, 0.2, 0.25)
		Sfx.PlayAt("CrystalBreak", event.Position, 1, 120)
	end
end

local function onLevelUp()
	local root = rootPart()
	Sfx.Play("LevelUp")
	if root == nil then
		return
	end
	local position = root.Position
	FxPool.Emit("Sparkles", position, 46)
	local ground = position - Vector3.new(0, 2.8, 0)
	FxPool.Ring(ground, 4, 30, 0.6, Color3.fromRGB(255, 214, 90), 0.15, 0.3)
	FxPool.Ring(ground, 2, 18, 0.45, Color3.fromRGB(140, 240, 255), 0.3, 0.2)
	-- Columna de luz breve sobre el jugador.
	local pillar = Instance.new("Part")
	pillar.Name = "LevelPillar"
	pillar.Shape = Enum.PartType.Cylinder
	pillar.Size = Vector3.new(40, 5, 5)
	pillar.CFrame = CFrame.new(ground + Vector3.new(0, 20, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	pillar.Material = Enum.Material.Neon
	pillar.Color = Color3.fromRGB(255, 230, 150)
	pillar.Transparency = 0.35
	pillar.Anchored = true
	pillar.CanCollide = false
	pillar.CanQuery = false
	pillar.CanTouch = false
	pillar.CastShadow = false
	pillar.Parent = effectsFolder
	TweenService:Create(pillar, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(40, 0.4, 0.4),
		Transparency = 1,
	}):Play()
	task.delay(0.55, function()
		pillar:Destroy()
	end)
end

local highlightToken = 0
local function onPlayerDamaged()
	Sfx.Play("PlayerHurt")
	local c = character()
	if c == nil then
		return
	end
	highlightToken += 1
	local token = highlightToken
	damageHighlight.Adornee = c
	damageHighlight.Enabled = true
	task.delay(0.15, function()
		if token == highlightToken then
			damageHighlight.Enabled = false
		end
	end)
end

local function onEnemyDied(info)
	if type(info) ~= "table" or typeof(info.Position) ~= "Vector3" then
		return
	end
	local color = if typeof(info.Color) == "Color3" then info.Color else Color3.fromRGB(150, 80, 230)
	local model = if typeof(info.Model) == "Instance" then info.Model else nil
	controllers.EnemyVisualsController.OnDied(model, info.Position, color, info.EnemyId)
end

-- Brillo de la espada según las mejoras (más hojas = más brillo; rayo = chispas).
local function onHud(snapshot)
	if type(snapshot) ~= "table" or type(snapshot.Stats) ~= "table" then
		return
	end
	local projectiles = snapshot.Stats.Projectiles or 1
	local chain = snapshot.Stats.Chain or 0
	swordGlow = math.max(0, projectiles - 1) + chain
	local sword = swordOf(character())
	local edge = sword and sword:FindFirstChild("Edge") :: BasePart?
	if edge then
		edge.Size = Vector3.new(0.12 + 0.04 * swordGlow, 0.12 + 0.04 * swordGlow, 3.2)
		edge.Color = if chain > 0 then Color3.fromRGB(180, 190, 255) else Color3.fromRGB(120, 235, 255)
		local sparks = edge:FindFirstChild("StormSparks") :: ParticleEmitter?
		if chain > 0 and sparks == nil then
			local emitter = Instance.new("ParticleEmitter")
			emitter.Name = "StormSparks"
			emitter.Color = ColorSequence.new(Color3.fromRGB(200, 210, 255))
			emitter.Size = NumberSequence.new(0.18, 0)
			emitter.Lifetime = NumberRange.new(0.1, 0.2)
			emitter.Speed = NumberRange.new(2, 5)
			emitter.SpreadAngle = Vector2.new(180, 180)
			emitter.LightEmission = 1
			emitter.Parent = edge
			sparks = emitter
		end
		if sparks then
			sparks.Rate = chain * 10
		end
	end
end

--------------------------------------------------------- Bucle visual
local function update(dt: number)
	debug.profilebegin("SkyBonk.CombatFx")
	local now = os.clock()

	-- Hojas en vuelo: persiguen la posición actual del objetivo.
	for index = #blades, 1, -1 do
		local blade = blades[index]
		local t = (now - blade.Start) / blade.Duration
		if t < 0 then
			-- Aún en la anticipación: la hoja espera en la punta de la espada.
			local tip = swordTip()
			if tip then
				blade.From = tip
			end
			continue
		end
		local target = (modelPosition(blade.Target) or blade.Fallback) + Vector3.new(0, 0.8, 0)
		if t >= 1 then
			table.remove(blades, index)
			onBladeArrived(blade, target)
			releaseBlade(blade)
		else
			if not blade.Trail.Enabled then
				blade.Trail.Enabled = true
			end
			local eased = 1 - (1 - t) * (1 - t)
			local position = blade.From:Lerp(target, eased) + Vector3.new(0, math.sin(t * math.pi) * 1.2, 0)
			blade.Part.CFrame = CFrame.lookAt(position, target)
				* CFrame.Angles(0, 0, blade.Spin + t * 6)
				* CFrame.Angles(0, math.pi / 2, 0)
		end
	end

	for index = #bolts, 1, -1 do
		local bolt = bolts[index]
		if now >= bolt.Until then
			for _, part in bolt.Parts do
				part.Parent = nil
				table.insert(boltPool, part)
			end
			table.remove(bolts, index)
		end
	end

	if swordTrail and now >= swordTrailUntil then
		swordTrail.Enabled = false
	end

	-- Gemas: aparición con salto, flotación y vuelo hacia el jugador cuando las atrae.
	local root = rootPart()
	for part, visual in gemVisuals do
		if part.Parent == nil then
			gemVisuals[part] = nil
			continue
		end
		if part:GetAttribute("Attracting") and root then
			visual.Flying = true
			visual.Speed += EXP.AttractAcceleration * dt
			local target = root.Position
			local offset = target - visual.Base.Position
			local distance = offset.Magnitude
			local step = math.min(distance, visual.Speed * dt)
			if distance > 1e-3 then
				visual.Base = CFrame.new(visual.Base.Position + offset / distance * step)
			end
			part.CFrame = visual.Base * CFrame.Angles(0, now * 12, 0)
			continue
		end
		local age = now - visual.Born
		local pop = if age < 0.3 then math.sin(age / 0.3 * math.pi) * 1.4 else 0
		part.CFrame = visual.Base
			* CFrame.new(0, pop + math.sin(now * 3 + visual.Phase) * 0.25, 0)
			* CFrame.Angles(0, now * 2.5, 0)
	end
	debug.profileend()
end

function CombatEffectsController.Init(allControllers)
	controllers = allControllers
end

function CombatEffectsController.Start()
	FxPool.Start()
	effectsFolder = FxPool.Folder()

	numbersAnchor = Instance.new("Part")
	numbersAnchor.Name = "NumbersAnchor"
	numbersAnchor.Size = Vector3.new(0.2, 0.2, 0.2)
	numbersAnchor.Transparency = 1
	numbersAnchor.Anchored = true
	numbersAnchor.CanCollide = false
	numbersAnchor.CanQuery = false
	numbersAnchor.CanTouch = false
	numbersAnchor.CFrame = CFrame.new()
	numbersAnchor.Parent = effectsFolder

	damageHighlight = Instance.new("Highlight")
	damageHighlight.Name = "DamageHighlight"
	damageHighlight.FillColor = Color3.fromRGB(255, 60, 60)
	damageHighlight.FillTransparency = 0.45
	damageHighlight.OutlineTransparency = 1
	damageHighlight.DepthMode = Enum.HighlightDepthMode.Occluded
	damageHighlight.Enabled = false
	damageHighlight.Parent = effectsFolder

	-- Solo el tajo (0,5 s): la estocada de Roblox dura 1,5 s y no cabe en el enfriamiento.
	for _, id in { GameConfig.Animations.PlayerSlashR15 } do
		local anim = Instance.new("Animation")
		anim.AnimationId = id
		table.insert(slashAnimations, anim)
	end
	player.CharacterAdded:Connect(function()
		table.clear(slashTracks)
		swordTrail = nil
	end)

	task.spawn(function()
		local list: { Instance } = Sfx.Preload()
		for _, anim in slashAnimations do
			table.insert(list, anim)
		end
		pcall(function()
			game:GetService("ContentProvider"):PreloadAsync(list)
		end)
	end)

	local orbs = Workspace:WaitForChild("ExperienceOrbs")
	orbs.ChildAdded:Connect(trackGem)
	orbs.ChildRemoved:Connect(untrackGem)
	for _, child in orbs:GetChildren() do
		trackGem(child)
	end

	Net.CombatFx.OnClientEvent:Connect(onCombatFx)
	Net.CombatHits.OnClientEvent:Connect(onCombatHits)
	Net.EnemyDied.OnClientEvent:Connect(onEnemyDied)
	Net.GemCollected.OnClientEvent:Connect(onGemCollected)
	Net.LevelUp.OnClientEvent:Connect(onLevelUp)
	Net.PlayerDamaged.OnClientEvent:Connect(onPlayerDamaged)
	Net.WorldFx.OnClientEvent:Connect(onWorldFx)
	Net.HudUpdate.OnClientEvent:Connect(onHud)

	RunService.RenderStepped:Connect(update)
end

return CombatEffectsController
