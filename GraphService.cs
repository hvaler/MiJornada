using System.Diagnostics;
using System.Net;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text;
using Microsoft.Identity.Client;
using Microsoft.Identity.Client.Extensions.Msal;

namespace MiJornada;

/// <summary>Respuesta cruda de Graph, con el eTag ya extraído.</summary>
/// <param name="Codigo">Código HTTP. 404 y 412 son respuestas esperadas, no errores.</param>
/// <param name="Cuerpo">Cuerpo de la respuesta, o cadena vacía.</param>
/// <param name="ETag">
/// eTag del recurso, con el formato literal que devuelve Graph (<c>"{GUID},N"</c>, comillas
/// incluidas). Hay que reenviarlo tal cual en <c>If-Match</c>.
/// </param>
public sealed record RespuestaGraph(HttpStatusCode Codigo, string Cuerpo, string? ETag)
{
    /// <summary>No hay token en caché y no se quiso pedir sesión interactiva.</summary>
    public static readonly RespuestaGraph SinSesion =
        new(HttpStatusCode.Unauthorized, "Sin sesión iniciada todavía.", null);

    public bool Correcta => (int)Codigo is >= 200 and < 300;

    /// <summary>Hace falta iniciar sesión: no es un fallo, solo aún no toca.</summary>
    public bool RequiereSesion => Codigo == HttpStatusCode.Unauthorized;

    /// <summary>El recurso no existe todavía. En la carpeta de aplicación es lo normal la
    /// primera vez, no un error.</summary>
    public bool NoExiste => Codigo == HttpStatusCode.NotFound;

    /// <summary>Otro equipo escribió antes que nosotros (<c>If-Match</c> no coincidió).</summary>
    public bool Conflicto => Codigo == HttpStatusCode.PreconditionFailed;
}

/// <summary>
/// Cliente de Microsoft Graph de la aplicación: autenticación, presencia de Teams y la carpeta
/// de aplicación de OneDrive donde se comparte el estado entre equipos.
/// </summary>
public class GraphService
{
    private const string Base = "https://graph.microsoft.com/v1.0/";

    private readonly IPublicClientApplication _app;
    private readonly HttpClient _http = new();
    private readonly Action<string, string> _mostrarCodigo;
    private bool _cacheRegistrada;

    /// <param name="mostrarCodigo">
    /// Qué hacer con el código de dispositivo (código, url). Va en el constructor y no en cada
    /// llamada porque ahora hay varias operaciones de Graph y repetirlo en todas las firmas
    /// sería ruido.
    /// </param>
    public GraphService(Action<string, string> mostrarCodigo)
    {
        _mostrarCodigo = mostrarCodigo;

        _app = PublicClientApplicationBuilder
            .Create(Config.ClientId)
            .WithAuthority(AzureCloudInstance.AzurePublic, Config.TenantId)
            .WithDefaultRedirectUri()
            .Build();
    }

    // ------------------------------------------------------------------ autenticación

    /// <summary>
    /// Cachea el token en disco (cifrado con DPAPI) para no pedir el código
    /// de dispositivo en cada arranque.
    /// </summary>
    private async Task RegistrarCacheAsync()
    {
        if (_cacheRegistrada) return;

        Directory.CreateDirectory(Rutas.Carpeta);

        var propiedades = new StorageCreationPropertiesBuilder("msal.cache", Rutas.Carpeta).Build();
        var helper = await MsalCacheHelper.CreateAsync(propiedades);
        helper.RegisterCache(_app.UserTokenCache);

        _cacheRegistrada = true;
    }

