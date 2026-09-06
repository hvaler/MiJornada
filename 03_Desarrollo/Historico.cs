using System.Globalization;
using System.Text.Json;

namespace MiJornada;

/// <summary>Cómo terminó una jornada.</summary>
public enum FinJornada
{
    /// <summary>Llegó a cero sola.</summary>
    Completada = 0,

    /// <summary>La canceló el usuario antes de tiempo.</summary>
    Cancelada = 1,
}

/// <summary>Una jornada terminada, tal y como queda anotada.</summary>
public sealed class Jornada
{
    public DateTimeOffset Inicio { get; set; }
    public DateTimeOffset Fin { get; set; }

    /// <summary>Minutos de jornada efectivos, ya descontadas las pausas.</summary>
    public int Minutos { get; set; }

    /// <summary>Minutos que estuvo en pausa.</summary>
    public int Pausados { get; set; }

    /// <summary>Duración con la que se fichó, para poder ver si se quedó corta o larga.</summary>
    public int Previstos { get; set; }

    public FinJornada Fin_ { get; set; }
    public bool Automatica { get; set; }
    public string? Equipo { get; set; }

    /// <summary>El día al que se imputa. Es el de <see cref="Inicio"/>: una jornada que cruza
    /// la medianoche cuenta en el día en que se empezó, que es como lo cuenta uno.</summary>
    [System.Text.Json.Serialization.JsonIgnore]
    public DateOnly Dia => DateOnly.FromDateTime(Inicio.LocalDateTime);
}

/// <summary>Resumen de una semana.</summary>
public sealed record ResumenSemana(DateOnly Lunes, int Minutos, int Dias)
{
    public DateOnly Domingo => Lunes.AddDays(6);
    public double Horas => Minutos / 60.0;

    /// <summary>Media por día trabajado, no por día natural: descansar no baja la media.</summary>
    public double MediaHoras => Dias == 0 ? 0 : Minutos / 60.0 / Dias;
}

/// <summary>
/// Histórico de jornadas: qué días se fichó, cuánto y cómo terminó, con resumen por semana.
///
/// <para>Es lo último que quedaba de la versión de Power Apps, donde salía gratis porque los datos
/// vivían en una lista de SharePoint. Aquí hay que anotarlo a mano, en <c>historico.json</c>
/// dentro de la carpeta de datos.</para>
///
/// <para><b>Se anotan también las canceladas</b>, marcadas como tales. Cancelar significa "hoy no
/// quiero estar fichado" y por eso limpia la presencia, pero el rato trabajado <i>existió</i>:
/// borrarlo del histórico sería falsear la semana. En el resumen se cuentan las dos, y en la lista
/// se distingue.</para>
///
/// <para><b>Nada de esto puede impedir fichar.</b> Escribir el histórico va después de cambiar la
/// presencia y dentro de un try/catch: si el fichero está corrupto o bloqueado, se pierde una
/// anotación, que es mucho menos grave que quedarse con la presencia sin cambiar.</para>
/// </summary>
public static class Historico
{
    private static string Fichero => Path.Combine(Rutas.Carpeta, "historico.json");

    /// <summary>
    /// Tope de anotaciones. Cinco años largos de trabajo: pasado eso se tiran las más antiguas
    /// para que el fichero no crezca sin fin. Es un JSON que se lee entero en memoria.
    /// </summary>
    private const int Tope = 1500;

    public static List<Jornada> Cargar()
    {
        try
        {
            if (File.Exists(Fichero))
                return JsonSerializer.Deserialize<List<Jornada>>(File.ReadAllText(Fichero)) ?? [];
        }
        catch
        {
            // Un histórico corrupto no debe impedir nada: se empieza de cero. Es un registro
            // informativo, no la fuente de verdad de ninguna decisión.
        }
        return [];
    }

