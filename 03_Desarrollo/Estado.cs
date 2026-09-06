using System.Text.Json;
using System.Text.Json.Serialization;

namespace MiJornada;

public static class Config
{
    /// <summary>
    /// Id de la aplicación registrada en Entra ID. Puede reutilizarse el registro
    /// "Teams Presence Flow", añadiéndole una plataforma de tipo "Aplicaciones
    /// móviles y de escritorio" y activando "Permitir flujos de cliente público".
    /// </summary>
    public const string ClientId = "PON-AQUI-TU-CLIENT-ID";

    public const string TenantId = "organizations";

    public static readonly string[] Scopes = { "Presence.ReadWrite" };

    /// <summary>Duración de la jornada. Bajar a minutos para probar.</summary>
    public static TimeSpan Jornada { get; set; } = TimeSpan.FromHours(7);
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

    private static readonly string Carpeta = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "MiJornada");

    private static readonly string Fichero = Path.Combine(Carpeta, "estado.json");

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
        Directory.CreateDirectory(Carpeta);
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
