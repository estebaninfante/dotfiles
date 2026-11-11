---
name: delegate-a-claude
description: Delegar a Claude Code (CLI `claude`) un problema en el que DeepSeek Harness se quedó estancado. Usar cuando tras 2-3 intentos serios el mismo síntoma sigue igual, cuando cada arreglo rompe otra cosa, cuando hace falta un cambio que toca un plugin/binario y no se converge, o cuando el usuario diga "delegá esto a Claude", "que lo resuelva Claude", "probá con otro modelo". Incluye el brief que funciona, cómo lanzarlo y cómo leer el resultado.
---

# Delegar a Claude Code

Claude Code está instalado en `~/.local/bin/claude` y corre headless con
`claude -p --permission-mode bypassPermissions < brief.md`. Resolvió en un solo intento
un caso donde este harness llevaba horas de ida y vuelta: la diferencia no fue el
modelo, fue el **brief** — con las variantes ya probadas (para que no las repita) y
las causas descartadas.

## Cuándo delegar (y cuándo no)

Delegá cuando:

- El mismo síntoma sigue después de 2 o 3 intentos serios (no de 10 variaciones de
  la misma idea).
- Cada arreglo rompe otra cosa (el clásico "arreglo A, rompo B").
- El arreglo necesita tocar un binario/plugin y cada iteración cuesta un reinicio de
  la sesión del usuario o un riesgo de dejarla rota.
- Te encontrás repitiendo prueba-y-error a ciegas en vez de instrumentar y medir.

No delegues: tareas de un solo paso, cosas que ya sabés hacer, ni para "probar suerte"
antes de haber leído el código relevante.

## Procedimiento

1. **Escribí el brief en un archivo** (no en un heredoc suelto). Usá la plantilla de
   abajo. Es lo más importante de todo: sin las variantes ya probadas y el entorno,
   Claude repite el mismo camino que vos.
2. **Lanzalo** con el helper:

   ```bash
   delegar-claude start /ruta/al/brief.md --name tema-corto
   ```

   Imprime el directorio de la sesión (brief, log, pid). El proceso queda en
   `~/.local/state/delegar-claude/<nombre>/`.
3. **Avisale al usuario** que Claude está corriendo y sobre qué, antes de esperar.
4. **Monitoreá sin bloquear**: `delegar-claude status` (¿sigue vivo?) y, si querés ver
   qué está haciendo en el momento, mirá la transcripción más nueva de
   `~/.claude/projects/*/*.jsonl` (líneas `tool_use` / `tool_result`). No hagas
   busy-poll: el harness te avisa cuando el job termina.
5. **Leé el resultado** con `delegar-claude read` y **verificá vos** lo que Claude dice
   que arregló (medidas, capturas): él también se equivoca.
6. **Pasale al usuario** el resumen de Claude + tu verificación + lo que queda de su
   lado (sudo, reinicios, pruebas manuales).

## Plantilla del brief

```markdown
# Encargo: <el problema en una línea>

Sos Claude Code trabajando en la máquina del usuario (<SO>, <entorno>).
<Contexto de quién es y desde dónde escribe, si importa.>

## Reglas del entorno (leelas antes de tocar nada)

- <fuente de verdad del repo, symlinks, cómo publicar>
- <cómo entrar a la otra máquina / sudo disponible o no>
- <qué NO se puede recargar en caliente y qué requiere reinicio>
- <cómo verificar (capturas, JSON de estado, mediciones)>

## Los problemas (en palabras del usuario)

### 1. <síntoma exacto>
<Lo que hace, lo que espera, lo que pasa. Pasos para reproducir.>

Piezas relevantes: <archivos con rutas, funciones, scripts>.
Causa probable (a confirmar): <tu hipótesis y la evidencia>.

### 2. ...

## Ya probado (NO repetir)

1. <variante> → <resultado>
2. ...

## Lo que ya está andando (no lo rompas)

- ...

## Qué espero de vos

1. ...
2. Al terminar: resumen corto en <idioma>: qué cambiaste, qué verificaste y con qué
   evidencia, qué reinicios hiciste, y qué queda pendiente para el usuario.
```

Reglas de oro del brief:

- **Incluí lo que falló**, con el resultado concreto. Es lo que más ahorra tiempo.
- **Nombres y rutas reales** de archivos, funciones y comandos de verificación.
- **Restricciones duras** primero (sudo, reinicios, sesión del usuario, no romper X).
- Si el usuario está presente y usando la máquina, decilo: condiciona cómo probar.

## Detalles que importan

- `--permission-mode bypassPermissions` es necesario para que pueda ejecutar comandos;
  se lo estás dando al CLI, así que el brief tiene que ser preciso y con límites claros.
- El output de `claude -p` llega **al final**; para progreso, la transcripción en
  `~/.claude/projects/*/*.jsonl`.
- Si el helper no está disponible: `claude -p --permission-mode bypassPermissions < brief.md`
  como job en background del harness (no con `nohup ... &` suelto: el proceso muere con
  el shell).
- Si Claude también se traba, no relances lo mismo: cambiá el insumo (mejor
  instrumentación, un caso más chico, o preguntarle al usuario).
