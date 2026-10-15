--[[
	HUDController
	Interfaz durante la partida (StarterGui equivalente: MainHUD):
	  • nivel, barra de experiencia, tiempo y enemigos derrotados (arriba),
	  • vida actual/máxima (arriba a la izquierda),
	  • panel de estadísticas plegable (Tab / C o botón táctil),
	  • rótulo de subida de nivel y viñeta roja al recibir daño.
	Solo muestra el estado que envía el servidor; no decide nada.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local Net = require(Shared.Net)
local Types = require(Shared.Types)
local Theme = require(script.Parent.Parent.UI.Theme)

local HUDController = {}

local C = Theme.Colors
local New = Theme.New

local controllers
local gui: ScreenGui
local refs: { [string]: any } = {}
local snapshot: Types.HudSnapshot? = nil
local elapsedBase = 0
local elapsedReceivedAt = 0
local lastShownSecond = -1
local statsVisible = true

local STAT_ROWS = {
	{ Key = "Damage", Label = "Daño", Format = "%.1f" },
	{ Key = "Cooldown", Label = "Enfriamiento", Format = "%.2f s" },
	{ Key = "Range", Label = "Alcance", Format = "%.1f" },
	{ Key = "Projectiles", Label = "Hojas", Format = "%d" },
	{ Key = "MoveSpeed", Label = "Velocidad", Format = "%.1f" },
	{ Key = "DamageReductionPct", Label = "Reducción daño", Format = "%.0f %%" },
	{ Key = "XpBonusPct", Label = "Bonus XP", Format = "+%.0f %%" },
	{ Key = "Luck", Label = "Suerte", Format = "%d" },
}

local function tween(instance: Instance, time: number, goal: { [string]: any }, style: Enum.EasingStyle?)
	local t = TweenService:Create(instance, TweenInfo.new(time, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal)
	t:Play()
	return t
end

local function buildTopPanel()
	local panel = New("Frame", {
		Name = "TopPanel",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.fromOffset(560, 62),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	Theme.Scaled(panel)

	local badge = New("Frame", {
		Name = "LevelBadge",
		Size = UDim2.fromOffset(62, 62),
		BackgroundColor3 = C.Panel,
		Parent = panel,
	}, {
		Theme.Corner(14),
		Theme.Stroke(C.Gold, 3, 0),
	})
	Theme.Label({
		Size = UDim2.new(1, 0, 0, 18),
		Position = UDim2.fromOffset(0, 5),
		Text = "NIVEL",
		Font = Theme.Fonts.Bold,
		TextSize = 12,
		TextColor3 = C.Gold,
		Parent = badge,
	})
	refs.Level = Theme.Label({
		Size = UDim2.new(1, 0, 0, 34),
		Position = UDim2.fromOffset(0, 21),
		Text = "1",
		Font = Theme.Fonts.Title,
		TextSize = 30,
		Parent = badge,
	})

	local xpBar, xpFill, xpText = Theme.Bar({
		Name = "XpBar",
		Position = UDim2.fromOffset(72, 4),
		Size = UDim2.new(1, -72, 0, 24),
		Parent = panel,
	}, C.Xp, C.XpDark)
	refs.XpBar, refs.XpFill, refs.XpText = xpBar, xpFill, xpText

	local infoRow = New("Frame", {
		Name = "InfoRow",
		Position = UDim2.fromOffset(72, 32),
		Size = UDim2.new(1, -72, 0, 28),
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.25,
		Parent = panel,
	}, { Theme.Corner(8) })
	refs.Timer = Theme.Label({
		Size = UDim2.new(0.5, -8, 1, 0),
		Position = UDim2.fromOffset(10, 0),
		Text = "⏱ 00:00",
		Font = Theme.Fonts.Bold,
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = infoRow,
	})
	refs.Kills = Theme.Label({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 0),
		Size = UDim2.new(0.5, -8, 1, 0),
		Text = "☠ 0",
		Font = Theme.Fonts.Bold,
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = infoRow,
	})
end

-- Columna izquierda escalada: vida + estadísticas (sin solaparse a ninguna escala).
local function buildLeftColumn()
	refs.LeftColumn = New("Frame", {
		Name = "LeftColumn",
		Position = UDim2.fromOffset(12, 8),
		Size = UDim2.fromOffset(250, 300),
		BackgroundTransparency = 1,
		Parent = gui,
	}, {
		New("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 8),
		}),
	})
	Theme.Scaled(refs.LeftColumn)
end

local function buildHealthPanel()
	local panel = New("Frame", {
		Name = "HealthPanel",
		LayoutOrder = 1,
		Size = UDim2.fromOffset(250, 40),
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.15,
		Parent = refs.LeftColumn,
	}, {
		Theme.Corner(10),
		Theme.Stroke(C.PanelStroke, 2, 0.4),
	})
	Theme.Label({
		Size = UDim2.fromOffset(34, 40),
		Text = "❤",
		TextSize = 22,
		TextColor3 = C.Health,
		Parent = panel,
	})
	local bar, fill, text = Theme.Bar({
		Name = "HealthBar",
		Position = UDim2.fromOffset(36, 8),
		Size = UDim2.new(1, -46, 0, 24),
		Parent = panel,
	}, C.Health, C.HealthDark)
	refs.HealthBar, refs.HealthFill, refs.HealthText = bar, fill, text
end

local function buildStatsPanel()
	local panel = New("Frame", {
		Name = "StatsPanel",
		LayoutOrder = 2,
		Size = UDim2.fromOffset(210, 36 + #STAT_ROWS * 22),
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.2,
		Parent = refs.LeftColumn,
	}, {
		Theme.Corner(10),
		Theme.Stroke(C.PanelStroke, 2, 0.5),
	})

	local header = New("TextButton", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 30),
		BackgroundTransparency = 1,
		Text = "",
		Parent = panel,
	})
	refs.StatsHeaderLabel = Theme.Label({
		Size = UDim2.new(1, -16, 1, 0),
		Position = UDim2.fromOffset(10, 0),
		Text = "ESTADÍSTICAS  ▾",
		Font = Theme.Fonts.Title,
		TextSize = 16,
		TextColor3 = C.Gold,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = header,
	})
	header.Activated:Connect(function()
		HUDController.ToggleStats()
	end)

	local rows = New("Frame", {
		Name = "Rows",
		Position = UDim2.fromOffset(10, 30),
		Size = UDim2.new(1, -20, 0, #STAT_ROWS * 22),
		BackgroundTransparency = 1,
		Parent = panel,
	}, {
		New("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	refs.StatValues = {}
	for index, row in STAT_ROWS do
		local line = New("Frame", {
			LayoutOrder = index,
			Size = UDim2.new(1, 0, 0, 22),
			BackgroundTransparency = 1,
			Parent = rows,
		})
		Theme.Label({
			Size = UDim2.fromScale(0.62, 1),
			Text = row.Label,
			TextSize = 15,
			TextColor3 = C.TextDim,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = line,
		})
		refs.StatValues[row.Key] = Theme.Label({
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.fromScale(0.38, 1),
			Text = "-",
			Font = Theme.Fonts.Bold,
			TextSize = 15,
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = line,
		})
	end
	refs.StatsPanel = panel
	refs.StatsRows = rows
end

local function buildBannerAndVignette()
	refs.Banner = Theme.Label({
		Name = "LevelUpBanner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.3),
		Size = UDim2.fromOffset(600, 80),
		Text = "",
		Font = Theme.Fonts.Title,
		TextSize = 54,
		TextColor3 = C.Gold,
		TextStrokeTransparency = 0.2,
		TextTransparency = 1,
		Parent = gui,
	})
	Theme.Scaled(refs.Banner)

	-- Viñeta: cuatro bordes rojos con degradado hacia el centro.
	local vignette = New("Frame", {
		Name = "DamageVignette",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = gui,
	})
	local edges = {
		{ UDim2.fromScale(1, 0.22), UDim2.fromScale(0, 0), 90 },
		{ UDim2.fromScale(1, 0.22), UDim2.fromScale(0, 0.78), -90 },
		{ UDim2.fromScale(0.16, 1), UDim2.fromScale(0, 0), 0 },
		{ UDim2.fromScale(0.16, 1), UDim2.fromScale(0.84, 0), 180 },
	}
	for _, edge in edges do
		New("Frame", {
			Size = edge[1],
			Position = edge[2],
			BackgroundColor3 = C.Danger,
			BorderSizePixel = 0,
			Parent = vignette,
		}, {
			New("UIGradient", {
				Rotation = edge[3],
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0.35),
					NumberSequenceKeypoint.new(1, 1),
				}),
			}),
		})
	end
	refs.Vignette = vignette
end

function HUDController.ToggleStats()
	statsVisible = not statsVisible
	refs.StatsRows.Visible = statsVisible
	refs.StatsPanel.Size = UDim2.fromOffset(210, if statsVisible then 36 + #STAT_ROWS * 22 else 30)
	refs.StatsHeaderLabel.Text = if statsVisible then "ESTADÍSTICAS  ▾" else "ESTADÍSTICAS  ▸"
end

local function applySnapshot(data: Types.HudSnapshot)
	local previous = snapshot
	snapshot = data
	elapsedBase = data.Elapsed
	elapsedReceivedAt = os.clock()

	refs.Level.Text = tostring(data.Level)
	local xpRatio = math.clamp(data.Xp / math.max(data.XpToNext, 1), 0, 1)
	if previous and previous.Level ~= data.Level then
		refs.XpFill.Size = UDim2.fromScale(0, 1)
	end
	tween(refs.XpFill, 0.15, { Size = UDim2.fromScale(xpRatio, 1) })
	refs.XpText.Text = string.format("XP  %d / %d", math.floor(data.Xp), data.XpToNext)

	local healthRatio = math.clamp(data.Health / math.max(data.MaxHealth, 1), 0, 1)
	tween(refs.HealthFill, 0.12, { Size = UDim2.fromScale(healthRatio, 1) })
	refs.HealthText.Text = string.format("%d / %d", math.ceil(data.Health), math.floor(data.MaxHealth))

	refs.Kills.Text = "☠ " .. data.Kills

	for _, row in STAT_ROWS do
		local value = (data.Stats :: any)[row.Key]
		if type(value) == "number" then
			refs.StatValues[row.Key].Text = string.format(row.Format, value)
		end
	end
end

local function showLevelBanner(level: number)
	local banner = refs.Banner
	banner.Text = "¡NIVEL " .. level .. "!"
	banner.TextTransparency = 0
	banner.TextStrokeTransparency = 0.2
	banner.Size = UDim2.fromOffset(420, 60)
	tween(banner, 0.25, { Size = UDim2.fromOffset(600, 80) }, Enum.EasingStyle.Back)
	task.delay(GameConfig.Effects.LevelUpBannerTime, function()
		if banner.Text == "¡NIVEL " .. level .. "!" then
			tween(banner, 0.4, { TextTransparency = 1, TextStrokeTransparency = 1 })
		end
	end)
end

local vignetteToken = 0
local function flashVignette()
	vignetteToken += 1
	local token = vignetteToken
	refs.Vignette.Visible = true
	task.delay(GameConfig.Effects.DamageVignetteTime, function()
		if token == vignetteToken then
			refs.Vignette.Visible = false
		end
	end)
end

function HUDController.GetSnapshot(): Types.HudSnapshot?
	return snapshot
end

function HUDController.Init(allControllers)
	controllers = allControllers
end

function HUDController.Start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = Theme.ScreenGui("MainHUD", 1, playerGui)
	buildTopPanel()
	buildLeftColumn()
	buildHealthPanel()
	buildStatsPanel()
	buildBannerAndVignette()
	if controllers.InputController.IsTouchOnly() then
		HUDController.ToggleStats() -- plegado por defecto en móvil
	end

	controllers.InputController.ToggleStats:Connect(HUDController.ToggleStats)
	Net.HudUpdate.OnClientEvent:Connect(applySnapshot)
	Net.LevelUp.OnClientEvent:Connect(function(info)
		if type(info) == "table" and type(info.Level) == "number" then
			showLevelBanner(info.Level)
		end
	end)
	Net.PlayerDamaged.OnClientEvent:Connect(flashVignette)

	-- El tiempo se extrapola localmente entre actualizaciones del servidor.
	RunService.RenderStepped:Connect(function()
		local data = snapshot
		if data == nil then
			return
		end
		local elapsed = elapsedBase
		if data.Phase == "Playing" then
			elapsed += os.clock() - elapsedReceivedAt
		end
		local second = math.floor(elapsed)
		if second ~= lastShownSecond then
			lastShownSecond = second
			refs.Timer.Text = "⏱ " .. Theme.FormatTime(elapsed)
		end
	end)
end

return HUDController
