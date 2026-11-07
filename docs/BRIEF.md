> Brief original de la versión 1 (solo CD). La app creció después: archivos,
> ecualizador y previo a válvulas. Ver el README.

# CDPlayer

Un reproductor de CD físico para Mac que imita un equipo de alta fidelidad de
verdad (como un Denon DCD-1700NE), pedido por alguien que no es programador.

## Replaces
Un reproductor de CD hi-fi físico, pero en el Mac mini usando un lector de
CD/DVD externo USB.

## Main jobs
1. Reproducir el CD físico insertado en el lector externo.
2. Ver y elegir canciones del disco en una pantalla tipo matriz (título,
   tiempo, número de pista, info del disco).
3. Marcar canciones como favoritas de ese álbum y reproducir solo esas.

## Data
- Disc: título del álbum, artista, número de pistas, tiempo total.
- Track: número, título, duración, favorita (sí/no).

## Shape
Una sola ventana, sin sidebar: el panel entero imita el frontal de un
reproductor de CD hi-fi. macOS 26 o posterior. Datos locales (favoritos
guardados en el Mac). Necesita internet solo para buscar título del álbum,
artista y nombres de las canciones (MusicBrainz) al meter un CD nuevo; una
vez buscado, se guarda localmente y no hace falta volver a buscarlo.

## System hooks
Lector de CD/DVD externo USB (acceso al disco óptico). Nada de menú barra
ni atajos globales en v1.

## Reference
Ninguna app de software como referencia. Referencia visual: equipos de CD
hi-fi reales (ejemplo: Denon DCD-1700NE) enviados como foto.

## Look
Look propio, no nativo de Mac: imitar un reproductor de CD de verdad.
- Panel oscuro tipo metal cepillado.
- Pantalla tipo matriz (estilo LCD de reproductor real) que muestra: título
  de la canción, artista/álbum, tiempo transcurrido, número de pista, y el
  total de pistas/tiempo del disco.
- Botones físicos redondos: play, pause, stop, eject, avance rápido,
  retroceso rápido, siguiente canción, canción anterior, shuffle, repeat,
  display (cambia qué info se ve en pantalla) y favoritos.
- Mando/perilla giratoria de volumen (no botones +/-).

## Not in version one
- Ripear o guardar las canciones como archivos de audio en el Mac.
- Reproducir archivos de audio locales (solo CD físico insertado).
- Programar un orden propio de pistas (Program).
- Ecualizador o balance izquierda/derecha.
- Buscar pista escribiendo su número directamente.
