--!strict
--[[
	MapLayout
	Descripción de la isla (datos puros, sin instancias). La usan:
	  • MapBuilder: para construir la geometría,
	  • SpawnService / ExperienceService: para validar posiciones,
	  • EnemyService: para no caminar hacia el vacío y para subir a las
	    mesetas o cruzar el puente por sus accesos (rampas y pasarelas).

	Zonas (áreas de navegación):
	  Main        isla principal: unión de varios lóbulos poligonales (silueta irregular)
	  Ruins       meseta de las Ruinas del Alba (+7), rampa y escalones de piedra
	  Lookout     mirador de roca (+8) con rampa
	  Sanctuary   santuario flotante unido a la isla por un puente
	La Colina del Viento es caminable por todos sus lados y pertenece a Main.
]]

local MapLayout = {}

export type Lobe = { Center: Vector3, Radius: number, Sides: number, Angle: number }
export type Mesa = {
	Id: string,
	Center: Vector3,
	Radius: number,
	Sides: number,
	Height: number,
	Angle: number,
	Ramped: boolean, -- true = rampas en todos los lados (forma parte de Main)
}
export type Link = {
	From: string,
	To: string,
	Entry: Vector3, -- punto de acceso en la zona From
	Exit: Vector3, -- punto de llegada en la zona To
	Width: number,
	Bidirectional: boolean,
}

MapLayout.SurfaceY = 0

MapLayout.Lobes = {
	{ Center = Vector3.new(0, 0, 0), Radius = 60, Sides = 16, Angle = 0 },
	{ Center = Vector3.new(52, 0, 34), Radius = 44, Sides = 13, Angle = 0.3 },
	{ Center = Vector3.new(-52, 0, 34), Radius = 42, Sides = 12, Angle = 0.1 },
	{ Center = Vector3.new(-34, 0, -52), Radius = 46, Sides = 14, Angle = 0.5 },
	{ Center = Vector3.new(44, 0, -50), Radius = 40, Sides = 11, Angle = 0.2 },
} :: { Lobe }

MapLayout.Mesas = {
	{
		Id = "Ruins",
		Center = Vector3.new(62, 0, 40),
		Radius = 19,
		Sides = 8,
		Height = 7,
		Angle = math.pi / 8,
		Ramped = false,
	},
	{
		Id = "Lookout",
		Center = Vector3.new(52, 0, -62),
		Radius = 10,
		Sides = 7,
		Height = 8,
		Angle = 0.3,
		Ramped = false,
	},
	{
		Id = "WindHill",
		Center = Vector3.new(-56, 0, 38),
		Radius = 15,
		Sides = 9,
		Height = 4,
		Angle = 0,
		Ramped = true,
	},
} :: { Mesa }

-- Santuario flotante (isla secundaria) y el puente que lo une a la principal.
MapLayout.Sanctuary = { Center = Vector3.new(0, 2, 120), Radius = 20, Sides = 12, Angle = 0.15 }
MapLayout.Bridge = { From = Vector3.new(0, 0, 54), To = Vector3.new(0, 2, 103), Width = 9 }

-- Accesos entre zonas. Las mesetas solo necesitan acceso para subir (se puede
-- bajar saltando); el puente se usa en ambos sentidos.
MapLayout.Links = {
	{
		From = "Main",
		To = "Ruins",
		Entry = Vector3.new(30, 0, 30),
		Exit = Vector3.new(47, 7, 36),
		Width = 10,
		Bidirectional = false,
	},
	{
		From = "Main",
		To = "Lookout",
		Entry = Vector3.new(32, 0, -48),
		Exit = Vector3.new(45, 8, -57),
		Width = 7,
		Bidirectional = false,
	},
	{
		From = "Main",
		To = "Sanctuary",
		Entry = Vector3.new(0, 0, 48),
		Exit = Vector3.new(0, 2, 108),
		Width = 9,
		Bidirectional = true,
	},
} :: { Link }

-- Cristales de Esencia: fuente de experiencia que premia la exploración.
MapLayout.EssenceCrystals = {
	Vector3.new(66, 7, 44), -- cima de las Ruinas del Alba
	Vector3.new(53, 8, -63), -- mirador
	Vector3.new(-6, 2, 126), -- santuario
	Vector3.new(9, 2, 116), -- santuario
	Vector3.new(-56, 4, 38), -- Colina del Viento
	Vector3.new(-46, 0, -70), -- Bosque Cristalino
}

