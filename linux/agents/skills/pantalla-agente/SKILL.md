---
name: pantalla-agente
description: "Montar una pantalla headless invisible para probar apps o capturar sin interrumpir al usuario; se desmonta sola cuando queda ociosa."
---

# Pantalla de agentes

Probar UI no puede abrir ventanas en las pantallas del usuario. Montá una salida
virtual, probá ahí, capturá con grim y desmontala.

## Cuándo

Cualquier prueba que abra una ventana: webapps, capturas a 390 y 1440 px, apps
nativas, diálogos. Nunca en las pantallas del usuario, ni "un segundo".

## Flujo

```bash
pantalla-agente montar --tamano 1440x900      # salida AGENTE-1, invisible, con su espacio
pantalla-agente abrir --clase brave-tester -- brave --user-data-dir=/tmp/t https://…
pantalla-agente capturar /tmp/shot.png       # PNG de la pantalla completa
pantalla-agente cerrar                       # cierra las ventanas de prueba
pantalla-agente desmontar
```

## Reglas

- `montar` sin `--tamano` da 1440x900. Poné el del caso: `--tamano 390x844` para mobile, `--transform 3` para vertical.
- `abrir` manda la ventana nueva directo al espacio propio con una window rule: no se ve en las pantallas del usuario.
- `capturar` saca la salida entera. La barra de Omarchy ocupa 24 px arriba: recortá si el test es de contenido.
- Ventanas ya abiertas: `mover class:<clase>` (o `title:<regex>`, `address:0x…`). Nunca mover ventanas del usuario.
- Al terminar, `desmontar`. Si te olvidás, el watchdog la descuelga a los 10 min sin uso (`PANTALLA_AGENTE_TTL`).
- Si `estado` dice "no montada", montá de nuevo: la salida virtual no sobrevive un `hyprctl reload`.
- `desmontar` cierra las ventanas que quedaron en el espacio propio para que no salten a las pantallas del usuario; `--conservar` las deja (solo si el usuario quiere verlas).
