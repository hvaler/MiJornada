namespace MiJornada;

/// <summary>
/// Ajustes de la aplicación. Vive en un diálogo aparte y no en la ventana principal para que
/// esta se quede solo con el anillo y el botón.
///
/// <para>Está en pestañas porque en una sola columna ya no cabía: con la duración por día son
/// diez controles solo en la primera sección, y apilarlo todo obligaba a una ventana de casi
/// 600 px que había que recorrer entera para cambiar una casilla.</para>
/// </summary>
public class DialogoAjustes : Form
{
    private static readonly Color Morado = Color.FromArgb(91, 95, 199);
    private static readonly Color MoradoOscuro = Color.FromArgb(75, 79, 179);
    private static readonly Color Tinta = Color.FromArgb(32, 31, 30);
    private static readonly Color Gris = Color.FromArgb(96, 94, 92);
    private static readonly Color Rojo = Color.FromArgb(164, 38, 44);

    /// <summary>Orden de lunes a domingo, como se lee una semana aquí. Ojo: NO es el orden de
    /// <see cref="DayOfWeek"/>, que empieza en domingo.</summary>
    private static readonly (DayOfWeek Dia, string Etiqueta)[] Semana =
    [
        (DayOfWeek.Monday, "Lunes"),
        (DayOfWeek.Tuesday, "Martes"),
        (DayOfWeek.Wednesday, "Miércoles"),
        (DayOfWeek.Thursday, "Jueves"),
        (DayOfWeek.Friday, "Viernes"),
        (DayOfWeek.Saturday, "Sábado"),
        (DayOfWeek.Sunday, "Domingo"),
    ];

    private readonly Ajustes _ajustes;
    private readonly bool _jornadaEnMarcha;

    private readonly NumericUpDown _horas = new();
    private readonly NumericUpDown _minutos = new();
    private readonly NumericUpDown _avisoMinutos = new();
    private readonly ComboBox _pausa = new();
    private readonly CheckBox _autoFichaje = new();
    private readonly CheckBox _arrancar = new();
    private readonly CheckBox _minimizado = new();
    private readonly CheckBox _sincronizar = new();
    private readonly Label _aviso = new();
    private readonly Button _guardar = new();
    private readonly ToolTip _pista = new();

    // Una fila por día: casilla para activar la excepción, y sus horas y minutos.
    private readonly CheckBox[] _diaActivo = new CheckBox[7];
    private readonly NumericUpDown[] _diaHoras = new NumericUpDown[7];
    private readonly NumericUpDown[] _diaMinutos = new NumericUpDown[7];

    public DialogoAjustes(Ajustes ajustes, bool jornadaEnMarcha)
    {
        _ajustes = ajustes;
        _jornadaEnMarcha = jornadaEnMarcha;

        Text = "Ajustes";
        ClientSize = new Size(384, 404);
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;
        StartPosition = FormStartPosition.CenterParent;
        BackColor = Color.White;
        Font = new Font("Segoe UI", 9f);
        ShowInTaskbar = false;
        Icon = Iconos.Cargar(32);

        var pestanas = new TabControl { Bounds = new Rectangle(12, 12, 360, 336) };
        pestanas.TabPages.Add(PestanaJornada());
        pestanas.TabPages.Add(PestanaPresencia());
        pestanas.TabPages.Add(PestanaAutomatismos());
        pestanas.TabPages.Add(PestanaEquipos());
        Controls.Add(pestanas);

        // --------------------------------------------------------- pie común
        var acerca = new LinkLabel
        {
            Bounds = new Rectangle(14, 362, 110, 24),
            Text = "Acerca de",
            LinkColor = Gris,
            LinkBehavior = LinkBehavior.HoverUnderline,
            TextAlign = ContentAlignment.MiddleLeft
        };
        acerca.Click += (_, _) => { using var d = new DialogoAcercaDe(); d.ShowDialog(this); };
        Controls.Add(acerca);

        var cancelar = new Button
        {
            Bounds = new Rectangle(196, 360, 84, 30),
            Text = "Cancelar",
            FlatStyle = FlatStyle.Flat,
            BackColor = Color.White,
            ForeColor = Tinta,
            Cursor = Cursors.Hand,
            DialogResult = DialogResult.Cancel
        };
        cancelar.FlatAppearance.BorderColor = Color.FromArgb(200, 198, 196);
        Controls.Add(cancelar);

        _guardar.SetBounds(288, 360, 84, 30);
        _guardar.Text = "Guardar";
        _guardar.FlatStyle = FlatStyle.Flat;
        _guardar.FlatAppearance.BorderSize = 0;
        _guardar.FlatAppearance.MouseOverBackColor = MoradoOscuro;
        _guardar.BackColor = Morado;
        _guardar.ForeColor = Color.White;
        _guardar.Cursor = Cursors.Hand;
        _guardar.Click += Guardar_Click;
        Controls.Add(_guardar);

        AcceptButton = _guardar;
        CancelButton = cancelar;

        Validar();
    }

    // ------------------------------------------------------------- pestañas

