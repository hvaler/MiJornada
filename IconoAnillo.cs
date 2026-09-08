using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;

namespace MiJornada;

/// <summary>
/// Dibuja el anillo de progreso como icono, para la bandeja del sistema. Permite ver cuánto
/// queda sin abrir la ventana, que es el sentido de tener la aplicación ahí abajo.
/// </summary>
public static class IconoAnillo
{
    /// <summary>
    /// Libera el HICON que devuelve <see cref="Bitmap.GetHicon"/>. **Imprescindible**: ese handle
    /// no lo gestiona el recolector de basura. La jornada actualiza el icono cientos de veces,
    /// y sin esto se agotarían los handles GDI del proceso.
    /// </summary>
    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool DestroyIcon(IntPtr handle);

    /// <summary>
    /// Crea un icono con el anillo relleno según <paramref name="fraccion"/> (1 = jornada entera
    /// por delante, 0 = terminada). El llamante es responsable de hacerle Dispose.
    /// </summary>
    public static Icon Crear(double fraccion, Color color, Color pista, Size tamano)
    {
        // El tamaño lo marca el sistema (SM_CXSMICON), que varía con el DPI: dibujar a 32 fijo
        // y dejar que Windows reduzca da un anillo emborronado en pantallas normales.
        var lado = Math.Max(16, Math.Min(tamano.Width, tamano.Height));

        using var bmp = new Bitmap(lado, lado, System.Drawing.Imaging.PixelFormat.Format32bppArgb);
        using (var g = Graphics.FromImage(bmp))
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.Clear(Color.Transparent);

            var grosor = Math.Max(2f, lado * 0.18f);
            var inset = grosor / 2f + lado * 0.04f;
            var rect = new RectangleF(inset, inset, lado - 2 * inset, lado - 2 * inset);

            using (var lapiz = new Pen(pista, grosor))
                g.DrawEllipse(lapiz, rect);

            var barrido = (float)(360 * Math.Clamp(fraccion, 0, 1));
            if (barrido > 1f)
            {
                using var pluma = new Pen(color, grosor)
                {
                    StartCap = LineCap.Round,
                    EndCap = LineCap.Round
                };
                g.DrawArc(pluma, rect, -90, barrido);
            }
        }

        var hicon = bmp.GetHicon();
        try
        {
            // Clone() porque Icon.FromHandle no toma posesión del handle: el icono devuelto
            // dejaría de ser válido en cuanto se destruya el HICON de abajo.
            using var temporal = Icon.FromHandle(hicon);
            return (Icon)temporal.Clone();
        }
        finally
        {
            DestroyIcon(hicon);
        }
    }
}
