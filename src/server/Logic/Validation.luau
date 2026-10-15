--!strict
--[[
	Validation
	Comprobaciones de tipos para los argumentos que llegan por RemoteEvents.
]]

local Validation = {}

function Validation.isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function Validation.isPositiveInteger(value: any): boolean
	return Validation.isFiniteNumber(value) and value >= 1 and value % 1 == 0 and value < 2 ^ 31
end

-- Identificadores: solo letras y números ASCII, longitud acotada.
function Validation.isIdentifier(value: any, maxLength: number?): boolean
	if type(value) ~= "string" then
		return false
	end
	local length = #value
	if length == 0 or length > (maxLength or 64) then
		return false
	end
	return string.match(value, "^[%w_]+$") ~= nil
end

return Validation
