--[[
	FxPool
	Efectos visuales reutilizables del cliente (solo presentación):
	  • emisores de partículas con nombre, emitidos en cualquier posición,
	  • anillos en el suelo que se expanden y desvanecen (aparición, nivel, golpes),
	  • resaltes (Highlight) cortos para indicar impactos,
	  • formas propias: corte en media luna (Beam curvado), estrella de crítico
	    y destello de impacto.
	Todo se reutiliza: no se crean instancias por impacto ni por enemigo, y
	las animaciones de los anillos se actualizan desde un único Heartbeat.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local VisualConfig = require(ReplicatedStorage.Shared.Config.VisualConfig)
local TEXTURE_GLOW = VisualConfig.Textures.Glow

local FxPool = {}

local folder: Folder
local anchor: Part
local emitters: { [string]: ParticleEmitter } = {}
local ringPool: { Part } = {}
local activeRings: { { Part: Part, Start: number, Duration: number, From: number, To: number, Transparency: number, Height: number } } =
	{}
local highlightPool: { Highlight } = {}
local activeHighlights: { { Highlight: Highlight, Until: number } } = {}

local EMITTERS: { [string]: { [string]: any } } = {
	HitSparks = {
		Color = ColorSequence.new(Color3.fromRGB(190, 250, 255), Color3.new(1, 1, 1)),
		Size = NumberSequence.new(0.55, 0),
		Lifetime = NumberRange.new(0.18, 0.32),
		Speed = NumberRange.new(14, 24),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 7,
		LightEmission = 1,
	},
	CritSparks = {
		Color = ColorSequence.new(Color3.fromRGB(255, 200, 90), Color3.fromRGB(255, 120, 60)),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0) }),
		Lifetime = NumberRange.new(0.25, 0.4),
		Speed = NumberRange.new(18, 30),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 6,
		LightEmission = 1,
	},
	DeathBurst = {
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 0) }),
		Lifetime = NumberRange.new(0.35, 0.65),
		Speed = NumberRange.new(10, 20),
		SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0, -35, 0),
		Drag = 3,
		LightEmission = 0.6,
	},
	Dust = {
		Color = ColorSequence.new(Color3.fromRGB(230, 220, 200)),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 2.4) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(0.4, 0.7),
		Speed = NumberRange.new(6, 12),
		SpreadAngle = Vector2.new(80, 80),
		EmissionDirection = Enum.NormalId.Top,
		Drag = 4,
		LightEmission = 0,
	},
	Sparkles = {
		Color = ColorSequence.new(Color3.fromRGB(255, 220, 110), Color3.fromRGB(120, 240, 255)),
		Size = NumberSequence.new(0.7, 0),
		Lifetime = NumberRange.new(0.6, 1.1),
		Speed = NumberRange.new(6, 16),
		SpreadAngle = Vector2.new(70, 70),
		EmissionDirection = Enum.NormalId.Top,
		Acceleration = Vector3.new(0, 10, 0),
		LightEmission = 1,
	},
	GemPop = {
		Color = ColorSequence.new(Color3.fromRGB(120, 245, 255), Color3.new(1, 1, 1)),
		Size = NumberSequence.new(0.35, 0),
		Lifetime = NumberRange.new(0.2, 0.35),
		Speed = NumberRange.new(5, 9),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 5,
		LightEmission = 1,
	},
	Spark = {
		Color = ColorSequence.new(Color3.fromRGB(200, 230, 255), Color3.fromRGB(140, 120, 255)),
		Size = NumberSequence.new(0.4, 0),
		Lifetime = NumberRange.new(0.1, 0.2),
		Speed = NumberRange.new(16, 26),
		SpreadAngle = Vector2.new(180, 180),
		LightEmission = 1,
	},
}

function FxPool.Folder(): Folder
	return folder
end

-- Emite `count` partículas del emisor `name` en `position` (color opcional).
function FxPool.Emit(name: string, position: Vector3, count: number, color: Color3?)
	local emitter = emitters[name]
	if emitter == nil then
		return
	end
	anchor.CFrame = CFrame.new(position)
	if color then
		emitter.Color = ColorSequence.new(color, color:Lerp(Color3.new(1, 1, 1), 0.6))
	end
	emitter:Emit(count)
end

-- Anillo plano en el suelo que crece de `from` a `to` studs de diámetro.
function FxPool.Ring(
	position: Vector3,
	from: number,
	to: number,
	duration: number,
	color: Color3,
	transparency: number?,
	height: number?
)
	local ring = table.remove(ringPool)
	if ring == nil then
		local part = Instance.new("Part")
		part.Name = "FxRing"
		part.Shape = Enum.PartType.Cylinder
		part.Material = Enum.Material.Neon
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		ring = part
	end
	local r = ring :: Part
	r.Color = color
	r.Size = Vector3.new(height or 0.2, from, from)
	r.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.pi / 2)
	r.Transparency = transparency or 0.3
	r.Parent = folder
	table.insert(activeRings, {
		Part = r,
		Start = os.clock(),
		Duration = duration,
		From = from,
		To = to,
		Transparency = transparency or 0.3,
		Height = height or 0.2,
	})
	return r
