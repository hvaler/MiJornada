using System.Text.Json;
using System.Text.Json.Serialization;

namespace MiJornada;

public static class Config
{
    /// <summary>
    /// Id de la aplicación "Mi jornada" registrada en Entra ID el 2026-09-06 con
    /// <c>02_Entorno/crear-registro-entra.ps1</c>. Cliente público, sin secreto (ADR-003):
    /// un Id de cliente público es información pública, no una credencial.
    /// Sus permisos delegados son <c>Presence.ReadWrite</c> y <c>Files.ReadWrite.AppFolder</c>.
    /// </summary>
    public const string ClientId = "dbcd6425-561b-4d91-a4d5-f0bb25b31241";

    /// <summary>
    /// Tenant concreto (comillas.edu) en lugar de "organizations": lleva la pantalla de inicio
    /// de sesión directa a Comillas, sin el paso previo de elegir tipo de cuenta.
    /// Se usa el GUID y no el dominio porque es inmune a cambios de dominio verificado.
    /// Verificado con Get-MgContext el 2026-09-06.
    /// </summary>
    public const string TenantId = "bcd2701c-aa9b-4d12-ba20-f3e3b83070c1";

    /// <summary>
    /// Permisos delegados. <c>Files.ReadWrite.AppFolder</c> da acceso SOLO a la carpeta propia
    /// de esta aplicación en OneDrive (<c>Aplicaciones/Mi jornada</c>), no al resto de ficheros:
    /// es el permiso más estrecho que permite compartir el estado entre equipos.
    /// Verificado el 2026-09-06 que funciona con cuenta de trabajo, pese a que la documentación
    /// antigua de OneDrive lo daba por exclusivo de cuentas personales.
    /// OJO: MSAL cachea el token por conjunto de scopes. Tocar este array obliga a un
    /// consentimiento nuevo, y por tanto a un código de dispositivo más.
    /// </summary>
    public static readonly string[] Scopes =
    {
        "Presence.ReadWrite",
        "Files.ReadWrite.AppFolder",
    };

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

    /// <summary>
    /// Arrancar oculto en la bandeja. Viene de <c>--minimizado</c>, que solo pone el acceso
    /// directo de inicio: abrir la aplicación a mano siempre muestra la ventana.
    /// </summary>
    public static bool ArrancarMinimizado { get; set; }
}

/// <summary>
/// Preferencias del usuario. Van en su propio fichero y no en <see cref="Estado"/> porque
/// sobreviven a <see cref="Estado.Limpiar"/>: cancelar una jornada no debe olvidar que tu
/// jornada dura 6 horas.
/// </summary>
public class Ajustes
{
    /// <summary>Duración general de la jornada en minutos. 420 = 7 h.</summary>
    public int DuracionMinutos { get; set; } = 420;

    /// <summary>
    /// Excepciones por día de la semana, en minutos. La clave es el nombre invariante de
    /// <see cref="DayOfWeek"/> (<c>"Monday"</c>, <c>"Friday"</c>...), no el traducido: la
    /// aplicación puede correr en equipos con idioma distinto y el fichero viaja entre ellos.
    /// Un día que no esté aquí usa la duración general.
    /// </summary>
    public Dictionary<string, int> DuracionPorDia { get; set; } = new();

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
    /// Al sincronizarse entre equipos, además evita que dos equipos fichen el mismo día.
    /// </summary>
    public DateTime? UltimoAutoFichaje { get; set; }

    /// <summary>
    /// Franja en la que el fichaje automático puede saltar, en formato <c>HH:mm</c> invariante.
    /// Sin ella, desbloquear el equipo a las tres de la madrugada ficharía la jornada.
    /// </summary>
    public string AutoFichajeDesde { get; set; } = "07:00";

    /// <inheritdoc cref="AutoFichajeDesde"/>
    public string AutoFichajeHasta { get; set; } = "11:00";

    /// <summary>
    /// Globo con un mensaje de ánimo al empezar y al terminar. Activado por defecto, pero con
    /// interruptor: los gustos varían y esto se lee un par de cientos de veces al año.
    /// </summary>
    public bool MensajesDeAnimo { get; set; } = true;

