using System.Runtime.InteropServices;

namespace MiJornada;

/// <summary>
/// Aviso propio en la esquina inferior derecha: una tarjeta que aparece, se lee y se va sola.
///
/// <para><b>Por qué no un globo de bandeja.</b> <c>NotifyIcon.ShowBalloonTip</c> era lo obvio y
/// resultó ser lo inservible: con <b>No molestar</b> activado, Windows no aplaza esos globos, los
/// <b>descarta</b> — no aparecen ni quedan en el centro de notificaciones. Verificado en este
/// equipo: los avisos de inicio y fin de jornada no salieron y tampoco figuran en la lista.
/// Como el modo No molestar suele estar puesto justo cuando más se usa la aplicación (reuniones,
/// pantalla compartida), el mensaje no se vería casi nunca.</para>
///
/// <para>Esta ventana es de la aplicación, así que no pasa por el filtro del sistema. No es una
/// forma de colarse: el aviso lo pide el propio usuario al fichar, dura unos segundos, no roba el
/// foco y no suena. Lo que No molestar silencia son las interrupciones ajenas.</para>
///
/// <para><b>No roba el foco</b> — es la mitad del "no bloqueante": <see cref="ShowWithoutActivation"/>
/// más <c>WS_EX_NOACTIVATE</c>. Sin eso, la tarjeta se llevaría el teclado a media frase.</para>
/// </summary>
public sealed class Aviso : Form
{
    private const int Ancho = 340;
    private const int Margen = 12;      // hasta el borde de la pantalla
    private const int Relleno = 14;     // interior de la tarjeta
    private const int Separacion = 8;   // entre tarjetas apiladas

    private static readonly Color Fondo = Color.FromArgb(250, 250, 250);
    private static readonly Color Borde = Color.FromArgb(216, 214, 212);
    private static readonly Color Tinta = Color.FromArgb(32, 31, 30);
    private static readonly Color Gris = Color.FromArgb(96, 94, 92);
    private static readonly Color Morado = Color.FromArgb(91, 95, 199);

    /// <summary>Las que están en pantalla, de abajo arriba, para poder apilarlas.</summary>
    private static readonly List<Aviso> Abiertos = [];

    private readonly string _titulo;
    private readonly string _mensaje;
    private readonly Font _fTitulo;
    private readonly Font _fMensaje;
    private readonly Rectangle _rTitulo;
    private readonly Rectangle _rMensaje;
    private readonly System.Windows.Forms.Timer _vida = new();
    private readonly System.Windows.Forms.Timer _fundido = new();
    private bool _cerrando;

    // TextRenderer (GDI) mide y pinta igual, asi que lo que se mide es lo que se ve. Con
    // Graphics.MeasureString habria que corregir a ojo la diferencia entre GDI y GDI+.
    private const TextFormatFlags Flags =
        TextFormatFlags.WordBreak | TextFormatFlags.NoPrefix | TextFormatFlags.NoPadding;

    private Aviso(string titulo, string mensaje, int milisegundos, Action? alPulsar)
    {
        _titulo = titulo;
        _mensaje = mensaje;

        // Segoe UI Emoji lleva los pictogramas; la fuente de texto normal no los tiene todos y
        // saldrian como rectangulos vacios. Windows tira de ella por sustitucion, pero pedirla
        // por su nombre evita depender de que la sustitucion acierte.
        _fTitulo = new Font("Segoe UI", 9.75f, FontStyle.Bold);
        _fMensaje = new Font("Segoe UI Emoji", 10.5f);

        var anchoTexto = Ancho - Relleno * 2;

        // Se mide el texto real para dar a la tarjeta el alto que necesita (TEC-014): con alto
        // fijo, un mensaje largo se cortaria por abajo sin avisar.
        var altoTitulo = TextRenderer.MeasureText(_titulo, _fTitulo,
            new Size(anchoTexto, 0), Flags).Height;
        var altoMensaje = TextRenderer.MeasureText(_mensaje, _fMensaje,
            new Size(anchoTexto, 0), Flags).Height;

        _rTitulo = new Rectangle(Relleno, Relleno, anchoTexto, altoTitulo);
        _rMensaje = new Rectangle(Relleno, Relleno + altoTitulo + 6, anchoTexto, altoMensaje);

        FormBorderStyle = FormBorderStyle.None;
        StartPosition = FormStartPosition.Manual;
        ShowInTaskbar = false;
        TopMost = true;
        BackColor = Fondo;
        DoubleBuffered = true;
        ClientSize = new Size(Ancho, _rMensaje.Bottom + Relleno);
        Cursor = alPulsar is null ? Cursors.Default : Cursors.Hand;

        EsquinasRedondeadas();

        _vida.Interval = Math.Max(1000, milisegundos);
        _vida.Tick += (_, _) => { _vida.Stop(); Desvanecer(); };

        _fundido.Interval = 30;
        _fundido.Tick += (_, _) =>
        {
            Opacity -= 0.08;
            if (Opacity > 0.05) return;
            _fundido.Stop();
            Close();
        };

        Click += (_, _) => { alPulsar?.Invoke(); Desvanecer(); };
    }

    /// <summary>
    /// Muestra un aviso. <paramref name="alPulsar"/> es lo que ocurre si se hace clic en él
    /// (normalmente, abrir la ventana); si es <c>null</c>, el clic solo lo cierra.
    /// </summary>
    public static void Mostrar(string titulo, string mensaje, int milisegundos = 6000,
        Action? alPulsar = null)
    {
        var aviso = new Aviso(titulo, mensaje, milisegundos, alPulsar);
        Abiertos.Add(aviso);
        aviso.Colocar();
        aviso.Show();       // sin Activate: no roba el foco
        aviso._vida.Start();
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

        Location = new Point(
            zona.Right - Width - Margen,
            zona.Bottom - Height - Margen - alturaPrevia);
    }

    private void Desvanecer()
    {
        if (_cerrando) return;
        _cerrando = true;
        _vida.Stop();
        _fundido.Start();
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
            p.ExStyle |= 0x08000000;   // WS_EX_NOACTIVATE: ni al pulsarla se lleva el foco
            p.ExStyle |= 0x00000080;   // WS_EX_TOOLWINDOW: fuera del Alt+Tab
            return p;
        }
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        base.OnPaint(e);

        // Filo de color a la izquierda: identifica la tarjeta como de esta aplicacion de un
        // vistazo, sin gastar espacio en un icono.
        using (var pincel = new SolidBrush(Morado))
            e.Graphics.FillRectangle(pincel, 0, 0, 3, Height);

        using (var lapiz = new Pen(Borde))
            e.Graphics.DrawRectangle(lapiz, 0, 0, Width - 1, Height - 1);

        TextRenderer.DrawText(e.Graphics, _titulo, _fTitulo, _rTitulo, Gris, Flags);
        TextRenderer.DrawText(e.Graphics, _mensaje, _fMensaje, _rMensaje, Tinta, Flags);
    }

    protected override void OnFormClosed(FormClosedEventArgs e)
    {
        Abiertos.Remove(this);
        base.OnFormClosed(e);

        // Al cerrarse la de abajo, las de encima bajan a ocupar el hueco. Sin esto quedaria un
        // agujero en la pila.
        foreach (var otro in Abiertos.ToArray())
            if (!otro.IsDisposed) otro.Colocar();
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            _vida.Dispose();
            _fundido.Dispose();
            _fTitulo.Dispose();
            _fMensaje.Dispose();
        }
        base.Dispose(disposing);
    }

    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(IntPtr ventana, int atributo,
        ref int valor, int tamano);
}
