import QtQuick

// Frames para un Canvas que dibuja a mano (morph, siembra, pintura densa).
// Destilado de omarchy-machine-mark (MIT, © Erik R. Johansson).
//
// FrameAnimation no dice cuándo cae el frame en pantalla, sólo cuánto duró el
// anterior. Acá se arma el reloj con eso y se avisa `tick(t)` con el momento en
// que ese frame VA A ESTAR en pantalla (clock + duración). Así el dibujo no
// llega tarde. En pantallas de más de 96 Hz se descarta un refresco de cada
// dos: pintar a 144 fps con frames parejos obliga a que algunos caigan entre
// refrescos, y eso se ve como stutter aunque el número sea más alto.
//
// Uso:
//   Frames { id: frames; running: card.morphing; onTick: function(t) { card.draw(t) } }
// Al pasar running de false a true el reloj arranca de cero (no arrastra el
// hueco de haber estado quieto).
QtObject {
    id: frames

    property bool running: false
    // Momento (ms, reloj absoluto) en que el frame que se está por dibujar
    // va a estar visible. Es lo que hay que pasarle a las animaciones.
    signal tick(real t)

    property real clock: 0
    property real lastT: 0
    property int refreshes: 0
    property real frameMs: 1000 / 60

    onRunningChanged: {
        if (!running) return
        clock = Date.now(); lastT = 0; refreshes = 0
    }

    property FrameAnimation anim: FrameAnimation {
        running: frames.running
        onTriggered: {
            var ms = frameTime * 1000
            // frameTime sólo vale con la animación corriendo; un frame raro
            // (arranque, suspensión) no puede mandar el reloj al pasado.
            if (!(ms > 0 && ms < 100)) ms = 1000 / 60
            frames.frameMs = ms
            frames.clock += ms
            frames.refreshes++
            if (ms < 10.5 && frames.refreshes % 2) return
            // Nunca hacia atrás: un frame largo seguido de uno corto predecía
            // un momento anterior al último dibujado y la forma temblaba.
            var t = Math.max(frames.clock + ms, frames.lastT)
            frames.lastT = t
            frames.tick(t)
        }
    }
}