    /// <summary>No fichar solo los sábados ni los domingos.</summary>
    public bool AutoFichajeSoloLaborables { get; set; } = true;

    /// <summary>
    /// Festivos en los que tampoco se ficha solo, en formato <c>yyyy-MM-dd</c> invariante.
    /// </summary>
    public List<string> Festivos { get; set; } = new();

    /// <summary>
    /// Compartir estado y ajustes entre equipos a través de la carpeta de aplicación de
    /// OneDrive. Activado por defecto: sin esto, cada equipo cree que no hay jornada y se
    /// pueden arrancar dos, que se pelearían por la misma presencia de Teams.
    /// </summary>
    public bool SincronizarEntreEquipos { get; set; } = true;

    /// <summary>
    /// Minutos de antelación del aviso de fin de jornada. 0 = sin aviso.
    /// Sirve para poder cerrar cosas antes de que te cambie el estado.
    /// </summary>
    public int AvisoMinutos { get; set; } = 15;

    /// <summary>
    /// Cuánto se queda el aviso en pantalla, en segundos. Los 6 s de la primera versión eran los
    /// de un globo de bandeja, y se quedaban cortos para un mensaje de dos líneas que además
    /// aparece mientras estás mirando otra cosa.
    /// </summary>
    public int SegundosAviso { get; set; } = 12;

    /// <summary>
    /// Si el aviso se va solo. Con <c>false</c> se queda hasta que lo pulsas, para no perderte
    /// ninguno — al precio de tener que quitarlo a mano.
    /// </summary>
    public bool AvisoSeCierraSolo { get; set; } = true;

    /// <summary>
    /// Arrancar en la bandeja en vez de abrir la ventana. Per-equipo, NO se sincroniza.
    ///
    /// <para>Nótese que NO hay un "ArrancarConWindows": la verdad sobre eso es la existencia del
    /// acceso directo en la carpeta de Inicio (ver <see cref="ArranqueWindows"/>). El usuario
    /// puede borrarlo desde el Administrador de tareas o del propio explorador, así que un
    /// booleano aquí solo podría desincronizarse y mentir.</para>
    /// </summary>
    public bool ArrancarMinimizado { get; set; }

    /// <summary>Momento del último cambio, en UTC. Al sincronizar, gana el más reciente.</summary>
    public DateTimeOffset? Actualizado { get; set; }

    [JsonIgnore]
    public TimeSpan Duracion => TimeSpan.FromMinutes(Math.Clamp(DuracionMinutos, 1, 24 * 60));

    /// <summary>
    /// Interpreta una fecha escrita a mano. Acepta lo que la gente escribe de verdad:
    /// <c>dd/MM/yyyy</c>, <c>d/M/yyyy</c>, <c>dd-MM-yyyy</c> y el ISO <c>yyyy-MM-dd</c>.
    ///
    /// <para>Formatos explícitos y cultura invariante, nunca la del equipo: el fichero de
    /// ajustes viaja por OneDrive entre máquinas que pueden tener otra configuración regional,
    /// y con la cultura local un <c>03/04/2026</c> sería marzo aquí y abril allí.</para>
    /// </summary>
    public static DateTime? ParsearFecha(string? texto)
    {
        if (string.IsNullOrWhiteSpace(texto)) return null;
        string[] formatos = ["dd/MM/yyyy", "d/M/yyyy", "yyyy-MM-dd", "dd-MM-yyyy"];
        return DateTime.TryParseExact(texto.Trim(), formatos,
            System.Globalization.CultureInfo.InvariantCulture,
            System.Globalization.DateTimeStyles.None, out var d) ? d : null;
    }

    /// <summary>Cierto si esa fecha está en la lista de festivos.</summary>
    public bool EsFestivo(DateTimeOffset momento) =>
        Festivos.Contains(momento.ToString("yyyy-MM-dd",
            System.Globalization.CultureInfo.InvariantCulture));

