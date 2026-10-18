--[[
	Theme
	Estilo visual común (fantasía low-poly) y utilidades para construir la
	interfaz por código: colores, fuentes, esquinas, bordes y escalado
	adaptable a la resolución (PC y móvil).
]]

local Workspace = game:GetService("Workspace")

local Theme = {}

-- Estilo anime fantasy (Fase 2.5): azul noche, acentos cian (jugador) y dorado (recompensa).
Theme.Colors = {
	Panel = Color3.fromRGB(14, 18, 42),
	PanelLight = Color3.fromRGB(30, 38, 84),
	PanelStroke = Color3.fromRGB(110, 200, 255),
	Accent = Color3.fromRGB(120, 235, 255),
	Boss = Color3.fromRGB(214, 60, 120),
	Gold = Color3.fromRGB(255, 208, 96),
	Text = Color3.fromRGB(240, 244, 255),
	TextDim = Color3.fromRGB(170, 182, 220),
	Xp = Color3.fromRGB(80, 230, 255),
	XpDark = Color3.fromRGB(20, 60, 90),
	Health = Color3.fromRGB(236, 72, 96),
	HealthDark = Color3.fromRGB(70, 20, 34),
	Danger = Color3.fromRGB(255, 70, 70),
	Shadow = Color3.fromRGB(8, 8, 20),
}

Theme.Fonts = {
	Title = Enum.Font.Bangers, -- rótulos (estilo cómic/manga)
	Numbers = Enum.Font.FredokaOne, -- cifras y números de daño (máxima legibilidad)
	Body = Enum.Font.GothamMedium,
	Bold = Enum.Font.GothamBold,
}

-- Resolución de diseño. La interfaz se escala para caber en pantallas pequeñas
-- sin que el texto baje de un tamaño legible.
local DESIGN_SIZE = Vector2.new(1280, 720)
local MIN_SCALE, MAX_SCALE = 0.72, 1.3

local scales: { UIScale } = {}
local currentScale = 1

-- Crea una instancia con propiedades e hijos.
function Theme.New(className: string, props: { [string]: any }?, children: { Instance }?): any
	local instance = Instance.new(className)
	local parent = nil
	if props then
		for key, value in props do
			if key == "Parent" then
				parent = value
			else
				(instance :: any)[key] = value
			end
		end
	end
	if children then
		for _, child in children do
			child.Parent = instance
		end
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

function Theme.Corner(radius: number?): UICorner
	return Theme.New("UICorner", { CornerRadius = UDim.new(0, radius or 10) })
end

function Theme.Stroke(color: Color3?, thickness: number?, transparency: number?): UIStroke
	return Theme.New("UIStroke", {
		Color = color or Theme.Colors.PanelStroke,
		Thickness = thickness or 2,
		Transparency = transparency or 0.2,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function Theme.Label(props: { [string]: any }): TextLabel
	local defaults = {
		BackgroundTransparency = 1,
		TextColor3 = Theme.Colors.Text,
		Font = Theme.Fonts.Body,
		TextSize = 18,
		TextStrokeTransparency = 0.6,
		TextStrokeColor3 = Theme.Colors.Shadow,
	}
	for key, value in props do
		defaults[key] = value
	end
	return Theme.New("TextLabel", defaults)
end

--[[
	Barra estilizada: fondo oscuro, relleno con degradado horizontal (más claro
	en la punta), brillo superior y borde luminoso del color del relleno.
	Devuelve (contenedor, relleno, texto).
]]
function Theme.Bar(props: { [string]: any }, fillColor: Color3, backColor: Color3): (Frame, Frame, TextLabel)
	local container = Theme.New("Frame", props, {
		Theme.Corner(6),
		Theme.Stroke(fillColor:Lerp(Color3.new(1, 1, 1), 0.2), 2, 0.25),
	})
	container.BackgroundColor3 = backColor
	container.BorderSizePixel = 0
	container.ClipsDescendants = false
	local fill = Theme.New("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = fillColor,
		BorderSizePixel = 0,
		Parent = container,
	}, {
		Theme.Corner(6),
		Theme.New("UIGradient", {
			Color = ColorSequence.new(
				fillColor:Lerp(Color3.new(0, 0, 0), 0.25),
				fillColor:Lerp(Color3.new(1, 1, 1), 0.35)
			),
		}),
	})
	Theme.New("Frame", {
		Name = "Shine",
		Size = UDim2.new(1, -6, 0.32, 0),
		Position = UDim2.fromOffset(3, 2),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.78,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = fill,
	}, { Theme.Corner(4) })
	local text = Theme.Label({
		Name = "Text",
		Size = UDim2.fromScale(1, 1),
		Font = Theme.Fonts.Bold,
		TextSize = 16,
		ZIndex = 3,
		Parent = container,
	})
	return container, fill, text
end

-- ScreenGui estándar (no se reinicia al reaparecer y respeta zonas seguras).
function Theme.ScreenGui(name: string, displayOrder: number, parent: Instance): ScreenGui
	return Theme.New("ScreenGui", {
		Name = name,
		DisplayOrder = displayOrder,
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = parent,
	})
end

local function computeScale(): number
	local camera = Workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or DESIGN_SIZE
	local scale = math.min(viewport.X / DESIGN_SIZE.X, viewport.Y / DESIGN_SIZE.Y)
	return math.clamp(scale, MIN_SCALE, MAX_SCALE)
end

-- Añade un UIScale adaptable a un panel (no a overlays de pantalla completa).
function Theme.Scaled(panel: GuiObject): UIScale
	local uiScale = Theme.New("UIScale", { Scale = currentScale, Parent = panel })
	table.insert(scales, uiScale)
	return uiScale
end

function Theme.GetScale(): number
	return currentScale
end

function Theme.StartAutoScale()
	local function update()
		currentScale = computeScale()
		for index = #scales, 1, -1 do
			local uiScale = scales[index]
			if uiScale.Parent then
				uiScale.Scale = currentScale
			else
				table.remove(scales, index)
			end
		end
	end
	local function bindCamera()
		local camera = Workspace.CurrentCamera
		if camera then
			camera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
		end
		update()
	end
	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCamera)
	bindCamera()
end

-- Panel con degradado vertical y línea de acento superior.
function Theme.Panel(props: { [string]: any }, accent: Color3?): Frame
	local panel = Theme.New("Frame", props, {
		Theme.Corner(10),
		Theme.Stroke(accent or Theme.Colors.PanelStroke, 2, 0.35),
		Theme.New("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new(Theme.Colors.PanelLight, Theme.Colors.Panel),
		}),
	})
	panel.BackgroundColor3 = Color3.new(1, 1, 1)
	panel.BorderSizePixel = 0
	Theme.New("Frame", {
		Name = "AccentLine",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 0),
		Size = UDim2.new(0.6, 0, 0, 2),
		BackgroundColor3 = accent or Theme.Colors.Accent,
		BorderSizePixel = 0,
		Parent = panel,
	})
	return panel
end

function Theme.FormatTime(seconds: number): string
	local total = math.max(0, math.floor(seconds))
	return string.format("%02d:%02d", total // 60, total % 60)
end

return Theme
