--!strict
--[[
	Types
	Tipos compartidos entre servidor y cliente para las interfaces importantes.
]]

export type GamePhase = "Playing" | "ChoosingUpgrade" | "GameOver"

export type WeaponDef = {
	Id: string,
	DisplayName: string,
	Description: string,
	Pattern: string,
	Damage: number,
	Cooldown: number,
	MinCooldown: number,
	Range: number,
	Projectiles: number,
	MaxProjectiles: number,
	TargetsPerProjectile: number,
	MaxTargetsPerProjectile: number,
	ProjectileSpeed: number, -- studs/s de la hoja visual (decide el instante del impacto)
	WindupTime: number, -- anticipación del tajo antes de lanzar las hojas
	ChainRange: number, -- distancia máxima de los saltos de Filo de Tormenta
	Color: Color3,
}

-- Lunge: salto corto hacia el jugador. Melee: tajo frontal. Slam: golpe en área.
export type EnemyAttackKind = "Lunge" | "Melee" | "Slam"

export type EnemyDef = {
	Id: string,
	DisplayName: string,
	ModelName: string,
	Rig: "Slime" | "Skeleton",
	Scale: number, -- escala del modelo respecto a la plantilla
	MaxHealth: number,
	ContactDamage: number,
	MoveSpeed: number,
	AttackKind: EnemyAttackKind,
	AttackRange: number, -- distancia horizontal a la que se inicia el ataque
	HitRange: number, -- distancia a la que el golpe impacta al terminar la anticipación
	AttackWindup: number, -- segundos de anticipación visible antes del daño
	AttackCooldown: number,
	Poise: boolean, -- true = los impactos no interrumpen su ataque
	Knockback: number, -- velocidad del retroceso al recibir un impacto (studs/s)
	HopFrequency: number?, -- saltos por segundo (solo slimes): modula la velocidad
	XpReward: number,
	Color: Color3,
}

-- Estadísticas modificables por las mejoras. Los porcentajes son aditivos
-- (0.15 = +15 %) y los multiplicadores se acumulan multiplicando.
export type Stats = {
	DamagePct: number,
	CooldownMult: number,
	RangePct: number,
	MaxHealthPct: number,
	MoveSpeedPct: number,
	XpGainPct: number,
	DamageTakenMult: number,
	Luck: number,
	ExtraProjectiles: number,
	ExtraChain: number,
	CritChance: number,
	HealthRegen: number,
	MagnetPct: number,
}

export type StatName =
	"DamagePct"
	| "CooldownMult"
	| "RangePct"
	| "MaxHealthPct"
	| "MoveSpeedPct"
	| "XpGainPct"
	| "DamageTakenMult"
	| "Luck"
	| "ExtraProjectiles"
	| "ExtraChain"
	| "CritChance"
	| "HealthRegen"
	| "MagnetPct"

-- "Add" suma Value a la estadística, "Mul" la multiplica y "HealPct" cura
-- al instante un porcentaje de la vida máxima (no modifica Stats).
export type UpgradeEffect = {
	Op: "Add" | "Mul" | "HealPct",
	Stat: StatName?,
	Value: number,
}

export type Rarity = "Common" | "Rare" | "Epic"

export type UpgradeDef = {
	Id: string,
	DisplayName: string,
	Description: string,
	Rarity: Rarity,
	Category: string,
	Icon: string,
	MaxLevel: number?, -- nil = sin límite
	Weight: number?, -- multiplicador adicional de probabilidad (por defecto 1)
	Effects: { UpgradeEffect },
	Requires: string?, -- nombre de un requisito evaluado por UpgradeLogic
	Enabled: boolean?, -- false = nunca se ofrece
	DisabledReason: string?,
	IsFallback: boolean?, -- solo se ofrece para completar ofertas incompletas
}

export type WeaponState = {
	Id: string,
	Def: WeaponDef,
	NextAttackAt: number,
}

export type WeaponStats = {
	Damage: number,
	Cooldown: number,
	Range: number,
	Projectiles: number,
	TargetsPerProjectile: number,
	CritChance: number,
}

export type Offer = {
	Token: number,
	Level: number,
	Options: { string },
	Consumed: boolean,
}

export type Progress = {
	Level: number,
	Xp: number,
	TotalXp: number,
	PendingLevels: { number }, -- niveles alcanzados cuya mejora aún no se ha elegido
}

-- Opción enviada al cliente: solo el id y los niveles; los textos se leen
-- de UpgradeConfig en el cliente (únicamente para mostrarlos).
export type OfferOptionPayload = {
	Id: string,
	CurrentLevel: number,
	NextLevel: number,
}

export type OfferPayload = {
	Token: number,
	Level: number,
	Options: { OfferOptionPayload },
}

export type StatSummary = {
	Damage: number,
	Cooldown: number,
	Range: number,
	Projectiles: number,
	MoveSpeed: number,
	DamageReductionPct: number,
	XpBonusPct: number,
	Luck: number,
	CritPct: number,
	Chain: number,
	Regen: number,
	Magnet: number,
}

export type HudSnapshot = {
	Phase: GamePhase,
	Level: number,
	Xp: number,
	XpToNext: number,
	Health: number,
	MaxHealth: number,
	Kills: number,
	Elapsed: number,
	Stats: StatSummary,
}

export type GameOverPayload = {
	Elapsed: number,
	Kills: number,
	Level: number,
}

return {}
