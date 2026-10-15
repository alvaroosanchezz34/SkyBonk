--[[
	DebugController (solo Roblox Studio)
	Piloto automático para medir el ritmo de la partida con física real.
	Se activa desde la barra de comandos del servidor:
	    _G.SkyBonkDebug.Autopilot(true)
	que marca al jugador con el atributo "Autopilot". Mientras está activo:
	  • desactiva los controles y mueve al personaje como un jugador básico
	    (huye de los enemigos cercanos, recoge gemas, evita el borde),
	  • elige mejoras a través de la interfaz real (InputController.SelectOption).
	Fuera de Studio no hace nada.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local DebugController = {}

local player = Players.LocalPlayer
local controllers
local controls: any = nil
local active = false
local nextChoiceAt = 0
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include

local PREFERENCE =
	{ "TwinBlade", "SharpEdge", "SwiftStrike", "StormEdge", "KeenStrike", "CelestialMagnet", "BasaltHeart", "VitalSap" }

local function setControls(enabled: boolean)
	if controls == nil then
		local ok, module = pcall(function()
			return require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule") :: ModuleScript)
		end)
		controls = ok and module:GetControls() or nil
	end
	if controls then
		if enabled then
			controls:Enable()
		else
			controls:Disable()
		end
	end
end

local function groundAhead(position: Vector3): boolean
	local map = Workspace:FindFirstChild("Map")
	if map == nil then
		return true
	end
	rayParams.FilterDescendantsInstances = { map }
	return Workspace:Raycast(position + Vector3.new(0, 6, 0), Vector3.new(0, -40, 0), rayParams) ~= nil
end

local function steer()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if humanoid == nil or root == nil or humanoid.Health <= 0 then
		return
	end
	local position = root.Position
	local flee = Vector3.zero
	local threats = 0
	for _, model in Workspace.ActiveEnemies:GetChildren() do
		local enemyRoot = (model :: Model).PrimaryPart
		if enemyRoot and not model:GetAttribute("Dead") then
			local away = Vector3.new(position.X - enemyRoot.Position.X, 0, position.Z - enemyRoot.Position.Z)
			local distance = away.Magnitude
			if distance < 11 and distance > 0.01 then
				flee += away.Unit * (11 - distance)
				threats += 1
			end
		end
	end
	local target, best = nil, 32
	for _, gem in Workspace.ExperienceOrbs:GetChildren() do
		local d = ((gem :: BasePart).Position - position).Magnitude
		if d < best then
			best = d
			target = (gem :: BasePart).Position
		end
	end
	local healthy = humanoid.Health > humanoid.MaxHealth * 0.45
	local direction = Vector3.zero
	if target and (threats == 0 or (healthy and best < 14)) then
		direction = Vector3.new(target.X - position.X, 0, target.Z - position.Z).Unit
	elseif threats > 0 then
		direction = flee.Unit
	else
		-- Sin peligro ni gemas: se acerca despacio al centro para atraer enemigos.
		local toCenter = Vector3.new(-position.X, 0, -position.Z)
		if toCenter.Magnitude > 25 then
			direction = toCenter.Unit * 0.6
		end
	end
	if direction.Magnitude > 0 and not groundAhead(position + direction.Unit * 6) then
		direction = Vector3.new(-position.X, 0, -position.Z).Unit
	end
	humanoid:Move(direction, false)
end

local function chooseUpgrade()
	if not controllers.UpgradeController.IsOpen() or os.clock() < nextChoiceAt then
		return
	end
	nextChoiceAt = os.clock() + 0.6
	local ids = controllers.UpgradeController.GetOptionIds()
	local pick = 1
	for _, preferred in PREFERENCE do
		local index = table.find(ids, preferred)
		if index then
			pick = index
			break
		end
	end
	controllers.InputController.SelectOption:Fire(pick)
end

function DebugController.Init(allControllers)
	controllers = allControllers
end

function DebugController.Start()
	if not RunService:IsStudio() then
		return
	end
	local function refresh()
		local enabled = player:GetAttribute("Autopilot") == true
		if enabled ~= active then
			active = enabled
			setControls(not enabled)
			print("[SkyBonk] Piloto automático", if enabled then "activado" else "desactivado")
		end
	end
	player:GetAttributeChangedSignal("Autopilot"):Connect(refresh)
	refresh()
	RunService.Heartbeat:Connect(function()
		if not active then
			return
		end
		if controllers.UpgradeController.IsOpen() then
			chooseUpgrade()
		else
			nextChoiceAt = math.max(nextChoiceAt, os.clock() + 0.4)
			steer()
		end
	end)
end

return DebugController
