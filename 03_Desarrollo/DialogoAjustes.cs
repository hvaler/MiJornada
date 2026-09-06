namespace MiJornada;

/// <summary>
/// Ajustes de la aplicación. Vive en un diálogo aparte y no en la ventana principal para que
/// esta se quede solo con el anillo y el botón, y para tener sitio donde ir añadiendo opciones.
/// </summary>
public class DialogoAjustes : Form
{
    private static readonly Color Morado = Color.FromArgb(91, 95, 199);
    private static readonly Color MoradoOscuro = Color.FromArgb(75, 79, 179);
    private static readonly Color Tinta = Color.FromArgb(32, 31, 30);
    private static readonly Color Gris = Color.FromArgb(96, 94, 92);

    private readonly Ajustes _ajustes;
    private readonly bool _jornadaEnMarcha;

    private readonly NumericUpDown _horas = new();
    private readonly NumericUpDown _minutos = new();
    private readonly ComboBox _pausa = new();
    private readonly CheckBox _autoFichaje = new();
    private readonly CheckBox _sincronizar = new();
    private readonly NumericUpDown _avisoMinutos = new();
    private readonly ToolTip _pista = new();
    private readonly CheckBox _arrancar = new();
    private readonly CheckBox _minimizado = new();
    private readonly Label _aviso = new();
    private readonly Button _guardar = new();