    private TabPage PestanaJornada()
    {
        var p = new TabPage("Jornada") { BackColor = Color.White };

        p.Controls.Add(Negrita(16, 12, 320, "Duración general"));
        Rueda(_horas, 16, 36, 58, 0, 23, 1, p);
        p.Controls.Add(Texto(78, 36, 16, "h", null, 24));
        Rueda(_minutos, 98, 36, 58, 0, 59, 5, p);
        p.Controls.Add(Texto(160, 36, 40, "min", null, 24));

        _horas.Value = Math.Clamp(_ajustes.DuracionMinutos / 60, 0, 23);
        _minutos.Value = _ajustes.DuracionMinutos % 60;
        _horas.ValueChanged += (_, _) => Validar();
        _minutos.ValueChanged += (_, _) => Validar();

        p.Controls.Add(Negrita(16, 72, 320, "Días con duración distinta"));
        p.Controls.Add(Texto(16, 94, 330, "Sin marcar, ese día usa la duración general.", null, 20));

        var y = 118;   // 7 filas de 25 px terminan en 290, dentro de la pestaña
        for (var i = 0; i < Semana.Length; i++)
        {
            var (dia, etiqueta) = Semana[i];
            var minutos = _ajustes.DuracionPorDia.TryGetValue(dia.ToString(), out var m) ? m : -1;
            var tiene = minutos >= 1;

            var casilla = new CheckBox
            {
                Bounds = new Rectangle(16, y, 92, 22),
                Text = etiqueta,
                ForeColor = Tinta,
                Checked = tiene
            };

            // La casilla se anade ANTES que sus ruedas: el orden de tabulacion lo marca el
            // orden de insercion, y con el ratio invertido se tabulaba a los numeros antes que
            // a la casilla que los habilita.
            p.Controls.Add(casilla);

            var h = new NumericUpDown();
            Rueda(h, 112, y - 1, 52, 0, 23, 1, p);
            p.Controls.Add(Texto(168, y, 14, "h", null, 22));
            var mi = new NumericUpDown();
            Rueda(mi, 186, y - 1, 52, 0, 59, 5, p);
            p.Controls.Add(Texto(242, y, 34, "min", null, 22));

            h.Value = tiene ? Math.Clamp(minutos / 60, 0, 23) : _horas.Value;
            mi.Value = tiene ? minutos % 60 : _minutos.Value;
            h.Enabled = tiene;
            mi.Enabled = tiene;

            // Copias locales para el closure: sin esto, todas las filas moverían la última.
            var hh = h; var mm = mi; var cc = casilla;
            casilla.CheckedChanged += (_, _) => { hh.Enabled = cc.Checked; mm.Enabled = cc.Checked; Validar(); };
            h.ValueChanged += (_, _) => Validar();
            mi.ValueChanged += (_, _) => Validar();

            _diaActivo[i] = casilla;
            _diaHoras[i] = h;
            _diaMinutos[i] = mi;

            y += 25;
        }

        // Cambiar la duración con una jornada abierta no debe afectar a la que ya corre. El
        // anillo está a salvo (usa la duración guardada en el estado), pero permitir el cambio
        // aquí daría a entender que se aplica ahora, y no es así.
        if (_jornadaEnMarcha)
        {
            _horas.Enabled = false;
            _minutos.Enabled = false;
            for (var i = 0; i < 7; i++)
            {
                _diaActivo[i].Enabled = false;
                _diaHoras[i].Enabled = false;
                _diaMinutos[i].Enabled = false;
            }
            p.Controls.Add(Texto(206, 36, 148, "En marcha: no editable", Rojo, 24));
        }

        return p;
    }

    private TabPage PestanaPresencia()
    {
        var p = new TabPage("Presencia") { BackColor = Color.White };

        p.Controls.Add(Negrita(16, 16, 320, "Al pausar, aparecer como"));
        _pausa.SetBounds(16, 42, 200, 24);
        _pausa.DropDownStyle = ComboBoxStyle.DropDownList;
        _pausa.FlatStyle = FlatStyle.Flat;
        _pausa.Items.AddRange(OpcionPresencia.ParaPausa);
        _pausa.SelectedItem = _ajustes.Pausa;
        p.Controls.Add(_pausa);

        p.Controls.Add(Texto(16, 74, 330,
            "Al terminar la jornada siempre se pone Fuera del trabajo."));

        p.Controls.Add(Negrita(16, 120, 320, "Aviso antes de terminar"));
        Rueda(_avisoMinutos, 16, 146, 58, 0, 120, 5, p);
        p.Controls.Add(Texto(78, 148, 260, "minutos antes"));
        _avisoMinutos.Value = Math.Clamp(_ajustes.AvisoMinutos, 0, 120);
        _pista.SetToolTip(_avisoMinutos, "0 = sin aviso");

        p.Controls.Add(Texto(16, 178, 330, "Un globo para poder cerrar cosas. 0 lo desactiva."));

        return p;
    }

