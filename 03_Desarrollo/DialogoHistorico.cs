using System.Globalization;

namespace MiJornada;

/// <summary>
/// Histórico de jornadas: resumen por semanas arriba y el detalle de los días debajo.
///
/// <para>Se pinta a mano en un panel con desplazamiento en lugar de usar un <c>DataGridView</c>.
/// Una rejilla traería ordenación, selección, redimensionado de columnas y un aspecto de hoja de
/// cálculo que no encaja con el resto de la aplicación — y aquí no se edita nada: esto se lee.</para>
///
/// <para>Lo primero que se ve es <b>la semana en curso</b>, que es la pregunta real ("¿cuánto
/// llevo esta semana?"). El histórico completo va debajo, para cuando de verdad se busca un día.</para>
/// </summary>
public sealed class DialogoHistorico : Form
{
    private static readonly Color Morado = Color.FromArgb(91, 95, 199);
    private static readonly Color Tinta = Color.FromArgb(32, 31, 30);
    private static readonly Color Gris = Color.FromArgb(96, 94, 92);
    private static readonly Color Ambar = Color.FromArgb(150, 120, 0);
    private static readonly Color Linea = Color.FromArgb(237, 235, 233);

    private readonly List<Jornada> _jornadas;
    private readonly List<ResumenSemana> _semanas;

