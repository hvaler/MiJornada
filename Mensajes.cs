using System.Text.Json;

namespace MiJornada;

/// <summary>
/// Mensajes de ánimo al empezar y al terminar la jornada. Veinticuatro de cada, y se pueden
/// sustituir por los tuyos con un fichero (ver <see cref="Fichero"/>).
///
/// <para>Se evita repetir el mismo dos veces seguidas: con esta cantidad el azar puro ya repite
/// poco, pero repetir <b>justo el del día anterior</b> es lo que hace que un detalle simpático
/// empiece a parecer un bucle.</para>
///
/// <para><b>Sobre el tono.</b> La primera versión eran frases de tres palabras ("Manos a la obra",
/// "En camino"): tan cortas que no decían nada, y el usuario lo dijo claro — poco profundas. Estas
/// tienen dos tiempos: una frase que sitúa y otra que aporta algo. Lo que se sigue evitando es el
/// <i>aleccionamiento genérico</i> tipo "el éxito es la suma de pequeños esfuerzos", que además de
/// cansar a la tercera vez no dice nada de <b>este</b> momento. La diferencia entre profundo y
/// pesado está en hablar de lo concreto: fichar, el correo, la hora de cerrar.</para>
///
/// <para>Restricción real: el ancho útil de la tarjeta son 306 px, así que un mensaje ocupa dos
/// líneas y, como mucho, tres. Medido, no supuesto — ver M16.</para>
///
/// <para><b>Los emoji están elegidos para verse en monocromo.</b> GDI no entiende las tablas de
/// color de Segoe UI Emoji, así que en la tarjeta salen como silueta blanca sobre la banda. A
/// 30 pt se leen como iconos de contorno y aguantan bastante detalle, pero los que son una
/// escena dentro de un cuadrado (🌅 🌇 🌆), una forma sin contorno claro (🌊 🔥) o una figura
/// humana pequeña (🧗) quedan en un borrón. <b>Antes de añadir uno, hay que verlo pintado en
/// blanco a 30 pt</b> — en color engañan todos.</para>
/// </summary>
public static class Mensajes
{
    private static readonly string[] InicioPorDefecto =
    [
        "☕ A por el día. El café es tuyo; el reloj, cosa mía.",
        "🚀 En marcha. Lo que hagas hoy no tiene que ser todo: basta con que sea algo.",
        "🎯 Dentro. Elige ahora lo importante, antes de que lo urgente elija por ti.",
        "🧩 Buen momento para empezar por lo difícil: a las seis de la tarde pesa el doble.",
        "📌 Fichado. Ya no tienes que acordarte de la hora, y eso también descansa.",
        "🧭 Arrancamos. Si a media mañana no sabes qué haces, vuelve a esta primera decisión.",
        "🌱 Otro día para dejarlo un poco mejor que ayer. Un poco basta.",
        "🎧 Tú a lo tuyo. El día tiene final y yo me encargo de avisarte.",
        "⚡ El día es largo: ve a tu ritmo, que el que corre al principio llega peor al final.",
        "🔔 Empieza la cuenta. Trabajar con final a la vista se lleva mejor.",
        "🚦 Jornada abierta. Nadie hace su mejor trabajo con doce cosas a la vez.",
        "⏱️ Sin prisa pero sin pausa. Las horas van a pasar igual; que pasen a tu favor.",
        "📋 Lo primero es decidir qué es lo primero. Lo demás es ir apagando fuegos.",
        "🛠️ Manos a la obra. Empezar mal es más rápido que no empezar.",
        "🪜 Un peldaño cada vez. Mirar la escalera entera solo sirve para cansarse antes.",
        "✏️ Página en blanco: hoy todavía no has tomado ninguna decisión de la que arrepentirte.",
        "💡 A ver qué se te ocurre hoy. Las buenas ideas suelen llegar trabajando, no esperando.",
        "🗝️ Día abierto. Lo que dejaste a medias ayer casi siempre se ve más fácil hoy.",
        "📐 Con calma y con medida. Hacerlo dos veces cuesta más que hacerlo bien una.",
        "🥾 En camino. No hace falta ver el final para dar el primer paso.",
        "⛳ Con una cosa bien hecha el día ya está justificado. Elige cuál.",
        "🕹️ Dale al play. El rato que cuesta arrancar es siempre peor que el trabajo en sí.",
        "🧠 Lo de pensar, mejor ahora que luego: la cabeza está más despejada de lo que estará.",
        "🧲 Que hoy salga a la primera. Y si no sale, que salga a la segunda sin drama.",
    ];

