// Replica de la lógica anti-bucle para verificarla con casos fijos.
const VENTANA = 60_000, MAX = 3, MIN_MS = 5_000;
function crear(nombre) {
  let ultimo = 0; const porRemitente = new Map();
  return (de, ahora) => {
    if (!de || de === nombre) return false;
    if (ahora - ultimo < MIN_MS) return false;
    const previos = (porRemitente.get(de) ?? []).filter((t) => ahora - t < VENTANA);
    if (previos.length >= MAX) { porRemitente.set(de, previos); return false; }
    previos.push(ahora); porRemitente.set(de, previos); ultimo = ahora; return true;
  };
}
let ok = 0, fail = 0;
const prueba = (nombre, de, ahora, esperado) => {
  const r = puede(de, ahora);
  const bien = r === esperado;
  console.log(`${bien ? "✓" : "✗"} ${nombre}: ${de} t=${ahora} → ${r} (esperaba ${esperado})`);
  bien ? ok++ : fail++;
};
const B = 1_700_000_000_000;
let puede = crear("yo");
prueba("mensaje ajeno despierta", "otro", B, true);
prueba("mensaje propio no despierta", "yo", B + 100000, false);
prueba("mismo remitente demasiado seguido", "otro", B + 3000, false);
prueba("pasado el enfriamiento, despierta", "otro", B + 20000, true);
prueba("tercer despertar del mismo remitente", "otro", B + 40000, true);
prueba("cuarto dentro de la ventana (corta)", "otro", B + 55000, false);
prueba("pasada la ventana vuelve a permitir", "otro", B + 130000, true);
puede = crear("yo");
for (let i = 0; i < 3; i++) puede("ruidoso", B + i * 10000);
prueba("remitente ruidoso cortado", "ruidoso", B + 40000, false);
prueba("otro remitente sí pasa", "tranquilo", B + 60000, true);
console.log(`\n${ok} ok, ${fail} fallos`);
process.exit(fail ? 1 : 0);