    public DialogoHistorico()
    {
        _jornadas = Historico.Cargar().OrderByDescending(j => j.Inicio).ToList();
        _semanas = Historico.PorSemana(_jornadas);

        Text = "Histórico de jornadas";
        ClientSize = new Size(460, 520);
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;
        StartPosition = FormStartPosition.CenterParent;
        BackColor = Color.White;
        Font = new Font("Segoe UI", 9f);
        ShowInTaskbar = false;
        Icon = Iconos.Cargar(32);

        if (_jornadas.Count == 0) MontarVacio();
        else MontarContenido();

        var cerrar = new Button
        {
            Bounds = new Rectangle(360, 478, 84, 30),
            Text = "Cerrar",
            FlatStyle = FlatStyle.Flat,
            BackColor = Color.White,
            ForeColor = Tinta,
            Cursor = Cursors.Hand,
            DialogResult = DialogResult.Cancel
        };
        cerrar.FlatAppearance.BorderColor = Color.FromArgb(200, 198, 196);
        Controls.Add(cerrar);
        CancelButton = cerrar;

        var carpeta = new LinkLabel
        {
            Bounds = new Rectangle(14, 480, 200, 24),
            Text = "Abrir la carpeta de datos",
            LinkColor = Gris,
            LinkBehavior = LinkBehavior.HoverUnderline,
            TextAlign = ContentAlignment.MiddleLeft
        };
        carpeta.Click += (_, _) =>
        {
            try
            {
                System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(
                    Rutas.Carpeta)
                { UseShellExecute = true });
            }
            catch (Exception ex)
            {
                MessageBox.Show(this, ex.Message, "No se pudo abrir la carpeta",
                    MessageBoxButtons.OK, MessageBoxIcon.Warning);
            }
        };
        Controls.Add(carpeta);
    }

    /// <summary>
    /// Sin datos todavía. Se explica <b>por qué</b> está vacío en vez de dejar un hueco: lo
    /// natural al estrenar esto es pensar que no funciona.
    /// </summary>
    private void MontarVacio()
    {
        Controls.Add(new Label
        {
            Bounds = new Rectangle(24, 24, 412, 30),
            Text = "Todavía no hay jornadas anotadas",
            Font = new Font("Segoe UI", 12f, FontStyle.Bold),
            ForeColor = Tinta
        });

        Controls.Add(new Label
        {
            Bounds = new Rectangle(24, 60, 412, 120),
            Text = "Cada jornada se anota cuando termina, así que aquí no aparecerá nada " +
                   "hasta que cierres la primera.\r\n\r\n" +
                   "Se anotan tanto las que llegan a su hora como las que cancelas: el rato " +
                   "trabajado cuenta igual, y distinguirlas es más útil que esconderlas.",
            ForeColor = Gris
        });
    }

    private void MontarContenido()
    {
        // ------------------------------------------------------- semana en curso
        var lunes = Historico.LunesDe(DateOnly.FromDateTime(DateTime.Today));
        var actual = _semanas.FirstOrDefault(s => s.Lunes == lunes)
                     ?? new ResumenSemana(lunes, 0, 0);

        Controls.Add(new Label
        {
            Bounds = new Rectangle(20, 16, 420, 22),
            Text = "ESTA SEMANA",
            Font = new Font("Segoe UI", 8.5f, FontStyle.Bold),
            ForeColor = Morado
        });

        Controls.Add(new Label
        {
            Bounds = new Rectangle(20, 38, 420, 42),
            Text = Historico.Duracion(actual.Minutos),
            Font = new Font("Segoe UI", 22f),
            ForeColor = Tinta
        });

        Controls.Add(new Label
        {
            Bounds = new Rectangle(20, 84, 420, 20),
            Text = actual.Dias switch
            {
                0 => $"{Historico.Rango(actual)} · sin jornadas todavía",
                1 => $"{Historico.Rango(actual)} · 1 día",
                _ => $"{Historico.Rango(actual)} · {actual.Dias} días · " +
                     $"media de {actual.MediaHoras:0.#} h"
            },
            ForeColor = Gris
        });

        // ------------------------------------------------------------- listado
        var lista = new Panel
        {
            Bounds = new Rectangle(12, 116, 436, 350),
            AutoScroll = true,
            BackColor = Color.White,
            BorderStyle = BorderStyle.FixedSingle
        };
        Controls.Add(lista);

        var y = 8;
        foreach (var semana in _semanas)
        {
            y = FilaSemana(lista, semana, y);

            foreach (var j in _jornadas.Where(x => Historico.LunesDe(x.Dia) == semana.Lunes))
                y = FilaJornada(lista, j, y);

            y += 10;
        }
    }

    /// <summary>Cabecera de semana: el total a la derecha, que es lo que se compara de un vistazo.</summary>
    private int FilaSemana(Panel padre, ResumenSemana s, int y)
    {
        padre.Controls.Add(new Label
        {
            Bounds = new Rectangle(10, y, 260, 20),
            Text = Historico.Rango(s),
            Font = new Font("Segoe UI", 9f, FontStyle.Bold),
            ForeColor = Tinta
        });

        padre.Controls.Add(new Label
        {
            Bounds = new Rectangle(270, y, 140, 20),
            Text = $"{Historico.Duracion(s.Minutos)} · {s.Dias} d",
            TextAlign = ContentAlignment.MiddleRight,
            Font = new Font("Segoe UI", 9f, FontStyle.Bold),
            ForeColor = Morado
        });

        padre.Controls.Add(new Panel
        {
            Bounds = new Rectangle(10, y + 22, 400, 1),
            BackColor = Linea
        });

        return y + 28;
    }

    private int FilaJornada(Panel padre, Jornada j, int y)
    {
        var ci = CultureInfo.CurrentCulture;
        var dia = j.Inicio.LocalDateTime;

        var etiqueta = $"{ci.DateTimeFormat.GetAbbreviatedDayName(dia.DayOfWeek)} {dia.Day}";
        padre.Controls.Add(new Label
        {
            Bounds = new Rectangle(14, y, 70, 20),
            Text = char.ToUpper(etiqueta[0]) + etiqueta[1..],
            ForeColor = Tinta
        });

        padre.Controls.Add(new Label
        {
            Bounds = new Rectangle(84, y, 110, 20),
            Text = $"{j.Inicio:HH:mm} – {j.Fin:HH:mm}",
            ForeColor = Gris
        });

        // Las pausas solo se mencionan si las hubo: una columna con "0 min" en todas las filas
        // es ruido.
        padre.Controls.Add(new Label
        {
            Bounds = new Rectangle(194, y, 110, 20),
            Text = j.Pausados > 0 ? $"pausa {Historico.Duracion(j.Pausados)}" : string.Empty,
            ForeColor = Gris
        });

        padre.Controls.Add(new Label
        {
            Bounds = new Rectangle(300, y, 110, 20),
            Text = Historico.Duracion(j.Minutos),
            TextAlign = ContentAlignment.MiddleRight,
            ForeColor = j.Fin_ == FinJornada.Cancelada ? Ambar : Tinta
        });

        if (j.Fin_ == FinJornada.Cancelada || j.Automatica)
        {
            var marcas = new List<string>();
            if (j.Fin_ == FinJornada.Cancelada) marcas.Add("cancelada");
            if (j.Automatica) marcas.Add("automática");

            padre.Controls.Add(new Label
            {
                Bounds = new Rectangle(14, y + 18, 396, 16),
                Text = string.Join(" · ", marcas),
                Font = new Font("Segoe UI", 7.5f),
                ForeColor = j.Fin_ == FinJornada.Cancelada ? Ambar : Gris
            });
            return y + 36;
        }

        return y + 22;
    }
}
