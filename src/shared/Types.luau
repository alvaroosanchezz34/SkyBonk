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
	Color: Color3,
}

export type EnemyDef = {
	Id: string,
	DisplayName: string,
	ModelName: string,
	MaxHealth: number,
	ContactDamage: number,
	MoveSpeed: number,
	AttackRange: number,
	AttackCooldown: number,
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