end

-- Resalte breve sobre un modelo (máximo 8 a la vez: el resto se omite).
function FxPool.Flash(model: Instance, color: Color3, duration: number)
	local highlight = table.remove(highlightPool)
	if highlight == nil then
		if #activeHighlights >= 8 then
			return
		end
		local created = Instance.new("Highlight")
		created.DepthMode = Enum.HighlightDepthMode.Occluded
		created.OutlineTransparency = 1
		created.FillTransparency = 0.25
		created.Parent = folder
		highlight = created
	end
	local h = highlight :: Highlight
	h.FillColor = color
	h.Adornee = model
	h.Enabled = true
	table.insert(activeHighlights, { Highlight = h, Until = os.clock() + duration })
end

------------------------------------------------- Efectos con forma propia
-- Cada efecto se reutiliza desde su pool y se anima en el bucle central.
type Shape = { Kind: string, Root: BasePart, Parts: { any }, Start: number, Duration: number, Data: any }
local shapePools: { [string]: { Shape } } = { Slash = {}, Star = {}, Flash = {} }
local activeShapes: { Shape } = {}

local function fxPart(name: string): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	return part
end

local function makeSlash(): Shape
	local root = fxPart("FxSlash")
	-- A0 a la izquierda con su eje X hacia delante; A1 a la derecha con el eje
	-- X hacia atrás: la curva de Bézier del Beam se abomba hacia delante.
	local a0 = Instance.new("Attachment")
	a0.Parent = root
	local a1 = Instance.new("Attachment")
	a1.Parent = root
	local beams = {}
	for index, style in { { Width = 3.2, Light = 0.6 }, { Width = 0.9, Light = 1 } } do
		local beam = Instance.new("Beam")
		beam.Name = "SlashBeam" .. index
		beam.Attachment0 = a0
		beam.Attachment1 = a1
		beam.Texture = TEXTURE_GLOW
		beam.TextureMode = Enum.TextureMode.Stretch
		beam.LightEmission = style.Light
		beam.LightInfluence = 0
		beam.Segments = 16
		beam.FaceCamera = false
		beam.Enabled = false
		beam.Parent = root
		beams[index] = { Beam = beam, Width = style.Width }
	end
	return { Kind = "Slash", Root = root, Parts = beams, Start = 0, Duration = 0.2, Data = { A0 = a0, A1 = a1 } }
end

local function makeStar(): Shape
	local root = fxPart("FxStar")
	local rays = {}
	for index = 1, 4 do
		local ray = fxPart("StarRay")
		ray.Material = Enum.Material.Neon
		ray.Parent = root
		rays[index] = ray
	end
	return { Kind = "Star", Root = root, Parts = rays, Start = 0, Duration = 0.22, Data = {} }
end

local function makeFlash(): Shape
	local root = fxPart("FxFlash")
	root.Shape = Enum.PartType.Ball
	root.Material = Enum.Material.Neon
	return { Kind = "Flash", Root = root, Parts = {}, Start = 0, Duration = 0.1, Data = {} }
end

local function acquireShape(kind: string): Shape
	local shape = table.remove(shapePools[kind])
	if shape == nil then
		shape = if kind == "Slash" then makeSlash() elseif kind == "Star" then makeStar() else makeFlash()
	end
	local s = shape :: Shape
	s.Start = os.clock()
	s.Root.Parent = folder
	table.insert(activeShapes, s)
	return s
end

--[[
	Corte en media luna delante de `origin` (CFrame mirando al objetivo).
	`radius` = semiancho del arco; `tilt` inclina el plano (variedad de tajos).
]]
function FxPool.Slash(origin: CFrame, radius: number, color: Color3, tilt: number, duration: number?)
	local shape = acquireShape("Slash")
	shape.Duration = duration or 0.2
	shape.Root.CFrame = origin * CFrame.Angles(0, 0, tilt)
	local forward, up = Vector3.new(0, 0, -1), Vector3.new(0, 1, 0)
	shape.Data.A0.CFrame = CFrame.fromMatrix(Vector3.new(-radius, 0, 0), forward, up)
	shape.Data.A1.CFrame = CFrame.fromMatrix(Vector3.new(radius, 0, 0), -forward, up)
	shape.Data.Radius = radius
	for index, entry in shape.Parts do
		local beam: Beam = entry.Beam
		beam.Color = if index == 1 then ColorSequence.new(color) else ColorSequence.new(Color3.new(1, 1, 1), color)
		beam.CurveSize0 = radius * 1.25
		beam.CurveSize1 = radius * 1.25
		beam.Enabled = true
	end
