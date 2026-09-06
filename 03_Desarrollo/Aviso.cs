using System.Diagnostics;
using System.Drawing.Drawing2D;
using System.Globalization;
using System.Runtime.InteropServices;

namespace MiJornada;

/// <summary>
/// Aviso propio en la esquina inferior derecha: una tarjeta que entra deslizándose, se lee de un
/// vistazo y se va sola.
///
/// <para><b>Por qué no un globo de bandeja.</b> <c>NotifyIcon.ShowBalloonTip</c> era lo obvio y
/// resultó ser lo inservible: con <b>No molestar</b> activado, Windows no aplaza esos globos, los
/// <b>descarta</b> — no aparecen y <b>tampoco quedan en el centro de notificaciones</b>. Verificado
/// en este equipo, y descartado que fuera cosa del código reproduciéndolo con un
/// <c>NotifyIcon</c> suelto. Como No molestar suele estar puesto justo cuando más se usa la
/// aplicación (reuniones, pantalla compartida), el mensaje no se vería casi nunca. Ver TEC-016.</para>
///
/// <para>Esta ventana es de la aplicación, así que no pasa por el filtro del sistema. No es una
/// forma de colarse: el aviso lo pide el propio usuario al fichar, dura segundos, no suena y
/// <b>no roba el foco</b> (<see cref="ShowWithoutActivation"/> más <c>WS_EX_NOACTIVATE</c>), que
/// es la otra mitad de "no bloqueante".</para>
///
/// <para><b>Qué lo hace visible de un vistazo</b>, que es distinto de "grande": una banda de color
/// saturado a la izquierda con el emoji a tamaño de icono —lo que el ojo pilla antes de leer
/// nada—, el mensaje en cuerpo grande, y una entrada deslizante que llama la atención por
/// movimiento. La barra inferior que se vacía dice cuánto le queda en pantalla, para que no
/// parezca que se ha ido sola.</para>
/// </summary>
public sealed class Aviso : Form
{
    private const int Ancho = 420;
    private const int Banda = 96;        // franja de color con el emoji
    private const int AltoMinimo = 104;
    private const int Margen = 16;       // hasta el borde del área de trabajo
    private const int Relleno = 18;
    private const int Separacion = 10;   // entre tarjetas apiladas
    private const int Barra = 5;         // grosor de la barra de tiempo

    private const int MsEntrada = 260;
    private const int MsSalida = 320;
    private const int Deslizamiento = 64;   // px que recorre al entrar

    private static readonly Color Papel = Color.FromArgb(252, 252, 253);
    private static readonly Color Tinta = Color.FromArgb(28, 27, 38);
    private static readonly Color Gris = Color.FromArgb(112, 110, 122);

    /// <summary>Las que están en pantalla, para poder apilarlas.</summary>
    private static readonly List<Aviso> Abiertos = [];

    private readonly string _glifo;
    private readonly string _titulo;
    private readonly string _mensaje;
    private readonly Color _acento;
    private readonly Action? _alPulsar;
    private readonly int _duracion;

    private readonly Font _fGlifo = new("Segoe UI Emoji", 30f);
    private readonly Font _fTitulo = new("Segoe UI", 9f, FontStyle.Bold);
    private readonly Font _fMensaje = new("Segoe UI Emoji", 12f);

    private readonly Rectangle _rTitulo;
    private readonly Rectangle _rMensaje;

    private readonly System.Windows.Forms.Timer _animacion = new();
    private readonly Stopwatch _reloj = Stopwatch.StartNew();
    private Fase _fase = Fase.Entrando;
    private Point _destino;
    private double _fraccionBarra = 1.0;

    private enum Fase { Entrando, Esperando, Saliendo }

    // TextRenderer (GDI) mide y pinta igual, así que lo que se mide es lo que se ve. Con
    // Graphics.MeasureString habría que corregir a ojo la diferencia entre GDI y GDI+.
    private const TextFormatFlags Flags =
        TextFormatFlags.WordBreak | TextFormatFlags.NoPrefix | TextFormatFlags.NoPadding;

    private const TextFormatFlags FlagsGlifo =
        TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPrefix;

