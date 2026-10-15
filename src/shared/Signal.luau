--!strict
--[[
	Signal
	Señal síncrona mínima para desacoplar controladores sin dependencias circulares.
]]

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

type Handler = (...any) -> ()

type ConnectionImpl = Connection & { _fn: Handler, _signal: SignalImpl }

export type Signal = {
	Connect: (self: Signal, fn: Handler) -> Connection,
	Fire: (self: Signal, ...any) -> (),
	DisconnectAll: (self: Signal) -> (),
}

type SignalImpl = Signal & { _connections: { ConnectionImpl } }

local Signal = {}

local function disconnect(self: ConnectionImpl)
	if not self.Connected then
		return
	end
	self.Connected = false
	local list = self._signal._connections
	local index = table.find(list, self)
	if index then
		table.remove(list, index)
	end
end

local function connect(self: SignalImpl, fn: Handler): Connection
	local connection = {
		Connected = true,
		Disconnect = disconnect,
		_fn = fn,
		_signal = self,
	} :: any
	table.insert(self._connections, connection)
	return connection
end

local function fire(self: SignalImpl, ...: any)
	-- Copia para tolerar desconexiones durante la emisión.
	for _, connection in table.clone(self._connections) do
		if connection.Connected then
			local ok, err = pcall(connection._fn, ...)
			if not ok then
				warn("[Signal] Error en un manejador:", err)
			end
		end
	end
end

local function disconnectAll(self: SignalImpl)
	for _, connection in self._connections do
		connection.Connected = false
	end
	table.clear(self._connections)
end

function Signal.new(): Signal
	local signal = {
		_connections = {},
		Connect = connect,
		Fire = fire,
		DisconnectAll = disconnectAll,
	} :: any
	return signal
end

return Signal
