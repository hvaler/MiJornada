using System.Drawing.Drawing2D;
using Microsoft.Win32;

namespace MiJornada;

public class MainForm : Form
{
    private static readonly Color Morado = Color.FromArgb(91, 95, 199);
    private static readonly Color MoradoOscuro = Color.FromArgb(75, 79, 179);
    private static readonly Color Ambar = Color.FromArgb(193, 156, 0);
    private static readonly Color Pista = Color.FromArgb(237, 235, 233);
    private static readonly Color Tinta = Color.FromArgb(32, 31, 30);
    private static readonly Color Gris = Color.FromArgb(96, 94, 92);
    private static readonly Color Rojo = Color.FromArgb(164, 38, 44);

    private readonly Estado _estado = Estado.Cargar();
    private readonly Ajustes _ajustes = Ajustes.Cargar();
    private readonly Lazy<PresenciaService> _presenciaLazy = new(() => new PresenciaService());
    private PresenciaService Presencia => _presenciaLazy.Value;

    private readonly Panel _anillo = new();
    private readonly Label _lblTiempo = new();
    private readonly Label _lblRotulo = new();
    private readonly Button _btnPrincipal = new();
    private readonly LinkLabel _lnkCancelar = new();
    private readonly System.Windows.Forms.Timer _reloj = new();
    private readonly NotifyIcon _tray = new();

    private readonly Button _btnAjustes = new();
    private readonly ToolTip _pista = new();

    // Icono de bandeja: el estatico cuando no hay jornada, y uno dibujado al vuelo mientras
    // corre, para ver cuanto queda sin abrir la ventana.
    private readonly Icon _iconoEstatico = Iconos.Cargar(16);
    private Icon? _iconoDinamico;
    private int _ultimoPorcentajePintado = -1;

    private bool _cerrandoDeVerdad;
    private bool _finalizando;

    public MainForm()
    {
        Text = "Mi jornada";
        ClientSize = new Size(340, 430);
        FormBorderStyle = FormBorderStyle.FixedSingle;
        MaximizeBox = false;
        StartPosition = FormStartPosition.CenterScreen;
        BackColor = Color.White;
        Font = new Font("Segoe UI", 9f);

        // ------------------------------------------------------------- anillo
        _anillo.SetBounds(50, 30, 240, 240);
        _anillo.BackColor = Color.Transparent;
        _anillo.Paint += DibujarAnillo;
        Controls.Add(_anillo);

        _lblTiempo.SetBounds(0, 95, 240, 50);
        _lblTiempo.TextAlign = ContentAlignment.MiddleCenter;
        _lblTiempo.Font = new Font("Segoe UI", 26f, FontStyle.Regular);
        _lblTiempo.ForeColor = Tinta;
        _lblTiempo.BackColor = Color.Transparent;
        _lblTiempo.Parent = _anillo;

        _lblRotulo.SetBounds(50, 280, 240, 24);
        _lblRotulo.TextAlign = ContentAlignment.MiddleCenter;
        _lblRotulo.ForeColor = Gris;
        Controls.Add(_lblRotulo);

        // ------------------------------------------------------------ botones
        _btnPrincipal.SetBounds(50, 320, 240, 40);
        _btnPrincipal.FlatStyle = FlatStyle.Flat;
        _btnPrincipal.FlatAppearance.BorderSize = 0;
        _btnPrincipal.Font = new Font("Segoe UI", 10f);
        _btnPrincipal.Cursor = Cursors.Hand;
        _btnPrincipal.Click += BotonPrincipal_Click;
        Controls.Add(_btnPrincipal);

        _lnkCancelar.SetBounds(50, 372, 240, 24);
        _lnkCancelar.TextAlign = ContentAlignment.MiddleCenter;
        _lnkCancelar.Text = "Cancelar jornada";
        _lnkCancelar.LinkColor = Gris;
        _lnkCancelar.ActiveLinkColor = Rojo;
        _lnkCancelar.LinkBehavior = LinkBehavior.HoverUnderline;
        _lnkCancelar.Click += Cancelar_Click;
        Controls.Add(_lnkCancelar);

        // ------------------------------------------------------------- ajustes
        // Discreto y arriba a la derecha: la pantalla principal se queda con el anillo y el
        // botón, y la configuración crece aquí dentro sin ensuciarla.
        _btnAjustes.SetBounds(298, 8, 30, 30);
        _btnAjustes.FlatStyle = FlatStyle.Flat;
        _btnAjustes.FlatAppearance.BorderSize = 0;
        _btnAjustes.BackColor = Color.White;
        _btnAjustes.ForeColor = Gris;
        _btnAjustes.FlatAppearance.MouseOverBackColor = Color.FromArgb(243, 242, 241);
        _btnAjustes.Cursor = Cursors.Hand;
        _btnAjustes.TabStop = false;
        // Segoe MDL2 Assets es la fuente de iconos del sistema en Windows 10 y 11.
        _btnAjustes.Font = new Font("Segoe MDL2 Assets", 11f);
        _btnAjustes.Text = "\uE713";   // engranaje de Segoe MDL2 Assets
        _btnAjustes.Click += Ajustes_Click;
        _pista.SetToolTip(_btnAjustes, "Ajustes");
        // El glifo no produce nombre accesible: sin esto, un lector de pantalla no lo anuncia.
        _btnAjustes.AccessibleName = "Ajustes";
        Controls.Add(_btnAjustes);

        // -------------------------------------------------------------- iconos
        // El .ico lleva varias resoluciones; hay que pedir el marco adecuado a cada uso
        // o Windows escala el que le parece y se ve borroso.
        Icon = Iconos.Cargar(32);

        // -------------------------------------------------------------- bandeja
        _tray.Icon = _iconoEstatico;
        _tray.Text = "Mi jornada";
        _tray.DoubleClick += (_, _) => Restaurar();
        var menu = new ContextMenuStrip();
        menu.Items.Add("Abrir", null, (_, _) => Restaurar());
        menu.Items.Add("Acerca de", null, (_, _) => MostrarAcercaDe());
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("Salir", null, (_, _) => { _cerrandoDeVerdad = true; Close(); });
        _tray.ContextMenuStrip = menu;

        // ------------------------------------------------ fichaje automatico
        // SystemEvents guarda una referencia estatica: hay que darse de baja al cerrar
        // (ver OnFormClosing) o el manejador seguiria vivo sobre un formulario ya destruido.
        SystemEvents.SessionSwitch += Sesion_Cambiada;

        // ---------------------------------------------------------------- reloj
        _reloj.Interval = 1000;
        _reloj.Tick += Reloj_Tick;
        _reloj.Start();

        // Si la jornada venció con la aplicación cerrada, se descarta en silencio.
        if (_estado.Situacion == EstadoJornada.Activa && _estado.Restante == TimeSpan.Zero)
            _estado.Limpiar();

        Refrescar();
    }

