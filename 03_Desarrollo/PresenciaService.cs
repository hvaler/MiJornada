using System.Diagnostics;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text;
using Microsoft.Identity.Client;
using Microsoft.Identity.Client.Extensions.Msal;

namespace MiJornada;

/// <summary>
/// Cambia la presencia preferida del usuario en Teams a través de Microsoft Graph.
/// </summary>
public class PresenciaService
{
    private readonly IPublicClientApplication _app;
    private readonly HttpClient _http = new();
    private bool _cacheRegistrada;

    public PresenciaService()
    {
        _app = PublicClientApplicationBuilder
            .Create(Config.ClientId)
            .WithAuthority(AzureCloudInstance.AzurePublic, Config.TenantId)
            .WithDefaultRedirectUri()
            .Build();
    }

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

    private async Task<string> ObtenerTokenAsync(Action<string, string> mostrarCodigo)
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
                // El refresh token caducó: se vuelve a pedir abajo.
            }
        }

        // Flujo de código de dispositivo. El interactivo normal falla en este
        // tenant con "Error response came from MDM terms of use page" por las
        // políticas de acceso condicional en equipos no gestionados.
        var resultado = await _app.AcquireTokenWithDeviceCode(Config.Scopes, info =>
        {
            mostrarCodigo(info.UserCode, info.VerificationUrl);
            return Task.CompletedTask;
        }).ExecuteAsync();

        return resultado.AccessToken;
    }

    /// <summary>Devuelve el object ID del usuario autenticado, sin llamadas extra.</summary>
    private async Task<string> ObtenerObjectIdAsync()
    {
        var cuentas = await _app.GetAccountsAsync();
        var cuenta = cuentas.FirstOrDefault()
            ?? throw new InvalidOperationException("No hay ninguna cuenta autenticada.");
        return cuenta.HomeAccountId.ObjectId;
    }

    /// <param name="disponibilidad">Available, Busy, DoNotDisturb, BeRightBack, Away, Offline</param>
    /// <param name="actividad">Available, Busy, DoNotDisturb, BeRightBack, Away, OffWork</param>
    public async Task EstablecerAsync(string disponibilidad, string actividad,
                                      Action<string, string> mostrarCodigo)
    {
        var token = await ObtenerTokenAsync(mostrarCodigo);
        var objectId = await ObtenerObjectIdAsync();

        // Importante: la ruta /me/presence/setUserPreferredPresence devuelve 404
        // con cuerpo vacío. Hay que usar la ruta con el object ID explícito.
        var uri = $"https://graph.microsoft.com/v1.0/users/{objectId}/presence/setUserPreferredPresence";

        using var peticion = new HttpRequestMessage(HttpMethod.Post, uri);
        peticion.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        peticion.Content = new StringContent(
            $$"""{"availability":"{{disponibilidad}}","activity":"{{actividad}}"}""",
            Encoding.UTF8, "application/json");

        using var respuesta = await _http.SendAsync(peticion);

        if (!respuesta.IsSuccessStatusCode)
        {
            var cuerpo = await respuesta.Content.ReadAsStringAsync();
            throw new HttpRequestException(
                $"Graph devolvió {(int)respuesta.StatusCode} {respuesta.ReasonPhrase}. {cuerpo}");
        }
    }

    public static void AbrirNavegador(string url) =>
        Process.Start(new ProcessStartInfo(url) { UseShellExecute = true });
}
