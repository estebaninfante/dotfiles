---
name: verification
description: Verificacion determinista de si un cambio realmente funciono, por dominio (quickshell/Omarchy, hyprland, systemd, code, syntax). Usar cuando pidan verificar un cambio, comprobar que funciono, "did it work", "salió bien", correr checks/tests/lint/typecheck, o validar que un edit aplico. Tambien para extender el sistema con un verificador nuevo.
---

# Verificacion

Sistema de verificacion por dominio. Cada dominio tiene un **verifier** (script
determinista) que responde "funciona / no funciona" sin gastar tokens razonando.

## Contrato de salida

Exit code manda:

- `0` PASS, `1` FAIL, `2` ERROR (no se pudo verificar).

Un verifier imprime lineas TSV `STATUS<TAB>nombre<TAB>detalle` donde STATUS es
`OK`, `FAIL` o `SKIP`. El dispatcher las formatea. Nunca imprime prosa libre.

## Uso

```bash
verify list                       # dominios registrados
verify detect <archivo...>        # a que dominio(s) pertenece
verify run <dominio> [archivo...] # corre un dominio a mano
verify auto <archivo...>          # detecta + corre lo que aplique
verify selftest                   # vigila que los verifiers no se pudran
verify scaffold <dominio> [glob]  # crea un verifier nuevo + lo registra
```

Flags: `--json`, `--quiet` (solo imprime FAIL), `--activate` (permite efectos:
`omarchy restart shell`, `hyprctl reload`, `daemon-reload`).

Atajo global: `~/.local/bin/verify` (symlink al dispatcher).

## Flujo esperado

1. Tras editar, corre `verify auto <archivo>`. Un comando Bash, una linea.
2. FAIL => arreglar y repetir. PASS => listo, sin necesidad de leer mas.
3. Cuando un cambio solo se confirma visualmente (barra/QML), usa
   `verify run quickshell --activate <archivo>` y luego un screenshot (`grim`) solo
   si el verifier no alcanza. Ver skill `omarchy`.

## Auto-mantenimiento (clave)

El sistema crece solo; no se edita el motor:

- **Dominio nuevo** (archivo que no encaja en ninguno): `verify scaffold <dominio> "<glob>"`.
  Esto crea `verifiers/<dominio>.sh` desde `TEMPLATE.sh` y lo registra en
  `scripts/registry.json`. Luego implementa los checks (sin comentarios, tipos/validacion
  fuertes) y corre `verify selftest`.
- **Prioridad**: si un archivo cae en varios dominios, gana el de mayor `priority`
  (evita doble check, p.ej. `shell.json` = quickshell, no syntax).
- **Salud**: corre `verify selftest` tras tocar verifiers o el registry.
- **Costo**: el razonamiento vive en los scripts, no en el modelo. Una verificacion
  rutinaria cuesta ~1 llamada Bash.

## Estructura

- `scripts/verify.py` — dispatcher tipado (deteccion por globs, timeout, formato).
- `scripts/registry.json` — `dominio -> {script, globs, priority, desc}`.
- `verifiers/*.sh` — un script por dominio; `TEMPLATE.sh` es la base.
- Hook automatico: `~/.config/opencode/plugins/verify-hook.js` corre `verify auto`
  tras cada edit/write y agrega el resultado al output del tool (solo si falla).

## Reglas

- Determinista y rapido: sin red, sin efectos salvo con `--activate`.
- Nada de comentarios en el codigo: nombres y estructura explican.
- Verifiers deben pasar `bash -n` (o su equivalente) y `verify selftest`.
- El hook NO duplica QML: `.qml` bajo `~/.config/omarchy|quickshell` ya lo cubre el
  plugin `qml-ux-lint`; el resto lo cubre `verify-hook`.