    /// <summary>
    /// Token sin molestar al usuario, o <c>null</c> si haría falta iniciar sesión.
    /// Lo usa la sincronización de fondo: abrir la ventana no debe pedir un código de
    /// dispositivo — la autenticación interactiva se la gana una acción del usuario.
    /// </summary>
    private async Task<string?> ObtenerTokenSilenciosoAsync()
    {
        await RegistrarCacheAsync();

        var cuentas = await _app.GetAccountsAsync();
        var cuenta = cuentas.FirstOrDefault();
        if (cuenta is null) return null;

        try
        {
            var r = await _app.AcquireTokenSilent(Config.Scopes, cuenta).ExecuteAsync();
            return r.AccessToken;
        }
        catch (MsalUiRequiredException)
        {
            return null;
        }
    }

    private async Task<string> ObtenerTokenAsync()
    {
        await RegistrarCacheAsync();

        var cuentas = await _app.GetAccountsAsync();
        var cuenta = cuentas.FirstOrDefault();

        if (cuenta is not null)
        {
            try
            {
                var silencioso = await _app.AcquireTokenSilent(Config.Scopes, cuenta).ExecuteAsync();
                return silencioso.AccessToken;
            }
            catch (MsalUiRequiredException)
            {
                // El refresh token caducó, o se ha añadido un scope nuevo: MSAL cachea por
                // conjunto de scopes, así que ampliar Config.Scopes invalida el token silencioso
                // y obliga a un consentimiento nuevo. Se vuelve a pedir abajo.
            }
        }

        // Flujo de código de dispositivo. El interactivo normal falla en este
        // tenant con "Error response came from MDM terms of use page" por las
        // políticas de acceso condicional en equipos no gestionados.
        var resultado = await _app.AcquireTokenWithDeviceCode(Config.Scopes, info =>
        {
            _mostrarCodigo(info.UserCode, info.VerificationUrl);
            return Task.CompletedTask;
        }).ExecuteAsync();

        return resultado.AccessToken;
    }

    /// <summary>Devuelve el object ID del usuario autenticado, sin llamadas extra.</summary>
    private async Task<string> ObtenerObjectIdAsync()
    {
        // Registrar la caché ANTES de preguntar por las cuentas. Sin esto MSAL mira una caché
        // en blanco —la de disco ni se ha leído— y responde que no hay ninguna cuenta, aunque
        // la haya. Es idempotente, así que llamarlo aquí no cuesta nada.
        //
        // Faltaba, y el fallo estuvo oculto detrás de la sincronización: como
        // SincronizarEntreEquipos viene activado, la sincronización del arranque pasaba por la
        // ruta del token y registraba la caché de rebote. Con la sincronización desactivada
        // —que es un ajuste normal— pulsar "Iniciar jornada" fallaba con "No hay ninguna cuenta
        // autenticada". También había carrera con la sincronización activada, si se pulsaba
        // antes de que terminara.
        await RegistrarCacheAsync();

        var cuentas = await _app.GetAccountsAsync();
        var cuenta = cuentas.FirstOrDefault()
            ?? throw new InvalidOperationException("No hay ninguna cuenta autenticada.");
        return cuenta.HomeAccountId.ObjectId;
    }

    // ------------------------------------------------------------------ llamada genérica

