# dsh-local-sidebar-fit

El handle para redimensionar la sidebar del GUI mide 8 px: cuesta agarrarlo con
el mouse. Este plugin lo ensancha a 14 px, centrado en el borde, sin tocar el
layout ni los anchos.

## Lo que ya es del bundle (no de acá)

- Ancho mínimo de la sidebar: **264 px** (`clampWidth(sidebar, 264, 420)`).
- Auto-colapso a riel de 56 px cuando la ventana baja de **1024 px**; a partir de
  **768 px** pasa a drawer. Si "no se puede achicar más" o "no se abre", eso sale
  de esos umbrales y se cambia en el bundle del layout, no en el plugin.

## Cómo se aplica

Fila `local-sidebar-fit` en `~/.dsh/profiles/web/cordis.patch.yml`; paquete
symlinkeado en `~/.dsh/plugins/sidebar-fit`. Se ve recargando con `Ctrl+Shift+R`.

## Revertir

Quitar la fila del patch del perfil y recargar.
