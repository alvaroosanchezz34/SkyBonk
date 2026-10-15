--!strict
--[[
	ServerTypes
	Tipos de las estructuras internas compartidas por los servicios del servidor.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage.Shared.Types)
local RunState = require(script.Parent.Logic.RunState)

-- Una partida en curso (una por jugador).
export type Run = {
	Player: Player,
	State: RunState.RunState,
	Active: boolean, -- false cuando la partida se ha limpiado
	Character: Model,
	Humanoid: Humanoid,
	Root: BasePart,
	Connections: { RBXScriptConnection },
	Rng: Random,
	Paused: boolean,
	InvulnerableUntil: number, -- en tiempo de partida
	HudDirty: boolean,
	NextRegenAt: number,
	LastHudSentAt: number,
	NextFallCheckAt: number,
	EndedAt: number?, -- os.clock() de la derrota
}

export type Enemy = {
	Id: number,
	Def: Types.EnemyDef,
	Run: Run,
	Model: Model,
	Root: BasePart,
	Mover: LinearVelocity,
	Facing: AlignOrientation,
	Health: number,
	MaxHealth: number,
	PendingDamage: number, -- daño de hojas en vuelo que aún no ha impactado
	Damage: number,
	Speed: number,
	Dead: boolean,
	Position: Vector3, -- posición cacheada en el último tick de IA
	State: string, -- Spawning | Chase | Windup | Recover | Stagger | Dead
	StateUntil: number, -- tiempo de partida en que termina el estado actual
	NextAttackAt: number,
	AttackDir: Vector3,
	PendingHitAt: number?, -- golpe del salto del slime pendiente de comprobar
	KnockDir: Vector3,
	HopSeed: number,
	LinkExit: Vector3?, -- salida del acceso (rampa/puente) que está recorriendo
	LastProgressPosition: Vector3,
	LastProgressAt: number,
	SidestepUntil: number,
	SidestepSign: number,
}

export type Gem = {
	Part: BasePart,
	Position: Vector3,
	Value: number,
	ExpiresAt: number, -- math.huge si las gemas no caducan
	Collected: boolean,
	AttractStart: number?, -- tiempo de partida en que empezó a volar hacia el jugador
}

-- Interfaz común de los servicios: Init recibe la tabla de todos los servicios
-- (inyección de dependencias, sin requires cruzados) y Start arranca la lógica.
export type Services = { [string]: any }

return {}