    private Aviso(string titulo, string mensaje, int milisegundos, Action? alPulsar, Color acento)
    {
        (_glifo, _mensaje) = Separar(mensaje);
        _titulo = titulo.ToUpperInvariant();   // el rótulo hace de etiqueta, no de frase
        _acento = acento;
        _alPulsar = alPulsar;
        _duracion = Math.Max(1500, milisegundos);

        var x = Banda + Relleno;
        var anchoTexto = Ancho - x - Relleno;

        // Se mide el texto real para dar a la tarjeta el alto que necesita (TEC-014): con alto
        // fijo, un mensaje largo se cortaría por abajo sin avisar.
        var altoTitulo = TextRenderer.MeasureText(_titulo, _fTitulo, new Size(anchoTexto, 0), Flags).Height;
        var altoMensaje = TextRenderer.MeasureText(_mensaje, _fMensaje, new Size(anchoTexto, 0), Flags).Height;

        var alto = Math.Max(AltoMinimo, Relleno + altoTitulo + 8 + altoMensaje + Relleno + Barra);
        var arriba = (alto - Barra - altoTitulo - 8 - altoMensaje) / 2;

        _rTitulo = new Rectangle(x, arriba, anchoTexto, altoTitulo);
        _rMensaje = new Rectangle(x, arriba + altoTitulo + 8, anchoTexto, altoMensaje);

        FormBorderStyle = FormBorderStyle.None;
        StartPosition = FormStartPosition.Manual;
        ShowInTaskbar = false;
        TopMost = true;
        BackColor = Papel;
        DoubleBuffered = true;
        ClientSize = new Size(Ancho, alto);
        Opacity = 0;
        Cursor = alPulsar is null ? Cursors.Default : Cursors.Hand;

        EsquinasRedondeadas();

        _animacion.Interval = 15;
        _animacion.Tick += Animar;

        Click += (_, _) => { _alPulsar?.Invoke(); Cerrar(); };
    }

    /// <summary>
    /// Muestra un aviso. <paramref name="alPulsar"/> es lo que ocurre si se hace clic en él
    /// (normalmente, abrir la ventana); si es <c>null</c>, el clic solo lo cierra.
    /// </summary>
    public static void Mostrar(string titulo, string mensaje, int milisegundos = 6000,
        Action? alPulsar = null, Color? acento = null)
    {
        var aviso = new Aviso(titulo, mensaje, milisegundos, alPulsar,
            acento ?? Color.FromArgb(91, 95, 199));

        Abiertos.Add(aviso);
        aviso.Colocar();

        // El struct se copia a una local antes de leer sus miembros: Form hereda de
        // MarshalByRefObject y acceder a `aviso._destino.X` desde fuera de la instancia
        // dispara CS1690.
        var destino = aviso._destino;
        aviso.Location = new Point(destino.X + Deslizamiento, destino.Y);

        aviso.Show();          // sin Activate: no roba el foco
        aviso._animacion.Start();
    }

    /// <summary>
    /// Separa el emoji inicial del texto. Se usa <see cref="StringInfo"/> y no <c>mensaje[0]</c>
    /// porque un emoji ocupa varios <c>char</c> (pares suplentes, selectores de variación); cortar
    /// por caracteres partiría el glifo por la mitad.
    ///
    /// <para>Los avisos funcionales ("La jornada está a punto de terminar") empiezan por letra y
    /// se quedan sin glifo: la banda de color aparece vacía, que es correcto.</para>
    /// </summary>
    private static (string glifo, string texto) Separar(string mensaje)
    {
        if (string.IsNullOrEmpty(mensaje)) return (string.Empty, string.Empty);

        var e = StringInfo.GetTextElementEnumerator(mensaje);
        if (!e.MoveNext()) return (string.Empty, mensaje);

        var primero = (string)e.Current;
        if (primero.Length == 0 || primero[0] < 128) return (string.Empty, mensaje);

        return (primero, mensaje[primero.Length..].TrimStart());
    }

    /// <summary>
    /// Abajo a la derecha del área de trabajo — que no es la pantalla: así queda por encima de
    /// la barra de tareas y no debajo. Si ya hay avisos, se apila hacia arriba.
    /// </summary>
    private void Colocar()
    {
        var zona = Screen.PrimaryScreen?.WorkingArea ?? new Rectangle(0, 0, 1024, 768);

        var alturaPrevia = 0;
        foreach (var otro in Abiertos)
            if (otro != this && !otro.IsDisposed)
                alturaPrevia += otro.Height + Separacion;

        _destino = new Point(
            zona.Right - Width - Margen,
            zona.Bottom - Height - Margen - alturaPrevia);
    }

    /// <summary>
    /// Un solo temporizador para las tres fases. La entrada usa una curva de desaceleración
    /// (cúbica) en lugar de un desplazamiento lineal: frenar al llegar es lo que hace que parezca
    /// que la tarjeta se posa en vez de chocar.
    /// </summary>
    private void Animar(object? sender, EventArgs e)
    {
        var t = _reloj.ElapsedMilliseconds;

        switch (_fase)
        {
            case Fase.Entrando:
                {
                    var p = Math.Min(1.0, t / (double)MsEntrada);
                    var suave = 1 - Math.Pow(1 - p, 3);
                    Opacity = suave;
                    Situar((int)(Deslizamiento * (1 - suave)));
                    if (p >= 1.0) Pasar(Fase.Esperando);
                    break;
                }

            case Fase.Esperando:
                {
                    _fraccionBarra = 1.0 - Math.Min(1.0, t / (double)_duracion);
                    Situar(0);
                    Invalidate(new Rectangle(0, Height - Barra, Width, Barra));
                    if (t >= _duracion) Pasar(Fase.Saliendo);
                    break;
                }

            case Fase.Saliendo:
                {
                    var p = Math.Min(1.0, t / (double)MsSalida);
                    Opacity = 1 - p;
                    Situar((int)(Deslizamiento * p * 0.6));
                    if (p >= 1.0) { _animacion.Stop(); Close(); }
                    break;
                }
        }
    }

