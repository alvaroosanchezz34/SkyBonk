-- Prueba B (selección de objetivos) y G (validación y límite de frecuencia).
local Logic = script.Parent.Parent.Logic
local Targeting = require(Logic.Targeting)
local RateLimiter = require(Logic.RateLimiter)
local Validation = require(Logic.Validation)

return function(it, expect)
	it("elige los objetivos vivos más cercanos dentro del alcance", function()
		local enemies = {
			{ Name = "lejos", Position = Vector3.new(40, 0, 0), Dead = false },
			{ Name = "cerca", Position = Vector3.new(5, 0, 0), Dead = false },
			{ Name = "muerto", Position = Vector3.new(1, 0, 0), Dead = true },
			{ Name = "medio", Position = Vector3.new(0, 0, 12), Dead = false },
			{ Name = "borde", Position = Vector3.new(0, 0, -27.9), Dead = false },
		}
		local one = Targeting.nearest(enemies, Vector3.zero, 28, 1)
		expect.equal(#one, 1)
		expect.equal(one[1].Name, "cerca")

		local many = Targeting.nearest(enemies, Vector3.zero, 28, 10)
		expect.equal(#many, 3, "solo 3 válidos dentro del alcance")
		expect.equal(many[1].Name, "cerca")
		expect.equal(many[2].Name, "medio")
		expect.equal(many[3].Name, "borde")

		local filtered = Targeting.nearest(enemies, Vector3.zero, 28, 2, function(e)
			return e.Name ~= "cerca"
		end)
		expect.equal(filtered[1].Name, "medio")
		expect.equal(#Targeting.nearest(enemies, Vector3.zero, 28, 0), 0)
		expect.equal(#Targeting.nearest({}, Vector3.zero, 28, 3), 0)
	end)

	it("el limitador de frecuencia bloquea el spam y se recupera tras la ventana", function()
		local now = 0
		local limiter = RateLimiter.new(3, 1, function()
			return now
		end)
		expect.truthy(limiter:Allow("p"))
		expect.truthy(limiter:Allow("p"))
		expect.truthy(limiter:Allow("p"))
		expect.falsy(limiter:Allow("p"), "la cuarta petición debe rechazarse")
		expect.truthy(limiter:Allow("otro"), "las claves son independientes")
		now = 1.01
		expect.truthy(limiter:Allow("p"))
		limiter:Forget("p")
		expect.truthy(limiter:Allow("p"))
	end)

	it("valida los tipos de los argumentos remotos", function()
		expect.truthy(Validation.isPositiveInteger(3))
		expect.falsy(Validation.isPositiveInteger(0))
		expect.falsy(Validation.isPositiveInteger(1.5))
		expect.falsy(Validation.isPositiveInteger(0 / 0))
		expect.falsy(Validation.isPositiveInteger(math.huge))
		expect.falsy(Validation.isPositiveInteger("3"))
		expect.truthy(Validation.isIdentifier("SharpEdge"))
		expect.falsy(Validation.isIdentifier(""))
		expect.falsy(Validation.isIdentifier("Sharp Edge"))
		expect.falsy(Validation.isIdentifier(string.rep("a", 100)))
		expect.falsy(Validation.isIdentifier({}))
		expect.falsy(Validation.isIdentifier(nil))
	end)
end