    private TabPage PestanaAutomatismos()
    {
        var p = new TabPage("Automatismos") { BackColor = Color.White };

        _autoFichaje.SetBounds(16, 20, 320, 22);
        _autoFichaje.Text = "Fichar al desbloquear el equipo";
        _autoFichaje.ForeColor = Tinta;
        _autoFichaje.Checked = _ajustes.FicharAlDesbloquear;
        p.Controls.Add(_autoFichaje);
        p.Controls.Add(Texto(34, 46, 306, "Una vez al día. Si ya has fichado o cancelado hoy, no hace nada."));

        _arrancar.SetBounds(16, 96, 320, 22);
        _arrancar.Text = "Arrancar con Windows";
        _arrancar.ForeColor = Tinta;
        _arrancar.Checked = ArranqueWindows.Activo;
        _arrancar.CheckedChanged += (_, _) => _minimizado.Enabled = _arrancar.Checked;
        p.Controls.Add(_arrancar);

        _minimizado.SetBounds(34, 120, 300, 22);
        _minimizado.Text = "y hacerlo en la bandeja";
        _minimizado.ForeColor = Gris;
        _minimizado.Checked = _ajustes.ArrancarMinimizado;
        _minimizado.Enabled = _arrancar.Checked;
        p.Controls.Add(_minimizado);

        p.Controls.Add(Texto(34, 148, 306,
            "El fichaje al desbloquear solo funciona si la aplicación está abierta."));

        return p;
    }

    private TabPage PestanaEquipos()
    {
        var p = new TabPage("Equipos") { BackColor = Color.White };

        _sincronizar.SetBounds(16, 20, 320, 22);
        _sincronizar.Text = "Compartir la jornada entre mis equipos";
        _sincronizar.ForeColor = Tinta;
        _sincronizar.Checked = _ajustes.SincronizarEntreEquipos;
        p.Controls.Add(_sincronizar);

        p.Controls.Add(Texto(34, 46, 306,
            "Guarda el estado en una carpeta privada de tu OneDrive para que no se te arranquen dos jornadas a la vez."));

        p.Controls.Add(Texto(34, 96, 306,
            "El arranque con Windows no se comparte: depende de cada equipo."));

        _aviso.SetBounds(16, 250, 330, 20);
        _aviso.ForeColor = Rojo;
        p.Controls.Add(_aviso);

        return p;
    }

    // ------------------------------------------------------------- ayudas

    private static Label Negrita(int x, int y, int ancho, string texto) => new()
    {
        Bounds = new Rectangle(x, y, ancho, 20),
        Text = texto,
        ForeColor = Tinta,
        Font = new Font("Segoe UI", 9f, FontStyle.Bold)
    };

    /// <param name="alto">
    /// 40 por defecto, para parrafos que envuelven. Las etiquetas en linea ("h", "min") deben
    /// pedir 20: con 40 se solapan con la fila de abajo y quedan tapadas por sus controles.
    /// </param>
    private static Label Texto(int x, int y, int ancho, string texto,
                               Color? color = null, int alto = 40) => new()
    {
        Bounds = new Rectangle(x, y, ancho, alto),
        Text = texto,
        TextAlign = alto <= 24 ? ContentAlignment.MiddleLeft : ContentAlignment.TopLeft,
        ForeColor = color ?? Gris
    };

    private static void Rueda(NumericUpDown n, int x, int y, int ancho,
                              int min, int max, int paso, Control padre)
    {
        n.SetBounds(x, y, ancho, 24);
        n.Minimum = min;
        n.Maximum = max;
        n.Increment = paso;
        n.TextAlign = HorizontalAlignment.Center;
        n.BorderStyle = BorderStyle.FixedSingle;
        padre.Controls.Add(n);
    }

    private int MinutosGenerales() => (int)_horas.Value * 60 + (int)_minutos.Value;

    private int MinutosDia(int i) => (int)_diaHoras[i].Value * 60 + (int)_diaMinutos[i].Value;

    /// <summary>
    /// Una jornada de cero minutos terminaría nada más empezar. Se impide guardar y se explica,
    /// en vez de corregir el valor mientras el usuario lo está escribiendo.
    /// </summary>
    private void Validar()
    {
        string? problema = null;

        if (!_jornadaEnMarcha)
        {
            if (MinutosGenerales() < 1)
            {
                problema = "La duración general tiene que ser de al menos un minuto.";
            }
            else
            {
                for (var i = 0; i < 7; i++)
                {
                    if (_diaActivo[i] is not null && _diaActivo[i].Checked && MinutosDia(i) < 1)
                    {
                        problema = $"{Semana[i].Etiqueta} tiene que durar al menos un minuto.";
                        break;
                    }
                }
            }
        }

        _guardar.Enabled = problema is null;
        _guardar.BackColor = problema is null ? Morado : Color.FromArgb(200, 198, 196);
        _aviso.Text = problema ?? string.Empty;
    }

    private void Guardar_Click(object? sender, EventArgs e)
    {
        if (!_jornadaEnMarcha)
        {
            _ajustes.DuracionMinutos = MinutosGenerales();

            _ajustes.DuracionPorDia.Clear();
            for (var i = 0; i < 7; i++)
                if (_diaActivo[i].Checked)
                    _ajustes.DuracionPorDia[Semana[i].Dia.ToString()] = MinutosDia(i);
        }

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