    /// <summary>Anota una jornada. Devuelve <c>false</c> si no se pudo, sin lanzar.</summary>
    public static bool Anotar(Jornada j)
    {
        try
        {
            var todas = Cargar();
            todas.Add(j);

            if (todas.Count > Tope)
                todas = todas.OrderBy(x => x.Inicio).TakeLast(Tope).ToList();

            Directory.CreateDirectory(Rutas.Carpeta);
            File.WriteAllText(Fichero, JsonSerializer.Serialize(todas,
                new JsonSerializerOptions { WriteIndented = true }));
            return true;
        }
        catch
        {
            return false;
        }
    }

    /// <summary>
    /// Construye la anotación a partir del estado que se está cerrando. Devuelve <c>null</c> si
    /// el estado no da para anotar nada (por ejemplo, jornadas empezadas antes de que existiera
    /// el campo <c>Inicio</c>, que no tienen hora de entrada que apuntar).
    /// </summary>
    public static Jornada? Desde(Estado e, FinJornada final, bool automatica)
    {
        if (e.Inicio is null) return null;

        var ahora = DateTimeOffset.Now;
        var pausados = e.MinutosPausados;

        // Si se cierra estando en pausa, esa pausa aún no se ha contabilizado.
        if (e.Situacion == EstadoJornada.Pausada && e.PausaDesde is not null)
            pausados += (int)Math.Round((ahora - e.PausaDesde.Value).TotalMinutes);

        var totales = (int)Math.Round((ahora - e.Inicio.Value).TotalMinutes);
        var trabajados = Math.Max(0, totales - pausados);

        return new Jornada
        {
            Inicio = e.Inicio.Value,
            Fin = ahora,
            Minutos = trabajados,
            Pausados = Math.Max(0, pausados),
            Previstos = e.DuracionMinutos,
            Fin_ = final,
            Automatica = automatica,
            Equipo = Environment.MachineName,
        };
    }

    // ------------------------------------------------------------------ resúmenes

    /// <summary>
    /// Agrupa por semana natural de lunes a domingo, de la más reciente a la más antigua.
    ///
    /// <para>Lunes y no domingo: aquí la semana laboral empieza el lunes, y el resumen de una
    /// semana partida en dos no diría nada. Se calcula a mano y no con <c>Calendar.GetWeekOfYear</c>
    /// para no depender de la cultura del equipo, que puede cambiar entre máquinas.</para>
    /// </summary>
    public static List<ResumenSemana> PorSemana(IEnumerable<Jornada> jornadas)
    {
        return jornadas
            .GroupBy(j => LunesDe(j.Dia))
            .Select(g => new ResumenSemana(
                g.Key,
                g.Sum(j => j.Minutos),
                g.Select(j => j.Dia).Distinct().Count()))
            .OrderByDescending(r => r.Lunes)
            .ToList();
    }

    public static DateOnly LunesDe(DateOnly dia)
    {
        // DayOfWeek empieza en domingo (0), así que el domingo hay que retroceder 6 días.
        var desplazamiento = dia.DayOfWeek == DayOfWeek.Sunday ? 6 : (int)dia.DayOfWeek - 1;
        return dia.AddDays(-desplazamiento);
    }

    /// <summary>Formatea minutos como "7 h 30 min", que es como se lee una jornada.</summary>
    public static string Duracion(int minutos)
    {
        if (minutos < 60) return $"{minutos} min";

        var h = minutos / 60;
        var m = minutos % 60;
        return m == 0 ? $"{h} h" : $"{h} h {m} min";
    }

    /// <summary>"Semana del 1 al 7 de septiembre", con el mes solo cuando cambia.</summary>
    public static string Rango(ResumenSemana r)
    {
        var ci = CultureInfo.CurrentCulture;
        var d = r.Domingo;

        return r.Lunes.Month == d.Month
            ? $"{r.Lunes.Day} – {d.Day} de {ci.DateTimeFormat.GetMonthName(d.Month)}"
            : $"{r.Lunes.Day} de {ci.DateTimeFormat.GetAbbreviatedMonthName(r.Lunes.Month)} – " +
              $"{d.Day} de {ci.DateTimeFormat.GetAbbreviatedMonthName(d.Month)}";
    }
}
