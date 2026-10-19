# Bodega unificada de los agentes (`rig db`)

Todo lo que hacen los agentes —a quién le hablan, qué tickets abren, qué eventos
dejan y en qué sesión— hoy vive en archivos sueltos. La bodega lo junta en **un
solo log append-only** y lo deja consultable, con el objetivo de que algún día se
pueda subir a la nube y leer desde varias aplicaciones.

## Qué guarda y de dónde lo saca

| tipo | fuente | forma |
|------|--------|-------|
| `mensaje` / `lectura` | `~/.local/state/rig/correo/buzon/*.jsonl` | mensajes entre agentes y acuses |
| `agente` | `~/.local/state/rig/correo/agentes/*.json` | presencia viva (identidad, cwd, tmux) |
| `evento` | `~/.local/state/rig/events.jsonl` | feed append-only de rig |
| `ticket` / `paso` | `~/.config/opencode/tickets.json` y `~/.local/share/pi/tareas.json` | tableros rig y pi |
| `sesion` | `~/.pi/agent/sessions/**/*.jsonl` | **solo metadata** (id, cwd, ruta, bytes) |

Los archivos originales **siguen siendo la fuente de escritura**: rig no cambia
cómo escribe. La bodega solo lee y consolida.

## Cómo funciona

- `~/.local/share/rig/db/unificado.ndjson` — el log canónico, una línea por
  hecho, con id estable y determinista. Es **la unidad de réplica**: idempotente,
  append-only, sin cursores que se rompan cuando un archivo muta (el buzón se
  reescribe in-place, los tickets se reescriben enteros).
- `~/.local/share/rig/db/rig.db` — SQLite reconstruible para consultar, con FTS5.
  Si se corrompe, se borra y se reconstruye del NDJSON.
- `~/.local/share/rig/db/cache.json` — hash/mtime de sesiones para no releer 158 MB.
- `sync.lock` — serializa syncs concurrentes (varios agentes a la vez).

El contenido crudo de las sesiones (158 MB) **no** se duplica: se indexa la
metadata y se referencia el archivo. Igual con `~/.local/share/opencode/opencode.db`
(3,6 GB): queda afuera de la bodega, se consulta donde está.

## Uso

```bash
rig db sync                    # guardar lo nuevo
rig db estado                  # qué hay, por tabla y por fuente
rig db buscar colisión         # búsqueda full-text (mensajes, eventos, tickets)
rig db mensajes --entre pi-106505:condor
rig db mensajes --sin-leer
rig db eventos --tipo correo
rig db tickets --estado in-progress
rig db sesiones
rig db sql "SELECT ..."
rig db exportar --desde 2026-10-19T00:00:00Z
rig db ruta
```

Se sincroniza solo al mandar un mensaje o tocar un ticket (con throttle de 45 s),
y con un timer opcional:

```bash
rig db timer instalar   # systemd --user, cada 2 minutos
rig db timer quitar
```

## Camino a la nube (todavía no hecho)

La decisión fue **local-first y sin atar el diseño a un proveedor**: el NDJSON ya
es el formato de réplica, así que no hace falta reescribir nada para subirlo.

1. **Copiar el log** con `rclone` (o cualquier object storage) en un job simple:
   `rig db exportar --desde <última marca> >> bucket/rig/$(date -u +%F).ndjson`.
2. **Consultar desde otro lado** leyendo ese NDJSON con DuckDB, sin servidor.
3. **Si hacen falta varias apps escribiendo o lectura concurrente**, importar el
   NDJSON a Postgres/Supabase (una tabla `registro` + las vistas que ya existen en
   `rig.db`). SQLite no sirve multi-escritor en la nube; el log sí.

Descartado por ahora (a propósito): API HTTP propia, daemon y esquema cloud. No
hay consumidor todavía; agregarlos después no cambia la ingesta.
