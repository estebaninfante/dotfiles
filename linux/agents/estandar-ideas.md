# Estándar de ideas y pendientes (todas las IAs)

El usuario suelta ideas y pendientes mientras conversa. Ninguna IA los deja en el
chat: se capturan en el vault `~/alicia` (grafo Markdown, CLI `alicia`), que es la
**única fuente de verdad**. La página de inicio del navegador lee de ahí.

## Capturar antes de responder

Cuando aparezca una idea, duda, pensamiento o pendiente que **no** sea una orden
concreta sobre la máquina:

1. Guardalo:

   ```sh
   alicia nuevo --tipo pensamiento --titulo "<título corto>" \
     --cuerpo "<lo que dije, tal cual>" --tags <tema1,tema2>
   ```

   Crea `Inbox/<fecha>-<slug>.md` con `estado: pendiente` e imprime la ruta.
   Confirmá en una línea: `Anotado: <título>`.
2. Si el tema ya existe (`alicia dup`, `alicia arbol`), **no dupliques**: agregá
   al nodo existente.
3. No preguntes "¿lo guardo?": se guarda y se sigue.

## Distinguir

- **Idea / pendiente suelto** → vault, como arriba.
- **Trabajo concreto sobre un repo o la máquina** → ticket, no idea:
  `agent-os-cli ticket add <slug> --project <P> --title "<6+ palabras>" --area <A>`
- **Algo que una IA debe hacer** → nodo `tipo: tarea` con criterios de aceptación:
  `alicia nuevo --tipo tarea --titulo "<título>" --cuerpo "<criterios>"`

## Consultar

- `alicia next` — lo accionable ahora (hojas activas sin subproblemas abiertos).
- `alicia arbol` — el grafo completo; `alicia ver <id>` — un nodo.
- `agent-os-cli board` — tablero de tickets.

## Cerrar

- Hecho: `alicia estado <id> resuelto`.
- Descartado: `alicia estado <id> descartado` (no se borra: queda el rastro).
- Si la sesión tocó ideas: `alicia check`.
