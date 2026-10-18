--[[
	AuraSystem
	Auras modulares (solo presentación, solo en el cliente). Cada aura se
	construye con las capas de su perfil (VisualConfig.Auras):

	  Rise    partículas que ascienden desde un volumen cilíndrico alrededor del cuerpo
	  Orbit   motas fijadas a un punto que gira: orbitan alrededor del personaje
	  Sparks  chispas rápidas que saltan desde la superficie
	  Ring    anillo en el suelo que pulsa (doble en perfiles de alto nivel)
	  Light   luz puntual (solo calidad alta)

	API:
	  local aura = AuraSystem.Attach(rootPart, "Electric", { Scale = 1, Height = 5 })
	  aura:SetProfile("Fire")  aura:SetIntensity(0.6)  aura:Burst()  aura:Destroy()
	  AuraSystem.SetQuality("Low")

	Todas las auras se animan desde un único RenderStepped; las que quedan lejos
	de la cámara (MaxDistance) apagan sus emisores. Las piezas son locales: no se
	replican ni tienen colisión, masa ni consultas.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local VisualConfig = require(ReplicatedStorage.Shared.Config.VisualConfig)
local Signal = require(ReplicatedStorage.Shared.Signal)

local AuraSystem = {}
AuraSystem.__index = AuraSystem

local TEXTURES = VisualConfig.Textures
local active: { any } = {}
local quality = VisualConfig.Quality[VisualConfig.DefaultQuality]
local qualityName = VisualConfig.DefaultQuality
-- Se dispara con el nombre del nivel de calidad ("High" / "Low").
AuraSystem.QualityChanged = Signal.new()
local connection: RBXScriptConnection? = nil

local function localPart(name: string, size: Vector3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Transparency = 1
	part.Anchored = false
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = false
	return part
end

local function weldTo(part: BasePart, target: BasePart, offset: CFrame)
	part.CFrame = target.CFrame * offset
	local weld = Instance.new("Weld")
	weld.Part0 = target
	weld.Part1 = part
	weld.C0 = offset
	weld.Parent = part
	return weld
end

local function makeEmitter(layer: any, color: Color3, accent: Color3, parent: Instance, dark: boolean?): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = TEXTURES[layer.Texture] or TEXTURES.Sparkle
	emitter.Color = ColorSequence.new(accent, color)
	emitter.LightEmission = if dark then 0 else 0.9
	emitter.LightInfluence = 0
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, layer.Size * 0.6),
		NumberSequenceKeypoint.new(0.3, layer.Size),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, if dark then 0.35 else 0.15),
		NumberSequenceKeypoint.new(0.7, 0.5),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Lifetime = NumberRange.new(layer.Lifetime * 0.7, layer.Lifetime)
	emitter.Speed = NumberRange.new(layer.Speed * 0.6, layer.Speed)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-90, 90)
	emitter.Rate = 0
	emitter.Parent = parent
	return emitter
end

local function makeRing(color: Color3): Part
	local ring = localPart("AuraRing", Vector3.new(0.12, 4, 4))
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Color = color
	return ring
end

export type Options = { Scale: number?, Height: number?, FloorOffset: number?, Intensity: number?, Light: boolean? }

