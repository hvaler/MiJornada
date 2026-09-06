using System.Net.Http;
using System.Text;
using System.Text.Json;

namespace MiJornada;

/// <summary>Resultado de traer el estado compartido.</summary>
public enum ResultadoLectura
{
    /// <summary>No se pudo hablar con Graph. Se sigue con el fichero local.</summary>
    SinConexion,
    /// <summary>No hay sesión iniciada todavía. No es un fallo: la primera acción del usuario
    /// la abrirá. La sincronización de fondo nunca pide un código de dispositivo.</summary>
    SinSesion,
    /// <summary>No hay nada compartido todavía, o lo remoto es más viejo que lo local.</summary>
    LocalManda,
    /// <summary>Lo remoto era más reciente y se ha adoptado.</summary>
    AdoptadoRemoto,
    /// <summary>La sincronización está desactivada en los ajustes.</summary>
    Desactivada,
}

/// <summary>
/// Comparte estado y ajustes entre equipos usando la carpeta de aplicación de OneDrive.
///
/// <para><b>El fichero local sigue siendo el almacén de trabajo; esto es solo una capa de
/// sincronización.</b> Ninguna operación de aquí puede tirar el proceso ni parar la cuenta
/// atrás: todas devuelven un resultado en vez de lanzar. La razón es concreta — la cuenta atrás
/// corre en un temporizador de un segundo y hay manejadores <c>async void</c> en las rutas de
/// cancelar y de finalizar; una excepción de red por ahí mataría el proceso, y con él la
/// jornada, que es justo lo que la aplicación existe para evitar.</para>
/// </summary>
public class SincronizacionGraph
{
    // El permiso Files.ReadWrite.AppFolder solo alcanza a esta carpeta: Aplicaciones/Mi jornada.
    private const string RutaEstado = "me/drive/special/approot:/estado.json:/content";
    private const string RutaAjustes = "me/drive/special/approot:/ajustes.json:/content";

    private static readonly JsonSerializerOptions Json = new() { WriteIndented = true };

    private readonly GraphService _graph;

    private string? _etagEstado;
    private string? _etagAjustes;

    public SincronizacionGraph(GraphService graph) => _graph = graph;

    /// <summary>Hay cambios locales que no se han podido subir. La interfaz lo muestra.</summary>
    public bool Pendiente { get; private set; }

    /// <summary>Último error de sincronización, para el indicador y el diagnóstico.</summary>
    public string? UltimoError { get; private set; }

    /// <summary>Cierto si alguna vez se ha completado una sincronización en esta ejecución.</summary>
    public bool AlgunaVezCorrecta { get; private set; }

    // ------------------------------------------------------------------ estado

    /// <summary>
    /// Trae el estado compartido y, si es más reciente que el local, lo adopta.
    /// </summary>
    public async Task<ResultadoLectura> TraerEstadoAsync(Estado local, Ajustes ajustes)
    {
        if (!ajustes.SincronizarEntreEquipos) return ResultadoLectura.Desactivada;

        try
        {
            var r = await _graph.LlamarAsync(HttpMethod.Get, RutaEstado, soloSilencioso: true);

            if (r.RequiereSesion) return ResultadoLectura.SinSesion;

            if (r.NoExiste)
            {
                // Primera vez: no hay nada compartido. Lo local pasa a ser la referencia.
                _etagEstado = null;
                AlgunaVezCorrecta = true;
                UltimoError = null;
                return ResultadoLectura.LocalManda;
            }

            if (!r.Correcta)
            {
                Anotar($"Graph devolvió {(int)r.Codigo} al leer el estado.");
                return ResultadoLectura.SinConexion;
            }

            _etagEstado = r.ETag;
            AlgunaVezCorrecta = true;
            UltimoError = null;

            var remoto = JsonSerializer.Deserialize<Estado>(r.Cuerpo);
            if (remoto is null) return ResultadoLectura.LocalManda;

            // Gana el más reciente. Con un solo usuario es correcto: no haces cosas
            // contradictorias en dos equipos en el mismo segundo.
            if (remoto.Actualizado is null) return ResultadoLectura.LocalManda;
            if (local.Actualizado is not null && local.Actualizado >= remoto.Actualizado)
                return ResultadoLectura.LocalManda;

            local.Adoptar(remoto);
            return ResultadoLectura.AdoptadoRemoto;
        }
        catch (Exception ex)
        {
            Anotar(ex.Message);
            return ResultadoLectura.SinConexion;
        }
    }

