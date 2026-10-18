--[[
	ModelFactory
	Plantillas de enemigos y la Espada del Vendaval. EnemyService clona las
	plantillas desde ServerStorage/EnemyModels.

	Todas las criaturas comparten la misma base física, que es lo que mueve la IA:
	  Root (colisionador esférico invisible) + RootAttachment + Mover
	  (LinearVelocity en el plano) + Facing (AlignOrientation) + HealthBar.
	La esfera sube sola escalones bajos (borde de la plaza, altar, tablones del
	puente); una caja sin fricción se quedaba atascada contra ellos.
	Lo visible va soldado al Root sin masa ni colisión, así que el cliente puede
	animarlo libremente sin afectar a la física ni al combate.

	  Slime     cuerpo elipsoidal; el cliente anima BodyWeld.C0 y BodyMesh.Scale.
	  Skeleton  rig R15 del asset ServerStorage/SkyBonkAssets/SkeletonRig
	            (mallas oficiales de Roblox, sin scripts) con AnimationController;
	            el cliente reproduce las animaciones de Roblox (paquete Zombie).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage.Shared.Types)
local VisualConfig = require(ReplicatedStorage.Shared.Config.VisualConfig)

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

local function buildHealthBar(root: BasePart, height: number, width: number)
	local gui = Instance.new("BillboardGui")
	gui.Name = "HealthBar"
	gui.Adornee = root
	gui.Size = UDim2.new(width, 0, 0.38, 0)
	gui.StudsOffset = Vector3.new(0, height, 0)
	gui.MaxDistance = 110
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.ResetOnSpawn = false
	-- Oculta hasta el primer impacto (menos ruido visual con muchos enemigos).
	gui.Enabled = false

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

-- Base física común: colisionador esférico, movimiento en el plano y orientación.
local function buildPhysicsRoot(model: Model, diameter: number): BasePart
	local size = Vector3.new(diameter, diameter, diameter)
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Shape = Enum.PartType.Ball
	root.Size = size
	root.CFrame = CFrame.new(0, size.Y / 2, 0)
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
	mover.MaxForce = 30000 * (size.X * size.Z) / 11.56
	mover.Parent = root

	-- Mantiene a la criatura erguida y mirando hacia su objetivo.
	local facing = Instance.new("AlignOrientation")
	facing.Name = "Facing"
	facing.Mode = Enum.OrientationAlignmentMode.OneAttachment
	facing.Attachment0 = attachment
	facing.Responsiveness = 22
	facing.MaxTorque = 1e7
	facing.RigidityEnabled = false
	facing.CFrame = CFrame.new()
	facing.Parent = root
	return root
end

-- Slime del Vacío (y Rey Slime con Scale > 1): cuerpo elipsoidal y detalles soldados.
function ModelFactory.buildSlime(def: Types.EnemyDef): Model
	local s = def.Scale
	local model = Instance.new("Model")
	model.Name = def.ModelName
	local root = buildPhysicsRoot(model, 3 * s)
	local function at(x: number, y: number, z: number): CFrame
		return CFrame.new(x * s, y * s, z * s)
	end

	local body = visualPart({
		Name = "Body",
		Size = Vector3.new(4, 3, 4) * s,
		CFrame = at(0, 1.5, 0),
		Color = def.Color,
		Transparency = 0.08,
		Reflectance = 0.05,
		CastShadow = true,
	}, model)
	local mesh = Instance.new("SpecialMesh")
	mesh.Name = "BodyMesh"
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = body
	-- El cliente anima BodyWeld.C0 y BodyMesh.Scale (saltos, anticipación, golpes), solo visualmente.
	weld(root, body, "BodyWeld")

	local core = visualPart({
		Name = "Core",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(1.4, 1.4, 1.4) * s,
		CFrame = at(0, 1.5, 0),
		Color = def.Color:Lerp(Color3.new(1, 1, 1), 0.45),
		Material = Enum.Material.Neon,
	}, model)
	weld(body, core, "CoreWeld")

	for _, side in { -1, 1 } do
		local eye = visualPart({
			Name = "Eye",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.85, 0.85, 0.85) * s,
			CFrame = at(side * 0.75, 2, -1.55),
			Color = Color3.fromRGB(250, 248, 255),
		}, model)
		weld(body, eye, "EyeWeld")
		local pupil = visualPart({
			Name = "Pupil",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.42, 0.42, 0.42) * s,
			CFrame = at(side * 0.75, 2, -1.92),
			Color = Color3.fromRGB(24, 10, 40),
		}, model)
		weld(body, pupil, "PupilWeld")
		-- Brillo de anime en la pupila: le da vida y expresión al slime.
		local shine = visualPart({
			Name = "EyeShine",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.16, 0.16, 0.16) * s,
			CFrame = at(side * 0.75 + 0.1, 2.12, -2.08),
			Color = Color3.new(1, 1, 1),
			Material = Enum.Material.Neon,
		}, model)
		weld(body, shine, "ShineWeld")
	end

	if s > 1.5 then
		-- Rey Slime: corona de cristal dorado (se reconoce de lejos como amenaza).
		for index = 0, 4 do
			local angle = index / 5 * math.pi * 2
			local spike = visualPart({
				Name = "CrownSpike",
				Size = Vector3.new(0.45, 1.2, 0.45) * s,
				CFrame = at(math.cos(angle) * 0.75, 3.2, math.sin(angle) * 0.75)
					* CFrame.Angles(math.sin(angle) * 0.25, 0, -math.cos(angle) * 0.25),
				Color = Color3.fromRGB(255, 214, 90),
				Material = Enum.Material.Neon,
			}, model)
			weld(body, spike, "CrownWeld")
		end
	else
		local crown = visualPart({
			Name = "CrownCrystal",
			Size = Vector3.new(0.7, 1.5, 0.7) * s,
			CFrame = at(0.3, 3.1, 0.2) * CFrame.Angles(0.25, 0.6, -0.3),
			Color = Color3.fromRGB(80, 230, 255),
			Material = Enum.Material.Neon,
		}, model)
		weld(body, crown, "CrownWeld")
	end

	buildHealthBar(root, 2.7 * s, 3.6 * s)
	return model
