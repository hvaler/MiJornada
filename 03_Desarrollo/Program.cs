namespace MiJornada;

internal static class Program
{
    [STAThread]
    private static void Main(string[] args)
    {
        // Permite probar sin esperar siete horas:  MiJornada.exe --minutos 2
        var i = Array.IndexOf(args, "--minutos");
        if (i >= 0 && i + 1 < args.Length && double.TryParse(args[i + 1], out var minutos))
            Config.Jornada = TimeSpan.FromMinutes(minutos);

        ApplicationConfiguration.Initialize();
        Application.Run(new MainForm());
    }
}