--[[
	Crea un aura alrededor de `root` (HumanoidRootPart o Root de un enemigo).
	Height: altura del cuerpo (studs) para el volumen de emisión.
]]
function AuraSystem.Attach(root: BasePart, profileName: string, options: Options?)
	local opts = options or {}
	local self = setmetatable({}, AuraSystem)
	self.Root = root
	self.Scale = opts.Scale or 1
	self.Height = opts.Height or 5
	-- Distancia del centro de `root` al suelo (para el anillo).
	self.FloorOffset = opts.FloorOffset or self.Height / 2
	self.Intensity = opts.Intensity or 1
	self.AllowLight = opts.Light ~= false
	self.BurstUntil = 0
	self.Phase = math.random() * 10
	self.Visible = true

	local folder = Instance.new("Folder")
	folder.Name = "Aura"
	self.Folder = folder

	-- Volumen alrededor del cuerpo (las partículas nacen en su superficie).
	local volume = localPart("AuraVolume", Vector3.new(4, self.Height, 4))
	weldTo(volume, root, CFrame.new(0, 0, 0))
	volume.Parent = folder
	self.Volume = volume

	-- Punto que gira para las motas en órbita.
	local orbitPart = localPart("AuraOrbit", Vector3.new(0.2, 0.2, 0.2))
	self.OrbitWeld = weldTo(orbitPart, root, CFrame.new())
	orbitPart.Parent = folder
	self.OrbitPart = orbitPart

	self.Rings = {}
	folder.Parent = root
	self:SetProfile(profileName)
	table.insert(active, self)
	return self
end

function AuraSystem:_clearLayers()
	for _, emitter in self.Emitters or {} do
		emitter:Destroy()
	end
	for _, ring in self.Rings do
		ring.Part:Destroy()
	end
	if self.Light then
		self.Light:Destroy()
		self.Light = nil
	end
	self.Emitters = {}
	self.Rings = {}
end

function AuraSystem:SetProfile(profileName: string)
	if self.ProfileName == profileName then
		return
	end
	local profile = VisualConfig.Auras[profileName]
	assert(profile, "Perfil de aura desconocido: " .. tostring(profileName))
	self:_clearLayers()
	self.ProfileName = profileName
	self.Profile = profile
	local scale = self.Scale
	local radius = profile.Radius * scale
	self.Volume.Size = Vector3.new(radius * 2, self.Height, radius * 2)

	local emitters = {}
	if profile.Rise then
		local rise = makeEmitter(profile.Rise, profile.Color, profile.Accent, self.Volume, profile.Rise.Dark)
		rise.Shape = Enum.ParticleEmitterShape.Cylinder
		rise.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
		rise.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
		rise.EmissionDirection = Enum.NormalId.Top
		rise.SpreadAngle = Vector2.new(12, 12)
		rise.Acceleration = Vector3.new(0, profile.Rise.Speed * 0.6, 0)
		emitters.Rise = rise
	end
	if profile.Sparks then
		local sparks = makeEmitter(profile.Sparks, profile.Accent, profile.Color, self.Volume)
		sparks.Shape = Enum.ParticleEmitterShape.Cylinder
		sparks.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
		sparks.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
		sparks.SpreadAngle = Vector2.new(40, 40)
		sparks.Drag = 4
		emitters.Sparks = sparks
	end
	if profile.Orbit then
		-- Emite desde un punto desplazado del eje que gira: las motas trazan una órbita.
		local attachment = Instance.new("Attachment")
		attachment.Position = Vector3.new(radius, 0, 0)
		attachment.Parent = self.OrbitPart
		local orbit = makeEmitter(profile.Orbit, profile.Color, profile.Accent, attachment)
		orbit.LockedToPart = true
		orbit.SpreadAngle = Vector2.new(180, 180)
		orbit.Speed = NumberRange.new(0.2, profile.Orbit.Speed * 0.3)
		emitters.Orbit = orbit
	end
	self.Emitters = emitters

	if profile.Ring then
		local count = if profile.Ring.Double then 2 else 1
		for index = 1, count do
			local ring = makeRing(if index == 1 then profile.Color else profile.Accent)
			local weld =
				weldTo(ring, self.Root, CFrame.new(0, -self.FloorOffset + 0.12, 0) * CFrame.Angles(0, 0, math.pi / 2))
			ring.Parent = self.Folder
			table.insert(self.Rings, { Part = ring, Weld = weld, Offset = (index - 1) * 0.5 })
		end
	end
	if profile.Light and self.AllowLight then
		local light = Instance.new("PointLight")
		light.Color = profile.Color
		light.Range = profile.Light.Range * scale
		light.Brightness = profile.Light.Brightness
		light.Shadows = false
		light.Parent = self.Volume
		self.Light = light
	end
	self:_applyRates()
