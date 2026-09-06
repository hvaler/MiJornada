using System.Text.Json;
using System.Text.Json.Serialization;

namespace MiJornada;

public static class Config
{
    /// <summary>
    /// Id de la aplicación "Mi jornada" registrada en Entra ID el 2026-09-06 con
    /// <c>02_Entorno/crear-registro-entra.ps1</c>. Cliente público, sin secreto (ADR-003):
    /// un Id de cliente público es información pública, no una credencial.
    /// Su único permiso es el delegado <c>Presence.ReadWrite</c>.
    /// </summary>
    public const string ClientId = "dbcd6425-561b-4d91-a4d5-f0bb25b31241";

    /// <summary>
    /// Tenant concreto (comillas.edu) en lugar de "organizations": lleva la pantalla de inicio
    /// de sesión directa a Comillas, sin el paso previo de elegir tipo de cuenta.
    /// Se usa el GUID y no el dominio porque es inmune a cambios de dominio verificado.
    /// Verificado con Get-MgContext el 2026-09-06.
    /// </summary>
    public const string TenantId = "bcd2701c-aa9b-4d12-ba20-f3e3b83070c1";

    public static readonly string[] Scopes = { "Presence.ReadWrite" };

    /// <summary>
    /// Duración de la jornada en curso. Sale de <see cref="Ajustes"/>, salvo que se haya
    /// pasado <c>--minutos N</c>, que manda sobre todo lo demás.
    /// </summary>
    public static TimeSpan Jornada { get; set; } = TimeSpan.FromHours(7);

    /// <summary>
    /// Cierto si la duración viene de <c>--minutos</c>. La interfaz deshabilita el selector
    /// en ese caso: cambiarlo no tendría efecto y sería confuso.
    /// </summary>
    public static bool JornadaForzada { get; set; }
}

/// <summary>
/// Preferencias del usuario. Van en su propio fichero y no en <see cref="Estado"/> porque
/// sobreviven a <see cref="Estado.Limpiar"/>: cancelar una jornada no debe olvidar que tu
/// jornada dura 6 horas.
/// </summary>
public class Ajustes
{
    /// <summary>Duración de la jornada en minutos. 420 = 7 h.</summary>
    public int DuracionMinutos { get; set; } = 420;

    /// <summary>
    /// Presencia que se pone al pausar. Se guarda la clave de Graph, no la etiqueta traducida,
    /// para que un cambio de textos no invalide los ajustes ya guardados.
    /// </summary>
    public string PausaDisponibilidad { get; set; } = "Away";

    /// <summary>
    /// Fichar solo al desbloquear el equipo. Desactivado por defecto: cambia la presencia del
    /// usuario sin que él haga nada, y eso hay que pedirlo, no imponerlo.
    /// </summary>
    public bool FicharAlDesbloquear { get; set; }

    /// <summary>
    /// Día del último fichaje automático. Evita que volver del café vuelva a fichar: el
    /// automatismo salta una vez al día y el resto de desbloqueos no hacen nada.
    /// Vive aquí y no en <see cref="Estado"/> porque debe sobrevivir a <see cref="Estado.Limpiar"/>.
    /// </summary>
    public DateTime? UltimoAutoFichaje { get; set; }

    [JsonIgnore]
    public TimeSpan Duracion => TimeSpan.FromMinutes(Math.Clamp(DuracionMinutos, 1, 24 * 60));

    /// <summary>Opción de pausa correspondiente, o Ausente si lo guardado ya no existe.</summary>
    [JsonIgnore]
    public OpcionPresencia Pausa =>
        Array.Find(OpcionPresencia.ParaPausa, o => o.Disponibilidad == PausaDisponibilidad)
        ?? OpcionPresencia.ParaPausa[0];

    private static readonly string Fichero = Path.Combine(Rutas.Carpeta, "ajustes.json");

    public static Ajustes Cargar()
    {
        try
        {
            if (File.Exists(Fichero))
                return JsonSerializer.Deserialize<Ajustes>(File.ReadAllText(Fichero)) ?? new Ajustes();
        }
        catch
        {
            // Unos ajustes corruptos no deben impedir arrancar: se vuelve a los de fábrica.
        }
        return new Ajustes();
    }

