-- Prueba A (mapa válido) y comprobaciones de la plantilla del enemigo.
local Shared = game:GetService("ReplicatedStorage").Shared
local GameConfig = require(Shared.Config.GameConfig)
local EnemyConfig = require(Shared.Config.EnemyConfig)
local MapBuilder = require(script.Parent.Parent.World.MapBuilder)
local ModelFactory = require(script.Parent.Parent.World.ModelFactory)
local MapLayout = require(script.Parent.Parent.World.MapLayout)

local function countParts(root: Instance): (number, number)
	local total, colliding = 0, 0
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BasePart") then
			total += 1
			if descendant.CanCollide then
				colliding += 1
			end
		end
	end
	return total, colliding
end

return function(it, expect)
	it("el mapa tiene suelo, zona de aparición y un número de piezas ligero", function()
		local holder = Instance.new("Folder")
		local map = MapBuilder.build(holder)
		local ground = map:FindFirstChild("Ground")
		expect.truthy(ground, "falta Ground")
		expect.truthy(map:FindFirstChild("Props"), "falta Props")
		expect.truthy(map:FindFirstChild("Decor"), "falta Decor")
		local spawn = ground:FindFirstChild("PlayerSpawn")
		expect.truthy(spawn and spawn:IsA("SpawnLocation"), "falta SpawnLocation")
		local offset = spawn.CFrame.Position - GameConfig.Map.PlayerSpawn
		expect.truthy(math.abs(offset.X) < 0.01 and math.abs(offset.Z) < 0.01, "spawn desplazado")

		local total = countParts(map)
		expect.truthy(total > 300, "mapa demasiado vacío: " .. total)
		-- Presupuesto para móvil: piezas ancladas y simples (sin contar el kit, que son mallas).
		expect.truthy(total < 1500, "demasiadas piezas para móvil: " .. total)

		for _, descendant in map:GetDescendants() do
			if descendant:IsA("BasePart") then
				expect.truthy(descendant.Anchored, descendant:GetFullName() .. " no anclada")
			end
		end
		for _, descendant in map.Decor:GetDescendants() do
			if descendant:IsA("BasePart") then
				expect.falsy(descendant.CanCollide, descendant.Name .. " decorativa con colisión")
				expect.falsy(descendant.CanQuery, descendant.Name .. " decorativa consultable")
			end
		end

		-- Cada punto que MapLayout considera caminable tiene suelo debajo (raycast real).
		-- (solo en Studio: fuera de Roblox no hay raycast real)
		if RaycastParams and workspace and workspace.Raycast then
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Include
			params.FilterDescendantsInstances = { ground }
			holder.Parent = workspace
			local misses = 0
			for x = -110, 110, 10 do
				for z = -110, 150, 10 do
					local point = Vector3.new(x, 0, z)
					if MapLayout.isWalkable(point, 2) then
						local hit = workspace:Raycast(point + Vector3.new(0, 30, 0), Vector3.new(0, -60, 0), params)
						if hit == nil then
							misses += 1
						end
					end
				end
			end
			expect.equal(misses, 0, "puntos caminables sin suelo")
		end
		expect.truthy(map:FindFirstChild("Interactables"), "faltan los Cristales de Esencia")
		expect.equal(#map.Interactables:GetChildren(), #MapLayout.EssenceCrystals)
		holder:Destroy()
	end)

	it("la plantilla del Slime del Vacío tiene todas las piezas necesarias", function()
		local def = EnemyConfig.VoidSlime
		local model = ModelFactory.Builders[def.Rig](def)
		local root = model:FindFirstChild("Root")
		expect.truthy(root and model.PrimaryPart == root, "Root no es PrimaryPart")
		expect.truthy(root:FindFirstChild("RootAttachment"))
		expect.truthy(root:FindFirstChild("Mover"))
		expect.truthy(root:FindFirstChild("Facing"))
		local bar = root:FindFirstChild("HealthBar")
		expect.truthy(bar and bar:FindFirstChild("Back") and bar.Back:FindFirstChild("Fill"), "falta barra de vida")
		local body = model:FindFirstChild("Body")
		expect.truthy(body and body:FindFirstChild("BodyWeld") and body:FindFirstChild("BodyMesh"))
		local total, colliding = countParts(model)
		expect.equal(colliding, 1, "solo Root debe colisionar")
		expect.truthy(total <= 10, "demasiadas piezas por enemigo: " .. total)
		model:Destroy()
	end)
	it("la navegación sube a las mesetas por su acceso y cruza el puente en ambos sentidos", function()
		local entry, exit = MapLayout.route("Main", "Ruins")
		expect.truthy(entry and exit, "sin acceso a las Ruinas")
		expect.truthy(MapLayout.onMainIsland(entry :: Vector3, 0), "la entrada de la rampa no está en la isla")
		expect.equal(MapLayout.areaAt(exit :: Vector3), "Ruins")
		-- Bajar de una meseta: en línea recta.
		expect.equal(MapLayout.route("Ruins", "Main"), nil)
		local toSanctuary = MapLayout.route("Main", "Sanctuary")
		local fromSanctuary = MapLayout.route("Sanctuary", "Main")
		expect.truthy(toSanctuary and fromSanctuary, "el puente debe usarse en ambos sentidos")
		-- De una meseta al santuario se pasa por la isla principal (sin recursión infinita).
		expect.equal(MapLayout.route("Ruins", "Sanctuary"), nil)
		expect.truthy(MapLayout.route("Lookout", "Ruins") == nil)
		for _, crystal in MapLayout.EssenceCrystals do
			expect.truthy(MapLayout.isWalkable(crystal, 0), "cristal fuera del suelo")
		end
		-- Fuera de la isla no hay suelo.
		expect.truthy(MapLayout.isWalkable(Vector3.new(0, 1, 80), 0), "el puente debe ser caminable")
		expect.falsy(MapLayout.isWalkable(Vector3.new(25, 0, 80), 0), "vacío junto al puente marcado como suelo")
		expect.falsy(MapLayout.isWalkable(Vector3.new(150, 0, 0), 0))
	end)

	it("todas las criaturas tienen plantilla y ataques que se pueden esquivar", function()
		for id, def in EnemyConfig do
			local model = ModelFactory.Builders[def.Rig](def)
			local root = model:FindFirstChild("Root")
			expect.truthy(root and model.PrimaryPart == root, id .. ": Root no es PrimaryPart")
			expect.truthy(
				root:FindFirstChild("Mover") and root:FindFirstChild("Facing"),
				id .. ": falta la base física"
			)
			expect.truthy(def.AttackWindup >= 0.3, id .. ": anticipación demasiado corta para reaccionar")
			expect.truthy(def.HitRange > 0 and def.AttackRange > 0, id .. ": alcances inválidos")
			expect.truthy(def.XpReward >= 1, id .. ": sin experiencia")
			local _, colliding = countParts(model)
			expect.equal(colliding, 1, id .. ": solo Root debe colisionar")
			model:Destroy()
		end
	end)
end
