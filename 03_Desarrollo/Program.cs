namespace MiJornada;

internal static class Program
{
    [STAThread]
    private static void Main(string[] args)
    {
        // --datos <ruta> redirige la carpeta de datos. Va PRIMERO, antes de tocar ajustes o
        // estado: permite levantar dos instancias con datos separados en una sola máquina y así
        // probar la sincronización entre equipos sin necesitar dos equipos.
        var d = Array.IndexOf(args, "--datos");
        if (d >= 0 && d + 1 < args.Length)
            Rutas.Redirigir(args[d + 1]);

        // La duración habitual sale de los ajustes del usuario...
        // Duracion del dia de hoy: puede haber una excepcion configurada para este dia.
        Config.Jornada = Ajustes.Cargar().DuracionDe(DateTimeOffset.Now.DayOfWeek);

        // ...pero --minutos N manda sobre ella, para poder probar sin tocar los ajustes:
        //    MiJornada.exe --minutos 2
        var i = Array.IndexOf(args, "--minutos");
        if (i >= 0 && i + 1 < args.Length && double.TryParse(args[i + 1], out var minutos) && minutos > 0)
        {
            Config.Jornada = TimeSpan.FromMinutes(minutos);
            Config.JornadaForzada = true;
        }

        // Lo pone el acceso directo de la carpeta de Inicio. Abrir la app a mano no lo lleva,
        // asi que un arranque manual siempre muestra la ventana.
        Config.ArrancarMinimizado = args.Contains("--minimizado");

        ApplicationConfiguration.Initialize();
        Application.Run(new MainForm());
    }
}
