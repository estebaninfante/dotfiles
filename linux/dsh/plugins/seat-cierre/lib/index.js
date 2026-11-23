/**
 * dsh-local-seat-cierre — el harness cierra el agent-seat cuando el turno termina.
 *
 * Un agente abría ventanas con `agent-seat run` y se iba sin `agent-seat stop`:
 * el broker, los sandboxes y las apps quedaban ocupando RAM hasta que alguien
 * los cerraba a mano. Acá el harness lo hace solo: escucha `turn/end` y llama
 *
 *     agent-seat cerrar-sesion <sesión>
 *
 * que cierra únicamente las ventanas que abrió esa sesión y baja el asiento
 * entero si no queda ninguna. Las ventanas de otras sesiones no se tocan.
 *
 * El cierre sale en segundo plano: no retrasa la respuesta del turno. Para los
 * agentes que no pasan por este harness (claude, codex, opencode), el vigía
 * `agent-seat-watch` sigue como red de inactividad.
 */
import { execFile } from 'node:child_process'
import { homedir } from 'node:os'
import { join } from 'node:path'

export const name = 'local-seat-cierre'

// Se puede pisar en las pruebas (AGENT_SEAT_BIN) sin tocar el asiento real.
const BIN = process.env.AGENT_SEAT_BIN ?? join(homedir(), '.local', 'bin', 'agent-seat')
const ESPERA_MS = 25000

/**
 * Un subagente no cierra el asiento de la sesión que lo lanzó: comparten el
 * host y, si comparten la sesión en el entorno, sus ventanas son las del padre.
 */
export function esPrimerNivel(session) {
    const header = session?.header
    if (!header) return true
    if (header.origin === 'subagent') return false
    return (header.delegationDepth ?? 0) === 0
}

/** Id de la sesión a cerrar, o null si este evento no corresponde. */
export function cierreDeTurno(session, event) {
    if (event?.type !== 'turn/end') return null
    const id = typeof session?.id === 'string' ? session.id.trim() : ''
    if (id === '') return null
    if (!esPrimerNivel(session)) return null
    return id
}

export function apply(ctx) {
    ctx.on('session/event', (session, event) => {
        const id = cierreDeTurno(session, event)
        if (!id) return
        execFile(BIN, ['cerrar-sesion', id], { timeout: ESPERA_MS }, (error) => {
            if (!error) return
            // Salir 1 es error de uso, no un cierre que falló.
            if (error.code === 1) return
            ctx.logger?.warn?.(`seat-cierre: no pude cerrar el asiento de ${id}: ${error.message}`)
        })
    })
    ctx.logger?.info?.('seat-cierre: el asiento se cierra al terminar el turno')
}