    // -------------------------------------------------------- fichaje automático

    private void Sesion_Cambiada(object? sender, SessionSwitchEventArgs e)
    {
        if (e.Reason != SessionSwitchReason.SessionUnlock) return;

        // SystemEvents notifica en un hilo del pool. Tocar la interfaz desde ahí revienta,
        // así que se vuelve al hilo de la ventana antes de hacer nada.
        if (IsHandleCreated && !IsDisposed) BeginInvoke(FicharAlDesbloquearAsync);
    }

    private async void FicharAlDesbloquearAsync()
    {
        try
        {
            if (!_ajustes.FicharAlDesbloquear) return;

            // Ya hay algo en marcha: desbloquear no debe tocarlo.
            if (_estado.Situacion != EstadoJornada.SinFichar) return;

            // Una vez al día: volver del café no vuelve a fichar. Y si hoy se canceló la
            // jornada a propósito, tampoco: cancelar significa "hoy no quiero estar fichado".
            if (_ajustes.UltimoAutoFichaje?.Date == DateTime.Today) return;

            if (!await IniciarAsync()) return;   // si Graph falla, el intento de hoy no se gasta

            _ajustes.UltimoAutoFichaje = DateTime.Today;
            _ajustes.Guardar();

            // Solo se avisa si la ventana no está a la vista: si lo está, ya se ve la cuenta
            // atrás corriendo y un globo sobraría (además dejaría el icono de bandeja puesto).
            if (!Visible)
            {
                _tray.Visible = true;
                _tray.ShowBalloonTip(5000, "Jornada iniciada",
                    $"Estás disponible. Termina a las {_estado.Fin:HH:mm}.", ToolTipIcon.Info);
            }
        }
        catch (Exception ex)
        {
            // async void: una excepción aquí tumbaría el proceso, y con él la jornada.
            MessageBox.Show(this, ex.Message, "No se pudo fichar al desbloquear",
                MessageBoxButtons.OK, MessageBoxIcon.Warning);
        }
    }

    // ------------------------------------------------------------------ ajustes

    /// <summary>Accesible desde el menu de la bandeja y desde el dialogo de ajustes.</summary>
    internal void MostrarAcercaDe()
    {
        // Si la ventana esta oculta en la bandeja, se muestra centrado en pantalla en vez de
        // sobre un padre invisible.
        using var dlg = new DialogoAcercaDe();
        if (!Visible) dlg.StartPosition = FormStartPosition.CenterScreen;
        dlg.ShowDialog(Visible ? this : null);
    }

