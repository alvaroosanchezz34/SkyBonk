--!strict
--[[
	RateLimiter
	Limita el número de peticiones por clave (jugador) en una ventana deslizante.
	El reloj se inyecta para poder probarlo fuera de Roblox.
]]

export type RateLimiter = {
	Allow: (self: RateLimiter, key: any) -> boolean,
	Forget: (self: RateLimiter, key: any) -> (),
}

local RateLimiter = {}

function RateLimiter.new(maxRequests: number, window: number, clock: (() -> number)?): RateLimiter
	local now = clock or os.clock
	local history: { [any]: { number } } = {}

	local limiter = {}

	function limiter.Allow(_self: RateLimiter, key: any): boolean
		local t = now()
		local stamps = history[key]
		if stamps == nil then
			stamps = {}
			history[key] = stamps
		end
		-- Descarta marcas fuera de la ventana.
		local firstValid = 1
		while firstValid <= #stamps and t - stamps[firstValid] >= window do
			firstValid += 1
		end
		if firstValid > 1 then
			stamps = table.move(stamps, firstValid, #stamps, 1, {})
			history[key] = stamps
		end
		if #stamps >= maxRequests then
			return false
		end
		table.insert(stamps, t)
		return true
	end

	function limiter.Forget(_self: RateLimiter, key: any)
		history[key] = nil
	end

	return limiter :: RateLimiter
end

return RateLimiter