    public DialogoAjustes(Ajustes ajustes, bool jornadaEnMarcha)
    {
        _ajustes = ajustes;
        _jornadaEnMarcha = jornadaEnMarcha;

        Text = "Ajustes";
        ClientSize = new Size(340, 566);
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;
        StartPosition = FormStartPosition.CenterParent;
        BackColor = Color.White;
        Font = new Font("Segoe UI", 9f);
        ShowInTaskbar = false;
        Icon = Iconos.Cargar(32);

        // ------------------------------------------------------- duración
        Añadir(new Label
        {
            Bounds = new Rectangle(20, 20, 300, 20),
            Text = "Duración de la jornada",
            ForeColor = Tinta,
            Font = new Font("Segoe UI", 9f, FontStyle.Bold)
        });

        Rueda(_horas, 20, 46, 58, 0, 23, 1);
        Añadir(Texto(82, 46, 16, "h"));
        Rueda(_minutos, 102, 46, 58, 0, 59, 5);
        Añadir(Texto(164, 46, 40, "min"));

        _horas.Value = Math.Clamp(_ajustes.DuracionMinutos / 60, 0, 23);
        _minutos.Value = _ajustes.DuracionMinutos % 60;
        _horas.ValueChanged += (_, _) => Validar();
        _minutos.ValueChanged += (_, _) => Validar();

        // Cambiar la duración con una jornada abierta descuadraría el anillo, que se calcula
        // contra Config.Jornada: mostraría una fracción distinta a la que se usó al fichar.
        if (_jornadaEnMarcha)
        {
            _horas.Enabled = false;
            _minutos.Enabled = false;
            Añadir(Texto(20, 74, 300, "No se puede cambiar con una jornada en marcha.", Gris));
        }

        Añadir(Texto(20, 76, 130, "Avisar", Tinta));
        Rueda(_avisoMinutos, 150, 76, 58, 0, 120, 5);
        Añadir(Texto(212, 76, 120, "min antes del final"));
        _avisoMinutos.Value = Math.Clamp(_ajustes.AvisoMinutos, 0, 120);
        _pista.SetToolTip(_avisoMinutos, "0 = sin aviso");

        // --------------------------------------------------- estado al pausar
        Añadir(new Label
        {
            Bounds = new Rectangle(20, 140, 300, 20),
            Text = "Al pausar, aparecer como",
            ForeColor = Tinta,
            Font = new Font("Segoe UI", 9f, FontStyle.Bold)
        });

        _pausa.SetBounds(20, 166, 184, 24);
        _pausa.DropDownStyle = ComboBoxStyle.DropDownList;
        _pausa.FlatStyle = FlatStyle.Flat;
        _pausa.Items.AddRange(OpcionPresencia.ParaPausa);
        _pausa.SelectedItem = _ajustes.Pausa;
        Añadir(_pausa);

        // ------------------------------------------------ fichaje automático
        Añadir(new Label
        {
            Bounds = new Rectangle(20, 222, 300, 20),
            Text = "Automatismos",
            ForeColor = Tinta,
            Font = new Font("Segoe UI", 9f, FontStyle.Bold)
        });

        _autoFichaje.SetBounds(20, 248, 300, 22);
        _autoFichaje.Text = "Fichar al desbloquear el equipo";
        _autoFichaje.ForeColor = Tinta;
        _autoFichaje.Checked = _ajustes.FicharAlDesbloquear;
        Añadir(_autoFichaje);

        Añadir(new Label
        {
            Bounds = new Rectangle(38, 270, 290, 32),
            Text = "Una vez al día. Si ya has fichado o cancelado hoy, no hace nada.",
            ForeColor = Gris
        });

        _arrancar.SetBounds(20, 306, 300, 22);
        _arrancar.Text = "Arrancar con Windows";
        _arrancar.ForeColor = Tinta;
        _arrancar.Checked = ArranqueWindows.Activo;
        _arrancar.CheckedChanged += (_, _) => _minimizado.Enabled = _arrancar.Checked;
        Añadir(_arrancar);

        _minimizado.SetBounds(38, 330, 290, 22);
        _minimizado.Text = "y hacerlo en la bandeja, sin abrir la ventana";
        _minimizado.ForeColor = Gris;
        _minimizado.Checked = _ajustes.ArrancarMinimizado;
        _minimizado.Enabled = _arrancar.Checked;
        Añadir(_minimizado);

        Añadir(new Label
        {
            Bounds = new Rectangle(38, 354, 290, 32),
            Text = "El fichaje al desbloquear solo funciona si la aplicación está abierta.",
            ForeColor = Gris
        });

        // ------------------------------------------------------ entre equipos
        Añadir(new Label
        {
            Bounds = new Rectangle(20, 396, 300, 20),
            Text = "Entre equipos",
            ForeColor = Tinta,
            Font = new Font("Segoe UI", 9f, FontStyle.Bold)
        });

        _sincronizar.SetBounds(20, 422, 300, 22);
        _sincronizar.Text = "Compartir la jornada entre mis equipos";
        _sincronizar.ForeColor = Tinta;
        _sincronizar.Checked = _ajustes.SincronizarEntreEquipos;
        Añadir(_sincronizar);

        Añadir(new Label
        {
            Bounds = new Rectangle(38, 444, 290, 32),
            Text = "Guarda el estado en tu OneDrive para que no se te arranquen dos jornadas.",
            ForeColor = Gris
        });

        // ---------------------------------------------------------- avisos
        _aviso.SetBounds(20, 490, 300, 20);
        _aviso.ForeColor = Color.FromArgb(164, 38, 44);
        _aviso.Text = "";
        Añadir(_aviso);

        // --------------------------------------------------------- botones
        var cancelar = new Button { Bounds = new Rectangle(146, 516, 82, 30), Text = "Cancelar" };
        cancelar.FlatStyle = FlatStyle.Flat;
        cancelar.FlatAppearance.BorderColor = Color.FromArgb(200, 198, 196);
        cancelar.BackColor = Color.White;
        cancelar.ForeColor = Tinta;
        cancelar.Cursor = Cursors.Hand;
        cancelar.DialogResult = DialogResult.Cancel;
        Añadir(cancelar);

        _guardar.SetBounds(236, 516, 84, 30);
        _guardar.Text = "Guardar";
        _guardar.FlatStyle = FlatStyle.Flat;
        _guardar.FlatAppearance.BorderSize = 0;
        _guardar.FlatAppearance.MouseOverBackColor = MoradoOscuro;
        _guardar.BackColor = Morado;
        _guardar.ForeColor = Color.White;
        _guardar.Cursor = Cursors.Hand;
        _guardar.Click += Guardar_Click;
        Añadir(_guardar);

        // Enlace discreto abajo a la izquierda, para no competir con Guardar/Cancelar.
        var acerca = new LinkLabel
        {
            Bounds = new Rectangle(20, 522, 110, 20),
            Text = "Acerca de",
            LinkColor = Gris,
            LinkBehavior = LinkBehavior.HoverUnderline,
            TextAlign = ContentAlignment.MiddleLeft
        };
        acerca.Click += (_, _) => { using var d = new DialogoAcercaDe(); d.ShowDialog(this); };
        Añadir(acerca);

        AcceptButton = _guardar;
        CancelButton = cancelar;

        Validar();
    }

