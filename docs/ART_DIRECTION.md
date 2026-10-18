# SKYBONK — Guía de dirección artística (Fase 2.5)

Identidad propia: **fantasía anime de islas flotantes**, low-poly limpio con luz
estilizada. No se copian personajes, modelos ni efectos de ningún juego concreto;
las referencias son el lenguaje visual general del anime de fantasía (auras,
cortes de energía, cielos de atardecer, santuarios, cristales).

Todos los valores viven en `src/shared/Config/VisualConfig.luau`.

## 1. Principios

1. **Silueta antes que partículas.** Cada arma, enemigo y zona se reconoce por su
   forma; las partículas solo acentúan.
2. **Secuencia de cuatro tiempos** en todo efecto de combate:
   *preparación → ejecución → impacto → desaparición*.
3. **Legibilidad en hordas.** Las zonas de peligro (anillos rojos) se dibujan
   siempre por encima de cualquier aura; los efectos del jugador son cian/blancos,
   los del enemigo violeta/rojo.
4. **Luz controlada.** Neón solo en núcleos y filos; nada de bloom que queme la
   imagen. Saturación moderada (+0,15), contraste ligero.
5. **Sin parpadeos fuertes.** Destellos ≤ 0,15 s, sacudidas ≤ 0,5 studs, cambios
   de FOV ≤ 6° y siempre reversibles.
6. **Modo de efectos reducido** disponible en todo momento (tecla **G** o botón FX):
   menos partículas, sin auras de enemigos y sin pétalos/luciérnagas.

## 2. Paleta

| Uso | Color | Notas |
|---|---|---|
| Energía del jugador | `#78EBFF` cian, blanco | Espada del Vendaval, hojas, XP |
| Peligro / enemigo | `#FF465A` rojo, `#8448D6` violeta | Anticipaciones, vacío |
| Recompensa | `#FFC45C` dorado | Gemas doradas, Cristales de Esencia, nivel |
| Rareza | Común `#B0C4D6`, Rara `#54AAFF`, Épica `#C46EFF` | Cartas de mejora |

## 3. Zonas

| Zona | Paleta | Firma visual |
|---|---|---|
| Bosque Sakura (SO) | rosa sakura, verde vivo | Árboles en flor, farolillos, pétalos, estanque |
| Ruinas del Alba (NE) | piedra blanca, runas cian | Templo de columnas, arco, cascada |
| Jardín Corrompido (SE) | roca violácea, cristales rojo/violeta | Agujas oscuras, grietas de vacío |
| Santuario Celestial (S) | blanco, oro, violeta suave | Torii, obelisco, luciérnagas doradas |
| Colina del Viento (NO) | verde, pinos | Piedras erguidas, viento |

## 4. Auras (perfiles modulares)

| Perfil | Capas | Estado del juego que lo activa |
|---|---|---|
| Eléctrica azul | chispas rápidas, anillo de suelo, arcos | Build de rayo (Filo de Tormenta) |
| Ígnea roja | llamas ascendentes, pulso de calor | Build de crítico |
| Arcana violeta | motas que orbitan, niebla oscura | Build de experiencia/suerte |
| Celestial dorada | motas brillantes, doble anillo | Subida de nivel (ráfaga) y build defensiva |
| Vacío | humo oscuro, borde luminoso | Vida crítica (< 30 %) |
| Jefe | anillo grande, llamas violeta/rojo, pulsos | Rey Slime |

Cada perfil define color, intensidad, radio, velocidad, partículas y distancia de
visibilidad; el sistema escala la cantidad según el modo de calidad.

## 5. Armas

Convención: **forma + color + efecto** propios.

| Familia | Silueta | Color | Corte / impacto |
|---|---|---|---|
| Viento (Espada del Vendaval) | hoja curva con guarda alada | cian | media luna + hojas espectrales |
| Elemental | hoja dentada | rojo/naranja | llamarada |
| Mágica | báculo/grimorio | violeta | runas y orbes |
| Pesada | hacha/maza ancha | acero/oro | onda de choque en el suelo |
| Proyectil | arco/dagas | verde/blanco | estela larga y fina |

El crítico usa siempre un destello dorado en estrella, un número mayor con «!» y
un pequeño golpe de FOV: se distingue sin depender del color.

## 6. Enemigos

Guía para familias nuevas: silueta única a 40 studs, un color elemental
dominante, ojos o núcleo luminoso como punto focal, anticipación visible
≥ 0,3 s y muerte que se lea (aplastarse, desmontarse, disolverse).

| Enemigo | Rasgo | Movimiento |
|---|---|---|
| Slime del Vacío | ojos grandes con brillo | saltos elásticos sincronizados con su avance |
| Hueso Errante | ojos de vacío, llama en el cráneo | paso zombi, tajo, se desmonta al morir |
| Rey Slime | corona dorada, aura de jefe, barra propia | entrada con franjas de cine, golpe en área |

## 7. Animación del personaje

Paquete **Ninja** de Roblox (propiedad de Roblox, reproducible en cualquier
experiencia): reposo, andar, correr, saltar y caer. Encima, movimiento procedural
local: inclinación en curvas y frenadas, líneas de velocidad, polvo al aterrizar,
retroceso al recibir daño, muerte (disolución) y reaparición (columna de luz).