    private static readonly string[] FinPorDefecto =
    [
        "🌙 Hasta aquí. Lo que quede, quedará; mañana también hay horas.",
        "🏁 Jornada cerrada. Has hecho lo que cabía en el tiempo que había.",
        "📖 Mañana sigue estando el mundo, y con él lo que no te ha dado tiempo.",
        "☑️ Cierra el portátil sin culpa: la jornada tenía una hora de final y ha llegado.",
        "🍃 El correo puede esperar. Casi nada de lo que llega ahora se resuelve mejor cansado.",
        "🧘 Ahora tu tiempo. Que se note la diferencia entre trabajar y no trabajar.",
        "🎬 Que el día se quede aquí. Llevártelo a casa no adelanta el trabajo de mañana.",
        "🎈 Lo pendiente seguirá pendiente mañana, y mañana lo verás con mejores ojos.",
        "🕯️ Fin. Apagar del todo es lo que hace que mañana se pueda encender otra vez.",
        "🏆 Día completado sin horas extra regaladas, que es más difícil de lo que parece.",
        "🛎️ Se cierra el chiringuito. Lo urgente de última hora casi nunca lo era.",
        "🎒 Fuera del trabajo, literalmente: tu estado ya lo dice por ti.",
        "🌜 Se acabó por hoy. Descansar no es lo que sobra del día, es parte del día.",
        "🛋️ El sofá lleva un rato esperando y tiene toda la razón.",
        "🔒 Cerrado hasta mañana. Nadie espera que estés disponible ahora, aunque lo parezca.",
        "📕 Fin del capítulo. Ni el mejor libro se lee entero de una sentada.",
        "🛏️ Mañana hay más; hoy ya no. Las dos cosas son verdad y conviene creerse las dos.",
        "🍵 Hora de algo caliente y de pensar en cualquier otra cosa.",
        "🎸 Que lo siguiente no sea trabajo. Lo que hagas ahora también cuenta como día.",
        "⚓ Amarrado hasta mañana. Dejarlo a tiempo es parte de hacerlo bien.",
        "🧺 A recoger, que ya está. Media hora más no habría cambiado gran cosa.",
        "🎁 El día ya está entregado. Lo demás sería trabajar gratis.",
        "🐢 Sin prisa a partir de ahora. Nada de lo que viene tiene hora de entrega.",
        "🪟 Cierra también las pestañas: si siguen abiertas, la cabeza tampoco cierra.",
    ];

    /// <summary>
    /// Fichero opcional con tus propios mensajes, en la carpeta de datos. Si existe y trae
    /// alguna lista, esa <b>sustituye</b> a la de serie; la que no traiga, se queda como está.
    /// </summary>
    public static string Fichero => Path.Combine(Rutas.Carpeta, "mensajes.json");

    private sealed class Fuente
    {
        public string[]? Inicio { get; set; }
        public string[]? Fin { get; set; }
    }

    // Se cargan una vez y se quedan: el fichero se lee al arrancar, no en cada fichaje. Cambiarlo
    // con la aplicación abierta exige reiniciarla, y es lo razonable para algo que se toca una vez.
    private static readonly Lazy<(string[] inicio, string[] fin)> Listas = new(Cargar);

    private static (string[], string[]) Cargar()
    {
        try
        {
            if (!File.Exists(Fichero)) return (InicioPorDefecto, FinPorDefecto);

            var f = JsonSerializer.Deserialize<Fuente>(File.ReadAllText(Fichero));

            // Una lista vacía o a medio escribir no debe dejar la aplicación sin mensajes: solo
            // sustituye la que traiga contenido de verdad.
            var inicio = f?.Inicio is { Length: > 0 } i ? Limpiar(i) : InicioPorDefecto;
            var fin = f?.Fin is { Length: > 0 } n ? Limpiar(n) : FinPorDefecto;

            return (inicio.Length > 0 ? inicio : InicioPorDefecto,
                    fin.Length > 0 ? fin : FinPorDefecto);
        }
        catch
        {
            // Un fichero corrupto no puede impedir fichar. Se ignora y se usan los de serie.
            return (InicioPorDefecto, FinPorDefecto);
        }
    }

    private static string[] Limpiar(string[] origen) =>
        origen.Where(m => !string.IsNullOrWhiteSpace(m)).Select(m => m.Trim()).ToArray();

    /// <summary>Escribe el fichero con los mensajes actuales, para tenerlo de plantilla.</summary>
    public static void CrearPlantilla()
    {
        Directory.CreateDirectory(Rutas.Carpeta);

        var (inicio, fin) = Listas.Value;
        File.WriteAllText(Fichero, JsonSerializer.Serialize(
            new Fuente { Inicio = inicio, Fin = fin },
            new JsonSerializerOptions { WriteIndented = true }));
    }

    private static readonly Random Azar = new();
    private static int _ultimoInicio = -1;
    private static int _ultimoFin = -1;

    public static string Inicio() => Elegir(Listas.Value.inicio, ref _ultimoInicio);

    public static string Fin() => Elegir(Listas.Value.fin, ref _ultimoFin);

    /// <summary>Uno al azar que no sea el anterior.</summary>
    private static string Elegir(string[] pool, ref int ultimo)
    {
        if (pool.Length == 0) return string.Empty;
        if (pool.Length == 1) return pool[0];

        int i;
        do { i = Azar.Next(pool.Length); } while (i == ultimo);

        ultimo = i;
        return pool[i];
    }
}
