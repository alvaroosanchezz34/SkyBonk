--[[
	MapBuilder
	Construye la isla flotante de pruebas con Parts low-poly (sin recursos
	externos). Es determinista (semilla en GameConfig.Map.Seed).

	Jerarquía generada:
	  Map/
	    Ground/   superficies caminables (válidas para generar enemigos)
	    Props/    obstáculos sólidos: ruinas, árboles, cristales, rocas del borde
	    Decor/    elementos sin colisión: islas lejanas, nubes, arbustos
	    PlayerSpawn (SpawnLocation)

	Si Workspace ya contiene un Map con Ground, Bootstrap lo respeta y no lo
	regenera, de modo que el mapa puede editarse a mano en Studio.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local MapBuilder = {}

local TAU = math.pi * 2

local PALETTE = {
	Grass = Color3.fromRGB(112, 186, 84),
	GrassDark = Color3.fromRGB(88, 160, 72),
	Rim = Color3.fromRGB(206, 190, 136),
	Rock1 = Color3.fromRGB(142, 122, 106),
	Rock2 = Color3.fromRGB(120, 102, 92),
	Rock3 = Color3.fromRGB(100, 86, 84),
	Rock4 = Color3.fromRGB(84, 72, 76),
	Rock5 = Color3.fromRGB(70, 60, 68),
	Stone = Color3.fromRGB(216, 204, 182),
	StoneDark = Color3.fromRGB(168, 156, 140),
	Trunk = Color3.fromRGB(122, 84, 58),
	Leaf1 = Color3.fromRGB(70, 150, 84),
	Leaf2 = Color3.fromRGB(96, 178, 92),
	Leaf3 = Color3.fromRGB(150, 206, 104),
	Cloud = Color3.fromRGB(248, 250, 255),
	CrystalCyan = Color3.fromRGB(98, 232, 255),
	CrystalViolet = Color3.fromRGB(178, 120, 255),
	CrystalPink = Color3.fromRGB(255, 132, 214),
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

--[[
	Capa poligonal: N bloques que, unidos, forman un polígono regular de
	circunradio `radius`. Cada bloque va del centro a la apotema y su cara
	exterior es un lado del polígono (aspecto facetado low-poly).
]]
local function polygonLayer(
	folder: Instance,
	name: string,
	sides: number,
	radius: number,
	topY: number,
	thickness: number,
	color: Color3,
	angleOffset: number
)
	local apothem = radius * math.cos(math.pi / sides)
	local side = 2 * radius * math.sin(math.pi / sides)
	for i = 0, sides - 1 do
		local angle = angleOffset + i * TAU / sides
		local direction = Vector3.new(-math.sin(angle), 0, -math.cos(angle))
		local center = direction * (apothem / 2) + Vector3.new(0, topY - thickness / 2, 0)
		newPart("Part", {
			Name = string.format("%s_%02d", name, i + 1),
			Size = Vector3.new(side, thickness, apothem),
			CFrame = CFrame.new(center) * CFrame.Angles(0, angle, 0),
			Color = color,
		}, folder)
	end
end

local function buildIsland(ground: Folder, props: Folder)
	local surfaceY = GameConfig.Map.SurfaceY
	polygonLayer(ground, "IslandSurface", 14, 101, surfaceY, 4, PALETTE.Grass, 0)
	-- Anillo exterior algo más bajo y de otro color: marca claramente el borde.
	polygonLayer(ground, "IslandRim", 14, 110, surfaceY - 0.5, 5, PALETTE.Rim, math.pi / 14)
	-- Cuerpo rocoso invertido bajo la isla.
	polygonLayer(props, "Cliff1", 12, 108, surfaceY - 5, 9, PALETTE.Rock1, 0.2)
	polygonLayer(props, "Cliff2", 10, 92, surfaceY - 13, 12, PALETTE.Rock2, 0.5)
	polygonLayer(props, "Cliff3", 9, 70, surfaceY - 24, 14, PALETTE.Rock3, 0.1)
	polygonLayer(props, "Cliff4", 8, 44, surfaceY - 37, 16, PALETTE.Rock4, 0.7)
	polygonLayer(props, "Cliff5", 7, 20, surfaceY - 52, 16, PALETTE.Rock5, 0.3)
end

-- Colina low-poly: meseta + 4 rampas (WedgeParts) caminables.
local function buildHill(ground: Folder, name: string, center: Vector3, width: number, depth: number, height: number)
	local run = height * 2.2
	local baseY = GameConfig.Map.SurfaceY
	local model = Instance.new("Model")
	model.Name = name
	newPart("Part", {
		Name = "Top",
		Size = Vector3.new(width, height, depth),
		CFrame = CFrame.new(center.X, baseY + height / 2, center.Z),
		Color = PALETTE.GrassDark,
	}, model)
	local sides = {
		{ Vector3.new(0, 0, -1), width, depth },
		{ Vector3.new(0, 0, 1), width, depth },
		{ Vector3.new(1, 0, 0), depth, width },
		{ Vector3.new(-1, 0, 0), depth, width },
	}
	for index, info in sides do
		local outward: Vector3 = info[1]
		local along: number = info[2]
		local across: number = info[3]
		local position = Vector3.new(center.X, baseY + height / 2, center.Z) + outward * (across / 2 + run / 2)
		-- La cara frontal (LookVector) de una WedgePart es el extremo bajo de la rampa.
		newPart("WedgePart", {
			Name = "Ramp" .. index,
			Size = Vector3.new(along, height, run),
			CFrame = CFrame.lookAt(position, position + outward),
			Color = PALETTE.Grass,
		}, model)
	end
	model.Parent = ground
end

local function buildSpawnPlatform(ground: Folder, decor: Folder): SpawnLocation
	local spawnPosition = GameConfig.Map.PlayerSpawn
	local surfaceY = GameConfig.Map.SurfaceY
	newPart("Part", {
		Name = "SpawnPlaza",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.6, 22, 22),
		CFrame = CFrame.new(spawnPosition.X, surfaceY + 0.3, spawnPosition.Z) * CFrame.Angles(0, 0, math.pi / 2),
		Color = PALETTE.Stone,
		Material = Enum.Material.Slate,
	}, ground)
	newPart("Part", decorProps({
		Name = "SpawnRuneRing",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.65, 14, 14),
		CFrame = CFrame.new(spawnPosition.X, surfaceY + 0.3, spawnPosition.Z) * CFrame.Angles(0, 0, math.pi / 2),
		Color = PALETTE.Rune,
		Material = Enum.Material.Neon,
		Transparency = 0.55,
	}), decor)

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "PlayerSpawn"
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0 -- sin campo de fuerza
	spawn.Size = Vector3.new(6, 0.8, 6)
	spawn.CFrame = CFrame.new(spawnPosition.X, surfaceY + 0.6, spawnPosition.Z)
	spawn.Color = PALETTE.StoneDark
	spawn.Material = Enum.Material.Slate
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = ground
	return spawn
end

local function buildRuins(props: Folder, rng)
	local surfaceY = GameConfig.Map.SurfaceY
	-- Arco en ruinas.
	local arch = Instance.new("Model")
	arch.Name = "RuinedArch"
	local archCenter = Vector3.new(-22, surfaceY, -52)
	for _, offset in { -6, 6 } do
		newPart("Part", {
			Name = "ArchPillar",
			Size = Vector3.new(3, 12, 3),
			CFrame = CFrame.new(archCenter + Vector3.new(offset, 6, 0)),
			Color = PALETTE.Stone,
		}, arch)
	end
	newPart("Part", {
		Name = "ArchLintel",
		Size = Vector3.new(16, 2.5, 4),
		CFrame = CFrame.new(archCenter + Vector3.new(0, 13.2, 0)) * CFrame.Angles(0, 0, math.rad(4)),
		Color = PALETTE.StoneDark,
	}, arch)
	arch.Parent = props

	-- Columnas rotas repartidas por la isla.
	local pillarSpots = {
		Vector3.new(48, 0, 22),
		Vector3.new(-60, 0, -14),
		Vector3.new(30, 0, -70),
		Vector3.new(-38, 0, 64),
		Vector3.new(72, 0, -36),
		Vector3.new(-74, 0, 40),
	}
	for index, spot in pillarSpots do
		local pillar = Instance.new("Model")
		pillar.Name = "BrokenPillar" .. index
		local height = rng.range(4, 9)
		local yaw = rng.range(0, TAU)
		newPart("Part", {
			Name = "Base",
			Size = Vector3.new(4.5, 1, 4.5),
			CFrame = CFrame.new(spot.X, surfaceY + 0.5, spot.Z) * CFrame.Angles(0, yaw, 0),
			Color = PALETTE.StoneDark,
		}, pillar)
		newPart("Part", {
			Name = "Shaft",
			Size = Vector3.new(2.8, height, 2.8),
			CFrame = CFrame.new(spot.X, surfaceY + 1 + height / 2, spot.Z) * CFrame.Angles(0, yaw + math.pi / 4, 0),
			Color = PALETTE.Stone,
		}, pillar)
		newPart("Part", {
			Name = "FallenPiece",
			Size = Vector3.new(2.6, 2.6, rng.range(3, 5)),
			CFrame = CFrame.new(spot.X + 3.5, surfaceY + 1.2, spot.Z + 1.5)
				* CFrame.Angles(math.rad(rng.range(-8, 8)), yaw, math.rad(rng.range(5, 20))),
			Color = PALETTE.Stone,
		}, pillar)
		pillar.Parent = props
	end

	-- Muros derruidos.
	local walls = {
		{ Vector3.new(14, 0, 34), 12, 4.5, 0.4 },
		{ Vector3.new(-16, 0, 30), 9, 3, -0.9 },
		{ Vector3.new(58, 0, 58), 11, 5, 2.2 },
	}
	for index, wall in walls do
		local position: Vector3 = wall[1]
		newPart("Part", {
			Name = "RuinedWall" .. index,
			Size = Vector3.new(wall[2], wall[3], 2),
			CFrame = CFrame.new(position.X, surfaceY + wall[3] / 2, position.Z) * CFrame.Angles(0, wall[4], 0),
			Color = PALETTE.StoneDark,
		}, props)
	end
end

local function buildCrystalCluster(parent: Instance, name: string, base: Vector3, rng, withLight: boolean)
	local cluster = Instance.new("Model")
	cluster.Name = name
	local color = rng.pick({ PALETTE.CrystalCyan, PALETTE.CrystalViolet, PALETTE.CrystalPink })
	for index = 1, 3 do
		local height = rng.range(2.5, 6.5)
		local shard = newPart("Part", {
			Name = "Shard" .. index,
			Size = Vector3.new(1.3, height, 1.3),
			CFrame = CFrame.new(base + Vector3.new(rng.range(-1.2, 1.2), height / 2 - 0.3, rng.range(-1.2, 1.2)))
				* CFrame.Angles(math.rad(rng.range(-22, 22)), rng.range(0, TAU), math.rad(rng.range(-22, 22))),
			Color = color,
			Material = if index == 1 then Enum.Material.Neon else Enum.Material.Glass,
			Transparency = if index == 1 then 0 else 0.25,
			CastShadow = false,
		}, cluster)
		if index == 1 and withLight then
			local light = Instance.new("PointLight")
			light.Color = color
			light.Range = 12
			light.Brightness = 1.4
			light.Shadows = false
			light.Parent = shard
		end
	end
	cluster.Parent = parent
end

local function buildTree(props: Folder, decor: Folder, name: string, base: Vector3, rng)
	local tree = Instance.new("Model")
	tree.Name = name
	local trunkHeight = rng.range(6, 9)
	newPart("Part", {
		Name = "Trunk",
		Size = Vector3.new(1.8, trunkHeight, 1.8),
		CFrame = CFrame.new(base + Vector3.new(0, trunkHeight / 2, 0)) * CFrame.Angles(0, rng.range(0, TAU), 0),
		Color = PALETTE.Trunk,
	}, tree)
	local canopyColors = { PALETTE.Leaf1, PALETTE.Leaf2, PALETTE.Leaf3 }
	local canopySizes = { 7, 5.5, 3.5 }
	for index = 1, 3 do
		local size = canopySizes[index]
		newPart("Part", decorProps({
			Name = "Canopy" .. index,
			Size = Vector3.new(size, size * 0.8, size),
			CFrame = CFrame.new(base + Vector3.new(0, trunkHeight + (index - 1) * 2.2, 0))
				* CFrame.Angles(math.rad(rng.range(-15, 15)), rng.range(0, TAU), math.rad(25)),
			Color = canopyColors[index],
		}), decor)
	end
	tree.Parent = props
end

local function buildEdgeMarkers(props: Folder, rng)
	local surfaceY = GameConfig.Map.SurfaceY
	local count = 16
	for index = 1, count do
		-- Huecos regulares: el borde se ve, pero no es una pared.
		if index % 4 ~= 0 then
			local angle = index * TAU / count + rng.range(-0.08, 0.08)
			local radius = rng.range(103, 106)
			local size = rng.range(2, 3.4)
			newPart("Part", {
				Name = "EdgeStone" .. index,
				Size = Vector3.new(size, size * 0.9, size * 1.2),
				CFrame = CFrame.new(math.sin(angle) * radius, surfaceY + size * 0.3, math.cos(angle) * radius)
					* CFrame.Angles(math.rad(rng.range(-20, 20)), rng.range(0, TAU), math.rad(rng.range(-20, 20))),
				Color = rng.pick({ PALETTE.Rock1, PALETTE.Rock2 }),
			}, props)
		end
	end
	-- Cristales luminosos en los cuatro puntos cardinales del borde.
	for index = 0, 3 do
		local angle = index * TAU / 4 + math.pi / 4
		buildCrystalCluster(props, "EdgeBeacon" .. (index + 1), Vector3.new(math.sin(angle) * 104, surfaceY, math.cos(angle) * 104), rng, true)
	end
end

local function buildFloatingRocks(decor: Folder, rng)
	for index = 1, 6 do
		local angle = (index / 6) * TAU + rng.range(-0.3, 0.3)
		local distance = rng.range(155, 230)
		local center = Vector3.new(math.sin(angle) * distance, rng.range(-15, 35), math.cos(angle) * distance)
		local size = rng.range(10, 20)
		local yaw = rng.range(0, TAU)
		local rock = Instance.new("Model")
		rock.Name = "FloatingRock" .. index
		newPart("Part", decorProps({
			Name = "GrassTop",
			Size = Vector3.new(size, 2, size * 0.85),
			CFrame = CFrame.new(center) * CFrame.Angles(0, yaw, 0),
			Color = PALETTE.Grass,
		}), rock)
		newPart("Part", decorProps({
			Name = "RockBody",
			Size = Vector3.new(size * 0.7, size * 0.7, size * 0.7),
			CFrame = CFrame.new(center - Vector3.new(0, size * 0.42, 0)) * CFrame.Angles(math.rad(45), yaw, math.rad(35)),
			Color = PALETTE.Rock2,
		}), rock)
		newPart("Part", decorProps({
			Name = "Crystal",
			Size = Vector3.new(1.4, size * 0.35, 1.4),
			CFrame = CFrame.new(center + Vector3.new(size * 0.15, size * 0.17 + 1, 0)) * CFrame.Angles(0.2, yaw, 0.25),
			Color = rng.pick({ PALETTE.CrystalCyan, PALETTE.CrystalViolet }),
			Material = Enum.Material.Neon,
			CastShadow = false,
		}), rock)
		rock.Parent = decor
	end
end

local function buildClouds(decor: Folder, rng)
	for index = 1, 8 do
		local angle = rng.range(0, TAU)
		local distance = rng.range(70, 280)
		local center = Vector3.new(math.sin(angle) * distance, rng.range(-75, -30), math.cos(angle) * distance)
		local cloud = Instance.new("Model")
		cloud.Name = "Cloud" .. index
		for puff = 1, 3 do
			local size = rng.range(14, 26)
			newPart("Part", decorProps({
				Name = "Puff" .. puff,
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(size, size, size),
				CFrame = CFrame.new(center + Vector3.new((puff - 2) * size * 0.6, rng.range(-2, 3), rng.range(-4, 4))),
				Color = PALETTE.Cloud,
				Transparency = 0.15,
				CastShadow = false,
			}), cloud)
		end
		cloud.Parent = decor
	end
end

-- Construye el mapa completo dentro de `parent` y devuelve la carpeta Map.
function MapBuilder.build(parent: Instance): Folder
	local rng = makeRng(GameConfig.Map.Seed)
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

	buildIsland(ground, props)
	buildHill(ground, "Hill1", Vector3.new(36, 0, -28), 14, 14, 3)
	buildHill(ground, "Hill2", Vector3.new(-46, 0, 18), 18, 12, 4)
	buildHill(ground, "Hill3", Vector3.new(12, 0, 62), 12, 16, 2.5)
	buildSpawnPlatform(ground, decor)
	buildRuins(props, rng)
	buildEdgeMarkers(props, rng)

	local crystalSpots = {
		Vector3.new(20, 0, -18),
		Vector3.new(-30, 0, -36),
		Vector3.new(66, 0, 8),
		Vector3.new(-62, 0, 52),
		Vector3.new(4, 0, 84),
	}
	for index, spot in crystalSpots do
		buildCrystalCluster(props, "CrystalCluster" .. index, spot, rng, index <= 2)
	end

	local treeSpots = {
		Vector3.new(-30, 0, 8),
		Vector3.new(44, 0, 44),
		Vector3.new(-50, 0, -50),
		Vector3.new(80, 0, 24),
		Vector3.new(-20, 0, 82),
	}
	for index, spot in treeSpots do
		buildTree(props, decor, "Tree" .. index, spot, rng)
	end

	for index = 1, 8 do
		local angle = rng.range(0, TAU)
		local distance = rng.range(25, 90)
		local size = rng.range(2.4, 4)
		newPart("Part", decorProps({
			Name = "Bush" .. index,
			Size = Vector3.new(size, size * 0.75, size),
			CFrame = CFrame.new(math.sin(angle) * distance, size * 0.3, math.cos(angle) * distance)
				* CFrame.Angles(0, rng.range(0, TAU), math.rad(12)),
			Color = rng.pick({ PALETTE.Leaf1, PALETTE.Leaf2 }),
		}), decor)
	end

	buildFloatingRocks(decor, rng)
	buildClouds(decor, rng)

	map.Parent = parent
	return map
end

-- Iluminación de fantasía luminosa, atmósfera y nubes volumétricas.
function MapBuilder.applyLighting()
	local Lighting = game:GetService("Lighting")
	Lighting.ClockTime = 14.5
	Lighting.Brightness = 2.6
	Lighting.Ambient = Color3.fromRGB(104, 104, 132)
	Lighting.OutdoorAmbient = Color3.fromRGB(150, 150, 176)
	Lighting.EnvironmentDiffuseScale = 0.5
	Lighting.EnvironmentSpecularScale = 0.4
	Lighting.GlobalShadows = true

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
	atmosphere.Density = 0.3
	atmosphere.Offset = 0.2
	atmosphere.Color = Color3.fromRGB(196, 222, 255)
	atmosphere.Decay = Color3.fromRGB(110, 146, 206)
	atmosphere.Glare = 0.3
	atmosphere.Haze = 1.4

	local sky = ensure("Sky", "SkyboxSky", Lighting) :: Sky
	sky.SunAngularSize = 14
	sky.MoonAngularSize = 8
	sky.CelestialBodiesShown = true

	local bloom = ensure("BloomEffect", "SkyBloom", Lighting) :: BloomEffect
	bloom.Intensity = 0.55
	bloom.Size = 24
	bloom.Threshold = 1.6

	local grading = ensure("ColorCorrectionEffect", "SkyColorGrade", Lighting) :: ColorCorrectionEffect
	grading.Saturation = 0.15
	grading.Contrast = 0.06
	grading.TintColor = Color3.fromRGB(255, 250, 244)

	local rays = ensure("SunRaysEffect", "SkySunRays", Lighting) :: SunRaysEffect
	rays.Intensity = 0.06
	rays.Spread = 0.8

	local clouds = ensure("Clouds", "SkyClouds", workspace.Terrain) :: Clouds
	clouds.Cover = 0.55
	clouds.Density = 0.55
	clouds.Color = Color3.fromRGB(255, 255, 255)
end

return MapBuilder