end

local function findSkeletonAsset(): Model?
	-- ServerStorage puede no existir en las pruebas fuera de Studio.
	local ok, serverStorage = pcall(function()
		return game:GetService("ServerStorage")
	end)
	local assets = ok and serverStorage and serverStorage:FindFirstChild("SkyBonkAssets")
	local rig = assets and assets:FindFirstChild("SkeletonRig")
	return if rig and rig:IsA("Model") then rig else nil
end

--[[
	Hueso Errante: rig R15 sobre la base física. Si falta el asset (p. ej. en
	las pruebas fuera de Studio), se usa un cuerpo simple de piezas para que la
	lógica siga funcionando.
]]
function ModelFactory.buildSkeleton(def: Types.EnemyDef): Model
	local s = def.Scale
	local model = Instance.new("Model")
	model.Name = def.ModelName
	local height = 5.2 * s
	-- La esfera hace de "pies"; el rig (sin colisión) va encima.
	local root = buildPhysicsRoot(model, 2.6 * s)

	local asset = findSkeletonAsset()
	if asset == nil then
		local body = visualPart({
			Name = "Body",
			Size = Vector3.new(2, height * 0.9, 1.2),
			CFrame = CFrame.new(0, height * 0.45, 0),
			Color = def.Color,
		}, model)
		weld(root, body, "BodyWeld")
		buildHealthBar(root, height - root.Size.Y / 2 + 0.8, 3)
		return model
	end

	local rig = asset:Clone()
	rig.Name = "Rig"
	if s ~= 1 then
		rig:ScaleTo(s)
	end
	local hrp = rig:FindFirstChild("HumanoidRootPart") :: BasePart
	assert(hrp, "SkeletonRig sin HumanoidRootPart")
	-- Coloca el rig mirando hacia -Z (el frente del Root) y con los pies a ras de su base.
	local boxCFrame, boxSize = rig:GetBoundingBox()
	local feetOffset = hrp.Position.Y - (boxCFrame.Position.Y - boxSize.Y / 2)
	local target = CFrame.new(0, feetOffset + 0.05, 0)
	rig:PivotTo(target * hrp.CFrame:Inverse() * rig:GetPivot())
	for _, descendant in rig:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.Massless = true
		end
	end
	rig.Parent = model
	weld(root, hrp, "RigWeld")

	-- Ojos de vacío: dan identidad al esqueleto y se leen bien a distancia.
	local head = rig:FindFirstChild("Head") :: BasePart?
	if head then
		for _, side in { -1, 1 } do
			local eye = visualPart({
				Name = "VoidEye",
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(0.32, 0.32, 0.32) * s,
				CFrame = head.CFrame * CFrame.new(side * 0.22 * s, 0.1 * s, -0.5 * s),
				Color = Color3.fromRGB(190, 120, 255),
				Material = Enum.Material.Neon,
			}, model)
			weld(head, eye, "EyeWeld")
		end
		-- Llama del vacío sobre el cráneo (el cliente la apaga en calidad baja).
		local flame = Instance.new("ParticleEmitter")
		flame.Name = "SkullFlame"
		flame.Texture = VisualConfig.Textures.Fire
		flame.Color = ColorSequence.new(Color3.fromRGB(220, 160, 255), Color3.fromRGB(120, 50, 220))
		flame.LightEmission = 1
		flame.LightInfluence = 0
		flame.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7 * s), NumberSequenceKeypoint.new(1, 0) })
		flame.Transparency = NumberSequence.new(0.2, 1)
		flame.Lifetime = NumberRange.new(0.3, 0.5)
		flame.Speed = NumberRange.new(2, 3)
		flame.SpreadAngle = Vector2.new(15, 15)
		flame.Rate = 10
		flame.EmissionDirection = Enum.NormalId.Top
		flame.Parent = head
	end

	buildHealthBar(root, height - root.Size.Y / 2 + 0.9, 3.2 * s)
	return model
