# Latido: pensamiento en vivo y tareas con id

`linux/pi/agent/extensions/conversar.ts` muestra, mientras el modelo trabaja, un
widget con:

1. **Una sola fila de encabezado:** `agente × título de la tarea · T-XXXXXX`.
   El nombre y la tarea se ven juntos, de un vistazo, en el widget y en el
   título de la ventana (lo que muestra herdr/la barra).
2. **El reloj:** cuánto lleva pensando el turno y cuánto acumula la sesión.
3. **El pensamiento en trozos legibles:** una oración fija que se ilumina
   palabra por palabra al ritmo de lectura. Las siguientes oraciones quedan
   tenues debajo. No hay ventana que se desplaza.

El bloque nativo de pensamiento de pi se oculta con `hideThinkingBlock: true`
en `linux/pi/agent/settings.json`. Así el widget es el **único** visor en vivo y
no se lee lo mismo dos veces. `Ctrl+T` muestra el bloque original cuando haga
falta.

## Ritmo

- Por defecto: 150 ms por palabra (antes 180).
- Si el modelo escribe más rápido de lo que se puede leer, la cola crece y el
  ritmo acelera hasta 100 ms por palabra.
- Si aun así sobra cola, se descartan las oraciones más viejas y se marca con
  `…` para no quedar atrasado.
- El código (bloques ``` y code inline largo) se saca. Los fragmentos que
  quedan partidos (`"while ."`, `"const x = 1"`) se descartan en vez de
  mostrarse rotos.

Se ajusta en `linux/config/pi/latido.json` o con variables de entorno
(la variable gana):

| Archivo / variable | Default | Qué hace |
|---|---|---|
| `lines` / `PI_LATIDO_LINES` | 3 | oraciones visibles |
| `paragraphWords` / `PI_LATIDO_PARAGRAPH_WORDS` | 28 | palabras tope por oración |
| `wordMs` / `PI_LATIDO_WORD_MS` | 150 | ritmo cómodo, ms por palabra |
| `fastWordMs` / `PI_LATIDO_FAST_WORD_MS` | 100 | ritmo acelerado con cola |
| `catchup` / `PI_LATIDO_CATCHUP` | 40 | palabras de cola que aceleran |
| `backlog` / `PI_LATIDO_BACKLOG` | 90 | tope de cola antes de descartar |
| `titleChars` / `PI_LATIDO_TITLE_CHARS` | 52 | largo del título en el encabezado |
| `PI_LATIDO=0` | — | apaga el widget |

## Tareas

`linux/pi/agent/extensions/rig.ts` captura cada pedido como una tarea, sin que
haya que crearla a mano:

- **Id corto:** `T-XXXXXX`.
- **Título:** se deriva del pedido (saca adjuntos, cortesías y artículo
  inicial). El modelo puede mejorarlo con la tool `tarea`.
- **Trace:** pedido, cada herramienta con su resultado y un resumen de lo que
  pensó el modelo. La conversación completa queda enlazada en `sesión:`.
- **Continuaciones:** un mensaje corto (`Continuemos`, `dale`, `seguí`, `y ...`)
  sigue en la misma tarea; un pedido nuevo abre otro id.

Vive en `~/.local/share/pi/tareas.json` (o `PI_RIG_DIR`). Se guarda con
write+rename y se recorta a las últimas 200 tareas / 200 pasos por tarea.

Uso:

```
/tareas                 lista las últimas 12 con su id
/tarea T-XXXXXX         muestra el trace en el panel
/tarea                  cierra el panel del trace
```

El agente también puede:

- `tarea` — `ver`, `renombrar`, `nota`, `cerrar` la tarea actual.
- `tareas` — listar o ver el trace de cualquier tarea.

## Verificación

```
scripts/verify/latido.sh
```

Chequea los helpers puros, que el bloque nativo esté oculto, el encabezado
agente × tarea, el ritmo adaptativo y las piezas de tareas/trace.