    /// <summary>
    /// Coloca la ventana en su destino más el desplazamiento horizontal de la animación. La Y se
    /// persigue con una interpolación suave para que, al cerrarse una tarjeta de abajo, las de
    /// encima bajen deslizándose en vez de dar un salto.
    /// </summary>
    private void Situar(int desplazamiento)
    {
        var y = Location.Y + (int)Math.Round((_destino.Y - Location.Y) * 0.25);
        if (Math.Abs(_destino.Y - y) <= 1) y = _destino.Y;
        Location = new Point(_destino.X + desplazamiento, y);
    }

    private void Pasar(Fase siguiente)
    {
        _fase = siguiente;
        _reloj.Restart();
    }

    /// <summary>Salta al desvanecido, sea cual sea la fase actual.</summary>
    private void Cerrar()
    {
        if (_fase == Fase.Saliendo) return;
        Pasar(Fase.Saliendo);
    }

    /// <summary>
    /// Esquinas redondeadas al estilo de Windows 11. En Windows 10 la llamada falla y no pasa
    /// nada: se queda con esquinas rectas, que es como se ve todo lo demás en ese sistema.
    /// </summary>
    private void EsquinasRedondeadas()
    {
        try
        {
            var redondear = 2;   // DWMWCP_ROUND
            DwmSetWindowAttribute(Handle, 33, ref redondear, sizeof(int));
        }
        catch (DllNotFoundException) { }
        catch (EntryPointNotFoundException) { }
    }

    protected override bool ShowWithoutActivation => true;

    protected override CreateParams CreateParams
    {
        get
        {
            var p = base.CreateParams;
            p.ExStyle |= 0x08000000;    // WS_EX_NOACTIVATE: ni al pulsarla se lleva el foco
            p.ExStyle |= 0x00000080;    // WS_EX_TOOLWINDOW: fuera del Alt+Tab
            p.ClassStyle |= 0x00020000; // CS_DROPSHADOW: sombra, que despega la tarjeta del fondo
            return p;
        }
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        base.OnPaint(e);
        var g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;

        // Banda de color con degradado: es lo que hace que la tarjeta se lea a un metro. El
        // degradado es sutil a propósito — un plano liso se ve barato, y uno marcado, chillón.
        var banda = new Rectangle(0, 0, Banda, Height);
        using (var degradado = new LinearGradientBrush(
            banda, Aclarar(_acento, 0.18), Oscurecer(_acento, 0.10), LinearGradientMode.Vertical))
            g.FillRectangle(degradado, banda);

        if (_glifo.Length > 0)
            TextRenderer.DrawText(g, _glifo, _fGlifo, banda, Color.White, FlagsGlifo);

        TextRenderer.DrawText(g, _titulo, _fTitulo, _rTitulo, Oscurecer(_acento, 0.25), Flags);
        TextRenderer.DrawText(g, _mensaje, _fMensaje, _rMensaje, Tinta, Flags);

        // Barra de tiempo: dice cuánto le queda en pantalla. Sin ella, la tarjeta desaparece de
        // golpe y parece que se ha ido sola. Va a color pleno sobre un carril tenue: en la
        // primera versión era translúcida y de 4 px, y aunque estaba ahí (comprobado muestreando
        // píxeles) no se veía, con lo que no servía para nada.
        var carril = new Rectangle(Banda, Height - Barra, Width - Banda, Barra);
        using (var pincel = new SolidBrush(Color.FromArgb(38, _acento)))
            g.FillRectangle(pincel, carril);

        var ancho = (int)Math.Round(carril.Width * _fraccionBarra);
        if (ancho > 0)
            using (var pincel = new SolidBrush(_acento))
                g.FillRectangle(pincel, carril.X, carril.Y, ancho, carril.Height);

        using (var lapiz = new Pen(Color.FromArgb(60, Tinta)))
            g.DrawRectangle(lapiz, 0, 0, Width - 1, Height - 1);
    }

    private static Color Aclarar(Color c, double f) => Color.FromArgb(
        c.R + (int)((255 - c.R) * f), c.G + (int)((255 - c.G) * f), c.B + (int)((255 - c.B) * f));

    private static Color Oscurecer(Color c, double f) => Color.FromArgb(
        (int)(c.R * (1 - f)), (int)(c.G * (1 - f)), (int)(c.B * (1 - f)));

    protected override void OnFormClosed(FormClosedEventArgs e)
    {
        Abiertos.Remove(this);
        base.OnFormClosed(e);

        // Al cerrarse la de abajo, las de encima bajan a ocupar el hueco (deslizando, ver Situar).
        foreach (var otro in Abiertos.ToArray())
            if (!otro.IsDisposed) otro.Colocar();
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            _animacion.Dispose();
            _fGlifo.Dispose();
            _fTitulo.Dispose();
            _fMensaje.Dispose();
        }
        base.Dispose(disposing);
    }

    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(IntPtr ventana, int atributo,
        ref int valor, int tamano);
}
