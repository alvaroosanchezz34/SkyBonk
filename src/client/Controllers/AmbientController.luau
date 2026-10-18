--[[
	AmbientController
	Vida ambiental del mundo (solo cliente, solo visual):

	  • Ciclo de luz local: la hora oscila entre la tarde y el atardecer dorado
	    (VisualConfig.DayCycle); la atmósfera se calienta hacia el atardecer.
	  • Gradación de color por zona (Bosque Sakura, Jardín Corrompido, Santuario
	    Celestial, Ruinas): un tinte suave que ayuda a reconocer dónde estás.
	  • Pétalos de sakura alrededor del jugador mientras está en el bosque.
	  • Cristales con el atributo "Float" flotan y oscilan.
	  • En calidad baja se apagan los emisores marcados "Ambient" y los pétalos.
	  • Atenuado por oclusión: árboles y rocas altos que quedan entre la cámara y
	    el personaje se vuelven semitransparentes (las piezas decorativas no
	    colisionan, así que la cámara de Roblox no las esquiva).
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local VisualConfig = require(ReplicatedStorage.Shared.Config.VisualConfig)
local AuraSystem = require(script.Parent.Parent.Util.AuraSystem)

local AmbientController = {}

local player = Players.LocalPlayer
local floaters: { { Model: Model, Base: CFrame, Amplitude: number, Phase: number } } = {}
local ambientEmitters: { ParticleEmitter } = {}
type Occluder = { Parts: { BasePart }, Center: Vector3, Radius: number, Alpha: number }
local occluders: { Occluder } = {}
local OCCLUDED_ALPHA = 0.72
local petals: ParticleEmitter
local petalPart: Part
local zoneGrade: ColorCorrectionEffect
local currentTint = Color3.new(1, 1, 1)
local startClock = os.clock()

local function collect(map: Instance)
	table.clear(floaters)
	table.clear(ambientEmitters)
	table.clear(occluders)
	for _, descendant in map:GetDescendants() do
		local height = descendant:GetAttribute("KitHeight")
		if descendant:IsA("Model") and type(height) == "number" and height > 5 then
			local parts = {}
			for _, part in descendant:GetDescendants() do
				if part:IsA("BasePart") then
					table.insert(parts, part)
				end
			end
			table.insert(occluders, {
				Parts = parts,
				Center = descendant:GetPivot().Position + Vector3.new(0, height / 2, 0),
				Radius = math.max(descendant:GetAttribute("KitRadius") or 2, height * 0.35),
				Alpha = 0,
			})
		end
		if descendant:IsA("Model") and descendant:GetAttribute("Float") then
			table.insert(floaters, {
				Model = descendant,
				Base = descendant:GetPivot(),
				Amplitude = descendant:GetAttribute("Float"),
				Phase = math.random() * math.pi * 2,
			})
		elseif descendant:IsA("ParticleEmitter") and descendant:GetAttribute("Ambient") then
			table.insert(ambientEmitters, descendant)
		end
	end
end

local function applyQuality()
	local ambient = AuraSystem.GetQuality().Ambient
	for _, emitter in ambientEmitters do
		emitter.Enabled = ambient
	end
end

local function zoneAt(position: Vector3): any?
	local best, bestDistance = nil, math.huge
	for _, zone in VisualConfig.Zones do
		if zone.Center then
			local d = Vector3.new(position.X - zone.Center.X, 0, position.Z - zone.Center.Z).Magnitude
			if d < zone.Radius and d < bestDistance then
				best, bestDistance = zone, d
			end
		end
	end
	return best
end

local function update(dt: number)
	local now = os.clock()
	-- Ciclo de luz (ida y vuelta, sin llegar a la noche).
	local cycle = VisualConfig.DayCycle
	local t = (math.sin((now - startClock) / cycle.Period * math.pi * 2 - math.pi / 2) + 1) / 2
	Lighting.ClockTime = cycle.From + (cycle.To - cycle.From) * t
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		atmosphere.Color = Color3.fromRGB(200, 222, 255):Lerp(Color3.fromRGB(255, 214, 196), t * 0.7)
	end

	for _, floater in floaters do
		local model = floater.Model
		if model.Parent then
			model:PivotTo(
				floater.Base
					* CFrame.new(0, math.sin(now * 1.3 + floater.Phase) * floater.Amplitude, 0)
					* CFrame.Angles(0, now * 0.3, 0)
			)
		end
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local zone = root and zoneAt(root.Position)
	local targetTint = if zone and zone.Tint then zone.Tint else Color3.new(1, 1, 1)
	currentTint = currentTint:Lerp(targetTint, math.min(1, dt * 1.5))
	zoneGrade.TintColor = currentTint

	-- Oclusión: distancia de cada pieza alta al segmento cámara → cabeza.
	local camera = Workspace.CurrentCamera
	if root and camera then
		local from = camera.CFrame.Position
		local to = root.Position + Vector3.new(0, 1.5, 0)
		local segment = to - from
		local lengthSq = segment:Dot(segment)
		for _, occluder in occluders do
			local target = 0
			if lengthSq > 1 then
				local t = math.clamp((occluder.Center - from):Dot(segment) / lengthSq, 0, 1)
				local closest = from + segment * t
				if t < 0.94 and (occluder.Center - closest).Magnitude < occluder.Radius then
					target = OCCLUDED_ALPHA
				end
			end
			if math.abs(target - occluder.Alpha) > 0.01 then
				occluder.Alpha += math.clamp(target - occluder.Alpha, -dt * 4, dt * 4)
				for _, part in occluder.Parts do
					part.LocalTransparencyModifier = occluder.Alpha
				end
			end
		end
	end

	local inForest = zone == VisualConfig.Zones.Forest and AuraSystem.GetQuality().Ambient
	petals.Enabled = inForest == true
	if root and inForest then
		petalPart.CFrame = CFrame.new(root.Position + Vector3.new(0, 18, 0))
	end
end

function AmbientController.Init(_controllers) end

function AmbientController.Start()
	zoneGrade = Instance.new("ColorCorrectionEffect")
	zoneGrade.Name = "SkyBonkZoneGrade"
	zoneGrade.Parent = Lighting

	petalPart = Instance.new("Part")
	petalPart.Name = "SakuraPetals"
	petalPart.Size = Vector3.new(70, 1, 70)
	petalPart.Transparency = 1
	petalPart.Anchored = true
	petalPart.CanCollide = false
	petalPart.CanQuery = false
	petalPart.CanTouch = false
	petalPart.Parent = Workspace
	petals = Instance.new("ParticleEmitter")
	petals.Texture = VisualConfig.Textures.Glow
	petals.Color = ColorSequence.new(VisualConfig.Zones.Forest.Leaf, Color3.fromRGB(255, 220, 235))
	petals.LightInfluence = 0.6
	petals.Size = NumberSequence.new(0.35)
	petals.Squash = NumberSequence.new(-0.6) -- pétalo aplanado
	petals.Lifetime = NumberRange.new(5, 7)
	petals.Speed = NumberRange.new(2, 4)
	petals.EmissionDirection = Enum.NormalId.Bottom
	petals.SpreadAngle = Vector2.new(30, 30)
	petals.Rotation = NumberRange.new(0, 360)
	petals.RotSpeed = NumberRange.new(-120, 120)
	petals.Acceleration = Vector3.new(1.5, -0.5, 0.8)
	petals.Rate = 14
	petals.Enabled = false
	petals.Parent = petalPart

	task.spawn(function()
		local map = Workspace:WaitForChild("Map", 30)
		if map then
			task.wait(1) -- el mapa termina de replicarse
			collect(map)
			applyQuality()
		end
	end)
	AuraSystem.QualityChanged:Connect(applyQuality)
	RunService.RenderStepped:Connect(function(dt)
		debug.profilebegin("SkyBonk.Ambient")
		update(dt)
		debug.profileend()
	end)
end

return AmbientController