    /// <summary>
    /// Decide si el fichaje automático puede saltar ahora mismo, y explica por qué no.
    ///
    /// <para>Solo condiciona al AUTOMATISMO. Fichar a mano funciona siempre: si un sábado
    /// decides trabajar, la aplicación no tiene por qué llevarte la contraria.</para>
    /// </summary>
    public bool PuedeFicharSolo(DateTimeOffset ahora, out string motivo)
    {
        if (AutoFichajeSoloLaborables &&
            ahora.DayOfWeek is DayOfWeek.Saturday or DayOfWeek.Sunday)
        {
            motivo = "es fin de semana";
            return false;
        }

        if (EsFestivo(ahora))
        {
            motivo = "es festivo";
            return false;
        }

        var desde = HoraDe(AutoFichajeDesde, new TimeSpan(0, 0, 0));
        var hasta = HoraDe(AutoFichajeHasta, new TimeSpan(23, 59, 0));
        var ahoraDelDia = ahora.TimeOfDay;

        if (ahoraDelDia < desde || ahoraDelDia > hasta)
        {
            motivo = $@"está fuera de la franja {desde:hh\:mm}-{hasta:hh\:mm}";
            return false;
        }

        motivo = string.Empty;
        return true;
    }

    /// <summary>Interpreta un <c>HH:mm</c> invariante; si no se puede, devuelve el respaldo.</summary>
    internal static TimeSpan HoraDe(string? texto, TimeSpan respaldo) =>
        TimeSpan.TryParseExact(texto, @"hh\:mm",
            System.Globalization.CultureInfo.InvariantCulture, out var t) ? t : respaldo;

    /// <summary>Duración que toca ese día: la excepción si la hay, y si no la general.</summary>
    public TimeSpan DuracionDe(DayOfWeek dia) =>
        DuracionPorDia.TryGetValue(dia.ToString(), out var m) && m >= 1
            ? TimeSpan.FromMinutes(Math.Clamp(m, 1, 24 * 60))
            : Duracion;

    /// <summary>Opción de pausa correspondiente, o Ausente si lo guardado ya no existe.</summary>
    [JsonIgnore]
    public OpcionPresencia Pausa =>
        Array.Find(OpcionPresencia.ParaPausa, o => o.Disponibilidad == PausaDisponibilidad)
        ?? OpcionPresencia.ParaPausa[0];

    // Propiedad y no campo estático: Rutas.Carpeta puede redirigirse en el arranque, y un
    // inicializador estático la capturaría antes de que Program.Main llegue a hacerlo.
    private static string Fichero => Path.Combine(Rutas.Carpeta, "ajustes.json");

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

    /// <param name="sellar">
    /// Marca la fecha de cambio. Va a <c>false</c> cuando se está adoptando lo que vino de otro
    /// equipo: si se sellara, este equipo parecería el autor del cambio y ganaría siempre el
    /// siguiente conflicto.
    /// </param>
    public void Guardar(bool sellar = true)
    {
        if (sellar) Actualizado = DateTimeOffset.UtcNow;

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
    private static string? _carpeta;

    /// <summary>
    /// Carpeta de datos. Se puede redirigir con <c>--datos &lt;ruta&gt;</c>, que es lo que permite
    /// simular dos equipos distintos en una sola máquina para probar la sincronización.
    /// </summary>
    public static string Carpeta => _carpeta ??= Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "MiJornada");

    /// <summary>Debe llamarse en <c>Program.Main</c>, antes de tocar estado o ajustes.</summary>
    public static void Redirigir(string ruta)
    {
        _carpeta = Path.GetFullPath(ruta);
        Directory.CreateDirectory(_carpeta);
    }
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
    /// <summary>Formato del documento. Permite cambiarlo sin romper equipos desactualizados.</summary>
    public int Esquema { get; set; } = 1;

    public EstadoJornada Situacion { get; set; } = EstadoJornada.SinFichar;

    // DateTimeOffset y no DateTime: el estado viaja entre equipos, y una hora sin desfase es
    // ambigua. Los estado.json ya escritos llevan el desfase, así que deserializan sin pérdida.
    public DateTimeOffset? Fin { get; set; }
    public DateTimeOffset? PausaDesde { get; set; }

