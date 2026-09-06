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
/// <para><b>El tono es corto y ligero a propósito.</b> Un mensaje que aleccione —"recuerda
/// hidratarte", "el éxito es la suma de pequeños esfuerzos"— cansa a la tercera vez, y esto se
/// lee unas cuatrocientas veces al año. Por eso los mensajes hablan de <i>este</i> momento
/// concreto (fichar, cerrar el portátil) y no de la vida en general.</para>
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
        "☕ A por el día.",
        "🚀 En marcha. Que sea de las buenas.",
        "🎯 Dentro. Lo importante primero.",
        "🧩 Buen momento para empezar por lo difícil.",
        "📌 Fichado. Yo me encargo del reloj.",
        "🧭 Arrancamos. Que el foco te acompañe.",
        "🌱 Otro día para dejarlo un poco mejor.",
        "🎧 Tú a lo tuyo, que ya te aviso.",
        "⚡ El día es largo: ve a tu ritmo.",
        "🔔 Empieza la cuenta.",
        "🚦 Jornada abierta. Buen camino.",
        "⏱️ Empezamos. Sin prisa pero sin pausa.",
        "📋 Lo primero es decidir qué es lo primero.",
        "🛠️ Manos a la obra.",
        "🪜 Un peldaño cada vez.",
        "✏️ Página en blanco. Buena señal.",
        "💡 A ver qué se te ocurre hoy.",
        "🗝️ Día abierto.",
        "📐 Con calma y con medida.",
        "🥾 En camino.",
        "⛳ Con una cosa bien hecha, ya vale.",
        "🕹️ Dale al play.",
        "🧠 Lo de pensar, mejor ahora que luego.",
        "🧲 Que hoy salgan las cosas a la primera.",
    ];

    private static readonly string[] FinPorDefecto =
    [
        "🌙 Hasta aquí. Lo que quede, quedará.",
        "🏁 Jornada cerrada.",
        "📖 Mañana sigue estando el mundo.",
        "☑️ Terminado. Cierra el portátil sin culpa.",
        "🍃 El correo puede esperar.",
        "🧘 Ahora tu tiempo.",
        "🎬 Que el día se quede aquí.",
        "🎈 Lo pendiente seguirá pendiente mañana.",
        "🕯️ Fin. Apaga y a otra cosa.",
        "🏆 Día completado, sin horas extra regaladas.",
        "🛎️ Se cierra el chiringuito.",
        "🎒 Fuera del trabajo. Literalmente.",
        "🌜 Se acabó por hoy.",
        "🛋️ El sofá lleva un rato esperando.",
        "🔒 Cerrado hasta mañana.",
        "📕 Fin del capítulo.",
        "🛏️ Mañana hay más; hoy ya no.",
        "🍵 Hora de algo caliente.",
        "🎸 Que lo siguiente no sea trabajo.",
        "⚓ Amarrado hasta mañana.",
        "🧺 A recoger, que ya está.",
        "🎁 El día ya está entregado.",
        "🐢 Sin prisa a partir de ahora.",
        "🪟 Cierra también las pestañas.",
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
