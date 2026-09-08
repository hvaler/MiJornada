<#
.SYNOPSIS
    Genera mijornada.ico (en la raiz del repositorio) a partir del anillo de la aplicacion.

.DESCRIPTION
    Dibuja el anillo con GDI+ a varias resoluciones y las empaqueta en un unico .ico
    multi-resolucion con marcos PNG (formato ICO de Vista en adelante).

    Por que un .ico multi-resolucion y no una sola imagen escalada: Windows elige el marco
    segun el contexto (16 px en la bandeja, 32 en la barra de tareas, 256 en el explorador).
    Con un solo tamano, los demas salen borrosos.

    El anillo se dibuja como un arco de 270 grados en vez del circulo completo de la
    aplicacion: a 16 px un circulo cerrado se lee como una rosquilla indistinguible, y el
    hueco es lo que hace reconocible que es un indicador de progreso.

.NOTES
    Solo hay que reejecutarlo si cambia el diseno del icono. El .ico resultante se commitea.
#>

[CmdletBinding()]
param(
    [string] $Salida = "$PSScriptRoot\..\mijornada.ico"
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

# Mismos colores que MainForm.cs
$Morado = [System.Drawing.Color]::FromArgb(255, 91, 95, 199)
$Pista  = [System.Drawing.Color]::FromArgb(255, 237, 235, 233)

$tamanos = @(16, 24, 32, 48, 64, 128, 256)
$marcos  = @()

foreach ($s in $tamanos) {
    $bmp = New-Object System.Drawing.Bitmap($s, $s, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g   = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)

    # Trazo proporcional. Mas grueso que en la app (7%) porque a 16 px un trazo fino desaparece.
    $grosor = [float]($s * 0.16)
    $inset  = [float](($grosor / 2) + ($s * 0.06))
    $lado   = [float]($s - 2 * $inset)
    $rect   = New-Object System.Drawing.RectangleF($inset, $inset, $lado, $lado)

    # La pista solo a partir de 32 px: por debajo es ruido gris.
    if ($s -ge 32) {
        $lapiz = New-Object System.Drawing.Pen($Pista, $grosor)
        $g.DrawEllipse($lapiz, $rect)
        $lapiz.Dispose()
    }

    $pluma = New-Object System.Drawing.Pen($Morado, $grosor)
    $pluma.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pluma.EndCap   = [System.Drawing.Drawing2D.LineCap]::Round
    $g.DrawArc($pluma, $rect, -90, 270)
    $pluma.Dispose()
    $g.Dispose()

    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    $marcos += [pscustomobject]@{ Tamano = $s; Datos = $ms.ToArray() }
    $ms.Dispose()
    Write-Host ("  {0,3} px  ->  {1,6} bytes" -f $s, $marcos[-1].Datos.Length)
}

# ---------------------------------------------------------------- ensamblar el .ico
# ICONDIR (6 bytes) + ICONDIRENTRY (16 bytes por marco) + los PNG concatenados.

$dir = [System.IO.Path]::GetDirectoryName($Salida)
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

$fs = [System.IO.File]::Create($Salida)
$w  = New-Object System.IO.BinaryWriter($fs)

$w.Write([uint16]0)                  # reservado
$w.Write([uint16]1)                  # tipo: 1 = icono
$w.Write([uint16]$marcos.Count)

$offset = 6 + (16 * $marcos.Count)
foreach ($m in $marcos) {
    # 0 significa 256 en este campo de un byte
    $b = if ($m.Tamano -ge 256) { 0 } else { $m.Tamano }
    $w.Write([byte]$b)               # ancho
    $w.Write([byte]$b)               # alto
    $w.Write([byte]0)                # colores de la paleta (0 = sin paleta)
    $w.Write([byte]0)                # reservado
    $w.Write([uint16]1)              # planos
    $w.Write([uint16]32)             # bits por pixel
    $w.Write([uint32]$m.Datos.Length)
    $w.Write([uint32]$offset)
    $offset += $m.Datos.Length
}
foreach ($m in $marcos) { $w.Write($m.Datos) }

$w.Flush(); $w.Close(); $fs.Close()

$info = Get-Item $Salida
Write-Host ""
Write-Host "Icono generado: $($info.FullName)  ($($info.Length) bytes, $($marcos.Count) resoluciones)" -ForegroundColor Green
