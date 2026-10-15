--[[
	FxPool
	Efectos visuales reutilizables del cliente (solo presentación):
	  • emisores de partículas con nombre, emitidos en cualquier posición,
	  • anillos en el suelo que se expanden y desvanecen (aparición, nivel, golpes),
	  • resaltes (Highlight) cortos para indicar impactos.
	Todo se reutiliza: no se crean instancias por impacto ni por enemigo, y
	las animaciones de los anillos se actualizan desde un único Heartbeat.
]]

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

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

local function update()
	debug.profilebegin("SkyBonk.FxPool")
	local now = os.clock()
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
