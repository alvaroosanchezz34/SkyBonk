--!strict
--[[
	Targeting
	Selección de los N objetivos válidos más cercanos dentro de un alcance.
	Recorre la lista una sola vez y mantiene un pequeño top-N ordenado,
	sin crear tablas intermedias por enemigo.
]]

export type Candidate = {
	Position: Vector3,
	Dead: boolean,
}

local Targeting = {}

-- `candidates` puede contener cualquier tabla con Position y Dead (p. ej. enemigos).
function Targeting.nearest(
	candidates: { any },
	origin: Vector3,
	range: number,
	count: number,
	isValid: ((any) -> boolean)?
): { any }
	local rangeSq = range * range
	local best: { any } = {}
	local bestDist: { number } = {}
	if count <= 0 then
		return best
	end

	for _, candidate: Candidate in candidates do
		if candidate.Dead then
			continue
		end
		local offset = candidate.Position - origin
		local distSq = offset.X * offset.X + offset.Y * offset.Y + offset.Z * offset.Z
		if distSq > rangeSq then
			continue
		end
		if isValid and not isValid(candidate) then
			continue
		end
		-- Inserción ordenada en el top-N.
		local n = #best
		if n < count or distSq < bestDist[n] then
			local insertAt = n + 1
			for i = 1, n do
				if distSq < bestDist[i] then
					insertAt = i
					break
				end
			end
			table.insert(best, insertAt, candidate)
			table.insert(bestDist, insertAt, distSq)
			if #best > count then
				table.remove(best)
				table.remove(bestDist)
			end
		end
	end
	return best
end

return Targeting
