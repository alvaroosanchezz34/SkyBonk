--[[
	Harness
	Carga módulos del proyecto fuera de Roblox (Lune) emulando lo mínimo:
	`script`, `require(instancia)`, `game:GetService(...)` y los tipos de datos
	de @lune/roblox. `options` permite sustituir servicios, globales y módulos
	concretos (p. ej. Shared/Net) por versiones simuladas.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local task = require("@lune/task")

local ROOT = process.cwd

-- Lune hace E/S asíncrona y los metamétodos no pueden ceder: se precarga
-- el árbol de archivos completo antes de ejecutar nada.
local IS_DIR: { [string]: boolean } = {}
local EXISTS: { [string]: boolean } = {}
local DIR_ENTRIES: { [string]: { string } } = {}
local SOURCES: { [string]: string } = {}

local function scan(path: string)
	EXISTS[path] = true
	if fs.isDir(path) then
		IS_DIR[path] = true
		local entries = fs.readDir(path)
		table.sort(entries)
		DIR_ENTRIES[path] = entries
		for _, entry in entries do
			scan(path .. "/" .. entry)
		end
	elseif string.sub(path, -5) == ".luau" then
		SOURCES[path] = fs.readFile(path)
	end
end
scan(ROOT .. "/src")

local Harness = {}
Harness.ROOT = ROOT

function Harness.new(options: { services: any?, globals: any?, modules: any? }?)
	options = options or {}

	-- Árbol de Rojo simplificado: nombre de instancia -> carpeta del repositorio.
	local SERVICE_ROOTS = {
		ReplicatedStorage = { Shared = ROOT .. "/src/shared" },
		ServerScriptService = { __path = ROOT .. "/src/server" },
	}

	local nodeCache = {}
	local moduleCache = {}
	local makeNode

	local function stripExtension(fileName: string): string
		for _, ext in { ".server.luau", ".client.luau", ".luau", ".model.json" } do
			if string.sub(fileName, -#ext) == ext then
				return string.sub(fileName, 1, -#ext - 1)
			end
		end
		return fileName
	end

	local function resolveChild(dir: string, name: string): string?
		for _, candidate in { dir .. "/" .. name .. ".luau", dir .. "/" .. name } do
			if EXISTS[candidate] then
				return candidate
			end
		end
		return nil
	end

	-- Un nodo representa una carpeta o un archivo como si fuera una instancia.
	function makeNode(path: string, virtualChildren: { [string]: string }?)
		if nodeCache[path] then
			return nodeCache[path]
		end
		local node = {}
		local isDir = IS_DIR[path] == true
		local name = stripExtension(string.match(path, "[^/]+$") or path)
		if string.sub(name, -5) == "/init" then
			name = string.sub(name, 1, -6)
		end

		local methods = {}
		function methods.GetChildren()
			local list = {}
			if virtualChildren then
				for _, childPath in virtualChildren do
					table.insert(list, makeNode(childPath))
				end
			elseif isDir then
				for _, entry in DIR_ENTRIES[path] do
					if entry ~= "init.luau" then
						table.insert(list, makeNode(path .. "/" .. entry))
					end
				end
			end
			return list
		end
		function methods.FindFirstChild(_, childName: string)
			if virtualChildren then
				return virtualChildren[childName] and makeNode(virtualChildren[childName]) or nil
			end
			local childPath = isDir and resolveChild(path, childName)
			return childPath and makeNode(childPath) or nil
		end
		function methods.WaitForChild(self, childName: string)
			local child = methods.FindFirstChild(self, childName)
			assert(child, "Hijo inexistente " .. childName .. " en " .. path)
			return child
		end
		function methods.IsA(_, className: string)
			return className == "ModuleScript" and not isDir
		end

		setmetatable(node, {
			__index = function(_, key)
				if key == "Name" then
					return name
				elseif key == "Parent" then
					local parentPath = string.match(path, "^(.*)/[^/]+$")
					return parentPath and makeNode(parentPath) or nil
				elseif key == "__path" then
					return path
				elseif methods[key] then
					return methods[key]
				end
				local child = methods.FindFirstChild(node, key)
				assert(child, "No existe '" .. tostring(key) .. "' en " .. path)
				return child
			end,
			__tostring = function()
				return name
			end,
		})
		nodeCache[path] = node
		return node
	end

	local services = {}
	for serviceName, mapping in SERVICE_ROOTS do
		if mapping.__path then
			services[serviceName] = makeNode(mapping.__path)
		else
			services[serviceName] = makeNode("<" .. serviceName .. ">", table.clone(mapping))
		end
	end

	local fakeGame = {
		GetService = function(_, serviceName: string)
			local override = options.services and options.services[serviceName]
			if override then
				return override
			end
			return assert(services[serviceName], "Servicio no simulado: " .. serviceName)
		end,
	}

	local requireNode

	local function moduleFile(node): string
		local path = node.__path
		if IS_DIR[path] then
			path ..= "/init.luau"
		end
		return path
	end

	function requireNode(node)
		if type(node) == "string" then
			return require(node)
		end
		local file = moduleFile(node)
		local relative = string.sub(file, #ROOT + 2)
		if options.modules and options.modules[relative] ~= nil then
			return options.modules[relative]
		end
		if moduleCache[file] ~= nil then
			return moduleCache[file]
		end
		local env = {
			script = node,
			require = requireNode,
			game = fakeGame,
			task = task,
			warn = function(...)
				print("[warn]", ...)
			end,
			Vector3 = roblox.Vector3,
			Vector2 = roblox.Vector2,
			CFrame = roblox.CFrame,
			Color3 = roblox.Color3,
			UDim2 = roblox.UDim2,
			UDim = roblox.UDim,
			Enum = roblox.Enum,
			Instance = roblox.Instance,
			NumberSequence = roblox.NumberSequence,
			NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
			ColorSequence = roblox.ColorSequence,
			NumberRange = roblox.NumberRange,
			PhysicalProperties = roblox.PhysicalProperties,
		}
		if options.globals then
			for key, value in options.globals do
				env[key] = value
			end
		end
		local chunk = luau.load(assert(SOURCES[file], "Módulo no encontrado: " .. file), {
			debugName = string.sub(file, #ROOT + 2),
			environment = env,
		})
		local result = chunk()
		moduleCache[file] = if result == nil then false else result
		return result
	end

	return {
		ROOT = ROOT,
		node = makeNode,
		require = requireNode,
		path = function(relative: string)
			return makeNode(ROOT .. "/" .. relative)
		end,
	}
end

return Harness
