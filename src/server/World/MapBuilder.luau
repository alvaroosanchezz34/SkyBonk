--[[
	MapBuilder
	Construye la isla flotante a partir de World/MapLayout. Es determinista
	(semilla en GameConfig.Map.Seed).

	Composición (de dentro afuera):
	  • Plaza Rúnica (centro, aparición): losas, anillo rúnico y pilares con cristales.
	  • Ruinas del Alba (NE): meseta +7 con templo en ruinas; rampa y escalones.
	  • Colina del Viento (NO): colina caminable por todos sus lados.
	  • Bosque Cristalino (SO): árboles, setas, cristales y un estanque.
	  • Jardín de Piedra (SE): agujas de roca y el Mirador (+8) con rampa.
	  • Santuario Flotante (S): isla secundaria unida por un puente colgante.
	  • Cristales de Esencia en las zonas elevadas y alejadas (fuente de XP).
	  • Debajo: acantilados escalonados; alrededor: rocas flotantes y nubes.

	Vegetación y rocas: kit de ServerStorage/SkyBonkAssets/MapKit (modelos de
	Creator Store revisados, sin scripts). Sus mallas no colisionan; cada pieza
	sólida lleva un colisionador simple e invisible en Props, así los enemigos
	no se enganchan en las hojas y las colisiones son predecibles. Si falta el
	kit (pruebas fuera de Studio), se usan formas simples de piezas.

	Jerarquía generada:
	  Map/
	    Ground/        superficies caminables (válidas para generar enemigos)
	    Props/         obstáculos sólidos y colisionadores
	    Decor/         elementos sin colisión
	    Interactables/ Cristales de Esencia (ExperienceService)
	    PlayerSpawn (SpawnLocation, dentro de Ground)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local MapLayout = require(script.Parent.MapLayout)

local MapBuilder = {}

local TAU = math.pi * 2
local SURFACE_Y = MapLayout.SurfaceY

local PALETTE = {
	Grass = Color3.fromRGB(116, 190, 88),
	GrassAlt = Color3.fromRGB(104, 178, 82),
	GrassDark = Color3.fromRGB(86, 156, 74),
	Rim = Color3.fromRGB(214, 196, 140),
	Rock1 = Color3.fromRGB(146, 126, 110),
	Rock2 = Color3.fromRGB(122, 104, 94),
	Rock3 = Color3.fromRGB(102, 88, 86),
	Rock4 = Color3.fromRGB(84, 72, 78),
	Rock5 = Color3.fromRGB(66, 58, 68),
	Cliff = Color3.fromRGB(150, 132, 112),
	Stone = Color3.fromRGB(220, 208, 186),
	StoneDark = Color3.fromRGB(170, 158, 142),
	Path = Color3.fromRGB(196, 184, 160),
	Wood = Color3.fromRGB(140, 96, 62),
	WoodDark = Color3.fromRGB(104, 70, 48),
	Rope = Color3.fromRGB(210, 190, 140),
	Trunk = Color3.fromRGB(122, 84, 58),
	Leaf1 = Color3.fromRGB(70, 150, 84),
	Leaf2 = Color3.fromRGB(96, 178, 92),
	Cloud = Color3.fromRGB(248, 250, 255),
	Water = Color3.fromRGB(96, 190, 255),
	CrystalCyan = Color3.fromRGB(98, 232, 255),
	CrystalViolet = Color3.fromRGB(178, 120, 255),
	CrystalPink = Color3.fromRGB(255, 132, 214),
	Essence = Color3.fromRGB(255, 196, 92),
	Rune = Color3.fromRGB(140, 230, 255),
}

-- Generador congruencial determinista (independiente de Random para poder
-- ejecutar este módulo también fuera de Roblox en las pruebas).
local function makeRng(seed: number)
	local state = seed % 2147483647
	if state <= 0 then
		state += 2147483646
	end
	local rng = {}
	function rng.next(): number
		state = (state * 48271) % 2147483647
		return state / 2147483647
	end
	function rng.range(min: number, max: number): number
		return min + (max - min) * rng.next()
	end
	function rng.pick<T>(list: { T }): T
		return list[math.floor(rng.next() * #list) + 1]
	end
	return rng
end

local function newPart(className: string, props: { [string]: any }, parent: Instance): BasePart
	local part = Instance.new(className) :: BasePart
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = Enum.Material.SmoothPlastic
	for key, value in props do
		(part :: any)[key] = value
	end
	part.Parent = parent
	return part
end

-- Elemento sin colisión ni consultas (no afecta a la física ni a los raycasts).
local function decorProps(props: { [string]: any }): { [string]: any }
	props.CanCollide = false
	props.CanQuery = false
	props.CanTouch = false
	return props
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

--[[
	Capa poligonal: N bloques que, unidos, forman un polígono regular de
	circunradio `radius` centrado en `center`. Cada bloque va del centro a la
	apotema y su cara exterior es un lado del polígono (aspecto facetado).
]]
local function polygonLayer(
	folder: Instance,
	name: string,
	center: Vector3,
	sides: number,
	radius: number,
	topY: number,
	thickness: number,
	color: Color3,
	angleOffset: number,
	material: Enum.Material?
)
	local apothem = radius * math.cos(math.pi / sides)
	local side = 2 * radius * math.sin(math.pi / sides)
	for i = 0, sides - 1 do
		local angle = angleOffset + i * TAU / sides
		local direction = Vector3.new(-math.sin(angle), 0, -math.cos(angle))
		local position = Vector3.new(center.X, topY - thickness / 2, center.Z) + direction * (apothem / 2)
		newPart("Part", {
			Name = string.format("%s_%02d", name, i + 1),
			Size = Vector3.new(side + 0.05, thickness, apothem),
			CFrame = CFrame.new(position) * CFrame.Angles(0, angle, 0),
			Color = color,
			Material = material or Enum.Material.SmoothPlastic,
		}, folder)
	end
end

-- Cuerpo rocoso invertido bajo una superficie poligonal (silueta de isla flotante).
local function cliffs(props: Instance, name: string, center: Vector3, radius: number, topY: number, rng)
	local layers = {
		{ 0.96, 5, 9, PALETTE.Rock1, 9 },
		{ 0.78, 13, 11, PALETTE.Rock2, 8 },
		{ 0.55, 23, 13, PALETTE.Rock3, 7 },
		{ 0.32, 35, 14, PALETTE.Rock4, 6 },
		{ 0.14, 47, 12, PALETTE.Rock5, 5 },
	}
	for index, layer in layers do
		local offset = Vector3.new(rng.range(-2, 2), 0, rng.range(-2, 2)) * index
		polygonLayer(
			props,
			string.format("%sCliff%d", name, index),
			center + offset,
			layer[5],
			radius * layer[1],
			topY - layer[2] + layer[3] / 2,
			layer[3],
			layer[4],
			rng.range(0, TAU)
		)
	end
end

------------------------------------------------------------------- Kit
type KitSpec = {
	Asset: string,
	Scale: { number }, -- rango de escala
	-- Trunk: cilindro (Radius en studs, Height en studs a escala media).
	-- Box: caja orientada (Radius y Height son fracciones del tamaño del modelo).
	Collider: { Kind: string, Radius: number, Height: number }?,
	Fallback: string, -- forma simple si falta el kit
}

local KIT: { [string]: KitSpec } = {
	TreeRound = {
		Asset = "Tree_Round",
		Scale = { 0.5, 0.65 },
		Collider = { Kind = "Trunk", Radius = 1.4, Height = 12 },
		Fallback = "Tree",
	},
	TreeTwist = {
		Asset = "Tree_Twist",
		Scale = { 0.55, 0.7 },
		Collider = { Kind = "Trunk", Radius = 1.2, Height = 10 },
		Fallback = "Tree",
	},
	TreePine = {
		Asset = "Tree_Pine",
		Scale = { 0.3, 0.42 },
		Collider = { Kind = "Trunk", Radius = 2.2, Height = 14 },
		Fallback = "Tree",
	},
	TreeBlossom = {
		Asset = "Tree_Blossom",
		Scale = { 0.85, 1.1 },
		Collider = { Kind = "Trunk", Radius = 0.9, Height = 8 },
		Fallback = "Tree",
	},
	TreeNormal = {
		Asset = "Tree_Normal",
		Scale = { 0.6, 0.8 },
		Collider = { Kind = "Trunk", Radius = 1.6, Height = 9 },
		Fallback = "Tree",
	},
	TreeDead = {
		Asset = "Tree_Dead",
		Scale = { 0.55, 0.7 },
		Collider = { Kind = "Trunk", Radius = 0.8, Height = 8 },
		Fallback = "Tree",
	},
	BushBig = { Asset = "Bush_Big", Scale = { 0.6, 0.85 }, Collider = nil, Fallback = "Bush" },
	BushSmall = { Asset = "Bush_Small", Scale = { 0.9, 1.3 }, Collider = nil, Fallback = "Bush" },
	GrassA = { Asset = "Grass_A", Scale = { 0.6, 0.9 }, Collider = nil, Fallback = "None" },
	GrassB = { Asset = "Grass_B", Scale = { 0.8, 1.2 }, Collider = nil, Fallback = "None" },
	GrassC = { Asset = "Grass_C", Scale = { 1, 1.5 }, Collider = nil, Fallback = "None" },
	Mushrooms = { Asset = "Mushrooms", Scale = { 0.6, 0.9 }, Collider = nil, Fallback = "None" },
	Log = {
		Asset = "Log",
		Scale = { 0.8, 1 },
		Collider = { Kind = "Box", Radius = 0.85, Height = 0.75 },
		Fallback = "Rock",
	},
	Boulder = {
		Asset = "Boulder_A",
		Scale = { 0.8, 1.3 },
		Collider = { Kind = "Box", Radius = 0.8, Height = 0.8 },
		Fallback = "Rock",
	},
	Rock = {
		Asset = "Rock_",
		Scale = { 0.7, 1.2 },
		Collider = { Kind = "Box", Radius = 0.8, Height = 0.85 },
		Fallback = "Rock",
	},
	Spire = {
		Asset = "Rock_",
		Scale = { 1.5, 2.1 },
		Collider = { Kind = "Box", Radius = 0.72, Height = 0.9 },
		Fallback = "Rock",
	},
}

local kitFolder: Instance? = nil

local function findKit(): Instance?
	local ok, serverStorage = pcall(function()
		return game:GetService("ServerStorage")
	end)
	local assets = ok and serverStorage and serverStorage:FindFirstChild("SkyBonkAssets")
	return assets and assets:FindFirstChild("MapKit")
end

local function fallbackShape(kind: string, position: Vector3, scale: number, yaw: number, decor: Instance, rng)
	if kind == "Tree" then
		newPart(
			"Part",
			decorProps({
				Name = "TreeTrunk",
				Size = Vector3.new(1.6, 7, 1.6) * scale * 1.5,
				CFrame = CFrame.new(position + Vector3.new(0, 5 * scale, 0)) * CFrame.Angles(0, yaw, 0),
				Color = PALETTE.Trunk,
			}),
			decor
		)
		newPart(
			"Part",
			decorProps({
				Name = "TreeCanopy",
				Size = Vector3.new(7, 5.5, 7) * scale * 1.5,
				CFrame = CFrame.new(position + Vector3.new(0, 11 * scale, 0)) * CFrame.Angles(0.2, yaw, 0.3),
				Color = rng.pick({ PALETTE.Leaf1, PALETTE.Leaf2 }),
			}),
			decor
		)
	elseif kind == "Bush" then
		newPart(
			"Part",
			decorProps({
				Name = "Bush",
				Size = Vector3.new(3, 2.2, 3) * scale,
				CFrame = CFrame.new(position + Vector3.new(0, 0.9 * scale, 0)) * CFrame.Angles(0, yaw, 0.2),
				Color = PALETTE.Leaf2,
			}),
			decor
		)
	elseif kind == "Rock" then
		newPart(
			"Part",
			decorProps({
				Name = "Rock",
				Size = Vector3.new(4, 3.4, 4.4) * scale,
				CFrame = CFrame.new(position + Vector3.new(0, 1.2 * scale, 0)) * CFrame.Angles(0.3, yaw, 0.25),
				Color = rng.pick({ PALETTE.Rock1, PALETTE.Rock2 }),
			}),
			decor
		)
	end
end

--[[
	Coloca una pieza del kit apoyada en `position` (base). Devuelve el tamaño
	aproximado ocupado. Los colisionadores van a Props (sólidos y consultables).
]]
local function placeKit(kind: string, position: Vector3, rng, decor: Instance, props: Instance, scaleMul: number?)
	local spec = KIT[kind]
	local scale = rng.range(spec.Scale[1], spec.Scale[2]) * (scaleMul or 1)
	local yaw = rng.range(0, TAU)
	local template: Instance? = nil
	if kitFolder then
		if spec.Asset == "Rock_" then
			template = kitFolder:FindFirstChild("Rock_" .. (math.floor(rng.next() * 10) + 1))
		else
			template = kitFolder:FindFirstChild(spec.Asset)
		end
	end
	local size = Vector3.new(4, 4, 4) * scale
	if template and template:IsA("Model") then
		local model = template:Clone()
		if scale ~= 1 then
			model:ScaleTo(scale)
		end
		model:PivotTo(CFrame.new(position) * CFrame.Angles(0, yaw, 0))
		if spec.Fallback == "Rock" then
			-- Las rocas del pack son blanco azuladas: se tiñen con la paleta cálida de la isla.
			local tint = rng.pick({ PALETTE.Rock1, PALETTE.Rock2, PALETTE.Cliff, PALETTE.StoneDark })
			for _, part in model:GetDescendants() do
				if part:IsA("MeshPart") and part.TextureID == "" then
					part.Color = tint
					part.Material = Enum.Material.Slate
				end
			end
		end
		local baseSize = template:GetAttribute("BaseSize")
		if typeof(baseSize) == "Vector3" then
			size = baseSize * scale
		end
		model.Parent = decor
	else
		fallbackShape(spec.Fallback, position, scale, yaw, decor, rng)
	end
	local collider = spec.Collider
	if collider then
		if collider.Kind == "Trunk" then
			local height = collider.Height * scale / (spec.Scale[1] + spec.Scale[2]) * 2
			newPart("Part", {
				Name = kind .. "Collider",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(height, collider.Radius * 2, collider.Radius * 2),
				CFrame = CFrame.new(position + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2),
				Transparency = 1,
				CastShadow = false,
			}, props)
		else
			-- Caja orientada como el modelo: Radius y Height son fracciones de su tamaño.
			local height = size.Y * collider.Height
			newPart("Part", {
				Name = kind .. "Collider",
				Size = Vector3.new(size.X * collider.Radius, height, size.Z * collider.Radius),
				CFrame = CFrame.new(position + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, yaw, 0),
				Transparency = 1,
				CastShadow = false,
			}, props)
		end
	end
	return size
end

-- Zonas que deben quedar libres (plaza, rampas, puente, accesos).
local clearZones: { { Center: Vector3, Radius: number } } = {}

local function isClear(position: Vector3, radius: number): boolean
	for _, zone in clearZones do
		if (flat(position) - flat(zone.Center)).Magnitude < zone.Radius + radius then
			return false
		end
	end
	return true
end

local function reserve(center: Vector3, radius: number)
	table.insert(clearZones, { Center = center, Radius = radius })
end

local function reserveSegment(a: Vector3, b: Vector3, radius: number)
	local length = (flat(b) - flat(a)).Magnitude
	local steps = math.max(1, math.ceil(length / radius))
	for i = 0, steps do
		reserve(a:Lerp(b, i / steps), radius)
	end
end

-- Esparce piezas del kit alrededor de un centro sin invadir zonas libres.
local function scatter(
	kinds: { string },
	center: Vector3,
	minR: number,
	maxR: number,
	count: number,
	spacing: number,
	rng,
	decor,
	props,
	baseY: number?
)
	local placed = 0
	local attempts = 0
	while placed < count and attempts < count * 8 do
		attempts += 1
		local angle = rng.range(0, TAU)
		local distance = rng.range(minR, maxR)
		local position = Vector3.new(
			center.X + math.cos(angle) * distance,
			baseY or SURFACE_Y,
			center.Z + math.sin(angle) * distance
		)
		if not MapLayout.isWalkable(position, 3) or not isClear(position, spacing) then
			continue
		end
		local inMesa = false
		for _, mesa in MapLayout.Mesas do
			if
				(flat(position) - flat(mesa.Center)).Magnitude
				< mesa.Radius + (if mesa.Ramped then mesa.Height * 2.4 else 1)
			then
				inMesa = true
			end
		end
		if inMesa and baseY == nil then
			continue
		end
		placeKit(rng.pick(kinds), position, rng, decor, props)
		reserve(position, spacing * 0.5)
		placed += 1
	end
end

------------------------------------------------------------- Elementos
local function buildCrystalCluster(
	parent: Instance,
	name: string,
	base: Vector3,
	rng,
	withLight: boolean,
	color: Color3?
)
	local cluster = Instance.new("Model")
	cluster.Name = name
	local tint = color or rng.pick({ PALETTE.CrystalCyan, PALETTE.CrystalViolet, PALETTE.CrystalPink })
	for index = 1, 4 do
		local height = if index == 1 then rng.range(5, 7.5) else rng.range(2, 4.5)
		local width = if index == 1 then 1.6 else 1.1
		local shard = newPart(
			"Part",
			decorProps({
				Name = "Shard" .. index,
				Size = Vector3.new(width, height, width),
				CFrame = CFrame.new(base + Vector3.new(rng.range(-1.4, 1.4), height / 2 - 0.4, rng.range(-1.4, 1.4)))
					* CFrame.Angles(math.rad(rng.range(-25, 25)), rng.range(0, TAU), math.rad(rng.range(-25, 25))),
				Color = tint,
				Material = if index == 1 then Enum.Material.Neon else Enum.Material.Glass,
				Transparency = if index == 1 then 0 else 0.2,
				CastShadow = false,
			}),
			cluster
		)
		if index == 1 and withLight then
			local light = Instance.new("PointLight")
			light.Color = tint
			light.Range = 14
			light.Brightness = 1.6
			light.Shadows = false
			light.Parent = shard
		end
	end
	cluster.Parent = parent
	return cluster
end

-- Cristal de Esencia: se rompe al tocarlo y suelta gemas (ExperienceService).
local function buildEssenceCrystal(interactables: Instance, props: Instance, index: number, base: Vector3)
	local model = Instance.new("Model")
	model.Name = "EssenceCrystal" .. index
	newPart("Part", {
		Name = "Pedestal",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.8, 4.4, 4.4),
		CFrame = CFrame.new(base + Vector3.new(0, 0.4, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Color = PALETTE.StoneDark,
		Material = Enum.Material.Slate,
	}, props)
	local core = newPart(
		"Part",
		decorProps({
			Name = "Core",
			Size = Vector3.new(1.8, 4.2, 1.8),
			CFrame = CFrame.new(base + Vector3.new(0, 3.3, 0)) * CFrame.Angles(0, math.rad(45), 0),
			Color = PALETTE.Essence,
			Material = Enum.Material.Neon,
			CastShadow = false,
		}),
		model
	)
	for i = 1, 3 do
		local angle = i / 3 * TAU
		newPart(
			"Part",
			decorProps({
				Name = "Shard",
				Size = Vector3.new(0.8, 2.2, 0.8),
				CFrame = CFrame.new(base + Vector3.new(math.cos(angle) * 1.4, 1.8, math.sin(angle) * 1.4))
					* CFrame.Angles(math.sin(angle) * 0.5, angle, math.cos(angle) * 0.5),
				Color = PALETTE.Essence:Lerp(Color3.new(1, 1, 1), 0.3),
				Material = Enum.Material.Glass,
				Transparency = 0.15,
				CastShadow = false,
			}),
			model
		)
	end
	local light = Instance.new("PointLight")
	light.Color = PALETTE.Essence
	light.Range = 12
	light.Brightness = 1.8
	light.Shadows = false
	light.Parent = core
	model.PrimaryPart = core
	model.WorldPivot = CFrame.new(base + Vector3.new(0, 2, 0))
	model:SetAttribute("EssenceCrystal", true)
	model.Parent = interactables
	reserve(base, 4)
	return model
end

local function buildIsland(ground: Folder, props: Folder, rng)
	for index, lobe in MapLayout.Lobes do
		local top = SURFACE_Y + (index - 1) * 0.02
		local grass = if index % 2 == 0 then PALETTE.GrassAlt else PALETTE.Grass
		polygonLayer(
			ground,
			"Lobe" .. index .. "Surface",
			lobe.Center,
			lobe.Sides,
			lobe.Radius,
			top,
			4,
			grass,
			lobe.Angle,
			Enum.Material.Grass
		)
		-- Borde algo más bajo y de otro color: marca claramente el final de la isla.
		polygonLayer(
			ground,
			"Lobe" .. index .. "Rim",
			lobe.Center,
			lobe.Sides,
			lobe.Radius + 4,
			top - 0.5,
			5,
			PALETTE.Rim,
			lobe.Angle + math.pi / lobe.Sides,
			Enum.Material.Sand
		)
		cliffs(props, "Lobe" .. index, lobe.Center, lobe.Radius + 3, top - 1, rng)
	end
end

local function buildSpawnPlaza(ground: Folder, props: Folder, decor: Folder, rng): SpawnLocation
	local spawnPosition = GameConfig.Map.PlayerSpawn
	local center = Vector3.new(spawnPosition.X, SURFACE_Y, spawnPosition.Z)
	newPart("Part", {
		Name = "SpawnPlaza", -- a ras del suelo (0,08 por encima): no es un escalón para los enemigos
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.6, 26, 26),
		CFrame = CFrame.new(center + Vector3.new(0, -0.22, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Color = PALETTE.Stone,
		Material = Enum.Material.Slate,
	}, ground)
	newPart(
		"Part",
		decorProps({
			Name = "SpawnRuneRing",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.65, 16, 16),
			CFrame = CFrame.new(center + Vector3.new(0, -0.2, 0)) * CFrame.Angles(0, 0, math.pi / 2),
			Color = PALETTE.Rune,
			Material = Enum.Material.Neon,
			Transparency = 0.6,
		}),
		decor
	)
	-- Cuatro pilares rúnicos con cristal: la plaza se reconoce desde cualquier punto.
	-- Van en los huecos entre los caminos (45°, 90°, 147°, 236° y 304°) para no cortarlos.
	for _, degrees in { 118, 191, 270, 354 } do
		local angle = math.rad(degrees)
		local base = center + Vector3.new(math.cos(angle) * 11, 0, math.sin(angle) * 11)
		newPart("Part", {
			Name = "RunePillar",
			Size = Vector3.new(1.8, 5, 1.8),
			CFrame = CFrame.new(base + Vector3.new(0, 2.5, 0)) * CFrame.Angles(0, angle, 0),
			Color = PALETTE.StoneDark,
			Material = Enum.Material.Slate,
		}, props)
		newPart(
			"Part",
			decorProps({
				Name = "RuneCrystal",
				Size = Vector3.new(1, 2.2, 1),
				CFrame = CFrame.new(base + Vector3.new(0, 6.3, 0)) * CFrame.Angles(0, angle + math.pi / 4, 0),
				Color = PALETTE.Rune,
				Material = Enum.Material.Neon,
				CastShadow = false,
			}),
			decor
		)
	end
	-- Losas alrededor de la plaza.
	for i = 1, 22 do
		local angle = i / 22 * TAU + rng.range(-0.08, 0.08)
		local distance = rng.range(14, 17)
		newPart(
			"Part",
			decorProps({
				Name = "PlazaTile",
				Size = Vector3.new(rng.range(2.2, 3.4), 0.3, rng.range(2.2, 3.4)),
				CFrame = CFrame.new(center + Vector3.new(math.cos(angle) * distance, 0.1, math.sin(angle) * distance))
					* CFrame.Angles(0, angle + rng.range(-0.3, 0.3), 0),
				Color = if i % 3 == 0 then PALETTE.StoneDark else PALETTE.Path,
				Material = Enum.Material.Slate,
			}),
			decor
		)
	end
	reserve(center, 18)

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "PlayerSpawn"
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0 -- sin campo de fuerza
	spawn.Size = Vector3.new(6, 0.4, 6)
	spawn.CFrame = CFrame.new(spawnPosition.X, SURFACE_Y + 0.2, spawnPosition.Z)
	spawn.Color = PALETTE.StoneDark
	spawn.Material = Enum.Material.Slate
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = ground
	return spawn
end

-- Camino de losas irregulares (decorativo, guía la exploración).
local function buildPath(decor: Folder, from: Vector3, to: Vector3, width: number, rng)
	local length = (flat(to) - flat(from)).Magnitude
	local direction = (flat(to) - flat(from)).Unit
	local side = Vector3.new(-direction.Z, 0, direction.X)
	local steps = math.floor(length / 3.2)
	for i = 0, steps do
		local t = i / math.max(1, steps)
		local base = from:Lerp(to, t)
		local offset = side * rng.range(-width / 3, width / 3)
		newPart(
			"Part",
			decorProps({
				Name = "PathStone",
				Size = Vector3.new(rng.range(2, 3.2), 0.25, rng.range(2, 3)),
				CFrame = CFrame.new(Vector3.new(base.X, base.Y + 0.08, base.Z) + offset)
					* CFrame.Angles(0, math.atan2(direction.X, direction.Z) + rng.range(-0.4, 0.4), 0),
				Color = if rng.next() < 0.3 then PALETTE.StoneDark else PALETTE.Path,
				Material = Enum.Material.Slate,
			}),
			decor
		)
	end
	reserveSegment(from, to, width / 2 + 1)
end

-- Rampa caminable de `bottom` a `top` (la cara frontal de la WedgePart es el extremo bajo).
local function buildRamp(ground: Folder, name: string, bottom: Vector3, top: Vector3, width: number, color: Color3)
	local horizontal = flat(top) - flat(bottom)
	local length = horizontal.Magnitude
	local height = top.Y - bottom.Y
	local midpoint = flat(bottom) + horizontal / 2 + Vector3.new(0, bottom.Y + height / 2, 0)
	newPart("WedgePart", {
		Name = name,
		Size = Vector3.new(width, height, length),
		CFrame = CFrame.lookAt(midpoint, midpoint - horizontal),
		Color = color,
		Material = Enum.Material.Slate,
	}, ground)
	-- Bordillos de piedra a los lados (decorativos).
	local direction = horizontal.Unit
	local sideDir = Vector3.new(-direction.Z, 0, direction.X)
	for _, sign in { -1, 1 } do
		local edgeMid = midpoint + sideDir * sign * (width / 2 + 0.4)
		newPart(
			"WedgePart",
			decorProps({
				Name = name .. "Curb",
				Size = Vector3.new(0.8, height + 0.6, length),
				CFrame = CFrame.lookAt(edgeMid + Vector3.new(0, 0.3, 0), edgeMid + Vector3.new(0, 0.3, 0) - horizontal),
				Color = PALETTE.StoneDark,
				Material = Enum.Material.Slate,
			}),
			ground.Parent:FindFirstChild("Decor") :: Instance
		)
	end
	reserveSegment(bottom, top, width / 2 + 2)
end

local function buildMesa(ground: Folder, props: Folder, mesa: MapLayout.Mesa, rng)
	local top = SURFACE_Y + mesa.Height
	-- Paredes de roca y tapa de hierba.
	polygonLayer(
		props,
		mesa.Id .. "Wall",
		mesa.Center,
		mesa.Sides,
		mesa.Radius,
		top - 0.6,
		mesa.Height + 3.4,
		PALETTE.Cliff,
		mesa.Angle,
		Enum.Material.Slate
	)
	polygonLayer(
		ground,
		mesa.Id .. "Top",
		mesa.Center,
		mesa.Sides,
		mesa.Radius - 0.4,
		top,
		0.8,
		PALETTE.GrassDark,
		mesa.Angle,
		Enum.Material.Grass
	)
	if mesa.Ramped then
		-- Rampas en todos los lados: la colina se sube desde cualquier dirección.
		local run = mesa.Height * 2.4
		local apothem = mesa.Radius * math.cos(math.pi / mesa.Sides)
		local sideLength = 2 * mesa.Radius * math.sin(math.pi / mesa.Sides)
		for i = 0, mesa.Sides - 1 do
			local angle = mesa.Angle + i * TAU / mesa.Sides
			local outward = Vector3.new(-math.sin(angle), 0, -math.cos(angle))
			local position = Vector3.new(mesa.Center.X, SURFACE_Y + mesa.Height / 2, mesa.Center.Z)
				+ outward * (apothem + run / 2 - 0.05)
			newPart("WedgePart", {
				Name = mesa.Id .. "Slope" .. (i + 1),
				Size = Vector3.new(sideLength + 0.4, mesa.Height, run),
				CFrame = CFrame.lookAt(position, position + outward),
				Color = PALETTE.Grass,
				Material = Enum.Material.Grass,
			}, ground)
		end
		reserve(mesa.Center, mesa.Radius + run * 0.6)
	end
	-- Rocas sueltas al pie de las paredes.
	if not mesa.Ramped then
		for i = 1, mesa.Sides do
			if rng.next() < 0.6 then
				local angle = mesa.Angle + (i + 0.5) * TAU / mesa.Sides
				local position = mesa.Center
					+ Vector3.new(
						math.sin(angle) * (mesa.Radius + 1.5),
						SURFACE_Y,
						math.cos(angle) * (mesa.Radius + 1.5)
					)
				if isClear(position, 2) then
					placeKit("Rock", position, rng, props.Parent:FindFirstChild("Decor") :: Instance, props)
				end
			end
		end
	end
end

local function buildRuins(ground: Folder, props: Folder, decor: Folder, rng)
	local mesa = MapLayout.mesaById("Ruins") :: MapLayout.Mesa
	local top = SURFACE_Y + mesa.Height
	local center = Vector3.new(mesa.Center.X, top, mesa.Center.Z)
	-- Templo: círculo de columnas (algunas rotas) alrededor de un patio abierto,
	-- con un hueco frente a la llegada de la rampa (no bloquea la entrada).
	local rampDir = (flat(MapLayout.Links[1].Exit) - flat(mesa.Center)).Unit
	local rampAngle = math.atan2(rampDir.Z, rampDir.X)
	for i = 0, 7 do
		local angle = i * TAU / 8 + 0.2
		local gap = math.abs((angle - rampAngle + math.pi) % TAU - math.pi)
		if gap < 0.55 then
			continue
		end
		local base = center + Vector3.new(math.cos(angle) * 12.5, 0, math.sin(angle) * 12.5)
		local broken = i % 3 == 1
		local height = if broken then rng.range(2.5, 4.5) else rng.range(8, 10)
		newPart("Part", {
			Name = "TempleColumnBase",
			Size = Vector3.new(3.2, 0.8, 3.2),
			CFrame = CFrame.new(base + Vector3.new(0, 0.4, 0)) * CFrame.Angles(0, angle, 0),
			Color = PALETTE.StoneDark,
			Material = Enum.Material.Slate,
		}, props)
		newPart("Part", {
			Name = "TempleColumn",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(height, 2.3, 2.3),
			CFrame = CFrame.new(base + Vector3.new(0, 0.8 + height / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2),
			Color = PALETTE.Stone,
			Material = Enum.Material.Limestone,
		}, props)
		if broken then
			newPart(
				"Part",
				decorProps({
					Name = "FallenDrum",
					Shape = Enum.PartType.Cylinder,
					Size = Vector3.new(2.6, 2.2, 2.2),
					CFrame = CFrame.new(base + Vector3.new(2.6, 1.1, 1.2)) * CFrame.Angles(0, angle, 0.1),
					Color = PALETTE.Stone,
					Material = Enum.Material.Limestone,
				}),
				decor
			)
		else
			newPart(
				"Part",
				decorProps({
					Name = "Capital",
					Size = Vector3.new(3, 0.8, 3),
					CFrame = CFrame.new(base + Vector3.new(0, 1.2 + height, 0)) * CFrame.Angles(0, angle, 0),
					Color = PALETTE.StoneDark,
					Material = Enum.Material.Slate,
				}),
				decor
			)
		end
	end
	-- Arco en ruinas sobre la llegada de la rampa (marca la entrada).
	local link = MapLayout.Links[1]
	local entryDir = (flat(link.Exit) - flat(mesa.Center)).Unit
	local archCenter = center + entryDir * 9
	local archSide = Vector3.new(-entryDir.Z, 0, entryDir.X)
	for _, sign in { -1, 1 } do
		newPart("Part", {
			Name = "ArchPillar",
			Size = Vector3.new(2.6, 11, 2.6),
			CFrame = CFrame.new(archCenter + archSide * sign * 6 + Vector3.new(0, 5.5, 0)),
			Color = PALETTE.Stone,
			Material = Enum.Material.Limestone,
		}, props)
	end
	newPart(
		"Part",
		decorProps({
			Name = "ArchLintel",
			Size = Vector3.new(15, 2.2, 3.2),
			CFrame = CFrame.lookAt(archCenter + Vector3.new(0, 12, 0), archCenter + Vector3.new(0, 12, 0) + entryDir)
				* CFrame.Angles(0, 0, math.rad(5)),
			Color = PALETTE.StoneDark,
			Material = Enum.Material.Slate,
		}),
		decor
	)
	-- Altar central (el cristal de esencia va encima).
	newPart("Part", {
		Name = "Altar",
		Size = Vector3.new(7, 0.6, 7),
		CFrame = CFrame.new(Vector3.new(66, top + 0.3, 44)) * CFrame.Angles(0, math.rad(45), 0),
		Color = PALETTE.Stone,
		Material = Enum.Material.Slate,
	}, ground)
	-- Muros derruidos al pie de la meseta.
	local walls = {
		{ Vector3.new(36, SURFACE_Y, 52), 10, 3.5, 0.4 },
		{ Vector3.new(78, SURFACE_Y, 18), 8, 4.5, 1.2 },
		{ Vector3.new(44, SURFACE_Y, 62), 7, 2.5, -0.6 },
	}
	for index, wall in walls do
		local position: Vector3 = wall[1]
		newPart("Part", {
			Name = "RuinedWall" .. index,
			Size = Vector3.new(wall[2], wall[3], 1.8),
			CFrame = CFrame.new(position + Vector3.new(0, wall[3] / 2, 0)) * CFrame.Angles(0, wall[4], 0),
			Color = PALETTE.StoneDark,
			Material = Enum.Material.Slate,
		}, props)
		reserve(position, 4)
	end
	-- Escalones de piedra (acceso alternativo saltando, ~2,3 studs cada uno).
	local stepDir = Vector3.new(0.45, 0, 1).Unit
	for i = 1, 3 do
		local position = mesa.Center + stepDir * (mesa.Radius + 7.5 - i * 2.6)
		local height = i * 2.3
		newPart("Part", {
			Name = "StoneStep" .. i,
			Size = Vector3.new(4.2, height, 4.2),
			CFrame = CFrame.new(position.X, SURFACE_Y + height / 2, position.Z) * CFrame.Angles(0, rng.range(0, 1), 0),
			Color = if i % 2 == 0 then PALETTE.Rock1 else PALETTE.Rock2,
			Material = Enum.Material.Slate,
		}, ground)
		reserve(Vector3.new(position.X, 0, position.Z), 3)
	end
end

local function buildBridge(ground: Folder, props: Folder, decor: Folder)
	local bridge = MapLayout.Bridge
	local from, to = bridge.From, bridge.To
	local horizontal = flat(to) - flat(from)
	local length = horizontal.Magnitude
	local direction = horizontal.Unit
	local side = Vector3.new(-direction.Z, 0, direction.X)
	local plankLength = 2.4
	local count = math.ceil(length / plankLength)
	for i = 0, count - 1 do
		local t = (i + 0.5) / count
		local position = from:Lerp(to, t)
		-- Ligera curva colgante del puente.
		local sag = math.sin(t * math.pi) * -0.8
		newPart("Part", {
			Name = "BridgePlank",
			Size = Vector3.new(bridge.Width, 0.5, plankLength - 0.15),
			CFrame = CFrame.lookAt(position + Vector3.new(0, sag, 0), position + Vector3.new(0, sag, 0) + horizontal)
				* CFrame.Angles(math.atan2(to.Y - from.Y, length), 0, 0),
			Color = if i % 2 == 0 then PALETTE.Wood else PALETTE.WoodDark,
			Material = Enum.Material.WoodPlanks,
		}, ground)
	end
	-- Postes y cuerdas (fuera del ancho caminable).
	local postCount = math.floor(length / 7)
	local previous: { [number]: Vector3 } = {}
	for i = 0, postCount do
		local t = i / postCount
		local base = from:Lerp(to, t) + Vector3.new(0, math.sin(t * math.pi) * -0.8, 0)
		for _, sign in { -1, 1 } do
			local postBase = base + side * sign * (bridge.Width / 2 + 0.3)
			newPart("Part", {
				Name = "BridgePost",
				Size = Vector3.new(0.6, 3.4, 0.6),
				CFrame = CFrame.new(postBase + Vector3.new(0, 1.2, 0)),
				Color = PALETTE.WoodDark,
				Material = Enum.Material.Wood,
			}, props)
			local topPoint = postBase + Vector3.new(0, 2.6, 0)
			local last = previous[sign]
			if last then
				local mid = (last + topPoint) / 2 - Vector3.new(0, 0.3, 0)
				newPart(
					"Part",
					decorProps({
						Name = "BridgeRope",
						Size = Vector3.new(0.18, 0.18, (topPoint - last).Magnitude),
						CFrame = CFrame.lookAt(mid, topPoint),
						Color = PALETTE.Rope,
						Material = Enum.Material.Fabric,
					}),
					decor
				)
			end
			previous[sign] = topPoint
		end
	end
	reserveSegment(from - direction * 6, to + direction * 4, bridge.Width / 2 + 2)
end

local function buildSanctuary(ground: Folder, props: Folder, decor: Folder, rng)
	local s = MapLayout.Sanctuary
	local top = s.Center.Y
	polygonLayer(
		ground,
		"SanctuarySurface",
		s.Center,
		s.Sides,
		s.Radius,
		top,
		4,
		PALETTE.GrassDark,
		s.Angle,
		Enum.Material.Grass
	)
	polygonLayer(
		ground,
		"SanctuaryRim",
		s.Center,
		s.Sides,
		s.Radius + 3,
		top - 0.5,
		5,
		PALETTE.Rim,
		s.Angle + math.pi / s.Sides,
		Enum.Material.Sand
	)
	cliffs(props, "Sanctuary", s.Center, s.Radius + 2, top - 1, rng)
	-- Círculo de piedras erguidas alrededor del obelisco.
	local center = Vector3.new(s.Center.X, top, s.Center.Z)
	for i = 0, 5 do
		local angle = i * TAU / 6 + 0.3
		local base = center + Vector3.new(math.cos(angle) * 13, 0, math.sin(angle) * 13)
		local height = rng.range(4.5, 7)
		newPart("Part", {
			Name = "StandingStone",
			Size = Vector3.new(2, height, 1.3),
			CFrame = CFrame.new(base + Vector3.new(0, height / 2, 0))
				* CFrame.Angles(rng.range(-0.08, 0.08), -angle, rng.range(-0.08, 0.08)),
			Color = PALETTE.Rock1,
			Material = Enum.Material.Slate,
		}, props)
	end
	-- Obelisco de cristal: punto de interés visible desde la isla principal.
	newPart("Part", {
		Name = "ObeliskBase",
		Size = Vector3.new(4, 1.2, 4),
		CFrame = CFrame.new(center + Vector3.new(0, 0.6, 0)) * CFrame.Angles(0, math.rad(45), 0),
		Color = PALETTE.StoneDark,
		Material = Enum.Material.Slate,
	}, props)
	local obelisk = newPart(
		"Part",
		decorProps({
			Name = "Obelisk",
			Size = Vector3.new(1.6, 11, 1.6),
			CFrame = CFrame.new(center + Vector3.new(0, 7.2, 0)) * CFrame.Angles(0, math.rad(45), 0),
			Color = PALETTE.CrystalViolet,
			Material = Enum.Material.Neon,
			CastShadow = false,
		}),
		decor
	)
	local light = Instance.new("PointLight")
	light.Color = PALETTE.CrystalViolet
	light.Range = 20
	light.Brightness = 2
	light.Shadows = false
	light.Parent = obelisk
	reserve(center, 3.5)
	scatter(
		{ "TreeBlossom", "TreeBlossom", "BushBig", "GrassA", "GrassB", "Mushrooms" },
		center,
		9,
		17,
		9,
		4,
		rng,
		decor,
		props,
		top
	)
end

local function buildEdgeDetails(props: Folder, decor: Folder, rng)
	-- Piedras y cristales repartidos por el borde de cada lóbulo (silueta viva).
	for _, lobe in MapLayout.Lobes do
		local count = math.floor(lobe.Radius / 6)
		for _ = 1, count do
			local angle = rng.range(0, TAU)
			local radius = lobe.Radius * math.cos(math.pi / lobe.Sides) - rng.range(1.5, 3.5)
			local position = Vector3.new(
				lobe.Center.X + math.cos(angle) * radius,
				SURFACE_Y,
				lobe.Center.Z + math.sin(angle) * radius
			)
			-- Solo en el borde exterior real (no en solapes entre lóbulos).
			if MapLayout.onMainIsland(position + (flat(position) - flat(lobe.Center)).Unit * 6, 0) then
				continue
			end
			if not isClear(position, 2) then
				continue
			end
			if rng.next() < 0.25 then
				buildCrystalCluster(decor, "EdgeCrystal", position, rng, false)
			else
				placeKit(rng.pick({ "Rock", "Rock", "GrassA", "BushSmall" }), position, rng, decor, props, 0.8)
			end
		end
	end
end

local function buildFloatingRocks(decor: Folder, rng)
	for index = 1, 9 do
		local angle = (index / 9) * TAU + rng.range(-0.25, 0.25)
		local distance = rng.range(170, 250)
		local center = Vector3.new(math.sin(angle) * distance, rng.range(-25, 40), math.cos(angle) * distance)
		local size = rng.range(9, 22)
		local yaw = rng.range(0, TAU)
		local rock = Instance.new("Model")
		rock.Name = "FloatingRock" .. index
		newPart(
			"Part",
			decorProps({
				Name = "GrassTop",
				Size = Vector3.new(size, 2, size * 0.85),
				CFrame = CFrame.new(center) * CFrame.Angles(0, yaw, 0),
				Color = PALETTE.Grass,
				Material = Enum.Material.Grass,
			}),
			rock
		)
		newPart(
			"Part",
			decorProps({
				Name = "RockBody",
				Size = Vector3.new(size * 0.7, size * 0.7, size * 0.7),
				CFrame = CFrame.new(center - Vector3.new(0, size * 0.42, 0))
					* CFrame.Angles(math.rad(45), yaw, math.rad(35)),
				Color = PALETTE.Rock2,
			}),
			rock
		)
		newPart(
			"Part",
			decorProps({
				Name = "Crystal",
				Size = Vector3.new(1.4, size * 0.35, 1.4),
				CFrame = CFrame.new(center + Vector3.new(size * 0.15, size * 0.17 + 1, 0))
					* CFrame.Angles(0.2, yaw, 0.25),
				Color = rng.pick({ PALETTE.CrystalCyan, PALETTE.CrystalViolet }),
				Material = Enum.Material.Neon,
				CastShadow = false,
			}),
			rock
		)
		rock.Parent = decor
	end
end

local function buildClouds(decor: Folder, rng)
	for index = 1, 10 do
		local angle = rng.range(0, TAU)
		local distance = rng.range(90, 300)
		local center = Vector3.new(math.sin(angle) * distance, rng.range(-85, -40), math.cos(angle) * distance)
		local cloud = Instance.new("Model")
		cloud.Name = "Cloud" .. index
		for puff = 1, 3 do
			local size = rng.range(16, 30)
			newPart(
				"Part",
				decorProps({
					Name = "Puff" .. puff,
					Shape = Enum.PartType.Ball,
					Size = Vector3.new(size, size, size),
					CFrame = CFrame.new(
						center + Vector3.new((puff - 2) * size * 0.6, rng.range(-2, 3), rng.range(-4, 4))
					),
					Color = PALETTE.Cloud,
					Transparency = 0.15,
					CastShadow = false,
				}),
				cloud
			)
		end
		cloud.Parent = decor
	end
end

local function buildPond(decor: Folder, center: Vector3, radius: number)
	newPart(
		"Part",
		decorProps({
			Name = "PondBank",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.3, radius * 2 + 3, radius * 2 + 3),
			CFrame = CFrame.new(center + Vector3.new(0, 0.07, 0)) * CFrame.Angles(0, 0, math.pi / 2),
			Color = PALETTE.Rim,
			Material = Enum.Material.Sand,
		}),
		decor
	)
	newPart(
		"Part",
		decorProps({
			Name = "PondWater",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.32, radius * 2, radius * 2),
			CFrame = CFrame.new(center + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.pi / 2),
			Color = PALETTE.Water,
			Material = Enum.Material.Glass,
			Transparency = 0.25,
			Reflectance = 0.15,
		}),
		decor
	)
	reserve(center, radius + 1)
end

-- Construye el mapa completo dentro de `parent` y devuelve la carpeta Map.
function MapBuilder.build(parent: Instance): Folder
	local rng = makeRng(GameConfig.Map.Seed)
	table.clear(clearZones)
	kitFolder = findKit()

	local map = Instance.new("Folder")
	map.Name = "Map"
	local ground = Instance.new("Folder")
	ground.Name = "Ground"
	ground.Parent = map
	local props = Instance.new("Folder")
	props.Name = "Props"
	props.Parent = map
	local decor = Instance.new("Folder")
	decor.Name = "Decor"
	decor.Parent = map
	local interactables = Instance.new("Folder")
	interactables.Name = "Interactables"
	interactables.Parent = map

	buildIsland(ground, props, rng)
	buildSpawnPlaza(ground, props, decor, rng)

	-- Accesos y caminos (reservan su espacio antes de repartir decoración).
	for index, link in MapLayout.Links do
		if link.To ~= "Sanctuary" then
			buildRamp(ground, "Ramp" .. index, link.Entry, link.Exit, link.Width, PALETTE.Path)
		end
	end
	buildBridge(ground, props, decor)
	buildPath(decor, Vector3.new(8, SURFACE_Y, 8), MapLayout.Links[1].Entry, 5, rng)
	buildPath(decor, Vector3.new(0, SURFACE_Y, 14), MapLayout.Links[3].Entry, 5, rng)
	buildPath(decor, Vector3.new(8, SURFACE_Y, -10), MapLayout.Links[2].Entry, 4, rng)
	buildPath(decor, Vector3.new(-10, SURFACE_Y, -9), Vector3.new(-30, SURFACE_Y, -45), 4, rng)
	buildPath(decor, Vector3.new(-12, SURFACE_Y, 8), Vector3.new(-40, SURFACE_Y, 26), 4, rng)

	for _, mesa in MapLayout.Mesas do
		buildMesa(ground, props, mesa, rng)
	end
	buildRuins(ground, props, decor, rng)
	buildSanctuary(ground, props, decor, rng)

	for index, position in MapLayout.EssenceCrystals do
		buildEssenceCrystal(interactables, props, index, position)
	end

	-- Bosque Cristalino (SO): arboleda densa con claros, setas, cristales y estanque.
	local forest = Vector3.new(-38, SURFACE_Y, -58)
	buildPond(decor, Vector3.new(-56, SURFACE_Y, -48), 6)
	for index, spot in
		{ Vector3.new(-24, 0, -44), Vector3.new(-48, 0, -78), Vector3.new(-62, 0, -60), Vector3.new(-30, 0, -74) }
	do
		buildCrystalCluster(decor, "ForestCrystal" .. index, spot, rng, index <= 2)
		reserve(spot, 3)
	end
	scatter(
		{ "TreeRound", "TreeNormal", "TreeTwist", "TreePine", "TreeBlossom" },
		forest,
		6,
		34,
		16,
		7,
		rng,
		decor,
		props
	)
	scatter({ "Mushrooms", "BushBig", "BushSmall", "GrassA", "GrassB", "Log" }, forest, 4, 36, 18, 3, rng, decor, props)

	-- Colina del Viento (NO): pinos, rocas y hierba alta.
	local hills = Vector3.new(-56, SURFACE_Y, 38)
	scatter({ "TreePine", "TreePine", "TreeRound", "Boulder" }, hills, 24, 38, 8, 7, rng, decor, props)
	scatter({ "GrassA", "GrassB", "GrassC", "BushSmall", "Rock" }, hills, 20, 40, 14, 3, rng, decor, props)
	placeKit("TreeBlossom", Vector3.new(-60, SURFACE_Y + 4, 41), rng, decor, props, 1.3)

	-- Jardín de Piedra (SE): agujas de roca entre las que se puede combatir.
	local rocks = Vector3.new(44, SURFACE_Y, -42)
	scatter({ "Spire" }, rocks, 10, 30, 7, 9, rng, decor, props)
	scatter({ "Rock", "Boulder", "TreeDead", "GrassC" }, rocks, 6, 34, 12, 4, rng, decor, props)

	-- Alrededores de las Ruinas (NE).
	scatter(
		{ "TreeTwist", "TreeDead", "Boulder", "BushBig" },
		Vector3.new(58, SURFACE_Y, 36),
		22,
		36,
		8,
		6,
		rng,
		decor,
		props
	)

	-- Toques sueltos cerca del centro (sin cerrar el espacio de combate).
	scatter({ "GrassA", "GrassB", "GrassC", "BushSmall" }, Vector3.zero, 22, 48, 14, 3, rng, decor, props)
	scatter({ "TreeRound", "TreeNormal", "Boulder" }, Vector3.zero, 34, 52, 5, 9, rng, decor, props)

	buildEdgeDetails(props, decor, rng)
	buildFloatingRocks(decor, rng)
	buildClouds(decor, rng)

	map.Parent = parent
	return map
end

-- Iluminación de fantasía luminosa, atmósfera y nubes volumétricas.
function MapBuilder.applyLighting()
	local Lighting = game:GetService("Lighting")
	Lighting.ClockTime = 15.3
	Lighting.GeographicLatitude = 28
	Lighting.Brightness = 2.8
	Lighting.Ambient = Color3.fromRGB(96, 98, 128)
	Lighting.OutdoorAmbient = Color3.fromRGB(146, 146, 176)
	Lighting.EnvironmentDiffuseScale = 0.55
	Lighting.EnvironmentSpecularScale = 0.4
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.25

	local function ensure(className: string, name: string, parent: Instance): Instance
		local existing = parent:FindFirstChild(name)
		if existing and existing.ClassName == className then
			return existing
		end
		local created = Instance.new(className)
		created.Name = name
		created.Parent = parent
		return created
	end

	local atmosphere = ensure("Atmosphere", "SkyAtmosphere", Lighting) :: Atmosphere
	atmosphere.Density = 0.34
	atmosphere.Offset = 0.15
	atmosphere.Color = Color3.fromRGB(200, 222, 255)
	atmosphere.Decay = Color3.fromRGB(150, 120, 200)
	atmosphere.Glare = 0.35
	atmosphere.Haze = 1.6

	local sky = ensure("Sky", "SkyboxSky", Lighting) :: Sky
	sky.SunAngularSize = 16
	sky.MoonAngularSize = 8
	sky.CelestialBodiesShown = true

	local bloom = ensure("BloomEffect", "SkyBloom", Lighting) :: BloomEffect
	bloom.Intensity = 0.6
	bloom.Size = 26
	bloom.Threshold = 1.5

	local grading = ensure("ColorCorrectionEffect", "SkyColorGrade", Lighting) :: ColorCorrectionEffect
	grading.Saturation = 0.18
	grading.Contrast = 0.08
	grading.Brightness = 0.01
	grading.TintColor = Color3.fromRGB(255, 248, 238)

	local rays = ensure("SunRaysEffect", "SkySunRays", Lighting) :: SunRaysEffect
	rays.Intensity = 0.07
	rays.Spread = 0.75

	local clouds = ensure("Clouds", "SkyClouds", workspace.Terrain) :: Clouds
	clouds.Cover = 0.5
	clouds.Density = 0.5
	clouds.Color = Color3.fromRGB(255, 250, 255)
end

return MapBuilder
