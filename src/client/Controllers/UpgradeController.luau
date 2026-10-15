--[[
	UpgradeController
	Pantalla de subida de nivel (StarterGui equivalente: UpgradeSelection).
	Muestra las opciones que envía el servidor y devuelve SOLO el token de la
	oferta y el id elegido. Los textos se leen de UpgradeConfig únicamente
	para mostrarlos. Admite ratón, toque y teclas 1/2/3.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local UpgradeConfig = require(Shared.Config.UpgradeConfig)
local Net = require(Shared.Net)
local Types = require(Shared.Types)
local Theme = require(script.Parent.Parent.UI.Theme)
local Sfx = require(script.Parent.Parent.Util.Sfx)

local UpgradeController = {}

local C = Theme.Colors
local New = Theme.New

local CARD_WIDTH, CARD_HEIGHT = 270, 340

local controllers
local gui: ScreenGui
local overlay: Frame
local container: Frame
local title: TextLabel
local subtitle: TextLabel
local cardRow: Frame
local hint: TextLabel

type Card = { Button: TextButton, Scale: UIScale, Stroke: UIStroke, Id: string }

local cards: { Card } = {}
local activeOffer: Types.OfferPayload? = nil
local waitingResponse = false

local function tween(instance: Instance, time: number, goal: { [string]: any }, style: Enum.EasingStyle?)
	local t = TweenService:Create(instance, TweenInfo.new(time, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal)
	t:Play()
	return t
end

local function clearCards()
	for _, card in cards do
		card.Button:Destroy()
	end
	table.clear(cards)
end

local function setCardsEnabled(enabled: boolean)
	for _, card in cards do
		card.Button.Active = enabled
		card.Button.AutoButtonColor = false
		card.Stroke.Transparency = if enabled then 0 else 0.5
	end
end

local function choose(index: number)
	local offer = activeOffer
	local card = cards[index]
	if offer == nil or card == nil or waitingResponse then
		return
	end
	waitingResponse = true
	setCardsEnabled(false)
	Sfx.Play("UiSelect")
	tween(card.Scale, 0.12, { Scale = 1.08 }, Enum.EasingStyle.Back)
	Net.ChooseUpgrade:FireServer(offer.Token, card.Id)
end

local function levelText(option: Types.OfferOptionPayload, def: Types.UpgradeDef): string
	if def.IsFallback then
		return "Bendición instantánea"
	end
	if option.CurrentLevel == 0 then
		return "¡NUEVA!"
	end
	local maxText = if def.MaxLevel then " / " .. def.MaxLevel else ""
	return string.format("Nv. %d → %d%s", option.CurrentLevel, option.NextLevel, maxText)
end

local function buildCard(index: number, option: Types.OfferOptionPayload, showKeys: boolean): Card?
	local def = UpgradeConfig.ById[option.Id]
	if def == nil then
		return nil -- id desconocido para este cliente: no se muestra
	end
	local rarity = UpgradeConfig.Rarities[def.Rarity]
	local rarityColor = rarity and rarity.Color or C.PanelStroke

	local button = New("TextButton", {
		Name = "Card" .. index,
		LayoutOrder = index,
		Size = UDim2.fromOffset(CARD_WIDTH, CARD_HEIGHT),
		BackgroundColor3 = C.Panel,
		AutoButtonColor = false,
		Text = "",
		Selectable = true,
		Parent = cardRow,
	}, {
		Theme.Corner(14),
		New("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new(C.PanelLight, C.Panel),
		}),
	})
	local stroke = Theme.Stroke(rarityColor, 3, 0)
	stroke.Parent = button
	local scale = New("UIScale", { Scale = 0.85, Parent = button })

	New("Frame", {
		Name = "RarityBand",
		Size = UDim2.new(1, -24, 0, 6),
		Position = UDim2.fromOffset(12, 10),
		BackgroundColor3 = rarityColor,
		BorderSizePixel = 0,
		Parent = button,
	}, { Theme.Corner(3) })

	local iconCircle = New("Frame", {
		Name = "Icon",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 26),
		Size = UDim2.fromOffset(76, 76),
		BackgroundColor3 = rarityColor:Lerp(C.Panel, 0.55),
		Parent = button,
	}, {
		New("UICorner", { CornerRadius = UDim.new(1, 0) }),
		Theme.Stroke(rarityColor, 2, 0.1),
	})
	Theme.Label({
		Size = UDim2.fromScale(1, 1),
		Text = def.Icon,
		TextSize = 38,
		Font = Theme.Fonts.Bold,
		Parent = iconCircle,
	})

	Theme.Label({
		Name = "UpgradeName",
		Position = UDim2.fromOffset(12, 108),
		Size = UDim2.new(1, -24, 0, 32),
		Text = def.DisplayName,
		Font = Theme.Fonts.Title,
		TextSize = 25,
		TextWrapped = true,
		Parent = button,
	})
	Theme.Label({
		Name = "Rarity",
		Position = UDim2.fromOffset(12, 140),
		Size = UDim2.new(1, -24, 0, 20),
		Text = string.format("%s · %s", rarity and rarity.DisplayName or def.Rarity, def.Category),
		Font = Theme.Fonts.Bold,
		TextSize = 16,
		TextColor3 = rarityColor,
		Parent = button,
	})
	Theme.Label({
		Name = "Description",
		Position = UDim2.fromOffset(16, 170),
		Size = UDim2.new(1, -32, 0, 110),
		Text = def.Description,
		TextSize = 19,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = C.Text,
		Parent = button,
	})
	New("Frame", {
		Name = "LevelTag",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.new(1, -36, 0, 34),
		BackgroundColor3 = C.Shadow,
		BackgroundTransparency = 0.3,
		Parent = button,
	}, {
		Theme.Corner(8),
		Theme.Label({
			Size = UDim2.fromScale(1, 1),
			Text = levelText(option, def),
			Font = Theme.Fonts.Bold,
			TextSize = 17,
			TextColor3 = if option.CurrentLevel == 0 then C.Gold else C.Text,
		}),
	})
	if showKeys then
		New("Frame", {
			Name = "KeyHint",
			Position = UDim2.fromOffset(10, 22),
			Size = UDim2.fromOffset(30, 30),
			BackgroundColor3 = C.Shadow,
			Parent = button,
		}, {
			Theme.Corner(8),
			Theme.Stroke(C.TextDim, 1, 0.3),
			Theme.Label({
				Size = UDim2.fromScale(1, 1),
				Text = tostring(index),
				Font = Theme.Fonts.Bold,
				TextSize = 17,
			}),
		})
	end

	local card: Card = { Button = button, Scale = scale, Stroke = stroke, Id = def.Id }
	button.MouseEnter:Connect(function()
		if button.Active and not waitingResponse then
			Sfx.Play("UiHover", 1.1)
			tween(scale, 0.12, { Scale = 1.05 })
		end
	end)
	button.MouseLeave:Connect(function()
		if not waitingResponse then
			tween(scale, 0.12, { Scale = 1 })
		end
	end)
	button.Activated:Connect(function()
		local position = table.find(cards, card)
		if position then
			choose(position)
		end
	end)
	return card
end

local function hide()
	activeOffer = nil
	waitingResponse = false
	if not gui.Enabled then
		return
	end
	tween(overlay, 0.2, { BackgroundTransparency = 1 })
	tween(container, 0.2, { Position = UDim2.fromScale(0.5, 0.56) })
	task.delay(0.2, function()
		if activeOffer == nil then
			gui.Enabled = false
			clearCards()
		end
	end)
end

local function show(offer: Types.OfferPayload)
	if type(offer) ~= "table" or type(offer.Token) ~= "number" or type(offer.Options) ~= "table" then
		return
	end
	clearCards()
	activeOffer = offer
	waitingResponse = false
	local showKeys = not controllers.InputController.IsTouchOnly()

	title.Text = "¡SUBISTE DE NIVEL!"
	subtitle.Text = string.format("Nivel %d · Elige una mejora", offer.Level)
	hint.Visible = showKeys
	for index, option in offer.Options do
		local card = buildCard(index, option, showKeys)
		if card then
			table.insert(cards, card)
		end
	end

	gui.Enabled = true
	overlay.BackgroundTransparency = 1
	container.Position = UDim2.fromScale(0.5, 0.56)
	tween(overlay, 0.25, { BackgroundTransparency = 0.4 })
	tween(container, 0.3, { Position = UDim2.fromScale(0.5, 0.5) }, Enum.EasingStyle.Back)
	for index, card in cards do
		task.delay((index - 1) * GameConfig.Effects.UpgradeCardStagger, function()
			if card.Button.Parent then
				tween(card.Scale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
			end
		end)
	end
end

local function onResolved(result)
	if type(result) ~= "table" then
		return
	end
	local offer = activeOffer
	if offer == nil or result.Token ~= offer.Token then
		return
	end
	if result.Accepted then
		hide()
	else
		-- Rechazada (p. ej. petición repetida): se permite volver a elegir.
		waitingResponse = false
		setCardsEnabled(true)
		for _, card in cards do
			tween(card.Scale, 0.1, { Scale = 1 })
		end
	end
end

function UpgradeController.IsOpen(): boolean
	return activeOffer ~= nil
end

function UpgradeController.Init(allControllers)
	controllers = allControllers
end

function UpgradeController.Start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = Theme.ScreenGui("UpgradeSelection", 10, playerGui)
	gui.Enabled = false

	overlay = New("Frame", {
		Name = "Overlay",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		Active = true, -- bloquea clics al mundo mientras se elige
		Parent = gui,
	})
	container = New("Frame", {
		Name = "Container",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(3 * CARD_WIDTH + 2 * 20, 470),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	Theme.Scaled(container)
	title = Theme.Label({
		Size = UDim2.new(1, 0, 0, 56),
		Text = "",
		Font = Theme.Fonts.Title,
		TextSize = 46,
		TextColor3 = C.Gold,
		TextStrokeTransparency = 0.3,
		Parent = container,
	})
	subtitle = Theme.Label({
		Position = UDim2.fromOffset(0, 54),
		Size = UDim2.new(1, 0, 0, 26),
		Text = "",
		Font = Theme.Fonts.Bold,
		TextSize = 20,
		TextColor3 = C.Text,
		Parent = container,
	})
	cardRow = New("Frame", {
		Name = "Cards",
		Position = UDim2.fromOffset(0, 92),
		Size = UDim2.new(1, 0, 0, CARD_HEIGHT),
		BackgroundTransparency = 1,
		Parent = container,
	}, {
		New("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 20),
		}),
	})
	hint = Theme.Label({
		Position = UDim2.fromOffset(0, 92 + CARD_HEIGHT + 8),
		Size = UDim2.new(1, 0, 0, 24),
		Text = "Pulsa 1, 2 o 3 · o haz clic en una carta",
		TextSize = 16,
		TextColor3 = C.TextDim,
		Parent = container,
	})

	Net.UpgradeOffer.OnClientEvent:Connect(show)
	Net.UpgradeResolved.OnClientEvent:Connect(onResolved)
	Net.GameOver.OnClientEvent:Connect(function()
		if activeOffer then
			hide()
		end
	end)
	controllers.InputController.SelectOption:Connect(function(index: number)
		if activeOffer then
			choose(index)
		end
	end)
end

return UpgradeController
