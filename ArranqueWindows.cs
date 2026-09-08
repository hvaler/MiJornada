using System.Diagnostics;

namespace MiJornada;

/// <summary>
/// Arranque con Windows mediante un acceso directo en la carpeta de Inicio del usuario.
///
/// <para>Se usa la carpeta de Inicio y no la clave <c>Run</c> del registro a propósito: es
/// visible e inspeccionable (el usuario puede ver el acceso directo, moverlo o borrarlo), no
/// requiere permisos especiales, y Windows la muestra en el Administrador de tareas junto al
/// resto de aplicaciones de inicio, donde se puede desactivar. Escribir en el registro sería
/// igual de eficaz y bastante más opaco.</para>
///
/// <para><b>Importa para el fichaje automático</b>: si la aplicación no está corriendo, nadie
/// escucha el desbloqueo de sesión. Sin esto, el automatismo obliga a abrirla a mano — justo lo
/// que venía a evitar.</para>
/// </summary>
public static class ArranqueWindows
{
    private const string NombreAcceso = "Mi jornada.lnk";

    private static string Ruta => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.Startup), NombreAcceso);

    public static bool Activo => File.Exists(Ruta);

    /// <summary>
    /// Crea o borra el acceso directo. Devuelve <c>null</c> si fue bien, o el mensaje de error.
    /// No lanza: que falle esto no puede impedir guardar el resto de ajustes.
    /// </summary>
    public static string? Establecer(bool activar, bool minimizado)
    {
        try
        {
            if (!activar)
            {
                if (File.Exists(Ruta)) File.Delete(Ruta);
                return null;
            }

            var exe = Environment.ProcessPath;
            if (string.IsNullOrEmpty(exe))
                return "No se pudo determinar la ruta del ejecutable.";

            CrearAccesoDirecto(Ruta, exe, minimizado ? "--minimizado" : string.Empty);
            return null;
        }
        catch (Exception ex)
        {
            return ex.Message;
        }
    }

    /// <summary>
    /// Crea el .lnk con el Windows Script Host por COM tardío. Es la forma de hacerlo sin
    /// añadir una dependencia (COMReference o una librería de terceros) a un proyecto que hoy
    /// solo tiene dos paquetes.
    /// </summary>
    private static void CrearAccesoDirecto(string destino, string exe, string argumentos)
    {
        var tipo = Type.GetTypeFromProgID("WScript.Shell")
            ?? throw new InvalidOperationException("WScript.Shell no está disponible.");

        dynamic shell = Activator.CreateInstance(tipo)!;
        try
        {
            dynamic acceso = shell.CreateShortcut(destino);
            acceso.TargetPath = exe;
            acceso.Arguments = argumentos;
            acceso.WorkingDirectory = Path.GetDirectoryName(exe) ?? string.Empty;
            acceso.Description = "Controla tu presencia de Teams";
            acceso.IconLocation = exe + ",0";
            acceso.Save();
        }
        finally
        {
            System.Runtime.InteropServices.Marshal.FinalReleaseComObject(shell);
        }
    }

    /// <summary>Abre la carpeta de Inicio, para que el usuario pueda ver o quitar el acceso.</summary>
    public static void AbrirCarpeta() =>
        Process.Start(new ProcessStartInfo(
            Environment.GetFolderPath(Environment.SpecialFolder.Startup))
        { UseShellExecute = true });
}
