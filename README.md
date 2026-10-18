# SkyBonk — Fase 1: núcleo jugable

Roguelike *survivor-like* 3D para Roblox. Islas flotantes, ataques automáticos, hordas,
experiencia, niveles y selección de mejoras. Todo el código, los modelos (Parts), la
interfaz y los efectos son originales; los sonidos son los incluidos con el propio
cliente de Roblox (`rbxasset://sounds/...`).

## Abrir y jugar

**Opción A — archivo listo:** abre `build/SkyBonk.rbxlx` en Roblox Studio y pulsa **Play** (F5).

**Opción B — desde el código (recomendado para desarrollar):**

```bash
# Herramientas (una vez): https://rojo.space  (o: cargo install rojo selene stylua lune)
rojo build default.project.json -o build/SkyBonk.rbxlx   # regenerar el place
rojo serve                                              # o sincronizar en vivo con el plugin de Rojo
```

Al pulsar Play, el servidor construye la isla (si `Workspace/Map` no existe), crea la
plantilla del enemigo en `ServerStorage/EnemyModels`, y la partida empieza en cuanto la
interfaz del cliente está lista. En Studio, además, se ejecutan las pruebas unitarias y
el resultado aparece en Output (`[SkyBonk Tests] N correctas, 0 fallidas`).

## Controles

| Acción | PC | Móvil |
|---|---|---|
| Moverse / saltar | WASD / Espacio | Joystick táctil / botón de salto |
| Cámara | Botón derecho + ratón, rueda para zoom | Arrastrar / pellizcar |
| Atacar | Automático | Automático |
| Elegir mejora | Clic o teclas **1 / 2 / 3** | Tocar la carta |
| Volver a jugar | Botón o **R** / **Enter** | Botón |
| Mostrar/ocultar estadísticas | **Tab** / **C** | Tocar "ESTADÍSTICAS" |
| Efectos completos / reducidos | **G** | Tocar "FX" |

Mando: X/Y/B eligen las cartas 1/2/3 y A reinicia.

## Dirección artística (Fase 2.5)

Fantasía anime de islas flotantes. Guía completa en [docs/ART_DIRECTION.md](docs/ART_DIRECTION.md);
todos los valores en `src/shared/Config/VisualConfig.luau`. Sin plugins: todo son
instancias nativas (ParticleEmitter, Beam, Trail, Highlight) y código, con texturas
internas del cliente (`rbxasset://textures/particles/...`).

- **Personaje**: paquete de animaciones *Ninja* de Roblox (aplicado al script `Animate`),
  inclinación procedural en curvas y frenadas, estelas de viento, polvo al aterrizar,
  retroceso al recibir daño, muerte con desaturación y reaparición con columna de luz.
- **Auras** (`Util/AuraSystem`): Eléctrica, Ígnea, Arcana, Celestial, Vacío y Jefe; el
  aura del jugador sigue su build real (rayo, crítico, XP, defensa, vida crítica, nivel).
- **Espada del Vendaval**: hoja de un filo con guarda alada; corte en media luna en cada
  tajo, destellos de impacto y crítico propio (estrella dorada + golpe de FOV).
- **Enemigos**: ojos con brillo, llama del vacío en los esqueletos; el Rey Slime tiene aura
  de jefe, entrada con franjas de cine y rótulo, y barra propia en el HUD.
- **Zonas**: Bosque Sakura (farolillos, pétalos, cascada), Jardín Corrompido (grietas y
  cristales del vacío), Santuario Celestial (torii, luciérnagas), Ruinas (runas, cascada).
  Ciclo local de atardecer y tinte de color por zona. Los árboles y rocas que tapan la
  cámara se vuelven semitransparentes.
- **Efectos reducidos**: tecla **G** o botón «FX» (menos partículas, sin efectos
  ambientales ni auras de enemigos).

## Arquitectura