    /// <summary>
    /// Llama a Graph y devuelve la respuesta sin lanzar por códigos de error: quien llama decide
    /// qué es un fallo. Un 404 al leer el estado compartido significa "primera vez" y un 412
    /// significa "otro equipo se adelantó"; ninguno de los dos es una excepción.
    /// </summary>
    /// <param name="rutaRelativa">Ruta sin el prefijo <c>https://graph.microsoft.com/v1.0/</c>.</param>
    /// <param name="soloSilencioso">
    /// Si es cierto y no hay token en caché, devuelve <see cref="RespuestaGraph.SinSesion"/> en
    /// lugar de lanzar el código de dispositivo. Para todo lo que ocurre de fondo.
    /// </param>
    public async Task<RespuestaGraph> LlamarAsync(
        HttpMethod metodo,
        string rutaRelativa,
        HttpContent? contenido = null,
        string? ifMatch = null,
        bool soloSilencioso = false)
    {
        string? token;
        if (soloSilencioso)
        {
            token = await ObtenerTokenSilenciosoAsync();
            if (token is null) return RespuestaGraph.SinSesion;
        }
        else
        {
            token = await ObtenerTokenAsync();
        }

        using var peticion = new HttpRequestMessage(metodo, Base + rutaRelativa);
        peticion.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        if (contenido is not null) peticion.Content = contenido;

        // TryAddWithoutValidation: el eTag de Graph lleva llaves y comillas, y el validador
        // de cabeceras de .NET lo rechaza como ETag mal formado.
        if (!string.IsNullOrEmpty(ifMatch))
            peticion.Headers.TryAddWithoutValidation("If-Match", ifMatch);

        using var respuesta = await _http.SendAsync(peticion);
        var cuerpo = respuesta.Content is null
            ? string.Empty
            : await respuesta.Content.ReadAsStringAsync();

        var etag = respuesta.Headers.ETag?.ToString();
        return new RespuestaGraph(respuesta.StatusCode, cuerpo, etag);
    }

    /// <summary>Como <see cref="LlamarAsync"/>, pero lanza si la respuesta no es correcta.</summary>
    public async Task<RespuestaGraph> LlamarOLanzarAsync(
        HttpMethod metodo,
        string rutaRelativa,
        HttpContent? contenido = null,
        string? ifMatch = null)
    {
        var r = await LlamarAsync(metodo, rutaRelativa, contenido, ifMatch);
        if (!r.Correcta)
            throw new HttpRequestException($"Graph devolvió {(int)r.Codigo} {r.Codigo}. {r.Cuerpo}");
        return r;
    }

    // ------------------------------------------------------------------ presencia

    /// <param name="disponibilidad">Available, Busy, DoNotDisturb, BeRightBack, Away, Offline</param>
    /// <param name="actividad">Available, Busy, DoNotDisturb, BeRightBack, Away, OffWork</param>
    public async Task EstablecerPresenciaAsync(string disponibilidad, string actividad)
    {
        var objectId = await ObtenerObjectIdAsync();

        // Importante: la ruta /me/presence/setUserPreferredPresence devuelve 404
        // con cuerpo vacío. Hay que usar la ruta con el object ID explícito.
        var ruta = $"users/{objectId}/presence/setUserPreferredPresence";

        var cuerpo = new StringContent(
            $$"""{"availability":"{{disponibilidad}}","activity":"{{actividad}}"}""",
            Encoding.UTF8, "application/json");

        await LlamarOLanzarAsync(HttpMethod.Post, ruta, cuerpo);
    }

    /// <summary>
    /// Quita la presencia preferida y devuelve el mando a Teams, que vuelve a calcularla sola
    /// (Disponible si estás activo, Ausente si no...).
    ///
    /// <para><b>No es lo mismo que poner <c>Offline</c>/<c>OffWork</c>.</b> Establecer una
    /// presencia la deja <b>fijada</b>: Teams no vuelve a tocarla, aunque estés teclando. Es lo
    /// correcto al terminar la jornada —quieres que se te vea fuera del trabajo hasta mañana—
    /// pero no al cancelar, donde lo que quieres es que la aplicación deje de opinar.</para>
    /// </summary>
    public async Task LimpiarPresenciaAsync()
    {
        var objectId = await ObtenerObjectIdAsync();

        // Mismo motivo que en EstablecerPresenciaAsync: con /me/... da 404.
        var ruta = $"users/{objectId}/presence/clearUserPreferredPresence";

        // Graph exige cuerpo JSON aunque no lleve datos; sin él responde 400.
        var cuerpo = new StringContent("{}", Encoding.UTF8, "application/json");

        await LlamarOLanzarAsync(HttpMethod.Post, ruta, cuerpo);
    }

    // ------------------------------------------------------------------ utilidades

    public static void AbrirNavegador(string url) =>
        Process.Start(new ProcessStartInfo(url) { UseShellExecute = true });
}