end

-- Estrella de crítico: cuatro rayos que se abren y se desvanecen.
function FxPool.Star(position: Vector3, color: Color3, size: number?)
	local shape = acquireShape("Star")
	shape.Data.Size = size or 5
	shape.Root.CFrame = CFrame.new(position) * CFrame.Angles(0, math.random() * math.pi, 0)
	for _, ray in shape.Parts do
		ray.Color = color
	end
end

-- Destello esférico breve en el punto de impacto.
function FxPool.ImpactFlash(position: Vector3, color: Color3, size: number?)
	local shape = acquireShape("Flash")
	shape.Data.Size = size or 2.2
	shape.Root.Color = color
	shape.Root.CFrame = CFrame.new(position)
end

local function updateShapes(now: number)
	for index = #activeShapes, 1, -1 do
		local shape = activeShapes[index]
		local t = (now - shape.Start) / shape.Duration
		if t >= 1 then
			shape.Root.Parent = nil
			if shape.Kind == "Slash" then
				for _, entry in shape.Parts do
					entry.Beam.Enabled = false
				end
			end
			table.insert(shapePools[shape.Kind], shape)
			table.remove(activeShapes, index)
			continue
		end
		if shape.Kind == "Slash" then
			-- Ejecución rápida (se abre) y desaparición (se estrecha y desvanece).
			local open = 1 - (1 - math.min(1, t * 2.5)) ^ 2
			for _, entry in shape.Parts do
				local beam: Beam = entry.Beam
				beam.Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1),
					NumberSequenceKeypoint.new(math.clamp(0.5 - open * 0.45, 0.02, 0.5), 0.1 + t * 0.9),
					NumberSequenceKeypoint.new(math.clamp(0.5 + open * 0.45, 0.5, 0.98), 0.1 + t * 0.9),
					NumberSequenceKeypoint.new(1, 1),
				})
				-- Centro más ancho que las puntas: forma de media luna.
				beam.Width0 = entry.Width * (0.15 + 0.1 * (1 - t))
				beam.Width1 = beam.Width0
				beam.CurveSize0 = shape.Data.Radius * (1.1 + 0.4 * open)
				beam.CurveSize1 = beam.CurveSize0
			end
		elseif shape.Kind == "Star" then
			local size = shape.Data.Size * (0.4 + 0.6 * (1 - (1 - t) ^ 3))
			for rayIndex, ray in shape.Parts do
				local thickness = 0.35 * (1 - t) + 0.05
				ray.Size = Vector3.new(thickness, thickness, size * (if rayIndex <= 2 then 1 else 0.6))
				ray.CFrame = shape.Root.CFrame * CFrame.Angles(0, (rayIndex - 1) * math.pi / 4, 0)
				ray.Transparency = t * t
			end
		else
			local size = shape.Data.Size * (0.5 + 0.5 * t)
			shape.Root.Size = Vector3.new(size, size, size)
			shape.Root.Transparency = 0.2 + 0.8 * t
		end
	end
end

local function update()
	debug.profilebegin("SkyBonk.FxPool")
	local now = os.clock()
	updateShapes(now)
	for index = #activeRings, 1, -1 do
		local entry = activeRings[index]
		local t = (now - entry.Start) / entry.Duration
		if t >= 1 then
			entry.Part.Parent = nil
			table.insert(ringPool, entry.Part)
			table.remove(activeRings, index)
		else
			local eased = 1 - (1 - t) ^ 3
			local diameter = entry.From + (entry.To - entry.From) * eased
			entry.Part.Size = Vector3.new(entry.Height, diameter, diameter)
			entry.Part.Transparency = entry.Transparency + (1 - entry.Transparency) * t
		end
	end
	for index = #activeHighlights, 1, -1 do
		local entry = activeHighlights[index]
		if now >= entry.Until then
			entry.Highlight.Enabled = false
			entry.Highlight.Adornee = nil
			table.insert(highlightPool, entry.Highlight)
			table.remove(activeHighlights, index)
		end
	end
	debug.profileend()
end

function FxPool.Start()
	folder = Instance.new("Folder")
	folder.Name = "ClientEffects"
	folder.Parent = Workspace

	anchor = Instance.new("Part")
	anchor.Name = "FxAnchor"
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Parent = folder

	for name, props in EMITTERS do
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = name
		emitter.Enabled = false
		emitter.LockedToPart = false
		for key, value in props do
			(emitter :: any)[key] = value
		end
		emitter.Parent = anchor
		emitters[name] = emitter
	end
	RunService.Heartbeat:Connect(update)
end

return FxPool
