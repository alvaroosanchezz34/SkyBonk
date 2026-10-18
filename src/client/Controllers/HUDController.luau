--[[
	HUDController
	Interfaz durante la partida (StarterGui equivalente: MainHUD):
	  • nivel, barra de experiencia, tiempo y enemigos derrotados (arriba),
	  • vida actual/máxima (arriba a la izquierda),
	  • panel de estadísticas plegable (Tab / C o botón táctil),
	  • rótulo de subida de nivel y viñeta roja al recibir daño,
	  • barra del jefe, franjas de cine para su entrada y botón de calidad FX.
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
local AuraSystem = require(script.Parent.Parent.Util.AuraSystem)

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
	{ Key = "Chain", Label = "Saltos de rayo", Format = "%d" },
	{ Key = "CritPct", Label = "Crítico", Format = "%.0f %%" },
	{ Key = "MoveSpeed", Label = "Velocidad", Format = "%.1f" },
	{ Key = "DamageReductionPct", Label = "Reducción daño", Format = "%.0f %%" },
	{ Key = "Regen", Label = "Regeneración", Format = "%.0f/s" },
	{ Key = "Magnet", Label = "Imán", Format = "%.0f" },
	{ Key = "XpBonusPct", Label = "Bonus XP", Format = "+%.0f %%" },
	{ Key = "Luck", Label = "Suerte", Format = "%d" },
}

local function tween(instance: Instance, time: number, goal: { [string]: any }, style: Enum.EasingStyle?)
	local t = TweenService:Create(
		instance,
		TweenInfo.new(time, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		goal
	)
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
	refs.LevelScale = New("UIScale", { Parent = badge })
	refs.Level = Theme.Label({
		Size = UDim2.new(1, 0, 0, 34),
		Position = UDim2.fromOffset(0, 21),
		Text = "1",
		Font = Theme.Fonts.Numbers,
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
		Size = UDim2.fromOffset(250, 380),
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
	-- Solo los bordes y semitransparente: avisa del golpe sin tapar el combate.
	local edges = {
		{ UDim2.fromScale(1, 0.1), UDim2.fromScale(0, 0), 90 },
		{ UDim2.fromScale(1, 0.1), UDim2.fromScale(0, 0.9), -90 },
		{ UDim2.fromScale(0.07, 1), UDim2.fromScale(0, 0), 0 },
		{ UDim2.fromScale(0.07, 1), UDim2.fromScale(0.93, 0), 180 },
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
					NumberSequenceKeypoint.new(0, 0.55),
					NumberSequenceKeypoint.new(1, 1),
				}),
			}),
		})
	end
	refs.Vignette = vignette
end

--------------------------------------------- Jefe, cinemática y calidad
-- Barra del jefe (Rey Slime): se muestra mientras haya uno vivo.
local function buildBossBar()
	local panel = New("Frame", {
		Name = "BossBar",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 80),
		Size = UDim2.fromOffset(460, 44),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = gui,
	})
	Theme.Scaled(panel)
	refs.BossName = Theme.Label({
		Size = UDim2.new(1, 0, 0, 20),
		Text = "REY SLIME DEL VACÍO",
		Font = Theme.Fonts.Title,
		TextSize = 22,
		TextColor3 = C.Boss:Lerp(Color3.new(1, 1, 1), 0.35),
		TextStrokeTransparency = 0.2,
		Parent = panel,
	})
	local _, fill, barText = Theme.Bar({
		Name = "Bar",
		Position = UDim2.fromOffset(0, 22),
		Size = UDim2.new(1, 0, 0, 16),
		Parent = panel,
	}, C.Boss, C.Shadow)
	barText.Text = ""
	refs.BossPanel, refs.BossFill = panel, fill
end

local bossModel: Model? = nil
local bossConnection: RBXScriptConnection? = nil

local function setBoss(model: Model?)
	if bossConnection then
		bossConnection:Disconnect()
		bossConnection = nil
	end
	bossModel = model
	refs.BossPanel.Visible = model ~= nil
	if model == nil then
		return
	end
	local function refresh()
		local health = model:GetAttribute("Health")
		local maxHealth = model:GetAttribute("MaxHealth")
		if type(health) == "number" and type(maxHealth) == "number" and maxHealth > 0 then
			tween(refs.BossFill, 0.15, { Size = UDim2.fromScale(math.clamp(health / maxHealth, 0, 1), 1) })
		end
		if model:GetAttribute("Dead") or model.Parent == nil then
			setBoss(nil)
		end
	end
	bossConnection = model.AttributeChanged:Connect(refresh)
	refresh()
end