    public void Guardar()
    {
        Directory.CreateDirectory(Rutas.Carpeta);
        File.WriteAllText(Fichero, JsonSerializer.Serialize(this,
            new JsonSerializerOptions { WriteIndented = true }));
    }
}

/// <summary>
/// Una pareja disponibilidad/actividad de las que Graph acepta, con su nombre en castellano.
/// Las parejas no son libres: hay que usar las combinaciones válidas (ver _hilo/DEPENDENCIAS.md).
/// </summary>
public record OpcionPresencia(string Etiqueta, string Disponibilidad, string Actividad)
{
    // El ComboBox muestra esto
    public override string ToString() => Etiqueta;

    /// <summary>Estados que tienen sentido al pausar. No se ofrece "Fuera del trabajo": ese
    /// es el del final de la jornada, y ponerlo en una pausa daría a entender que has terminado.</summary>
    public static readonly OpcionPresencia[] ParaPausa =
    [
        new("Ausente",          "Away",         "Away"),
        new("Vuelvo enseguida", "BeRightBack",  "BeRightBack"),
        new("Ocupado",          "Busy",         "Busy"),
        new("No molestar",      "DoNotDisturb", "DoNotDisturb"),
    ];
}

/// <summary>Carpeta de datos de la aplicación, compartida por estado, ajustes y caché de token.</summary>
public static class Rutas
{
    public static readonly string Carpeta = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "MiJornada");
}

/// <summary>Icono propio de la aplicación, incrustado como recurso.</summary>
public static class Iconos
{
    private const string Recurso = "MiJornada.mijornada.ico";

    /// <summary>
    /// Devuelve el marco del tamaño pedido. Un <c>.ico</c> multi-resolución tiene varios y
    /// Windows elige mal si no se le indica: 16 px para la bandeja, 32 para la ventana.
    /// </summary>
    public static Icon Cargar(int px)
    {
        try
        {
            using var s = typeof(Iconos).Assembly.GetManifestResourceStream(Recurso);
            if (s is not null) return new Icon(s, px, px);
        }
        catch
        {
            // Si el recurso faltara, mejor un icono feo que no arrancar.
        }
        return SystemIcons.Application;
    }
}

public enum EstadoJornada { SinFichar, Activa, Pausada }

public class Estado
{
    public EstadoJornada Situacion { get; set; } = EstadoJornada.SinFichar;
    public DateTime? Fin { get; set; }
    public DateTime? PausaDesde { get; set; }

    [JsonIgnore]
    public TimeSpan Restante
    {
        get
        {
            if (Fin is null) return TimeSpan.Zero;
            var referencia = Situacion == EstadoJornada.Pausada && PausaDesde is not null
                ? PausaDesde.Value
                : DateTime.Now;
            var queda = Fin.Value - referencia;
            return queda > TimeSpan.Zero ? queda : TimeSpan.Zero;
        }
    }

    [JsonIgnore]
    public double Fraccion =>
        Config.Jornada.TotalSeconds <= 0
            ? 0
            : Math.Clamp(Restante.TotalSeconds / Config.Jornada.TotalSeconds, 0, 1);

    // ---------------------------------------------------------------- persistencia

    private static readonly string Fichero = Path.Combine(Rutas.Carpeta, "estado.json");

    public static Estado Cargar()
    {
        try
        {
            if (File.Exists(Fichero))
                return JsonSerializer.Deserialize<Estado>(File.ReadAllText(Fichero)) ?? new Estado();
        }
        catch
        {
            // Un estado corrupto no debe impedir arrancar: se empieza de cero.
        }
        return new Estado();
    }

    public void Guardar()
    {
        Directory.CreateDirectory(Rutas.Carpeta);
        File.WriteAllText(Fichero, JsonSerializer.Serialize(this,
            new JsonSerializerOptions { WriteIndented = true }));
    }

    public void Limpiar()
    {
        Situacion = EstadoJornada.SinFichar;
        Fin = null;
        PausaDesde = null;
        Guardar();
    }
}