    private void Ajustes_Click(object? sender, EventArgs e)
    {
        var enMarcha = _estado.Situacion != EstadoJornada.SinFichar;

        using var dlg = new DialogoAjustes(_ajustes, enMarcha);
        if (dlg.ShowDialog(this) != DialogResult.OK) return;

        // --minutos manda sobre los ajustes mientras dure esta ejecución.
        if (!Config.JornadaForzada) Config.Jornada = _ajustes.Duracion;

        // Devolver el foco al botón principal: si no, el engranaje se queda con el
        // rectángulo de foco dibujado encima.
        _btnPrincipal.Focus();
        Refrescar();
    }

    // ------------------------------------------------------------------ pintado

    private void DibujarAnillo(object? sender, PaintEventArgs e)
    {
        var g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;

        var rect = new Rectangle(12, 12, 216, 216);

        using (var lapiz = new Pen(Pista, 16))
            g.DrawEllipse(lapiz, rect);

        if (_estado.Situacion == EstadoJornada.SinFichar) return;

        var color = _estado.Situacion == EstadoJornada.Pausada ? Ambar : Morado;
        var barrido = (float)(360 * _estado.Fraccion);
        if (barrido <= 0.5f) return;

        using var pluma = new Pen(color, 16)
        {
            StartCap = LineCap.Round,
            EndCap = LineCap.Round
        };
        g.DrawArc(pluma, rect, -90, barrido);
    }

    private void Refrescar()
    {
        _anillo.Invalidate();

        switch (_estado.Situacion)
        {
            case EstadoJornada.Activa:
                _lblTiempo.Text = _estado.Restante.ToString(@"hh\:mm\:ss");
                _lblTiempo.ForeColor = Tinta;
                _lblRotulo.Text = $"Termina a las {_estado.Fin:HH:mm}";
                EstiloSecundario(_btnPrincipal, "Pausar");
                _lnkCancelar.Visible = true;
                break;

            case EstadoJornada.Pausada:
                _lblTiempo.Text = _estado.Restante.ToString(@"hh\:mm\:ss");
                _lblTiempo.ForeColor = Gris;
                _lblRotulo.Text = $"En pausa desde las {_estado.PausaDesde:HH:mm}";
                EstiloPrimario(_btnPrincipal, "Reanudar");
                _lnkCancelar.Visible = true;
                break;

            default:
                _lblTiempo.Text = "--:--:--";
                _lblTiempo.ForeColor = Pista;
                _lblRotulo.Text = "Sin fichar";
                EstiloPrimario(_btnPrincipal, "Iniciar jornada");
                _lnkCancelar.Visible = false;
                break;
        }

        _tray.Text = _lblRotulo.Text.Length > 60 ? "Mi jornada" : _lblRotulo.Text;
        ActualizarIconoBandeja();
    }

    /// <summary>
    /// Dibuja el anillo en el icono de la bandeja para poder ver el avance sin abrir la ventana.
    /// </summary>
    private void ActualizarIconoBandeja()
    {
        if (_estado.Situacion == EstadoJornada.SinFichar)
        {
            if (_ultimoPorcentajePintado == -1) return;   // ya está puesto el estático
            _ultimoPorcentajePintado = -1;
            _tray.Icon = _iconoEstatico;
            _iconoDinamico?.Dispose();
            _iconoDinamico = null;
            return;
        }

        // Solo se redibuja cuando cambia el porcentaje. A un icono por segundo durante siete
        // horas serían 25.000 iconos para 100 imágenes distintas.
        var porcentaje = (int)Math.Round(_estado.Fraccion * 100);
        if (porcentaje == _ultimoPorcentajePintado) return;
        _ultimoPorcentajePintado = porcentaje;

        var color = _estado.Situacion == EstadoJornada.Pausada ? Ambar : Morado;
        var nuevo = IconoAnillo.Crear(_estado.Fraccion, color, Pista, SystemInformation.SmallIconSize);

        _tray.Icon = nuevo;              // primero se asigna...
        _iconoDinamico?.Dispose();       // ...y después se suelta el anterior
        _iconoDinamico = nuevo;
    }

    private static void EstiloPrimario(Button b, string texto)
    {
        b.Text = texto;
        b.BackColor = Morado;
        b.ForeColor = Color.White;
        b.FlatAppearance.MouseOverBackColor = MoradoOscuro;
        b.FlatAppearance.BorderSize = 0;
    }

    private static void EstiloSecundario(Button b, string texto)
    {
        b.Text = texto;
        b.BackColor = Color.White;
        b.ForeColor = Tinta;
        b.FlatAppearance.MouseOverBackColor = Color.FromArgb(243, 242, 241);
        b.FlatAppearance.BorderSize = 1;
        b.FlatAppearance.BorderColor = Color.FromArgb(200, 198, 196);
    }

    // ------------------------------------------------------------------ acciones

