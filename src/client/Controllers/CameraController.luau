--[[
	CameraController
	Cámara en tercera persona estándar de Roblox (modo Classic) con zoom
	inicial alejado para ver a los enemigos cercanos, límites de zoom y
	una sacudida muy suave al recibir daño (vía Humanoid.CameraOffset, sin
	pelear con los scripts de cámara por defecto).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local Net = require(Shared.Net)

local CameraController = {}

local player = Players.LocalPlayer
local shakeUntil = 0
local shakeConnection: RBXScriptConnection? = nil

local function applyZoom()
	local cfg = GameConfig.Player
	player.CameraMaxZoomDistance = cfg.CameraMaxZoom
	-- Truco estándar: fijar el mínimo al zoom deseado fuerza la distancia
	-- inicial; después se restaura el mínimo real.
	player.CameraMinZoomDistance = cfg.CameraStartZoom
	task.delay(0.2, function()
		player.CameraMinZoomDistance = cfg.CameraMinZoom
	end)
	local camera = Workspace.CurrentCamera
	if camera then
		camera.FieldOfView = cfg.CameraFieldOfView
	end
end

local shakeStrength = 0
local shakeDuration = 1

-- Sacudida breve: `strength` en studs y `duration` en segundos (por defecto, la de recibir daño).
local function shake(strength: number?, duration: number?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil then
		return
	end
	local newStrength = strength or GameConfig.Effects.CameraShakeStrength
	local newDuration = duration or GameConfig.Effects.CameraShakeTime
	if os.clock() >= shakeUntil or newStrength >= shakeStrength then
		shakeStrength = newStrength
		shakeDuration = newDuration
		shakeUntil = os.clock() + newDuration
	end
	if shakeConnection then
		return
	end
	shakeConnection = RunService.RenderStepped:Connect(function()
		local remaining = shakeUntil - os.clock()
		if remaining <= 0 or humanoid.Parent == nil then
			humanoid.CameraOffset = Vector3.zero
			if shakeConnection then
				shakeConnection:Disconnect()
				shakeConnection = nil
			end
			return
		end
		local strength = shakeStrength * (remaining / shakeDuration)
		humanoid.CameraOffset = Vector3.new(
			(math.random() - 0.5) * strength,
			(math.random() - 0.5) * strength,
			(math.random() - 0.5) * strength
		)
	end)
end

CameraController.Shake = function(strength: number, duration: number)
	shake(strength, duration)
end

function CameraController.Init(_controllers) end

function CameraController.Start()
	player.CameraMode = Enum.CameraMode.Classic
	player.CharacterAdded:Connect(function()
		applyZoom()
	end)
	if player.Character then
		applyZoom()
	end
	Net.PlayerDamaged.OnClientEvent:Connect(function()
		shake()
	end)
end

return CameraController