    /// <summary>
    /// Cuándo se fichó. No se puede deducir de <see cref="Fin"/>, porque cada pausa lo desplaza:
    /// sin este campo, una jornada con pausas mentiría sobre la hora de entrada. Hace falta para
    /// el histórico (M17). <c>null</c> en estados escritos antes de existir el campo.
    /// </summary>
    public DateTimeOffset? Inicio { get; set; }

    /// <summary>Minutos acumulados en pausa, que se suman al reanudar. Para el histórico.</summary>
    public int MinutosPausados { get; set; }

    /// <summary>
    /// Duración con la que arrancó ESTA jornada, en minutos. Se guarda aquí y no se recalcula
    /// de los ajustes para que el anillo sea correcto aunque la duración cambie a mitad —o
    /// aunque la jornada la iniciara otro equipo con otra configuración—. 0 = desconocida
    /// (estados escritos antes de existir este campo): en ese caso se usa Config.Jornada.
    /// </summary>
    public int DuracionMinutos { get; set; }

    /// <summary>Equipo que hizo el último cambio, para poder decir "iniciada en PORTATIL-HUGO".</summary>
    public string? Dispositivo { get; set; }

    /// <summary>Momento del último cambio, en UTC. Al resolver conflictos, gana el más reciente.</summary>
    public DateTimeOffset? Actualizado { get; set; }

    /// <summary>Cierto si el último cambio lo hizo este equipo.</summary>
    [JsonIgnore]
    public bool EsDeEsteEquipo =>
        Dispositivo is null || string.Equals(Dispositivo, Environment.MachineName,
                                             StringComparison.OrdinalIgnoreCase);

    [JsonIgnore]
    public TimeSpan Restante
    {
        get
        {
            if (Fin is null) return TimeSpan.Zero;
            var referencia = Situacion == EstadoJornada.Pausada && PausaDesde is not null
                ? PausaDesde.Value
                : DateTimeOffset.Now;
            var queda = Fin.Value - referencia;
            return queda > TimeSpan.Zero ? queda : TimeSpan.Zero;
        }
    }

    /// <summary>Duración de referencia del anillo: la de esta jornada, no la configurada hoy.</summary>
    [JsonIgnore]
    public TimeSpan DuracionJornada =>
        DuracionMinutos >= 1 ? TimeSpan.FromMinutes(DuracionMinutos) : Config.Jornada;

    [JsonIgnore]
    public double Fraccion =>
        DuracionJornada.TotalSeconds <= 0
            ? 0
            : Math.Clamp(Restante.TotalSeconds / DuracionJornada.TotalSeconds, 0, 1);

    // ---------------------------------------------------------------- persistencia

    private static string Fichero => Path.Combine(Rutas.Carpeta, "estado.json");

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

    /// <param name="sellar">
    /// Marca este equipo y la hora como autores del cambio. Va a <c>false</c> al adoptar lo que
    /// vino de otro equipo: si se sellara, este equipo pasaría por autor y ganaría siempre el
    /// conflicto siguiente, además de mentir en el "iniciada en ...".
    /// </param>
    public void Guardar(bool sellar = true)
    {
        if (sellar)
        {
            Dispositivo = Environment.MachineName;
            Actualizado = DateTimeOffset.UtcNow;
        }

        Directory.CreateDirectory(Rutas.Carpeta);
        File.WriteAllText(Fichero, JsonSerializer.Serialize(this,
            new JsonSerializerOptions { WriteIndented = true }));
    }

    /// <summary>Copia los valores de otro estado (el que vino de Graph) sobre este.</summary>
    public void Adoptar(Estado otro)
    {
        Esquema = otro.Esquema;
        Situacion = otro.Situacion;
        DuracionMinutos = otro.DuracionMinutos;
        Fin = otro.Fin;
        PausaDesde = otro.PausaDesde;
        Inicio = otro.Inicio;
        MinutosPausados = otro.MinutosPausados;
        Dispositivo = otro.Dispositivo;
        Actualizado = otro.Actualizado;
        Guardar(sellar: false);
    }

    public void Limpiar()
    {
        Situacion = EstadoJornada.SinFichar;
        Fin = null;
        PausaDesde = null;
        Inicio = null;
        MinutosPausados = 0;
        Guardar();
    }
}
