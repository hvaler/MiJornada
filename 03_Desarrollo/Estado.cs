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