    /// <summary>
    /// Publica el estado local. Si otro equipo escribió antes (412), relee y deja que gane el
    /// más reciente en la próxima lectura, sin machacar su cambio a ciegas.
    /// </summary>
    public async Task PublicarEstadoAsync(Estado local, Ajustes ajustes)
    {
        if (!ajustes.SincronizarEntreEquipos) return;

        try
        {
            var r = await Subir(RutaEstado, local, _etagEstado);

            if (r.RequiereSesion) return;   // aún sin sesión: no es un fallo que anotar

            if (r.Conflicto)
            {
                // Otro equipo se adelantó. Se relee para quedarse con su eTag y su estado;
                // TraerEstadoAsync decidirá quién gana por fecha.
                Anotar("Otro equipo escribió antes; se reintentará en la próxima lectura.");
                await TraerEstadoAsync(local, ajustes);
                return;
            }

            if (!r.Correcta)
            {
                Anotar($"Graph devolvió {(int)r.Codigo} al publicar el estado.");
                return;
            }

            _etagEstado = r.ETag;
            Pendiente = false;
            AlgunaVezCorrecta = true;
            UltimoError = null;
        }
        catch (Exception ex)
        {
            Anotar(ex.Message);
        }
    }

    // ------------------------------------------------------------------ ajustes

    /// <summary>
    /// Trae los ajustes compartidos. Sin la ceremonia del estado: los ajustes cambian poco y
    /// aquí basta con que gane el último.
    /// </summary>
    public async Task<bool> TraerAjustesAsync(Ajustes local)
    {
        if (!local.SincronizarEntreEquipos) return false;

        try
        {
            var r = await _graph.LlamarAsync(HttpMethod.Get, RutaAjustes, soloSilencioso: true);
            if (r.RequiereSesion) return false;
            if (r.NoExiste) { _etagAjustes = null; return false; }
            if (!r.Correcta) { Anotar($"Graph devolvió {(int)r.Codigo} al leer los ajustes."); return false; }

            _etagAjustes = r.ETag;
            var remoto = JsonSerializer.Deserialize<Ajustes>(r.Cuerpo);
            if (remoto?.Actualizado is null) return false;
            if (local.Actualizado is not null && local.Actualizado >= remoto.Actualizado) return false;

            local.DuracionMinutos = remoto.DuracionMinutos;
            local.PausaDisponibilidad = remoto.PausaDisponibilidad;
            local.FicharAlDesbloquear = remoto.FicharAlDesbloquear;
            local.UltimoAutoFichaje = remoto.UltimoAutoFichaje;
            local.AvisoMinutos = remoto.AvisoMinutos;
            local.Actualizado = remoto.Actualizado;
            // NO se copian los ajustes per-equipo:
            //  - SincronizarEntreEquipos: la decisión de este equipo sobre si participar;
            //    traerla de fuera permitiría que otro equipo lo desactivara aquí.
            //  - ArrancarMinimizado: acompaña al acceso directo de la carpeta de Inicio de
            //    ESTA máquina. Copiarlo describiría un arranque que en el otro equipo no existe.
            local.Guardar(sellar: false);
            return true;
        }
        catch (Exception ex)
        {
            Anotar(ex.Message);
            return false;
        }
    }

    public async Task PublicarAjustesAsync(Ajustes local)
    {
        if (!local.SincronizarEntreEquipos) return;

        try
        {
            var r = await Subir(RutaAjustes, local, _etagAjustes);
            if (r.RequiereSesion) return;
            if (r.Conflicto)
            {
                await TraerAjustesAsync(local);
                return;
            }
            if (!r.Correcta) { Anotar($"Graph devolvió {(int)r.Codigo} al publicar los ajustes."); return; }

            _etagAjustes = r.ETag;
            AlgunaVezCorrecta = true;
        }
        catch (Exception ex)
        {
            Anotar(ex.Message);
        }
    }

    // ------------------------------------------------------------------ interno

    private Task<RespuestaGraph> Subir(string ruta, object contenido, string? etag)
    {
        var cuerpo = new StringContent(
            JsonSerializer.Serialize(contenido, Json), Encoding.UTF8, "application/json");

        // Sin eTag conocido no se manda If-Match: es el caso de la primera escritura, y
        // mandarlo vacío haría fallar la petición en vez de crear el fichero.
        return _graph.LlamarAsync(HttpMethod.Put, ruta, cuerpo, etag, soloSilencioso: true);
    }

    private void Anotar(string mensaje)
    {
        UltimoError = mensaje;
        Pendiente = true;
    }
}