```
default.project.json            Árbol de Rojo
src/shared/      -> ReplicatedStorage.Shared
  Config/GameConfig             Mapa, jugador, curva de XP, aparición, dificultad, efectos, sonidos
  Config/WeaponConfig           Espada del Vendaval (daño 12, enfriamiento 1,4 s, alcance 28)
  Config/EnemyConfig            Slime del Vacío (vida 35, daño 5, velocidad 9, 1 XP)
  Config/UpgradeConfig          10 mejoras + comodín, rarezas y pesos
  Types                         Tipos compartidos (--!strict)
  Progression                   Función única de XP por nivel
  Net + Remotes/                RemoteEvents con nombre y propósito únicos
  Signal                        Señal ligera para desacoplar controladores
src/server/      -> ServerScriptService
  Bootstrap.server              Mundo, grupos de colisión, Init/Start de servicios, pruebas en Studio
  ServerTypes                   Tipos de Run / Enemy / Gem
  Services/MatchService         Partidas, bucle Heartbeat único, vida, caídas, derrota, reinicio, HUD
  Services/CombatService        Programación centralizada de ataques y patrones de armas
  Services/EnemyService         IA centralizada, daño, muerte, congelación y limpieza
  Services/SpawnService         Aparición válida alrededor del jugador y dificultad creciente
  Services/ExperienceService    Gemas, recogida por proximidad centralizada, caducidad y límite
  Services/LevelService         Punto único para conceder experiencia
  Services/UpgradeService       Ofertas, validación de elecciones y aplicación de mejoras
  Logic/                        Lógica pura y probada: RunState, LevelLogic, UpgradeLogic,
                                StatSheet, Targeting, RateLimiter, Validation
  World/MapBuilder              Isla low-poly determinista + iluminación/atmósfera/nubes
  World/ModelFactory            Modelo low-poly del Slime del Vacío
  Tests/                        Pruebas (se ejecutan en Studio y con Lune)
src/client/      -> StarterPlayer.StarterPlayerScripts
  ClientBootstrap.client        Init/Start de controladores y aviso ClientReady
  Controllers/InputController   Teclas 1/2/3, R/Enter, Tab/C, mando
  Controllers/CameraController  Tercera persona, zoom inicial, sacudida suave
  Controllers/HUDController     HUD (MainHUD)
  Controllers/UpgradeController Pantalla de mejoras (UpgradeSelection)
  Controllers/GameOverController Pantalla de derrota (GameOverScreen)
  Controllers/CombatEffectsController Hojas, números de daño, muertes, gemas, nivel, animación de slimes
  UI/Theme, Util/Sfx            Estilo de interfaz y sonido
src/character/   -> StarterCharacterScripts
  Health.server                 Desactiva la regeneración de vida por defecto
tests/                          Ejecución fuera de Roblox (Lune) + motor simulado
```

Desviaciones respecto a la estructura propuesta, y por qué:

- **`RunService` → `MatchService`**: `RunService` es un servicio del motor de Roblox
  (`game:GetService("RunService")`). Usar el mismo nombre para un módulo propio lleva a errores.
- **Interfaz creada por código** (ScreenGuis `MainHUD`, `UpgradeSelection` y `GameOverScreen`,
  creados en `PlayerGui` por sus controladores) en lugar de instancias en StarterGui. Así es
  texto revisable y versionable, y escala a móvil con un `UIScale` común.
- **`GameOverController`** separado del HUD, con una responsabilidad clara.
- **Sin `ServerStorage/WeaponModels`**: la Espada del Vendaval es un efecto visual en el cliente
  y no necesita modelo físico. Así se evita replicar proyectiles.

### Reglas que cumple el código

- El servidor es la autoridad sobre vida, daño, XP, niveles, enemigos, mejoras y estado.
- Solo hay 3 remotes cliente → servidor: `ClientReady()`, `ChooseUpgrade(token, id)` y
  `RequestRestart()`. Todos tienen comprobación de tipos y límite de frecuencia. La elección se
  valida contra la oferta activa (token + id) y el estado `ChoosingUpgrade`. No existe ningún
  remote con el que el cliente pueda indicar daño o experiencia.
- Hay un único `Heartbeat` en el servidor. No hay scripts ni bucles por arma, enemigo o gema.
  La IA va a 10 Hz y la recogida de gemas a 10 Hz.
- **Pausa real** al elegir mejora: el reloj de la partida no avanza; enemigos y jugador quedan
  anclados; no hay aparición, combate ni daño. Todos los temporizadores (enfriamientos, oleadas,
  caducidad de gemas, dificultad) usan el reloj de partida.
- Estados `Playing` → `ChoosingUpgrade` → `Playing` / `GameOver`, en `Logic/RunState`.
- Al morir: los enemigos se congelan; a los 2 s se limpian enemigos y gemas; el reinicio crea una
  partida nueva y un personaje nuevo. Al salir el jugador también se limpia todo.

### Balance (todo en `src/shared/Config`)

Se mantienen los valores pedidos: arma 12 de daño, 1,4 s de enfriamiento y 28 de alcance;
slime con 35 de vida, 5 de daño, velocidad 9 y 1 de XP; máximo 35 enemigos; intervalo inicial
de 1,5 s; curva de XP 5/8/12/17/23…

Los multiplicadores de dificultad son propios: +8 % de vida enemiga por minuto, +10 % de daño
y +4 % de velocidad.

Ritmo medido en la simulación con un bot que esquiva, recoge gemas y prioriza mejoras de daño:
**Nv2 a los 31 s, Nv3 a los 83 s, Nv4 a los 141 s, Nv5 a los 231 s**. El ritmo lo limita la
cadencia de muertes (3 golpes por slime cada 1,4 s). Si se quiere un arranque más rápido,
típico del género, basta con un solo cambio: `WeaponConfig.GaleSword.Damage = 18`, para matar
en 2 golpes.

## Pruebas

