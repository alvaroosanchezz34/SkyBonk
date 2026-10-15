-- Prueba A (mapa válido) y comprobaciones de la plantilla del enemigo.
local Shared = game:GetService("ReplicatedStorage").Shared
local GameConfig = require(Shared.Config.GameConfig)
local EnemyConfig = require(Shared.Config.EnemyConfig)
local MapBuilder = require(script.Parent.Parent.World.MapBuilder)
local ModelFactory = require(script.Parent.Parent.World.ModelFactory)

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
		expect.truthy(total > 60, "mapa demasiado vacío: " .. total)
		expect.truthy(total < 320, "demasiadas piezas para móvil: " .. total)

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

		-- La superficie cubre el radio jugable: algún bloque de suelo llega al borde.
		local maxReach = 0
		for _, part in ground:GetChildren() do
			if part:IsA("BasePart") and string.find(part.Name, "IslandRim") then
				local p = part.CFrame.Position
				local reach = math.sqrt(p.X * p.X + p.Z * p.Z) + part.Size.Z / 2
				maxReach = math.max(maxReach, reach)
			end
		end
		expect.truthy(maxReach >= GameConfig.Map.PlayableRadius, "el borde no cubre el radio jugable")
		holder:Destroy()
	end)

	it("la plantilla del Slime del Vacío tiene todas las piezas necesarias", function()
		local def = EnemyConfig.VoidSlime
		local model = ModelFactory.Builders[def.ModelName](def)
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
end
