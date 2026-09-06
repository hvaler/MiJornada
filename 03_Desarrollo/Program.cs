namespace MiJornada;

internal static class Program
{
    [STAThread]
    private static void Main(string[] args)
    {
        // La duración habitual sale de los ajustes del usuario...
        Config.Jornada = Ajustes.Cargar().Duracion;

        // ...pero --minutos N manda sobre ella, para poder probar sin tocar los ajustes:
        //    MiJornada.exe --minutos 2
        var i = Array.IndexOf(args, "--minutos");
        if (i >= 0 && i + 1 < args.Length && double.TryParse(args[i + 1], out var minutos) && minutos > 0)
        {
            Config.Jornada = TimeSpan.FromMinutes(minutos);
            Config.JornadaForzada = true;
        }

        ApplicationConfiguration.Initialize();
        Application.Run(new MainForm());
    }
}
