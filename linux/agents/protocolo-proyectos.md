# Protocolo de proyectos — plantillas y comandos

Las reglas (obligatorias, en `~/.dsh/AGENTS.md`) están resumidas en
`linux/agents/reglas-harness.md`. Este archivo tiene lo operativo: las plantillas
que se usan al empezar y al cerrar, y los comandos del registro.

## Definition of Done (plantilla)

```md
## DoD — <nombre del proyecto>

Objetivo medible: <una frase que se verifica sin opinar>

Alcance de esta versión:
- SÍ: <lo que se construye>
- NO: <lo que queda afuera, explícito>

Criterios de éxito (cómo se comprueba):
- <comando / URL / captura / número que pasa>

Terminado = <el criterio de verificación pasa y el usuario lo ve funcionando>

Fuera de alcance / próxima versión:
- <ideas que aparecieron y NO entran>
```

Reglas de la DoD:

- El objetivo se escribe con un número o una acción verificable, no con un adjetivo.
- La lista **NO** no es opcional: es lo que evita que el alcance crezca.
- Si aparece algo que no estaba en la DoD, va a "fuera de alcance" o a un ticket nuevo.
- La DoD no se aprueba por silencio: el usuario dice que sí.

## Hitos

Cada hito tiene que poder cerrarse en **una sesión** y dejar algo que el usuario pueda
tocar. Si un hito no se puede cerrar en una sesión, está mal cortado: partirlo.

Orden: hito de "se ve funcionando" primero (camino feliz), después los bordes. Nunca
empezar por la infraestructura que todavía no se necesita.

## Cierre de sesión (plantilla)

```md
Cerrado: <qué quedó funcionando, con la evidencia>
Pendiente: <lo que quedó a medias y cómo se retoma>
Siguiente paso: <uno solo, concreto>
```

## Registro: tickets (`agent-os-cli`)

```bash
agent-os-cli ticket add <slug> --project <P> --title "<6+ palabras>" --area <A>
agent-os-cli ticket set <id> --status in-progress|blocked|done
agent-os-cli ticket done <id>            # cierra con evidencia
agent-os-cli ticket list --porcelain     # JSON: id, project, status
agent-os-cli board                       # tablero
```

Ratio empezados vs terminados (cuando el usuario pregunte cómo viene):

```bash
agent-os-cli ticket list --porcelain | python3 -c 'import json,sys,collections;
d=json.load(sys.stdin); c=collections.Counter(t["status"] for t in d);
print(dict(c), "total", len(d))'
```

Un proyecto con tickets `pending` y ninguno `done` hace semanas se **archiva**
(`~/Proyectos/_archivo/`), no se retoma: retomarlo compite con el que está abierto.

## Ideas sueltas a mitad de proyecto (`machine`)

Se anotan y se sigue, no se persiguen. Viven en `machine`, nunca en el vault
`~/alicia` (congelado: notas personales, ninguna IA escribe ahí):

```bash
machine idea --title "Dos o tres palabras" "<lo que dije>"
machine idea             # lista las que hay, para no duplicar
machine task add <proyecto> "<tarea>"
```
