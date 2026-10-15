--[[
	TestRunner
	Microframework de pruebas que funciona igual en Roblox Studio (al iniciar el
	servidor, ver Bootstrap) y fuera de Roblox con Lune (tests/run.luau).

	Cada módulo *.spec devuelve function(it, expect).
]]

local TestRunner = {}

local function format(value: any): string
	if type(value) == "string" then
		return string.format("%q", value)
	end
	return tostring(value)
end

local expect = {}

function expect.equal(actual: any, expected: any, message: string?)
	if actual ~= expected then
		error(string.format("%sse esperaba %s, se obtuvo %s", message and (message .. ": ") or "", format(expected), format(actual)), 2)
	end
end

function expect.near(actual: number, expected: number, epsilon: number?, message: string?)
	if type(actual) ~= "number" or math.abs(actual - expected) > (epsilon or 1e-6) then
		error(string.format("%sse esperaba ≈%s, se obtuvo %s", message and (message .. ": ") or "", format(expected), format(actual)), 2)
	end
end

function expect.truthy(value: any, message: string?)
	if not value then
		error((message or "se esperaba un valor verdadero") .. ", se obtuvo " .. format(value), 2)
	end
end

function expect.falsy(value: any, message: string?)
	if value then
		error((message or "se esperaba un valor falso") .. ", se obtuvo " .. format(value), 2)
	end
end

TestRunner.expect = expect

export type Report = { Passed: number, Failed: number, Failures: { string } }

function TestRunner.runSpec(name: string, spec: (any, any) -> (), report: Report)
	local cases: { { name: string, fn: () -> () } } = {}
	spec(function(caseName: string, fn: () -> ())
		table.insert(cases, { name = caseName, fn = fn })
	end, expect)
	for _, case in cases do
		local ok, err = pcall(case.fn)
		if ok then
			report.Passed += 1
			print(string.format("  ✔ %s › %s", name, case.name))
		else
			report.Failed += 1
			local line = string.format("  ✘ %s › %s\n      %s", name, case.name, tostring(err))
			table.insert(report.Failures, line)
			print(line)
		end
	end
end

-- `folder` es una instancia (o un nodo simulado en Lune) con hijos *.spec.
function TestRunner.runFolder(folder: any): Report
	local report: Report = { Passed = 0, Failed = 0, Failures = {} }
	local children = folder:GetChildren()
	table.sort(children, function(a, b)
		return a.Name < b.Name
	end)
	for _, child in children do
		if string.sub(child.Name, -5) == ".spec" then
			local ok, spec = pcall(require, child)
			if ok and type(spec) == "function" then
				TestRunner.runSpec(string.sub(child.Name, 1, -6), spec, report)
			else
				report.Failed += 1
				local line = "  ✘ " .. child.Name .. " no se pudo cargar: " .. tostring(spec)
				table.insert(report.Failures, line)
				print(line)
			end
		end
	end
	print(string.format("[SkyBonk Tests] %d correctas, %d fallidas", report.Passed, report.Failed))
	return report
end

return TestRunner
