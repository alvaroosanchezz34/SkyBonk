--[[
	GameOverController
	Pantalla de derrota (StarterGui equivalente: GameOverScreen): tiempo
	sobrevivido, enemigos derrotados, nivel alcanzado y botón para volver a
	jugar. El servidor decide si el reinicio es válido. (La Fase 1 no tiene
	menú principal, por eso no se muestra el botón "Volver al menú".)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local Net = require(Shared.Net)
local Theme = require(script.Parent.Parent.UI.Theme)
local Sfx = require(script.Parent.Parent.Util.Sfx)

local GameOverController = {}

local C = Theme.Colors
local New = Theme.New

local controllers
local gui: ScreenGui
local overlay: Frame
local panel: Frame
local values: { [string]: TextLabel } = {}
local restartButton: TextButton
local restartLabel: TextLabel
local shownAt = 0
local requested = false

local function tween(instance: Instance, time: number, goal: { [string]: any }, style: Enum.EasingStyle?)
	TweenService:Create(instance, TweenInfo.new(time, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal):Play()
end

local function requestRestart()
	if not gui.Enabled or requested then
		return
	end
	-- Mismo enfriamiento que el servidor para evitar peticiones inútiles.
	if os.clock() - shownAt < GameConfig.Match.RestartCooldown then
		return
	end
	requested = true
	restartLabel.Text = "Cargando..."
	Sfx.Play("UiSelect")
	Net.RequestRestart:FireServer()
	-- Si el servidor no responde (petición rechazada), se permite reintentar.
	task.delay(3, function()
		if gui.Enabled and requested then
			requested = false
			restartLabel.Text = controllers.InputController.IsTouchOnly() and "VOLVER A JUGAR" or "VOLVER A JUGAR  [R]"
		end
	end)
end

local function hide()
	gui.Enabled = false
	requested = false
end

local function show(summary)
	if type(summary) ~= "table" then
		return
	end
	values.Time.Text = Theme.FormatTime(tonumber(summary.Elapsed) or 0)
	values.Kills.Text = tostring(tonumber(summary.Kills) or 0)
	values.Level.Text = tostring(tonumber(summary.Level) or 1)
	restartLabel.Text = controllers.InputController.IsTouchOnly() and "VOLVER A JUGAR" or "VOLVER A JUGAR  [R]"
	requested = false
	shownAt = os.clock()
	gui.Enabled = true
	overlay.BackgroundTransparency = 1
	panel.Position = UDim2.fromScale(0.5, 0.58)
	tween(overlay, 0.5, { BackgroundTransparency = 0.35 })
	tween(panel, 0.45, { Position = UDim2.fromScale(0.5, 0.5) }, Enum.EasingStyle.Back)
end

local function statRow(order: number, label: string, key: string)
	local row = New("Frame", {
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundColor3 = C.PanelLight,
		BackgroundTransparency = 0.3,
		Parent = panel:FindFirstChild("Rows"),
	}, { Theme.Corner(8) })
	Theme.Label({
		Position = UDim2.fromOffset(14, 0),
		Size = UDim2.new(0.65, -14, 1, 0),
		Text = label,
		TextSize = 19,
		TextColor3 = C.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	})
	values[key] = Theme.Label({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 0),
		Size = UDim2.new(0.35, 0, 1, 0),
		Text = "-",
		Font = Theme.Fonts.Title,
		TextSize = 24,
		TextColor3 = C.Gold,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = row,
	})
end

function GameOverController.Init(allControllers)
	controllers = allControllers
end

function GameOverController.Start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = Theme.ScreenGui("GameOverScreen", 20, playerGui)
	gui.Enabled = false

	overlay = New("Frame", {
		Name = "Overlay",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(20, 6, 18),
		BackgroundTransparency = 1,
		Active = true,
		Parent = gui,
	})
	panel = New("Frame", {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(460, 400),
		BackgroundColor3 = C.Panel,
		Parent = gui,
	}, {
		Theme.Corner(16),
		Theme.Stroke(C.Danger, 3, 0.1),
		New("UIGradient", { Rotation = 90, Color = ColorSequence.new(C.PanelLight, C.Panel) }),
	})
	Theme.Scaled(panel)

	Theme.Label({
		Position = UDim2.fromOffset(0, 18),
		Size = UDim2.new(1, 0, 0, 52),
		Text = "HAS CAÍDO",
		Font = Theme.Fonts.Title,
		TextSize = 48,
		TextColor3 = C.Danger,
		TextStrokeTransparency = 0.3,
		Parent = panel,
	})
	Theme.Label({
		Position = UDim2.fromOffset(0, 70),
		Size = UDim2.new(1, 0, 0, 24),
		Text = "La isla reclama a otro aventurero...",
		TextSize = 17,
		TextColor3 = C.TextDim,
		Parent = panel,
	})
	New("Frame", {
		Name = "Rows",
		Position = UDim2.fromOffset(30, 108),
		Size = UDim2.new(1, -60, 0, 140),
		BackgroundTransparency = 1,
		Parent = panel,
	}, {
		New("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8) }),
	})
	statRow(1, "Tiempo sobrevivido", "Time")
	statRow(2, "Enemigos derrotados", "Kills")
	statRow(3, "Nivel alcanzado", "Level")

	restartButton = New("TextButton", {
		Name = "RestartButton",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -24),
		Size = UDim2.fromOffset(320, 64),
		BackgroundColor3 = C.Gold,
		AutoButtonColor = true,
		Text = "",
		Parent = panel,
	}, {
		Theme.Corner(12),
		Theme.Stroke(C.Shadow, 3, 0.2),
	})
	restartLabel = Theme.Label({
		Size = UDim2.fromScale(1, 1),
		Text = "VOLVER A JUGAR",
		Font = Theme.Fonts.Title,
		TextSize = 26,
		TextColor3 = C.Shadow,
		TextStrokeTransparency = 1,
		Parent = restartButton,
	})
	restartButton.Activated:Connect(requestRestart)

	Net.GameOver.OnClientEvent:Connect(show)
	Net.HudUpdate.OnClientEvent:Connect(function(snapshot)
		-- Una partida nueva cierra la pantalla de derrota.
		if gui.Enabled and type(snapshot) == "table" and snapshot.Phase == "Playing" then
			hide()
		end
	end)
	controllers.InputController.Confirm:Connect(requestRestart)
end

return GameOverController