    // ------------------------------------------------------------- ayudas

    private void Añadir(Control c) => Controls.Add(c);

    private Label Texto(int x, int y, int ancho, string texto, Color? color = null) => new()
    {
        Bounds = new Rectangle(x, y, ancho, 24),
        Text = texto,
        TextAlign = ContentAlignment.MiddleLeft,
        ForeColor = color ?? Gris
    };

    private void Rueda(NumericUpDown n, int x, int y, int ancho, int min, int max, int paso)
    {
        n.SetBounds(x, y, ancho, 24);
        n.Minimum = min;
        n.Maximum = max;
        n.Increment = paso;
        n.TextAlign = HorizontalAlignment.Center;
        n.BorderStyle = BorderStyle.FixedSingle;
        Añadir(n);
    }

    private int MinutosTotales() => (int)_horas.Value * 60 + (int)_minutos.Value;

    /// <summary>
    /// Una jornada de cero minutos terminaría nada más empezar. Se impide guardar y se explica,
    /// en vez de corregir el valor mientras el usuario lo está escribiendo.
    /// </summary>
    private void Validar()
    {
        var vale = _jornadaEnMarcha || MinutosTotales() >= 1;
        _guardar.Enabled = vale;
        _guardar.BackColor = vale ? Morado : Color.FromArgb(200, 198, 196);
        _aviso.Text = vale ? "" : "La jornada tiene que durar al menos un minuto.";
    }

    private void Guardar_Click(object? sender, EventArgs e)
    {
        if (!_jornadaEnMarcha) _ajustes.DuracionMinutos = MinutosTotales();

        if (_pausa.SelectedItem is OpcionPresencia p)
            _ajustes.PausaDisponibilidad = p.Disponibilidad;

        // Al desactivarlo se olvida la marca del día: si se vuelve a activar más tarde,
        // el automatismo puede saltar hoy mismo en vez de esperar a mañana.
        if (_ajustes.FicharAlDesbloquear && !_autoFichaje.Checked)
            _ajustes.UltimoAutoFichaje = null;
        _ajustes.FicharAlDesbloquear = _autoFichaje.Checked;

        _ajustes.SincronizarEntreEquipos = _sincronizar.Checked;
        _ajustes.AvisoMinutos = (int)_avisoMinutos.Value;
        _ajustes.ArrancarMinimizado = _minimizado.Checked;

        // El acceso directo se crea o se borra aquí. Si falla no se impide guardar el resto:
        // un problema con la carpeta de Inicio no debe tirar por tierra los demás ajustes.
        var fallo = ArranqueWindows.Establecer(_arrancar.Checked, _minimizado.Checked);
        if (fallo is not null)
            MessageBox.Show(this,
                "Los ajustes se han guardado, pero no se pudo cambiar el arranque con Windows:"
                + Environment.NewLine + fallo,
                "Arranque con Windows", MessageBoxButtons.OK, MessageBoxIcon.Warning);

        _ajustes.Guardar();
        DialogResult = DialogResult.OK;
        Close();
    }
}
