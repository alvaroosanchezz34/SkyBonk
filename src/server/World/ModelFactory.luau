--[[
	ModelFactory
	Construye las plantillas de enemigos (low-poly, solo Parts). EnemyService
	las clona desde ServerStorage/EnemyModels; si un diseñador coloca allí un
	modelo con el mismo nombre (con Root, RootAttachment, Mover, Facing y
	HealthBar), se usa ese en lugar del generado.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage.Shared.Types)

local ModelFactory = {}

local function weld(part0: BasePart, part1: BasePart, name: string): Weld
	local w = Instance.new("Weld")
	w.Name = name
	w.Part0 = part0
	w.Part1 = part1
	w.C0 = part0.CFrame:Inverse() * part1.CFrame
	w.Parent = part1
	return w
end

local function visualPart(props: { [string]: any }, parent: Instance): BasePart
	local part = Instance.new(props.ClassName or "Part") :: BasePart
	props.ClassName = nil
	part.Anchored = false
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = Enum.Material.SmoothPlastic
	for key, value in props do
		(part :: any)[key] = value
	end
	part.Parent = parent
	return part
end

local function buildHealthBar(root: BasePart)
	local gui = Instance.new("BillboardGui")
	gui.Name = "HealthBar"
	gui.Adornee = root
	gui.Size = UDim2.new(3.6, 0, 0.42, 0)
	gui.StudsOffset = Vector3.new(0, 2.9, 0)
	gui.MaxDistance = 110
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.ResetOnSpawn = false

	local back = Instance.new("Frame")
	back.Name = "Back"
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Color3.fromRGB(26, 18, 40)
	back.BorderSizePixel = 0
	back.Parent = gui
	local backCorner = Instance.new("UICorner")
	backCorner.CornerRadius = UDim.new(0.5, 0)
	backCorner.Parent = back

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(236, 84, 120)
	fill.BorderSizePixel = 0
	fill.Parent = back
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0.5, 0)
	fillCorner.Parent = fill

	gui.Parent = root
end

-- Slime del Vacío: caja física invisible + cuerpo elipsoidal y detalles soldados.
function ModelFactory.buildVoidSlime(def: Types.EnemyDef): Model
	local model = Instance.new("Model")
	model.Name = def.ModelName

	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(3.4, 2.6, 3.4)
	root.CFrame = CFrame.new(0, 1.3, 0)
	root.Transparency = 1
	root.Anchored = false
	root.CanCollide = true
	root.CanTouch = false
	root.CastShadow = false
	-- Sin fricción ni rebote: se desliza de forma estable por el terreno.
	root.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0, 0, 100, 100)
	root.Parent = model
	model.PrimaryPart = root

	local attachment = Instance.new("Attachment")
	attachment.Name = "RootAttachment"
	attachment.Parent = root

	-- Movimiento horizontal (la gravedad sigue actuando en Y).
	local mover = Instance.new("LinearVelocity")
	mover.Name = "Mover"
	mover.Attachment0 = attachment
	mover.RelativeTo = Enum.ActuatorRelativeTo.World
	mover.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	mover.PrimaryTangentAxis = Vector3.new(1, 0, 0)
	mover.SecondaryTangentAxis = Vector3.new(0, 0, 1)
	mover.PlaneVelocity = Vector2.new(0, 0)
	mover.ForceLimitMode = Enum.ForceLimitMode.Magnitude
	mover.MaxForce = 20000
	mover.Parent = root

	-- Mantiene al slime erguido y mirando hacia su objetivo.
	local facing = Instance.new("AlignOrientation")
	facing.Name = "Facing"
	facing.Mode = Enum.OrientationAlignmentMode.OneAttachment
	facing.Attachment0 = attachment
	facing.Responsiveness = 25
	facing.MaxTorque = 1e6
	facing.RigidityEnabled = false
	facing.CFrame = CFrame.new()
	facing.Parent = root

	local body = visualPart({
		Name = "Body",
		Size = Vector3.new(4, 3, 4),
		CFrame = CFrame.new(0, 1.5, 0),
		Color = def.Color,
		Transparency = 0.08,
		Reflectance = 0.05,
	}, model)
	local mesh = Instance.new("SpecialMesh")
	mesh.Name = "BodyMesh"
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = body
	-- El cliente anima BodyWeld.C0 y BodyMesh.Scale (rebote), solo visualmente.
	weld(root, body, "BodyWeld")

	local core = visualPart({
		Name = "Core",
		ClassName = "Part",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(1.4, 1.4, 1.4),
		CFrame = CFrame.new(0, 1.5, 0),
		Color = def.Color:Lerp(Color3.new(1, 1, 1), 0.45),
		Material = Enum.Material.Neon,
	}, model)
	weld(body, core, "CoreWeld")

	for _, side in { -1, 1 } do
		local eye = visualPart({
			Name = "Eye",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.85, 0.85, 0.85),
			CFrame = CFrame.new(side * 0.75, 2, -1.55),
			Color = Color3.fromRGB(250, 248, 255),
		}, model)
		weld(body, eye, "EyeWeld")
		local pupil = visualPart({
			Name = "Pupil",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.42, 0.42, 0.42),
			CFrame = CFrame.new(side * 0.75, 2, -1.92),
			Color = Color3.fromRGB(24, 10, 40),
		}, model)
		weld(body, pupil, "PupilWeld")
	end

	local crown = visualPart({
		Name = "CrownCrystal",
		Size = Vector3.new(0.7, 1.5, 0.7),
		CFrame = CFrame.new(0.3, 3.1, 0.2) * CFrame.Angles(0.25, 0.6, -0.3),
		Color = Color3.fromRGB(80, 230, 255),
		Material = Enum.Material.Neon,
	}, model)
	weld(body, crown, "CrownWeld")

	buildHealthBar(root)
	return model
end

-- Constructores por nombre de modelo (EnemyConfig.ModelName).
ModelFactory.Builders = {
	VoidSlime = ModelFactory.buildVoidSlime,
} :: { [string]: (Types.EnemyDef) -> Model }

return ModelFactory