local function watchBosses()
	local enemies = workspace:WaitForChild("ActiveEnemies")
	enemies.ChildAdded:Connect(function(child)
		task.defer(function()
			if child:GetAttribute("EnemyId") == "VoidKing" then
				setBoss(child :: Model)
			end
		end)
	end)
	enemies.ChildRemoved:Connect(function(child)
		if child == bossModel then
			setBoss(nil)
			-- Si queda otro rey vivo, pasa a mostrarse el suyo.
			for _, other in enemies:GetChildren() do
				if other:GetAttribute("EnemyId") == "VoidKing" and not other:GetAttribute("Dead") then
					setBoss(other :: Model)
					break
				end
			end
		end
	end)
end

-- Franjas de cine con rótulo (entrada del jefe). No bloquea el control.
local function buildCinematic()
	-- ZIndex 0: las franjas quedan por detrás del HUD (vida y XP siguen visibles).
	local layer = New("Frame", {
		Name = "Cinematic",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 0,
		Parent = gui,
	})
	refs.CinemaTop = New("Frame", {
		Size = UDim2.new(1, 0, 0.08, 0),
		Position = UDim2.fromScale(0, -0.08),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BorderSizePixel = 0,
		Parent = layer,
	})
	refs.CinemaBottom = New("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Size = UDim2.new(1, 0, 0.08, 0),
		Position = UDim2.fromScale(0, 1.08),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BorderSizePixel = 0,
		Parent = layer,
	})
	refs.CinemaTitle = Theme.Label({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.22),
		Size = UDim2.fromOffset(700, 70),
		Text = "",
		Font = Theme.Fonts.Title,
		TextSize = 56,
		TextColor3 = C.Boss:Lerp(Color3.new(1, 1, 1), 0.3),
		TextStrokeTransparency = 0,
		TextTransparency = 1,
		Parent = layer,
	})
	refs.CinemaSubtitle = Theme.Label({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.29),
		Size = UDim2.fromOffset(700, 30),
		Text = "",
		Font = Theme.Fonts.Bold,
		TextSize = 20,
		TextTransparency = 1,
		Parent = layer,
	})
	refs.Cinematic = layer
end

local cinemaToken = 0
function HUDController.Cinematic(title: string, subtitle: string, duration: number)
	cinemaToken += 1
	local token = cinemaToken
	local layer = refs.Cinematic
	layer.Visible = true
	refs.CinemaTitle.Text = title
	refs.CinemaSubtitle.Text = subtitle
	refs.CinemaTitle.Size = UDim2.fromOffset(500, 50)
	tween(refs.CinemaTop, 0.3, { Position = UDim2.fromScale(0, 0) })
	tween(refs.CinemaBottom, 0.3, { Position = UDim2.fromScale(0, 1) })
	tween(refs.CinemaTitle, 0.35, { TextTransparency = 0, Size = UDim2.fromOffset(700, 70) }, Enum.EasingStyle.Back)
	tween(refs.CinemaSubtitle, 0.4, { TextTransparency = 0 })
	task.delay(duration, function()
		if token ~= cinemaToken then
			return
		end
		tween(refs.CinemaTop, 0.35, { Position = UDim2.fromScale(0, -0.08) })
		tween(refs.CinemaBottom, 0.35, { Position = UDim2.fromScale(0, 1.08) })
		tween(refs.CinemaTitle, 0.3, { TextTransparency = 1 })
		tween(refs.CinemaSubtitle, 0.3, { TextTransparency = 1 })
		task.delay(0.4, function()
			if token == cinemaToken then
				layer.Visible = false
			end
		end)
	end)
end

-- Botón de calidad de efectos (también tecla G).
local function buildFxButton()
	local button = New("TextButton", {
		Name = "FxButton",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -12, 1, -12),
		Size = UDim2.fromOffset(118, 34),
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.15,
		AutoButtonColor = true,
		Text = "",
		Parent = gui,
	}, {
		Theme.Corner(8),
		Theme.Stroke(C.PanelStroke, 2, 0.4),
	})
	Theme.Scaled(button)
	local label = Theme.Label({
		Size = UDim2.fromScale(1, 1),
		Text = "",
		Font = Theme.Fonts.Bold,
		TextSize = 15,
		Parent = button,
	})
	local function refresh()
		local high = AuraSystem.GetQualityName() == "High"
		label.Text = if high then "✨ FX: ALTO  [G]" else "FX: BAJO  [G]"
		label.TextColor3 = if high then C.Accent else C.TextDim
	end
	button.Activated:Connect(function()
		AuraSystem.ToggleQuality()
	end)
	AuraSystem.QualityChanged:Connect(refresh)
	refresh()
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
	-- Destello de la barra de XP y del distintivo de nivel.
	local fill = refs.XpFill
	fill.BackgroundColor3 = Color3.new(1, 1, 1)
	tween(fill, 0.35, { BackgroundColor3 = C.Xp })
	local badgeScale = refs.LevelScale
	if badgeScale then
		badgeScale.Scale = 1.35
		tween(badgeScale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
	end
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
	buildBossBar()
	buildCinematic()
	buildFxButton()
	task.spawn(watchBosses)
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