local function flatDistance(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

-- Distancia al centro por debajo de la cual un punto está seguro dentro de
-- un polígono regular (su apotema), menos un margen.
local function insidePolygon(position: Vector3, center: Vector3, radius: number, sides: number, margin: number): boolean
	return flatDistance(position, center) <= radius * math.cos(math.pi / sides) - margin
end

local function onBridge(position: Vector3, margin: number): boolean
	local bridge = MapLayout.Bridge
	local a, b = bridge.From, bridge.To
	local ab = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	local ap = Vector3.new(position.X - a.X, 0, position.Z - a.Z)
	local length = ab.Magnitude
	local t = ap:Dot(ab) / (length * length)
	if t < -0.05 or t > 1.05 then
		return false
	end
	local closest = ab * math.clamp(t, 0, 1)
	return (ap - closest).Magnitude <= bridge.Width / 2 - margin
end

function MapLayout.onMainIsland(position: Vector3, margin: number?): boolean
	local m = margin or 0
	for _, lobe in MapLayout.Lobes do
		if insidePolygon(position, lobe.Center, lobe.Radius, lobe.Sides, m) then
			return true
		end
	end
	return false
end

function MapLayout.onSanctuary(position: Vector3, margin: number?): boolean
	local s = MapLayout.Sanctuary
	return insidePolygon(position, s.Center, s.Radius, s.Sides, margin or 0)
end

-- ¿Hay suelo caminable bajo este punto (vista en planta)?
function MapLayout.isWalkable(position: Vector3, margin: number?): boolean
	local m = margin or 0
	return MapLayout.onMainIsland(position, m) or MapLayout.onSanctuary(position, m) or onBridge(position, m * 0.5)
end

function MapLayout.mesaById(id: string): Mesa?
	for _, mesa in MapLayout.Mesas do
		if mesa.Id == id then
			return mesa
		end
	end
	return nil
end

-- Zona de navegación en la que está un punto (se usa la altura para las mesetas).
function MapLayout.areaAt(position: Vector3): string
	for _, mesa in MapLayout.Mesas do
		if not mesa.Ramped and position.Y > MapLayout.SurfaceY + mesa.Height - 2.5 then
			if insidePolygon(position, mesa.Center, mesa.Radius, mesa.Sides, -1) then
				return mesa.Id
			end
		end
	end
	if MapLayout.onSanctuary(position, -2) then
		return "Sanctuary"
	end
	return "Main"
end

-- ¿Está el punto sobre el tramo entrada→salida de un acceso (rampa o puente)?
function MapLayout.onLink(position: Vector3, entry: Vector3, exit: Vector3, width: number): boolean
	local ab = Vector3.new(exit.X - entry.X, 0, exit.Z - entry.Z)
	local ap = Vector3.new(position.X - entry.X, 0, position.Z - entry.Z)
	local t = ap:Dot(ab) / ab:Dot(ab)
	if t <= 0 or t >= 1 then
		return false
	end
	return (ap - ab * t).Magnitude <= width / 2 + 1
end

function MapLayout.linkWidth(entry: Vector3): number
	for _, link in MapLayout.Links do
		if link.Entry == entry or link.Exit == entry then
			return link.Width
		end
	end
	return 6
end

--[[
	Siguiente punto de paso para ir de la zona `from` a la zona `to`, o nil si
	se puede ir en línea recta. Devuelve (entrada, salida) del acceso a usar.
]]
function MapLayout.route(from: string, to: string): (Vector3?, Vector3?)
	if from == to then
		return nil, nil
	end
	-- Bajar de una meseta: en línea recta (se puede saltar al suelo).
	if from ~= "Main" and from ~= "Sanctuary" and to == "Main" then
		return nil, nil
	end
	for _, link in MapLayout.Links do
		if link.From == from and link.To == to then
			return link.Entry, link.Exit
		end
		if link.Bidirectional and link.From == to and link.To == from then
			return link.Exit, link.Entry
		end
	end
	-- Entre dos zonas sin acceso directo se pasa primero por Main.
	if from ~= "Main" and to ~= "Main" then
		return MapLayout.route(from, "Main")
	end
	return nil, nil
end

return MapLayout