end

function AuraSystem:_applyRates()
	local profile = self.Profile
	local burst = os.clock() < self.BurstUntil
	local intensity = self.Intensity * (if burst then 1.8 else 1)
	local scale = quality.ParticleScale * (if self.Visible then 1 else 0)
	for name, emitter in self.Emitters do
		local layer = profile[name]
		emitter.Rate = layer.Rate * intensity * scale * math.max(1, self.Scale * 0.8)
	end
	if self.Light then
		self.Light.Enabled = quality.Lights and self.Visible
		self.Light.Brightness = profile.Light.Brightness * math.min(intensity, 1.5)
	end
	for _, ring in self.Rings do
		ring.Part.LocalTransparencyModifier = if self.Visible and intensity > 0.05 then 0 else 1
	end
end

function AuraSystem:SetIntensity(intensity: number)
	if math.abs((self.Intensity or 0) - intensity) < 0.02 then
		return
	end
	self.Intensity = intensity
	self:_applyRates()
end

-- Ráfaga breve (subida de nivel, entrada del jefe): más emisión y un destello de chispas.
function AuraSystem:Burst(duration: number?)
	self.BurstUntil = os.clock() + (duration or 0.8)
	for _, emitter in self.Emitters do
		emitter:Emit(math.floor(10 * quality.ParticleScale + 0.5))
	end
	self:_applyRates()
	task.delay((duration or 0.8) + 0.05, function()
		if self.Folder and self.Folder.Parent then
			self:_applyRates()
		end
	end)
end

function AuraSystem:Destroy()
	local index = table.find(active, self)
	if index then
		table.remove(active, index)
	end
	if self.Folder then
		self.Folder:Destroy()
		self.Folder = nil
	end
end

function AuraSystem.SetQuality(name: string)
	if VisualConfig.Quality[name] == nil then
		return
	end
	quality = VisualConfig.Quality[name]
	qualityName = name
	for _, aura in active do
		aura:_applyRates()
	end
	AuraSystem.QualityChanged:Fire(name)
end

function AuraSystem.ToggleQuality(): string
	AuraSystem.SetQuality(if qualityName == "High" then "Low" else "High")
	return qualityName
end

function AuraSystem.GetQuality()
	return quality
end

function AuraSystem.GetQualityName(): string
	return qualityName
end

local function update()
	local camera = Workspace.CurrentCamera
	local cameraPosition = camera and camera.CFrame.Position or Vector3.zero
	local now = os.clock()
	for index = #active, 1, -1 do
		local aura = active[index]
		local root = aura.Root
		if root.Parent == nil or aura.Folder == nil or aura.Folder.Parent == nil then
			aura:Destroy()
			continue
		end
		local visible = (root.Position - cameraPosition).Magnitude <= aura.Profile.MaxDistance
		if visible ~= aura.Visible then
			aura.Visible = visible
			aura:_applyRates()
		end
		if not visible then
			continue
		end
		-- Órbita y anillos pulsantes.
		aura.OrbitWeld.C0 =
			CFrame.Angles(0, now * (aura.Profile.Orbit and aura.Profile.Orbit.Spin or 1) + aura.Phase, 0)
		local ringCfg = aura.Profile.Ring
		if ringCfg then
			for _, ring in aura.Rings do
				local t = ((now + aura.Phase) / ringCfg.Pulse + ring.Offset) % 1
				local size = ringCfg.Size * aura.Scale * (0.55 + 0.45 * t)
				ring.Part.Size = Vector3.new(0.12, size, size)
				ring.Part.Transparency = ringCfg.Transparency + (1 - ringCfg.Transparency) * t
			end
		end
	end
end

function AuraSystem.Start()
	if connection == nil then
		connection = RunService.RenderStepped:Connect(function()
			debug.profilebegin("SkyBonk.Auras")
			update()
			debug.profileend()
		end)
	end
end

return AuraSystem