```bash
lune run tests/run.luau          # 20 pruebas unitarias (también se ejecutan en Studio al pulsar Play)
lune run tests/simulation.luau   # 62 comprobaciones: partidas completas con los servicios reales
selene src tests                 # lint
stylua --check src tests         # formato
```

`tests/simulation.luau` carga los **servicios reales** del servidor sobre un motor emulado
(`tests/lib/FakeEngine.luau`: instancias, Players, Heartbeat, raycast, remotes y reloj).
Un bot juega una partida completa, elige mejoras, cae al vacío, muere y reinicia. Durante la
partida también envía peticiones manipuladas. El emulador no tiene física real, red ni interfaz;
eso se cubre con la lista manual de abajo.

### Lista manual en Roblox Studio (pruebas A–H)

| # | Pasos | Resultado esperado |
|---|---|---|
| A | Play. Mirar Output. | `[SkyBonk] Servidor listo` y `[SkyBonk Tests] 20 correctas, 0 fallidas`; personaje sobre la plataforma rúnica; HUD visible (nivel 1, XP 0/5, 100/100). |
| B | Esperar 3 s y quedarse cerca del centro. | Aparecen slimes a 30–50 studs que persiguen al jugador; salen hojas cian hacia el más cercano; números de daño; mueren con 3 golpes y explotan en partículas. |
| C | Caminar sobre las gemas cian. | La gema vuela al jugador, suena, la barra de XP sube; nunca suma dos veces. |
| D | Recoger 5 gemas. Después, en la barra de comandos (vista **Servidor**): `_G.SkyBonkDebug.GrantXp(60)` | "¡NIVEL 2!" y 3 cartas distintas. Con 60 XP: varias ofertas seguidas, una cada vez; la XP sobrante se conserva. |
| E | Con las cartas abiertas: comprobar que slimes y jugador no se mueven y que el tiempo no avanza. Elegir *Filo Afilado*. | La partida continúa; "Daño" en el panel de estadísticas pasa de 12.0 a 13.8. |
| F | `_G.SkyBonkDebug.Kill()` (o dejarse rodear). | Pantalla "HAS CAÍDO" con tiempo, enemigos y nivel. A los 2 s desaparecen slimes y gemas. "Volver a jugar" reinicia en el nivel 1 con 100/100. |
| G | Saltar fuera de la isla. | Reaparece en la plataforma con −25 % de vida e invulnerabilidad de 1,5 s. |
| H | Test → *Device Emulator* (p. ej. iPhone 14, horizontal). | Joystick y botón de salto; cartas tocables sin solaparse; panel de estadísticas plegado; textos legibles. |

## Limitaciones conocidas

- **No se ha ejecutado en Roblox Studio** en este entorno (Linux sin Studio). Esto implica:
  - La física de los slimes, el escalado de la interfaz en dispositivos reales y los sonidos no se han visto funcionar.
  - Las pruebas automáticas cubren la lógica y el flujo del servidor sobre un motor emulado.
  - Falta pasar la lista manual de arriba.
- Los ids `rbxasset://sounds/...` son los del cliente clásico de Roblox. Si alguno no existe en
  tu versión, solo se oye silencio y no hay error de juego. Se cambian en `GameConfig.Sounds`.
- **Impulso Arcano** está definida pero desactivada (`Enabled = false`), porque la Fase 1 no
  tiene habilidades activas. No se muestra ninguna mejora que no haga nada. Para completar ofertas
  cuando ya no quedan opciones válidas se usa el comodín *Bendición del Cielo* (cura el 30 %).
- Los slimes no colisionan con el jugador (su grupo de colisión lo impide) para evitar lanzamientos
  físicos. El daño por contacto se calcula por distancia.
- La comprobación de tipos estricta de Luau (`--!strict`) está en los módulos de lógica y tipos.
  No se ha podido ejecutar el analizador de tipos de Roblox aquí. Selene ha comprobado el código
  con una definición mínima de globales de Roblox (`roblox_min.yml`).
- En partidas largas, los slimes se acumulan hasta el máximo de 35 si el jugador no los
  elimina; la presión crece con el tiempo de forma deliberada.

## Fase 2 (pendiente)

1. Armas adicionales con patrones nuevos (órbita, área, cadena, proyectil perforante): una entrada en `WeaponConfig` + un manejador en `CombatService.Patterns`.
2. Tomos de estadísticas (mejoras con varias estadísticas y escalado por rareza).
3. Objetos pasivos e inventario (ranuras, niveles, iconos en el HUD).
4. Sinergias y evoluciones entre arma y objeto.
5. Cofres y santuarios en el mapa (recompensas que abren ofertas especiales).
6. Habilidades activas → activar *Impulso Arcano*.
7. Más criaturas (a distancia, cargadoras, élites) reutilizando `EnemyService`, y oleadas por tiempo.
8. Imán/radio de recogida como estadística mejorable; usar la Suerte en más sistemas.
9. Menú principal, ajustes (sensibilidad, sacudida de cámara) y luego DataStore/progresión (fuera del alcance actual).
