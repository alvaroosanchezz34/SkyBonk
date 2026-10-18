--[[
	CharacterFxController
	Presentación anime del personaje local (solo visual, sin efecto en el juego):

	  • Aura según la build real (VisualConfig.PlayerAuraRules, a partir del HUD):
	    Eléctrica (rayo), Ígnea (crítico), Arcana (experiencia/suerte), Celestial
	    (defensa y ráfaga al subir de nivel) y Vacío (vida crítica).
	  • Inclinación procedural: el torso se inclina hacia la curva y hacia atrás
	    al frenar (Motor6D Root.C0; las animaciones usan Transform, no C0).
	  • Estelas de viento al correr deprisa, impulso al saltar y polvo al aterrizar.
	  • Retroceso breve al recibir daño.
	  • Muerte: disolución y desaturación; reaparición: columna de luz.
	El paquete de animaciones (Ninja, de Roblox) lo aplica el servidor al
	script Animate del personaje (MatchService).
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local VisualConfig = require(Shared.Config.VisualConfig)
local Net = require(Shared.Net)
local AuraSystem = require(script.Parent.Parent.Util.AuraSystem)
local FxPool = require(script.Parent.Parent.Util.FxPool)

local CharacterFxController = {}

local MOTION = VisualConfig.Motion
local RULES = VisualConfig.PlayerAuraRules
local player = Players.LocalPlayer

local controllers
local aura: any = nil
-- Articulación raíz del cuerpo: Motor6D (avatares antiguos) o AnimationConstraint
-- (articulaciones actuales de Roblox, cuyo C0 es de solo lectura: se gira su
-- Attachment0, que está en el HumanoidRootPart).
local rootJoint: Motor6D? = nil
local rootAttachment: Attachment? = nil
local rootBaseC0 = CFrame.new()
local humanoid: Humanoid? = nil
local hrp: BasePart? = nil
local lastVelocity = Vector3.zero
local lean = Vector2.zero -- (cabeceo, alabeo)
local recoil = 0
local windTrails: { Trail } = {}
local levelBurstUntil = 0
local deathGrade: ColorCorrectionEffect
local characterConnections: { RBXScriptConnection } = {}

local function chooseProfile(): (string, number)
	local snapshot = controllers.HUDController.GetSnapshot()
	if os.clock() < levelBurstUntil then
		return "Celestial", 1.4
	end
	if snapshot == nil or snapshot.MaxHealth <= 0 then
		return RULES.Default, 0.4
	end
	local stats = snapshot.Stats or {}
	-- La intensidad crece con el nivel: el personaje se ve cada vez más poderoso.
	local intensity = math.clamp(0.35 + snapshot.Level * 0.05, 0.35, 1)
	if snapshot.Health / snapshot.MaxHealth < RULES.CriticalHealthPct then
		return "Void", 1
	elseif (stats.Chain or 0) >= RULES.ChainForElectric then
		return "Electric", math.min(1.2, intensity + 0.2)
	elseif (stats.CritPct or 0) >= RULES.CritPctForFire then
		return "Fire", intensity
	elseif (stats.XpBonusPct or 0) >= RULES.XpBonusForArcane or (stats.Luck or 0) >= 2 then
		return "Arcane", intensity
	elseif (stats.Regen or 0) >= RULES.DefenseForCelestial or (stats.DamageReductionPct or 0) >= 20 then
		return "Celestial", intensity
	end
	return RULES.Default, intensity
end

local function makeWindTrail(root: BasePart, offset: Vector3): Trail
	local a0 = Instance.new("Attachment")
	a0.Name = "WindA0"
	a0.Position = offset
	a0.Parent = root
	local a1 = Instance.new("Attachment")
	a1.Name = "WindA1"
	a1.Position = offset + Vector3.new(0, 0.35, 0)
	a1.Parent = root
	local trail = Instance.new("Trail")
	trail.Name = "WindTrail"
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.22
	trail.LightEmission = 0.8
	trail.FaceCamera = true
	trail.Color = ColorSequence.new(Color3.new(1, 1, 1), VisualConfig.Palette.Player)
	trail.Transparency = NumberSequence.new(0.35, 1)
	trail.WidthScale = NumberSequence.new(1, 0)
	trail.Enabled = false
	trail.Parent = root
	return trail
end

local function lightPillar(position: Vector3, color: Color3, height: number)
	local pillar = Instance.new("Part")
	pillar.Name = "LightPillar"
	pillar.Shape = Enum.PartType.Cylinder
	pillar.Size = Vector3.new(height, 0.6, 0.6)
	pillar.CFrame = CFrame.new(position + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	pillar.Material = Enum.Material.Neon
	pillar.Color = color
	pillar.Transparency = 0.25
	pillar.Anchored = true
	pillar.CanCollide = false
	pillar.CanQuery = false
	pillar.CanTouch = false
	pillar.CastShadow = false
	pillar.Parent = FxPool.Folder()
	local grow = TweenService:Create(pillar, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(height, 6, 6),
	})
	grow:Play()
	task.delay(0.18, function()
		TweenService:Create(pillar, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Size = Vector3.new(height, 0.2, 0.2),
			Transparency = 1,
		}):Play()
	end)
	task.delay(0.75, function()
		pillar:Destroy()
	end)
end

local function onCharacter(character: Model)
	for _, connection in characterConnections do
		connection:Disconnect()
	end
	table.clear(characterConnections)
	table.clear(windTrails)
	if aura then
		aura:Destroy()
		aura = nil
	end
	local hum = character:WaitForChild("Humanoid", 10) :: Humanoid?
	local root = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if hum == nil or root == nil then
		return
	end
	humanoid, hrp = hum, root
	local lowerTorso = character:WaitForChild("LowerTorso", 3)
	local joint = lowerTorso and lowerTorso:FindFirstChild("Root")
	rootJoint, rootAttachment = nil, nil
	if joint and joint:IsA("Motor6D") then
		rootJoint = joint
		rootBaseC0 = joint.C0
	elseif joint and joint:IsA("AnimationConstraint") and joint.Attachment0 then
		rootAttachment = joint.Attachment0
		rootBaseC0 = joint.Attachment0.CFrame
	end
	lean = Vector2.zero
	recoil = 0
	lastVelocity = Vector3.zero

	-- Aura: el suelo está a HipHeight + media altura del HumanoidRootPart.
	local floorOffset = hum.HipHeight + root.Size.Y / 2
	local profile, intensity = chooseProfile()
	aura = AuraSystem.Attach(root, profile, { Height = 5.4, FloorOffset = floorOffset, Intensity = intensity })

	for _, offset in { Vector3.new(-1.1, 0.4, 0.5), Vector3.new(1.1, 0.4, 0.5), Vector3.new(0, 1.6, 0.6) } do
		table.insert(windTrails, makeWindTrail(root, offset))
	end

	-- Reaparición: columna de luz y ráfaga del aura; la pantalla recupera el color.
	TweenService:Create(deathGrade, TweenInfo.new(0.6), { Saturation = 0, Brightness = 0, Contrast = 0 }):Play()
	local feet = root.Position - Vector3.new(0, floorOffset, 0)
	lightPillar(feet, VisualConfig.Palette.PlayerCore, 40)
	FxPool.Ring(feet + Vector3.new(0, 0.2, 0), 2, 16, 0.5, VisualConfig.Palette.Player, 0.2, 0.2)
	FxPool.Emit("Sparkles", root.Position, 30)
	aura:Burst(1)

	table.insert(
		characterConnections,
		hum.StateChanged:Connect(function(_, new)
			if new == Enum.HumanoidStateType.Jumping then
				FxPool.Ring(
					root.Position - Vector3.new(0, floorOffset - 0.2, 0),
					1.5,
					7,
					0.3,
					Color3.new(1, 1, 1),
					0.4,
					0.12
				)
			elseif new == Enum.HumanoidStateType.Landed then
				if -lastVelocity.Y >= MOTION.LandingMinFall then
					local ground = root.Position - Vector3.new(0, floorOffset - 0.2, 0)
					FxPool.Emit("Dust", ground, math.floor(math.clamp(-lastVelocity.Y / 3, 6, 18)))
					FxPool.Ring(ground, 2, 9, 0.35, Color3.fromRGB(235, 225, 205), 0.45, 0.12)
					recoil = math.max(recoil, MOTION.HitRecoil * 0.6) -- amortigua el aterrizaje
				end
			end
		end)
	)
	table.insert(
		characterConnections,
		hum.Died:Connect(function()
			-- Disolución: partículas del vacío sobre cada pieza y pantalla desaturada.
			for _, part in character:GetChildren() do
				if part:IsA("BasePart") then
					FxPool.Emit("DeathBurst", part.Position, 3, VisualConfig.Palette.Void)
				end
			end
			FxPool.Emit("Sparkles", root.Position, 24)
			TweenService
				:Create(deathGrade, TweenInfo.new(0.8), { Saturation = -0.7, Brightness = -0.05, Contrast = 0.1 })
				:Play()
			controllers.CameraController.Reset()
			if aura then
				aura:SetProfile("Void")
				aura:Burst(0.6)
			end
		end)
	)
end

local function update(dt: number)
	local root, hum = hrp, humanoid
	if root == nil or hum == nil or root.Parent == nil then
		return
	end
	local velocity = root.AssemblyLinearVelocity
	local flat = Vector3.new(velocity.X, 0, velocity.Z)
	local speed = flat.Magnitude
	if dt > 0 and hum.Health > 0 then
		-- Inclinación: aceleración en el espacio del personaje.
		local accel = (flat - Vector3.new(lastVelocity.X, 0, lastVelocity.Z)) / dt
		local localAccel = root.CFrame:VectorToObjectSpace(accel)
		local localVel = root.CFrame:VectorToObjectSpace(flat)
		-- X negativo = hacia delante (al correr); positivo = hacia atrás (al frenar o recibir un golpe).
		local targetPitch = math.clamp(localVel.Z * 0.006 + localAccel.Z * 0.004, -MOTION.MaxLean, MOTION.MaxLean)
		local targetRoll = math.clamp(-localAccel.X * 0.006, -MOTION.MaxLean, MOTION.MaxLean)
		local alpha = math.min(1, dt * MOTION.LeanResponsiveness)
		lean = lean:Lerp(Vector2.new(targetPitch, targetRoll), alpha)
		recoil = math.max(0, recoil - dt * 1.5)
		local tilt = rootBaseC0 * CFrame.Angles(lean.X + recoil, 0, lean.Y)
		if rootJoint and rootJoint.Parent then
			rootJoint.C0 = tilt
		elseif rootAttachment and rootAttachment.Parent then
			rootAttachment.CFrame = tilt
		end
	end
	lastVelocity = velocity

	local fast = speed >= MOTION.SpeedlineSpeed and AuraSystem.GetQuality().Speedlines and hum.Health > 0
	for _, trail in windTrails do
		if trail.Enabled ~= fast then
			trail.Enabled = fast
		end
	end
end

function CharacterFxController.Init(allControllers)
	controllers = allControllers
end

function CharacterFxController.Start()
	AuraSystem.Start()
	deathGrade = Instance.new("ColorCorrectionEffect")
	deathGrade.Name = "SkyBonkDeathGrade"
	deathGrade.Parent = Lighting

	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
	Net.LevelUp.OnClientEvent:Connect(function()
		levelBurstUntil = os.clock() + RULES.LevelUpBurst
		if aura then
			aura:SetProfile("Celestial")
			aura:Burst(RULES.LevelUpBurst)
		end
		controllers.CameraController.FovKick(VisualConfig.Camera.LevelUpFovKick, 0.6)
	end)
	Net.PlayerDamaged.OnClientEvent:Connect(function()
		recoil = math.max(recoil, MOTION.HitRecoil)
	end)
	controllers.InputController.ToggleFx:Connect(function()
		AuraSystem.ToggleQuality()
	end)
	-- El aura se revisa 4 veces por segundo (la build cambia al elegir mejoras).
	task.spawn(function()
		while true do
			task.wait(0.25)
			if aura and humanoid and humanoid.Health > 0 then
				local profile, intensity = chooseProfile()
				aura:SetProfile(profile)
				aura:SetIntensity(intensity)
			end
		end
	end)
	RunService.RenderStepped:Connect(function(dt)
		debug.profilebegin("SkyBonk.CharacterFx")
		update(dt)
		debug.profileend()
	end)
end

return CharacterFxController
