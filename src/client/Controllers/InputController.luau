--[[
	InputController
	Atajos de teclado y mando para la interfaz. El movimiento, el salto y la
	cámara usan los controles estándar de Roblox (teclado/ratón, joystick y
	botón de salto táctiles), que ya cumplen los requisitos.

	Señales:
	  SelectOption(index)  teclas 1/2/3 (o botones X/Y/B del mando)
	  Confirm()            Enter / R / botón A (reiniciar tras la derrota)
	  ToggleStats()        Tab / C
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Signal = require(ReplicatedStorage.Shared.Signal)

local InputController = {}

InputController.SelectOption = Signal.new()
InputController.Confirm = Signal.new()
InputController.ToggleStats = Signal.new()

local OPTION_KEYS: { [Enum.KeyCode]: number } = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.KeypadOne] = 1,
	[Enum.KeyCode.KeypadTwo] = 2,
	[Enum.KeyCode.KeypadThree] = 3,
	[Enum.KeyCode.ButtonX] = 1,
	[Enum.KeyCode.ButtonY] = 2,
	[Enum.KeyCode.ButtonB] = 3,
}

local CONFIRM_KEYS: { [Enum.KeyCode]: boolean } = {
	[Enum.KeyCode.Return] = true,
	[Enum.KeyCode.KeypadEnter] = true,
	[Enum.KeyCode.R] = true,
	[Enum.KeyCode.ButtonA] = true,
}

local STATS_KEYS: { [Enum.KeyCode]: boolean } = {
	[Enum.KeyCode.Tab] = true,
	[Enum.KeyCode.C] = true,
}

-- Dispositivo táctil sin teclado (móvil/tableta).
function InputController.IsTouchOnly(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

function InputController.Init(_controllers) end

function InputController.Start()
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return -- escribiendo en el chat, etc.
		end
		local key = input.KeyCode
		local option = OPTION_KEYS[key]
		if option then
			InputController.SelectOption:Fire(option)
		elseif CONFIRM_KEYS[key] then
			InputController.Confirm:Fire()
		elseif STATS_KEYS[key] then
			InputController.ToggleStats:Fire()
		end
	end)
end

return InputController
