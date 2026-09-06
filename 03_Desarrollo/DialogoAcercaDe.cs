using System.Diagnostics;
using System.Reflection;

namespace MiJornada;

/// <summary>
/// Acerca de. Además de la versión, enseña los datos que hacen falta para diagnosticar cuando
/// algo no va: qué registro de Entra usa, contra qué tenant, y dónde guarda sus ficheros.
/// </summary>
public class DialogoAcercaDe : Form
{
    private static readonly Color Morado = Color.FromArgb(91, 95, 199);
    private static readonly Color MoradoOscuro = Color.FromArgb(75, 79, 179);
    private static readonly Color Tinta = Color.FromArgb(32, 31, 30);
    private static readonly Color Gris = Color.FromArgb(96, 94, 92);

    public DialogoAcercaDe()
    {
        Text = "Acerca de Mi jornada";
        ClientSize = new Size(400, 300);
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;
        StartPosition = FormStartPosition.CenterParent;
        BackColor = Color.White;
        Font = new Font("Segoe UI", 9f);
        ShowInTaskbar = false;
        Icon = Iconos.Cargar(32);

        var icono = Iconos.Cargar(48);
        Controls.Add(new PictureBox
        {
            Bounds = new Rectangle(24, 24, 48, 48),
            Image = icono.ToBitmap(),
            SizeMode = PictureBoxSizeMode.StretchImage
        });

        Controls.Add(new Label
        {
            Bounds = new Rectangle(88, 24, 290, 26),
            Text = "Mi jornada",
            ForeColor = Tinta,
            Font = new Font("Segoe UI", 14f, FontStyle.Regular)
        });

        Controls.Add(new Label
        {
            Bounds = new Rectangle(88, 52, 290, 20),
            Text = $"Versión {Version()}",
            ForeColor = Gris
        });

        Controls.Add(new Label
        {
            Bounds = new Rectangle(24, 90, 352, 34),
            Text = "Controla tu presencia de Teams desde la barra de tareas, "
                 + "hablando directamente con Microsoft Graph.",
            ForeColor = Gris
        });

        // --------------------------------------------------- datos de diagnóstico
        Fila(136, "Registro de Entra", Config.ClientId);
        Fila(158, "Tenant", Config.TenantId);
        Fila(180, "Permiso", string.Join(", ", Config.Scopes));

        var enlaceDatos = new LinkLabel
        {
            Bounds = new Rectangle(140, 202, 240, 20),
            Text = "Abrir carpeta de datos",
            LinkColor = Morado,
            LinkBehavior = LinkBehavior.HoverUnderline,
            TextAlign = ContentAlignment.MiddleLeft
        };
        enlaceDatos.Click += (_, _) => AbrirCarpetaDeDatos();
        Controls.Add(new Label
        {
            Bounds = new Rectangle(24, 202, 116, 20),
            Text = "Datos",
            ForeColor = Gris
        });
        Controls.Add(enlaceDatos);

        var cerrar = new Button
        {
            Bounds = new Rectangle(296, 250, 80, 30),
            Text = "Cerrar",
            FlatStyle = FlatStyle.Flat,
            BackColor = Morado,
            ForeColor = Color.White,
            Cursor = Cursors.Hand,
            DialogResult = DialogResult.OK
        };
        cerrar.FlatAppearance.BorderSize = 0;
        cerrar.FlatAppearance.MouseOverBackColor = MoradoOscuro;
        Controls.Add(cerrar);

        AcceptButton = cerrar;
        CancelButton = cerrar;
    }

    private void Fila(int y, string etiqueta, string valor)
    {
        Controls.Add(new Label
        {
            Bounds = new Rectangle(24, y, 116, 20),
            Text = etiqueta,
            ForeColor = Gris
        });

        // Seleccionable: el ClientId hace falta para cualquier consulta de soporte, y copiarlo
        // a mano de una captura de pantalla es innecesariamente molesto.
        Controls.Add(new TextBox
        {
            Bounds = new Rectangle(140, y - 2, 240, 20),
            Text = valor,
            ReadOnly = true,
            BorderStyle = BorderStyle.None,
            BackColor = Color.White,
            ForeColor = Tinta,
            TabStop = false
        });
    }

    private static string Version()
    {
        var v = Assembly.GetExecutingAssembly().GetName().Version;
        return v is null ? "desconocida" : $"{v.Major}.{v.Minor}.{v.Build}";
    }

    private void AbrirCarpetaDeDatos()
    {
        try
        {
            Directory.CreateDirectory(Rutas.Carpeta);
            Process.Start(new ProcessStartInfo(Rutas.Carpeta) { UseShellExecute = true });
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, ex.Message, "No se pudo abrir la carpeta",
                MessageBoxButtons.OK, MessageBoxIcon.Warning);
        }
    }
}