end

ModelFactory.Builders = {
	Slime = ModelFactory.buildSlime,
	Skeleton = ModelFactory.buildSkeleton,
} :: { [string]: (Types.EnemyDef) -> Model }

--[[
	Espada del Vendaval: modelo decorativo soldado a la mano derecha. El
	cliente la ilumina según las mejoras (más hojas, rayo) y reproduce el tajo.
]]
function ModelFactory.attachGaleSword(character: Model, hand: BasePart): Model
	local existing = character:FindFirstChild("GaleSword")
	if existing then
		existing:Destroy()
	end
	local palette = VisualConfig.Weapons.GaleSword
	local gold = palette.Guard
	local sword = Instance.new("Model")
	sword.Name = "GaleSword"
	-- La empuñadura es la raíz; la hoja apunta a -Z. Medidas en studs.
	local grip = visualPart({
		Name = "Grip",
		Size = Vector3.new(0.26, 0.26, 1.15),
		CFrame = CFrame.new(),
		Color = Color3.fromRGB(46, 36, 72),
		Material = Enum.Material.Fabric,
	}, sword)
	sword.PrimaryPart = grip
	local function piece(props: { [string]: any }, name: string): BasePart
		local part = visualPart(props, sword)
		weld(grip, part, name)
		return part
	end
	-- Anillas doradas de la empuñadura y pomo con gema.
	for index, z in { 0.38, -0.05, -0.42 } do
		piece({
			Name = "GripBand" .. index,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.08, 0.32, 0.32),
			CFrame = CFrame.new(0, 0, z) * CFrame.Angles(0, math.pi / 2, 0),
			Color = gold,
			Material = Enum.Material.Metal,
		}, "BandWeld")
	end
	piece({
		Name = "Pommel",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(0.4, 0.4, 0.4),
		CFrame = CFrame.new(0, 0, 0.7),
		Color = gold,
		Material = Enum.Material.Metal,
	}, "PommelWeld")
	piece({
		Name = "PommelGem",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(0.24, 0.24, 0.24),
		CFrame = CFrame.new(0, 0, 0.86),
		Color = palette.Edge,
		Material = Enum.Material.Neon,
	}, "GemWeld")
	-- Guarda alada: barra central + dos alas inclinadas hacia la empuñadura.
	piece({
		Name = "Guard",
		Size = Vector3.new(0.9, 0.18, 0.28),
		CFrame = CFrame.new(0, 0, -0.62),
		Color = gold,
		Material = Enum.Material.Metal,
	}, "GuardWeld")
	for _, side in { -1, 1 } do
		piece({
			ClassName = "WedgePart",
			Name = "GuardWing",
			Size = Vector3.new(0.12, 0.42, 0.75),
			CFrame = CFrame.new(side * 0.72, 0, -0.5) * CFrame.Angles(0, side * math.rad(28), side * math.rad(90)),
			Color = gold,
			Material = Enum.Material.Metal,
		}, "WingWeld")
	end
	piece({
		Name = "GuardGem",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(0.3, 0.3, 0.3),
		CFrame = CFrame.new(0, 0, -0.66),
		Color = palette.Edge,
		Material = Enum.Material.Neon,
	}, "GuardGemWeld")
	-- Hoja de un solo filo: cuerpo, filo de energía y punta en cuña.
	local blade = piece({
		Name = "Blade",
		Size = Vector3.new(0.1, 0.36, 3.1),
		CFrame = CFrame.new(0, 0.02, -2.3),
		Color = palette.Blade,
		Material = Enum.Material.Glass,
		Transparency = 0.1,
		Reflectance = 0.15,
	}, "BladeWeld")
	piece({
		Name = "Edge",
		Size = Vector3.new(0.12, 0.08, 3.2),
		CFrame = CFrame.new(0, -0.18, -2.35),
		Color = palette.Edge,
		Material = Enum.Material.Neon,
	}, "EdgeWeld")
	piece({
		ClassName = "WedgePart",
		Name = "Tip",
		Size = Vector3.new(0.1, 0.44, 0.9),
		CFrame = CFrame.new(0, -0.02, -4.28) * CFrame.Angles(0, math.pi, 0),
		Color = palette.Blade,
		Material = Enum.Material.Glass,
		Transparency = 0.1,
	}, "TipWeld")
	piece({
		Name = "Rune",
		Size = Vector3.new(0.12, 0.06, 1.5),
		CFrame = CFrame.new(0, 0.1, -1.7),
		Color = VisualConfig.Palette.PlayerCore,
		Material = Enum.Material.Neon,
		Transparency = 0.2,
	}, "RuneWeld")
	-- Puntos de la estela del tajo (el cliente activa la Trail durante el golpe).
	local a0 = Instance.new("Attachment")
	a0.Name = "TrailBase"
	a0.Position = Vector3.new(0, 0, 1.3)
	a0.Parent = blade
	local a1 = Instance.new("Attachment")
	a1.Name = "TrailTip"
	a1.Position = Vector3.new(0, 0, -2.2)
	a1.Parent = blade

	local gripAttachment = hand:FindFirstChild("RightGripAttachment") :: Attachment?
	local gripOffset = if gripAttachment then gripAttachment.CFrame else CFrame.new(0, -1, 0)
	-- La hoja apunta hacia delante con el brazo en reposo
	-- (las demás piezas siguen a la empuñadura por sus soldaduras).
	grip.CFrame = hand.CFrame * gripOffset * CFrame.Angles(-math.pi / 2, 0, 0) * CFrame.new(0, 0, -0.1)
	local handWeld = Instance.new("Weld")
	handWeld.Name = "HandWeld"
	handWeld.Part0 = hand
	handWeld.Part1 = grip
	handWeld.C0 = hand.CFrame:Inverse() * grip.CFrame
	handWeld.Parent = grip
	sword.Parent = character
	return sword
end

return ModelFactory
