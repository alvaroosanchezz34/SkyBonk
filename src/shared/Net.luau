--[[
	Net
	Acceso tipado a los RemoteEvents definidos en Shared/Remotes.

	Cliente -> Servidor (el servidor valida tipos, estado y frecuencia):
	  ClientReady()                         el cliente ha cargado su interfaz
	  ChooseUpgrade(token: number, id: string) elección de la oferta activa
	  RequestRestart()                      reiniciar tras la derrota

	Servidor -> Cliente (solo presentación):
	  HudUpdate(snapshot)        estado de la partida para el HUD
	  UpgradeOffer(offer)        abrir la pantalla de mejoras
	  UpgradeResolved(result)    la oferta se ha cerrado (o la elección se rechazó)
	  CombatFx(attack)           tajo y hojas lanzadas (solo presentación)
	  CombatHits(hits)           impactos aplicados por el servidor (daño, crítico, muerte)
	  WorldFx(event)             efectos del mundo (p. ej. Cristal de Esencia roto)
	  EnemyDied(info)            efecto de muerte de un enemigo
	  GemCollected(info)         efecto de recogida de experiencia
	  PlayerDamaged(info)        indicador de daño recibido
	  LevelUp(info)              efecto de subida de nivel
	  GameOver(summary)          pantalla de derrota
]]

local RemotesFolder = script.Parent:WaitForChild("Remotes")

local NAMES = {
	"ClientReady",
	"ChooseUpgrade",
	"RequestRestart",
	"HudUpdate",
	"UpgradeOffer",
	"UpgradeResolved",
	"CombatFx",
	"CombatHits",
	"WorldFx",
	"EnemyDied",
	"GemCollected",
	"PlayerDamaged",
	"LevelUp",
	"GameOver",
}

local Net = {} :: { [string]: RemoteEvent }

for _, name in NAMES do
	local remote = RemotesFolder:WaitForChild(name, 10)
	assert(remote and remote:IsA("RemoteEvent"), "Falta el RemoteEvent " .. name)
	Net[name] = remote :: RemoteEvent
end

return Net
