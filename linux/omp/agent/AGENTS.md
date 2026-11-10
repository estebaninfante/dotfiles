# Reglas del usuario (omp)

## Escritorio: no invadir el espacio de trabajo

El usuario trabaja en la misma sesión gráfica mientras corro. Reglas duras:

- **Nunca abrir ventanas, pestañas del navegador ni terminales visibles** en el escritorio del usuario, ni cambiar de workspace/foco para probar algo.
- **Nunca inyectar teclas** (`wtype`, `ydotool`, `dotool`) a la ventana activa del usuario.
- Para pruebas de GUI/entrada usar entornos **headless** (compositor headless en un `WAYLAND_DISPLAY` privado, PTY propio, `--headless` del navegador). Si no hay forma de hacerlo sin una ventana visible, **preguntar antes** y usar un workspace dedicado (`special:agent`), nunca el que el usuario está mirando.
- Procesos de prueba largos: servicios con nombre y limpieza explícita al terminar.

## Estándar de ideas y pendientes

@../../agents/estandar-ideas.md
