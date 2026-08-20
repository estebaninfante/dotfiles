#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/debug/log/Logger.hpp>
#include <hyprland/src/animation/WorkspaceAnimationController.hpp>
#include <hyprland/src/desktop/Workspace.hpp>
#include <hyprland/src/output/Monitor.hpp>

#include <hyprland/src/plugins/HookSystem.hpp>

#include <format>
#include <cstdint>
#include <fstream>
#include <iostream>
#include <map>
#include <optional>
#include <string>

// El Log::logger del DSO es instancia separada de la de Hyprland y escribe a
// stderr (no capturado). Duplicamos a /tmp/hyprradial.log para el spike.
#define LOG(fmt, ...)                                                                                                  \
    do {                                                                                                               \
        try {                                                                                                          \
            const std::string _msg = std::format("[hyprradial] " fmt, __VA_ARGS__);                                   \
            Log::logger->log(Log::INFO, "{}", _msg);                                                                   \
            std::ofstream _f("/tmp/hyprradial.log", std::ios::app);                                                    \
            if (_f)                                                                                                    \
                _f << _msg << std::endl;                                                                               \
        } catch (...) {                                                                                                \
        }                                                                                                              \
    } while (0)

using namespace HyprlandAPI;

typedef void (*startAnimation_t)(PHLWORKSPACE ws, Animation::Workspace::eAnimationType type, bool left, bool instant,
                                 std::optional<std::string> style);

static HANDLE      g_handle = nullptr;
static CFunctionHook* g_startAnimationHook = nullptr;
static startAnimation_t g_origStartAnimation = nullptr;

// Grid Scope B (8 ejes), ws1..ws9 en rejilla 3x3, ws0 fuera:
//   (0,0)ws7 (1,0)ws8 (2,0)ws9   <- arriba
//   (0,1)ws4 (1,1)ws5 (2,1)ws6   <- centro
//   (0,2)ws1 (1,2)ws2 (2,2)ws3   <- abajo
static const std::map<int64_t, std::pair<int, int>> GRID = {
    {1, {0, 2}}, {2, {1, 2}}, {3, {2, 2}},
    {4, {0, 1}}, {5, {1, 1}}, {6, {2, 1}},
    {7, {0, 0}}, {8, {1, 0}}, {9, {2, 0}},
};

static std::optional<std::pair<int, int>> gridPos(int64_t id) {
    auto it = GRID.find(id);
    if (it == GRID.end())
        return std::nullopt;
    return it->second;
}

void startAnimationHook(PHLWORKSPACE ws, Animation::Workspace::eAnimationType type, bool left, bool instant,
                        std::optional<std::string> style) {
    LOG("HOOK fired: type={} instant={} left={}", type == Animation::Workspace::ANIMATION_TYPE_OUT ? "OUT" : "IN", instant,
        left);

    // NOTA: NO llamamos al original (g_origStartAnimation). En Phase 1
    // animaremos nosotros m_renderOffset en 2D; saltar el original evita
    // ademas el trampoline de CFunctionHook (causa probable del crash 0.56.1).

    if (!ws)
        return;

    // Only intercept the OUT call: at that point ws->m_id == OLD,
    // and the monitor's activeWorkspace is already the NEW one.
    const auto PMONITOR = ws->m_monitor.lock();
    if (!PMONITOR)
        return;
    if (ws->m_isSpecialWorkspace)
        return;

    const auto  ACTIVE = PMONITOR->m_activeWorkspace;
    if (!ACTIVE)
        return;
    const int64_t OLD_ID = ws->m_id;
    const int64_t NEW_ID = ACTIVE->m_id;

    // This is the IN call (ws == active): not useful, skip.
    if (OLD_ID == NEW_ID)
        return;

    const auto OLD_POS = gridPos(OLD_ID);
    const auto NEW_POS = gridPos(NEW_ID);

    if (!OLD_POS || !NEW_POS) {
        LOG("ws switch {} -> {} (fuera de grid, skip)", OLD_ID, NEW_ID);
        return;
    }

    const auto [ox, oy] = *OLD_POS;
    const auto [nx, ny] = *NEW_POS;
    const int  dx       = nx - ox;
    const int  dy       = ny - oy;

    const std::string dirname = (dx == 0 && dy < 0) ? "arriba" : (dx == 0 && dy > 0) ? "abajo"
                                : (dx < 0 && dy == 0)                                ? "izquierda"
                                : (dx > 0 && dy == 0)                                ? "derecha"
                                : (dx < 0 && dy < 0)                                 ? "arriba-izquierda"
                                : (dx > 0 && dy < 0)                                 ? "arriba-derecha"
                                : (dx < 0 && dy > 0)                                 ? "abajo-izquierda"
                                : (dx > 0 && dy > 0)                                 ? "abajo-derecha"
                                                                                     : "centro";

    LOG("HOOK delta grid: ws {} -> {}  pos ({},{}) -> ({},{})  dx={} dy={} dir={} type={} instant={} left={}", OLD_ID, NEW_ID, ox,
        oy, nx, ny, dx, dy, dirname, type == Animation::Workspace::ANIMATION_TYPE_OUT ? "OUT" : "IN", instant, left);
}

APICALL EXPORT std::string pluginAPIVersion() {
    return HYPRLAND_API_VERSION;
}

APICALL EXPORT PLUGIN_DESCRIPTION_INFO pluginInit(HANDLE handle) {
    g_handle = handle;

    const auto matches = findFunctionsByName(g_handle, "startAnimation");
    LOG("findFunctionsByName(startAnimation): {} matches total", matches.size());

    for (const auto& m : matches) {
        const bool isWs = m.demangled.find("Animation::Workspace::startAnimation") != std::string::npos;
        LOG("  match addr={} ws={} demangled={}", (std::uintptr_t)m.address, isWs ? "YES" : "no", m.demangled);

        if (!isWs)
            continue;

        g_startAnimationHook = createFunctionHook(g_handle, m.address, (void*)&startAnimationHook);
        if (g_startAnimationHook) {
            g_origStartAnimation  = (startAnimation_t)g_startAnimationHook->m_original;
            const bool hookOk     = g_startAnimationHook->hook();
            LOG("hook() -> {} para addr={}", hookOk ? "TRUE" : "FALSE", (std::uintptr_t)m.address);
            if (hookOk)
                LOG("hooked startAnimation at {} (demangled: {})", (std::uintptr_t)m.address, m.demangled);
            else
                removeFunctionHook(g_handle, g_startAnimationHook);
            break;
        }
        LOG("  createFunctionHook devolvio NULL para addr={}", (std::uintptr_t)m.address);
    }

    if (!g_startAnimationHook) {
        LOG("ERROR: no se encontro Animation::Workspace::startAnimation para hookear ({} matches)", matches.size());
        for (const auto& m : matches)
            LOG("  match: {}", m.demangled);
    }

    return {"hyprradial", "spike: log grid delta de cambio de workspace", "eztvn", "0.0.1"};
}

APICALL EXPORT void pluginExit() {
    if (g_startAnimationHook) {
        g_startAnimationHook->unhook();
        removeFunctionHook(g_handle, g_startAnimationHook);
        g_startAnimationHook = nullptr;
    }
}