    private async void BotonPrincipal_Click(object? sender, EventArgs e)
    {
        switch (_estado.Situacion)
        {
            case EstadoJornada.SinFichar: await IniciarAsync(); break;
            case EstadoJornada.Activa: await PausarAsync(); break;
            case EstadoJornada.Pausada: await ReanudarAsync(); break;
        }
    }

    /// <returns>Cierto si se llego a fichar. El fichaje automatico lo necesita para no
    /// consumir el intento del dia cuando la llamada a Graph ha fallado.</returns>
    private async Task<bool> IniciarAsync()
    {
        if (!await CambiarPresenciaAsync("Available", "Available")) return false;

        _estado.Situacion = EstadoJornada.Activa;
        _estado.Fin = DateTime.Now + Config.Jornada;
        _estado.PausaDesde = null;
        _estado.Guardar();
        Refrescar();
        return true;
    }

    private async Task PausarAsync()
    {
        _estado.Situacion = EstadoJornada.Pausada;
        _estado.PausaDesde = DateTime.Now;
        _estado.Guardar();
        Refrescar();
        await CambiarPresenciaAsync(_ajustes.Pausa.Disponibilidad, _ajustes.Pausa.Actividad);
    }

    private async Task ReanudarAsync()
    {
        if (_estado.PausaDesde is not null)
            _estado.Fin = _estado.Fin!.Value + (DateTime.Now - _estado.PausaDesde.Value);

        _estado.Situacion = EstadoJornada.Activa;
        _estado.PausaDesde = null;
        _estado.Guardar();
        Refrescar();
        await CambiarPresenciaAsync("Available", "Available");
    }

    private async void Cancelar_Click(object? sender, EventArgs e)
    {
        var r = MessageBox.Show(this, "¿Seguro que quieres cancelar la jornada?", "Mi jornada",
            MessageBoxButtons.YesNo, MessageBoxIcon.Question);
        if (r != DialogResult.Yes) return;

        _estado.Limpiar();
        Refrescar();
        await CambiarPresenciaAsync("Offline", "OffWork");
    }

    private async void Reloj_Tick(object? sender, EventArgs e)
    {
        if (_estado.Situacion == EstadoJornada.Activa && _estado.Restante == TimeSpan.Zero && !_finalizando)
        {
            _finalizando = true;
            _estado.Limpiar();
            Refrescar();
            await CambiarPresenciaAsync("Offline", "OffWork");
            _tray.Visible = true;
            _tray.ShowBalloonTip(5000, "Jornada finalizada",
                "Tu estado ha cambiado a Fuera del trabajo.", ToolTipIcon.Info);
            _finalizando = false;
            return;
        }

        Refrescar();
    }

    private async Task<bool> CambiarPresenciaAsync(string disponibilidad, string actividad)
    {
        Cursor = Cursors.WaitCursor;
        _btnPrincipal.Enabled = false;
        try
        {
            await Presencia.EstablecerAsync(disponibilidad, actividad, MostrarCodigoDispositivo);
            return true;
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, ex.Message, "No se pudo cambiar la presencia",
                MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return false;
        }
        finally
        {
            Cursor = Cursors.Default;
            _btnPrincipal.Enabled = true;
        }
    }

    private void MostrarCodigoDispositivo(string codigo, string url)
    {
        Invoke(() =>
        {
            Clipboard.SetText(codigo);
            PresenciaService.AbrirNavegador(url);
            MessageBox.Show(this,
                $"Pega este código en la ventana del navegador que se acaba de abrir:\n\n{codigo}\n\n" +
                "Ya está copiado en el portapapeles. Cuando termines, vuelve aquí.",
                "Iniciar sesión", MessageBoxButtons.OK, MessageBoxIcon.Information);
        });
    }

    // -------------------------------------------------------------------- cierre

    private void Restaurar()
    {
        Show();
        WindowState = FormWindowState.Normal;
        Activate();
        _tray.Visible = false;
    }

    protected override void OnFormClosing(FormClosingEventArgs e)
    {
        // Con una jornada en marcha, cerrar la ventana la deja corriendo en la
        // bandeja: si el proceso muere, nadie pondrá el Fuera del trabajo al final.
        if (!_cerrandoDeVerdad && _estado.Situacion != EstadoJornada.SinFichar)
        {
            e.Cancel = true;
            Hide();
            _tray.Visible = true;
            _tray.ShowBalloonTip(3000, "Mi jornada",
                "Sigue contando aquí abajo. Doble clic para volver.", ToolTipIcon.Info);
            return;
        }

        SystemEvents.SessionSwitch -= Sesion_Cambiada;
        _tray.Visible = false;
        _tray.Icon = null;
        _iconoDinamico?.Dispose();
        _iconoEstatico.Dispose();
        base.OnFormClosing(e);
    }
}
