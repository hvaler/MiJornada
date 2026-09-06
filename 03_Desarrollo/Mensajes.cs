namespace MiJornada;

/// <summary>
/// Mensajes de ánimo al empezar y al terminar la jornada.
///
/// <para>Se evita repetir el mismo dos veces seguidas: con doce mensajes, el azar puro te da el
/// mismo dos días de cada doce, y eso es justo lo que hace que un detalle simpático empiece a
/// parecer un bucle.</para>
///
/// <para>El tono es corto y ligero a propósito. Un mensaje que aleccione —"recuerda hidratarte",
/// "desconecta de verdad"— cansa a la tercera vez, y esto se va a leer doscientas veces al año.</para>
///
/// <para><b>Los emoji están elegidos para verse en blanco y negro.</b> La tarjeta de aviso
/// (<see cref="Aviso"/>) pinta con GDI, que no entiende las tablas de color de Segoe UI Emoji: todo
/// sale en silueta monocroma. Los pictogramas que son una escena dentro de un cuadrado (amanecer,
/// atardecer, ciudad) o una forma sin contorno claro (ola, sol con cara) se convierten en un
/// borrón ilegible; los que son una silueta reconocible (cohete, diana, campana, bandera de
/// cuadros) se ven perfectos. Comprobado glifo a glifo renderizándolos. <b>Antes de añadir un
/// emoji aquí, mírelo pintado en monocromo</b> — en color engañan todos.</para>
/// </summary>
public static class Mensajes
{
    private static readonly string[] AlEmpezar =
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
    ];

    private static readonly string[] AlTerminar =
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
    ];

    private static readonly Random Azar = new();
    private static int _ultimoInicio = -1;
    private static int _ultimoFin = -1;

    public static string Inicio() => Elegir(AlEmpezar, ref _ultimoInicio);

    public static string Fin() => Elegir(AlTerminar, ref _ultimoFin);

    /// <summary>Uno al azar que no sea el anterior.</summary>
    private static string Elegir(string[] pool, ref int ultimo)
    {
        if (pool.Length == 1) return pool[0];

        int i;
        do { i = Azar.Next(pool.Length); } while (i == ultimo);

        ultimo = i;
        return pool[i];
    }
}
