# Cómo se hizo

*[Read in English](HOW-IT-WAS-MADE.md)*

XENON lo hizo alguien que **no sabe programar**. Esa persona describía lo que quería, mandaba fotos de equipos que le gustaban, escuchaba el resultado y decía qué estaba mal. El código, las pruebas y las comprobaciones los escribió un asistente de programación con IA ([Claude Code](https://claude.com/claude-code)), trabajando en esta carpeta de un Mac.

De la plantilla vacía a los cuatro aparatos hicieron falta **dos sesiones de trabajo en dos días**, con 31 cambios guardados.

## La idea

Empezó con un lector de CD USB en un Mac mini y un deseo: *escuchar mis CD como en un reproductor hi-fi de verdad*. La foto de referencia era un lector Denon. El primer brief ([docs/BRIEF.md](BRIEF.md)) pedía solo eso: una ventana que pareciera el frontal de un lector de CD, pantalla de puntitos, botones redondos de metal, perilla de volumen y canciones favoritas por disco. Pasar CD a archivos, reproducir archivos y el ecualizador quedaron fuera de la primera versión a propósito.

Después la app fue creciendo, deseo a deseo:

| Cuándo | Qué se pidió | En qué se convirtió |
|---|---|---|
| Día 1 | «Que suene mi CD y parezca el Denon» | El lector de CD, su pantalla de puntitos y los títulos de MusicBrainz |
| Día 1 | «Quiero ver el sonido» | Barras de espectro y después vúmetros de aguja con inercia real |
| Día 1 | «La música se corta» | Memoria antisaltos: leer el disco de 2 en 2 segundos, con 12 segundos por delante |
| Día 1 | «Balance izquierda/derecha» | Una perilla de balance que engancha en el centro |
| Día 2 | «Un ecualizador, como segundo aparato» | El EQ-10, apilado encima, con medidores de pico y luces OVER |
| Día 2 | «Como un streamer de audiófilo, pero con mis discos de FLAC y MP3» | El reproductor de archivos, que cambia solo la frecuencia del DAC |
| Día 2 | «CDPLAYER es feo, quiero una marca brillante» | El logo XENON de cromo con un destello que se mueve |
| Día 2 | «La calidez de las válvulas hi-fi, y válvulas que brillen con el sonido» | El previo a válvulas: primero dibujadas, luego fotorrealistas |

## El método

El mismo bucle corto, una y otra vez:

1. **Un deseo en palabras normales.** «La rueda es muy sensible», «no suena cuando la siguiente canción es de más calidad», «las válvulas no parecen reales».
2. **Para lo grande, primero un plan corto:** el objetivo, qué entra, qué no y cómo se comprobará. No se construye nada hasta que la persona dice OK. Lo pequeño se hace directamente.
3. **Preguntas solo sobre el producto, nunca sobre el código.** «¿Cuatro válvulas o seis?», «¿dónde va en la pila?», «¿favoritas como filtro o como álbum propio?». Los detalles técnicos los decide el asistente.
4. **Construir en pasos pequeños que se puedan comprobar.**
5. **Demostrar que funciona antes de decir que funciona.** Cada cambio pasa por:
   - **pruebas de la lógica y del sonido** (`swift test`): la etapa de válvulas, por ejemplo, se mide en armónicos, nivel, tonos falsos y chasquidos;
   - **una autoprueba** que maneja la app real sobre datos de usar y tirar (`tools/selftest.sh`);
   - **capturas** en claro y oscuro (`tools/snap.sh`), que el asistente revisa él mismo;
   - **una comprobación de la rejilla** de 4 puntos (`tools/grid-lint.sh`).
6. **Decir con honestidad qué no se ha comprobado.** Las pruebas no oyen. Cada paso termina con una lista como *«sin probar de oído: el hueco entre canciones, desenchufar el DAC sonando»*. Eso lo prueba luego la persona, con discos reales, el DAC real y sus oídos.
7. **Apuntarlo todo.** El proyecto llevaba tres notas, que no se publican porque son personales:
   - una **bitácora** con lo que se pidió y cómo se resolvió;
   - un **estado**: qué está hecho, qué falta probar a mano y qué falta decidir;
   - un **archivo de decisiones**, donde cada decisión apunta también **qué se descartó y por qué**, para que otra sesión no lo vuelva a proponer.

   Las decisiones de diseño están resumidas en [DESIGN-DECISIONS.md](DESIGN-DECISIONS.md).

Las piezas más grandes (el reproductor de archivos y una revisión completa del motor de sonido) las revisaron además **agentes revisores**: otra pasada de IA dedicada solo a buscar fallos. Lo que encontraron se arregló y se volvió a revisar.

## Lo difícil y cómo se resolvió

- **El lector USB cortaba la música.** Muchas lecturas pequeñas por segundo eran demasiado para él. La solución: leer el disco en trozos grandes de 2 segundos, tener 12 segundos preparados por delante y que nada más lea el disco a la vez. Las barras y los vúmetros escuchan el sonido que ya está sonando, nunca el disco.
- **Un CD cuyo nombre empieza por punto** (como *«...But Seriously»*) no aparecía al abrir la app, porque macOS lo trata como un volumen oculto. La búsqueda no debe saltarse los volúmenes ocultos.
- **macOS volvía a pedir permiso para leer el CD tras cada compilación.** Con firma ad hoc, cada versión parece una app distinta. La solución: firmar con un certificado que no cambie.
- **Silencio cuando la siguiente canción tenía más calidad.** Al cambiar la frecuencia del DAC, macOS reinicia el audio y el reproductor perdía lo que tenía en cola. Ahora vuelve a leer desde el segundo exacto donde iba.
- **Válvulas que parecían dibujadas.** Con formas vectoriales nunca parecían cristal. Se generaron cuatro imágenes fotorrealistas con una IA de imagen y la persona eligió dos. Un script pasó el fondo a negro puro y separó en otra capa la luz ámbar del filamento. En la app, esa capa sube y baja con la música por encima de la válvula fría.

## Lo que hizo la persona y la IA no podía

- Decidir qué tenía que ser la app y decir que no.
- Escuchar. Las pruebas pueden medir el 2º armónico de las válvulas, pero solo una persona puede decir si suena bien.
- Probar el aparato real: discos rayados, CD dobles, desenchufar el DAC sonando.
- Darse cuenta de lo que se veía mal («las válvulas no parecen reales») y de lo que se sentía mal («la rueda salta varios álbumes de golpe»).

## Para hacer lo mismo

No hace falta saber programar. Hace falta saber lo que quieres, probar lo que te dan y decir con claridad qué está mal. Pide un plan antes de los cambios grandes, pide pruebas antes de creer que «funciona», y apunta cada decisión y lo que descartaste.

Para cambiar esta app, abre la carpeta con tu asistente de IA. `CLAUDE.md` y `AGENTS.md` le explican cómo funciona el proyecto.
