import Foundation

/// The in-app guide (Ayuda > Ayuda de CDPlayer, ⌘?): what every unit does,
/// how it treats the sound, and every button, shortcut and setting. Keep it
/// in step with the app: a new control, shortcut or setting gets its line here.
struct HelpTopic: Identifiable, Hashable {
    let id: String
    let title: String
    let symbol: String
    let summary: String
    let sections: [HelpSection]
}

struct HelpSection: Hashable {
    let title: String
    var text: [String] = []
    var controls: [HelpControl] = []
}

/// One control or menu command: its name, its shortcut, what it does.
struct HelpControl: Hashable {
    let name: String
    var key: String = ""
    let text: String
}

extension HelpTopic {
    static let all: [HelpTopic] = [start, sound, cd, files, tubes, equalizer, meters, settings, shortcuts, questions]

    static let start = HelpTopic(
        id: "start", title: "Primeros pasos", symbol: "hifispeaker.2",
        summary: "Qué es CDPlayer y cómo se maneja la torre.",
        sections: [
            HelpSection(title: "La torre", text: [
                "CDPlayer imita una torre de aparatos de alta fidelidad apilados. De abajo arriba: el **reproductor de CD** (CDP-1), el **reproductor de archivos** (MF-1), el **previo a válvulas** (TP-4) y el **ecualizador gráfico** (EQ-10).",
                "Es el mismo orden por el que pasa el sonido: sale del CD o del archivo, pasa por las válvulas y por el ecualizador, y llega a tu DAC.",
                "Al encender la app salen todos los aparatos. Cada uno tiene su botón para apagarlo; para volver a abrirlo, usa el menú **Reproducción** o **Archivos**.",
            ]),
            HelpSection(title: "Cómo se maneja", text: [
                "**Arrastra** cualquier aparato y se mueve la torre entera.",
                "Los **botones** se pulsan con un clic. Las **perillas** y los **faders** se mueven arrastrando arriba o abajo, y un **doble clic** los lleva a su punto de partida.",
                "Deja el ratón quieto sobre cualquier control y aparece qué hace y su atajo de teclado. Todo lo que hay en los paneles está también en los menús, con su atajo.",
            ]),
            HelpSection(title: "Un solo aparato suena a la vez", text: [
                "El reproductor de CD y el de archivos no suenan juntos: al empezar uno, el otro se pone en pausa. Las teclas multimedia del teclado mandan sobre el último que empezó a sonar.",
                "El **volumen** y el **balance** están en el reproductor de CD y valen para los dos.",
            ]),
            HelpSection(title: "Apagar", text: [
                "El botón de encendido del reproductor de CD cierra CDPlayer, igual que ⌘Q. Si hay música, baja el sonido en un instante antes de cerrar, para que no se oiga ningún chasquido en el DAC.",
            ]),
        ])

    static let sound = HelpTopic(
        id: "sound", title: "Cómo trata el sonido", symbol: "waveform.path",
        summary: "El camino de la música desde el disco hasta tu DAC, y cuándo llega intacta.",
        sections: [
            HelpSection(title: "El camino", text: [
                "**Lector** (memoria antisaltos) → **reproductor** (balance) → **válvulas** y **crossfeed** → **ecualizador** → **volumen** → **DAC**.",
                "Por dentro todo va en coma flotante de 32 bits, el formato propio del audio del Mac. Ese formato guarda exactamente cualquier muestra de 16 o 24 bits, así que llevar la música así no pierde nada.",
            ]),
            HelpSection(title: "Leer la música: la memoria antisaltos", text: [
                "Los lectores de CD por USB van rápidos con lecturas grandes y muy lentos con muchas pequeñas. Por eso la app lee **2 segundos de cada vez** (medio segundo la primera, para empezar enseguida) y tiene unos **12 segundos preparados** por delante de lo que suena, como la memoria antisaltos de un aparato.",
                "Si una lectura falla (una raya, un cable flojo), lo intenta **3 veces**. Si sigue fallando, suena todo lo ya leído y se para en el punto exacto con **ERROR DE LECTURA**; al pulsar Reproducir sigue desde ahí.",
                "Con un CD, macOS da cada pista como un archivo con las muestras exactas del disco (44,1 kHz, 16 bits). Los archivos (FLAC, ALAC, WAV, AIFF, MP3) los descodifica el propio Mac a su frecuencia, sin convertirla. Los mono suenan por los dos canales. El CD y los archivos usan el mismo sistema.",
            ]),
            HelpSection(title: "El DAC a la frecuencia de cada canción", text: [
                "Antes de cada canción, la app pone tu DAC a la frecuencia de esa canción: 44,1 kHz para un CD, 96 kHz para un archivo de 96 kHz… Sin esto, macOS convertiría toda la música, sin avisar, a la frecuencia que tuviera puesta el DAC.",
                "Entre canciones de distinta frecuencia hay un silencio breve mientras el DAC cambia. Si el DAC se desenchufa o vuelve, la música sigue desde el segundo exacto donde iba.",
            ]),
            HelpSection(title: "El DAC en exclusiva (opcional)", text: [
                "Con **Ajustes > Sonido > Usar el DAC en exclusiva**, mientras suena la música la app se queda el DAC para ella sola: ningún aviso, vídeo o programa se mezcla con la música ni le cambia la frecuencia.",
                "macOS manda entonces los demás sonidos a otra salida (los altavoces del Mac). Al pausar o parar, la app suelta el DAC; si la app se cierra, macOS lo libera solo. Al pulsar Reproducir tarda unas décimas en empezar: es el tiempo que macOS necesita para hacer el cambio.",
            ]),
            HelpSection(title: "Cuándo llega intacta (bit a bit)", text: [
                "La música llega a tu DAC exactamente como está en el disco o en el archivo cuando: las **válvulas** y el **crossfeed están apagados**, el **ecualizador está en NEUTRO o apagado**, el **balance en el centro** y el **volumen al máximo**, tanto el de la app como el del Mac para ese DAC.",
                "Entonces regula lo fuerte que suena con la rueda del DAC o del amplificador: así el DAC recibe la señal completa y el volumen lo baja la parte eléctrica, que es la mejor forma.",
                "El volumen de la app es digital: por debajo del máximo multiplica las muestras, como cualquier volumen digital. No se pierde nada audible, pero ya no es bit a bit.",
                "Límite conocido: los WAV o AIFF de 32 bits *enteros* (rarísimos) no salen idénticos, porque el motor trabaja en coma flotante.",
            ]),
            HelpSection(title: "Lo que de verdad se oye", text: [
                "La app entrega la música limpia. Lo que oyes después es tu **DAC**, tu **amplificador** y tus **auriculares o altavoces**: ahí es donde se nota de verdad un cambio de equipo.",
            ]),
        ])

    static let cd = HelpTopic(
        id: "cd", title: "Reproductor de CD", symbol: "opticaldisc",
        summary: "CDP-1: el aparato de abajo. Lee el CD del lector USB.",
        sections: [
            HelpSection(title: "Qué hace", text: [
                "Lee el CD que metes en el lector USB y lo reconoce por su huella. La primera vez busca en internet (MusicBrainz) el álbum, el artista y las canciones, y los guarda para no volver a preguntar. Sin internet usa los títulos que da macOS.",
                "La pantalla de puntitos enseña la pista, el título y el tiempo, y abajo el total del disco (por ejemplo «12 PISTAS 59:46»). Las tildes salen sin acento, como en los aparatos reales.",
            ]),
            HelpSection(title: "Botones y perillas", controls: [
                HelpControl(name: "Reproducir / pausa", key: "Espacio", text: "Empieza o para la música."),
                HelpControl(name: "Detener", key: "⌘.", text: "Para y vuelve al principio de la canción."),
                HelpControl(name: "Canción anterior / siguiente", key: "⌘← / ⌘→", text: "Salta de canción."),
                HelpControl(name: "Retroceso / avance rápido", key: "⌥← / ⌥→", text: "Mantén pulsado para moverte dentro de la canción."),
                HelpControl(name: "Expulsar", key: "⌘E", text: "Expulsa el disco, o abre la bandeja si no hay disco."),
                HelpControl(name: "FAVORITA", key: "F", text: "Marca la canción que suena como favorita."),
                HelpControl(name: "SOLO FAV", key: "⇧F", text: "Solo suenan las favoritas del disco."),
                HelpControl(name: "ALEATORIO", key: "S", text: "Orden aleatorio."),
                HelpControl(name: "REPETIR", key: "R", text: "Repite el disco."),
                HelpControl(name: "DISPLAY", key: "D", text: "Cambia la pantalla: tiempo transcurrido → restante → barras → vúmetros."),
                HelpControl(name: "VOLUMEN", key: "⌘↑ / ⌘↓", text: "Perilla grande. Volumen digital de la app, para el CD y los archivos; se guarda."),
                HelpControl(name: "BALANCE", key: "⇧⌘← / ⇧⌘→", text: "Como en un amplificador: en el centro los dos lados quedan enteros y al girar baja solo el contrario. Doble clic o ⇧⌘B la centra."),
                HelpControl(name: "Encendido", key: "⌘Q", text: "Cierra CDPlayer."),
            ]),
            HelpSection(title: "Mensajes de la pantalla", controls: [
                HelpControl(name: "SIN DISCO", text: "No hay CD en el lector."),
                HelpControl(name: "ERROR DE LECTURA", text: "El disco no se dejó leer ni tras 3 intentos. Suena todo lo leído y se para justo ahí; limpia el disco y pulsa Reproducir para seguir."),
            ]),
        ])

    static let files = HelpTopic(
        id: "files", title: "Reproductor de archivos", symbol: "music.note.list",
        summary: "MF-1: tu música en FLAC, ALAC, WAV, AIFF o MP3, desde la carpeta o el disco que elijas.",
        sections: [
            HelpSection(title: "Qué hace", text: [
                "Toca la música de la carpeta o el disco que eliges con **MÚSICA**. Cada carpeta con canciones es un álbum; una carpeta de canciones sueltas aparece como «Varios».",
                "La pantalla en color enseña la portada, la canción y su calidad (formato, bits y kHz). La música llega al DAC a su propia calidad: un FLAC de 24 bits y 96 kHz llega a 96 kHz.",
                "Al volver a abrir la app recuerda la canción y el segundo donde ibas, en pausa.",
            ]),
            HelpSection(title: "La lista y la selección", text: [
                "**LISTA** va dando la vuelta: lo que suena → álbumes → canciones del álbum → carpetas → lo que suena. En los álbumes, «★ Favoritas» va primero cuando has marcado alguna.",
                "La rueda **SELECCIÓN** se mueve de uno en uno; doble clic elige. Con el teclado, **↑ y ↓** hacen lo mismo si lo último que pulsaste fue este aparato. Desde la pantalla de lo que suena, el primer paso abre la lista de álbumes.",
                "Con la lista abierta, Reproducir pone lo que está marcado. Un clic en la línea de tiempo salta a ese punto.",
            ]),
            HelpSection(title: "Botones", controls: [
                HelpControl(name: "Reproducir / pausa", key: "⌥Espacio", text: "Empieza, para, o pone lo marcado en la lista."),
                HelpControl(name: "Canción anterior / siguiente", key: "⌥⌘← / ⌥⌘→", text: "Salta de canción; mantén pulsado para retroceder o avanzar."),
                HelpControl(name: "Retroceder / avanzar 5 s", key: "⇧⌥⌘← / ⇧⌥⌘→", text: "Se mueve cinco segundos."),
                HelpControl(name: "Detener", key: "⌥⌘.", text: "Para la música."),
                HelpControl(name: "MÚSICA", key: "⌥⌘O", text: "Elige la carpeta o el disco con tu música."),
                HelpControl(name: "Buscar canciones nuevas", key: "⌥⌘R", text: "Vuelve a mirar la carpeta por si has añadido música."),
                HelpControl(name: "FAVORITA", key: "⌥⌘F", text: "Marca la canción que suena; las favoritas están en «★ Favoritas»."),
                HelpControl(name: "LISTA", key: "⌥⌘L", text: "Cambia la pantalla: álbumes, canciones, carpetas y lo que suena."),
                HelpControl(name: "SELECCIÓN", key: "↑ / ↓", text: "Se mueve por la lista; doble clic en la rueda para elegir."),
                HelpControl(name: "Encendido", text: "Apaga este aparato (la música se para)."),
                HelpControl(name: "Abrir el aparato", key: "⌥⌘M", text: "Lo vuelve a poner en la torre si lo apagaste."),
            ]),
        ])

    static let tubes = HelpTopic(
        id: "tubes", title: "Previo a válvulas", symbol: "flame",
        summary: "TP-4: añade la calidez de una etapa de válvulas, sin cambiar el volumen, y tiene el crossfeed para auriculares.",
        sections: [
            HelpSection(title: "Qué hace", text: [
                "Imita por software una etapa de válvula triodo de alta fidelidad, como las ECC88 o 12AU7 de un previo a válvulas. Una válvula amplifica un poco más una mitad de la onda que la otra, y eso añade sobre todo **armónicos pares**, en especial el 2º (una octava por encima). El oído lo oye como calidez y cuerpo, no como distorsión.",
                "Está ajustada para que el volumen no cambie: solo cambia el color.",
            ]),
            HelpSection(title: "Cómo trabaja por dentro", text: [
                "**CALIDEZ** decide cuánto se empuja la válvula. Al 100 %, un tono fuerte (−6 dBFS) recibe un 4 % de 2º armónico, y el 3º queda muy por debajo. Los pasajes suaves reciben mucho menos, como en una válvula real.",
                "**Sobremuestreo.** La curva de la válvula crea armónicos nuevos más agudos. Para que los que pasan del límite del CD no se «doblen» hacia lo audible como tonos falsos, la etapa trabaja a 4 veces la frecuencia con música de CD o 48 kHz, a 2 veces con 88,2 o 96 kHz, y a 1 vez por encima: siempre entre 176 y 192 kHz. Luego la devuelve a su calidad. Los filtros retrasan el sonido 1,5 milésimas, imposible de notar.",
                "Un filtro quita el pequeño desplazamiento fijo que añade la curva, sin tocar la música.",
                "**Apagada es apagada**: la música pasa intacta, bit a bit. Al encender o apagar hace un fundido de 30 milésimas, así que nunca da un chasquido.",
                "Las cuatro válvulas brillan con el nivel de cada canal y tardan 4 segundos en calentarse.",
            ]),
            HelpSection(title: "Crossfeed, para auriculares", text: [
                "Con altavoces, cada oído oye los dos: el sonido del izquierdo llega también al oído derecho, rodeando la cabeza, unas décimas de milisegundo más tarde, algo más flojo y sin agudos. Con auriculares cada oído oye solo su canal, así que la música suena **dentro de la cabeza**, y lo que va mezclado a un solo lado (muy típico en los discos estéreo de los años 60) suena **pegado a una oreja**. Cansa.",
                "**CROSSFEED** imita lo que hace la cabeza: pasa a cada oído un poco del otro canal, solo los graves y medios (a partir de 650–700 Hz los agudos apenas cruzan), y unos **0,23 milisegundos más tarde**. Lo que suena por el centro, como la voz, sale **exactamente igual**: ni más fuerte ni con más graves. Solo se acerca lo que iba a los lados.",
                "Los tres niveles son los ajustes clásicos: **SUAVE** (Jan Meier: 650 Hz, el otro lado 9,5 dB más bajo), **MEDIO** (Chu Moy: 700 Hz, 6 dB) y **FUERTE** (Bauer: 700 Hz, 4,5 dB). La luz del nivel elegido está siempre encendida, aunque el crossfeed esté apagado.",
                "Está en el previo, justo después de las válvulas. Como el ecualizador trata igual los dos canales, suena igual que si estuviera al final. **Apagado no toca nada**: la música pasa bit a bit. Encender, apagar o cambiar de nivel hace un fundido de 30 milésimas, sin chasquidos.",
                "Es **solo para auriculares**: con altavoces el cruce ya ocurre en la habitación. Enciéndelo a mano: el Mac no sabe qué tienes enchufado al DAC.",
            ]),
            HelpSection(title: "Botones", controls: [
                HelpControl(name: "VÁLVULAS", key: "V", text: "Enciende o apaga las válvulas, para comparar."),
                HelpControl(name: "CALIDEZ", key: "⌥⌘↑ / ⌥⌘↓", text: "Cuánto colorean el sonido. Doble clic la pone a la mitad."),
                HelpControl(name: "CROSSFEED", key: "C", text: "Enciende o apaga el crossfeed, para escuchar con auriculares."),
                HelpControl(name: "SUAVE · MEDIO · FUERTE", key: "⇧C", text: "Cuánto cruza. Mayúsculas C pasa al siguiente nivel. Viene en MEDIO."),
                HelpControl(name: "Encendido", text: "Cierra el aparato. Ojo: el sonido sigue como estaba; para quitar los efectos, apaga VÁLVULAS y CROSSFEED."),
                HelpControl(name: "Abrir el aparato", key: "⌥⌘V", text: "Lo vuelve a poner en la torre."),
            ]),
        ])

    static let equalizer = HelpTopic(
        id: "equalizer", title: "Ecualizador", symbol: "slider.vertical.3",
        summary: "EQ-10: diez bandas para ajustar graves, medios y agudos, con medidores de pico.",
        sections: [
            HelpSection(title: "Qué hace", text: [
                "**Diez bandas** separadas una octava, de 31 Hz (graves profundos) a 16 kHz (agudos de aire), que suben o bajan ±12 dB en pasos de medio decibelio. **NIVEL** baja el conjunto de 0 a −12 dB, para dejar sitio cuando subes varias bandas.",
                "Las bandas de los extremos tienen un interruptor **SHELF**: encendido, la banda deja de ser una campana y pasa a subir o bajar todo un extremo, como el control de tono de un amplificador (graves desde 63 Hz, agudos desde 8 kHz).",
            ]),
            HelpSection(title: "Cómo trabaja por dentro", text: [
                "Usa los filtros del propio Mac, de una octava de ancho. Medidos contra la referencia clásica de estos filtros (el *Audio EQ Cookbook*), la curva coincide en ±0,01 dB.",
                "Cada cambio pasa por una rampa de una décima de segundo, así que mover un fader nunca da chasquidos.",
                "**En NEUTRO es bit a bit**: con todas las bandas a 0, la música sale idéntica. Tras medio segundo en plano, el ecualizador se aparta del todo.",
                "Se descartaron los filtros de «fase lineal»: dan eco previo y retraso, y nada demostró que sonaran mejor aquí.",
            ]),
            HelpSection(title: "Medidores de pico y OVER", text: [
                "Cada canal tiene su medidor de pico y su luz **OVER**, medidos donde la música llega al DAC (después del balance y del volumen). OVER cuenta las veces que la señal se pasa del máximo; el contador vuelve a 0 en cada canción. Si se enciende a menudo, baja **NIVEL**.",
            ]),
            HelpSection(title: "Botones", controls: [
                HelpControl(name: "Faders", text: "Arrastra arriba o abajo; doble clic lo devuelve a 0."),
                HelpControl(name: "EQ", key: "E", text: "Enciende o apaga el ecualizador, para comparar. Apagado guarda la posición de los faders."),
                HelpControl(name: "NEUTRO", key: "⌥⇧⌘E", text: "Todas las bandas a 0 y el nivel al máximo: el sonido tal cual."),
                HelpControl(name: "NIVEL", text: "Nivel general del ecualizador."),
                HelpControl(name: "SHELF", text: "En las bandas de 31 Hz y 16 kHz: cambia campana por estantería."),
                HelpControl(name: "◀ / ▶", text: "Recorre los ajustes guardados."),
                HelpControl(name: "GUARDAR", text: "Guarda el ajuste actual con un nombre."),
                HelpControl(name: "BORRAR", text: "Borra el ajuste guardado que suena ahora."),
                HelpControl(name: "Encendido", text: "Cierra el aparato. Ojo: el sonido sigue como estaba; para quitar el efecto, pulsa EQ o NEUTRO."),
                HelpControl(name: "Abrir el aparato", key: "⌥⌘E", text: "Lo vuelve a poner en la torre."),
            ]),
        ])

    static let meters = HelpTopic(
        id: "meters", title: "Pantallas y medidores", symbol: "gauge.with.needle",
        summary: "Barras, vúmetros y luces OVER: enseñan lo que oyes.",
        sections: [
            HelpSection(title: "Escuchan lo que suena", text: [
                "Todos los medidores escuchan la música **después del ecualizador**, así que enseñan lo que de verdad oyes. Nunca vuelven a leer el disco: eso causaría tirones.",
            ]),
            HelpSection(title: "Los medidores", controls: [
                HelpControl(name: "Barras", text: "Analizador de 24 bandas, de 40 Hz a 16 kHz. Llevan un pequeño realce en los agudos para que las barras altas también se muevan, como en un analizador real."),
                HelpControl(name: "Vúmetros", text: "Agujas del nivel medio de cada canal, con la inercia de un vúmetro real (unas tres décimas de segundo). 0 VU equivale a −16 dBFS; el rojo empieza por encima de 0."),
                HelpControl(name: "Picos y OVER", text: "En el ecualizador: el pico de cada canal donde llega al DAC. OVER cuenta golpes, no muestras: una racha seguida por encima del máximo cuenta 1. La luz se queda encendida 2 segundos."),
                HelpControl(name: "Brillo de las válvulas", text: "Sigue el nivel de cada canal."),
            ]),
        ])

    static let settings = HelpTopic(
        id: "settings", title: "Ajustes", symbol: "gearshape",
        summary: "CDPlayer > Ajustes (⌘,): qué hace cada opción.",
        sections: [
            HelpSection(title: "Opciones", controls: [
                HelpControl(name: "Buscar títulos en internet", text: "La primera vez que metes un disco, pregunta a MusicBrainz el álbum, el artista y las canciones, y los guarda. Apagado, usa los títulos de macOS."),
                HelpControl(name: "Empezar a sonar en cuanto se lea", text: "Al meter un CD, suena solo, sin pulsar Reproducir."),
                HelpControl(name: "Usar el DAC en exclusiva", text: "Mientras suena, la app se queda el DAC: no se mezcla ningún otro sonido ni le cambia la frecuencia. Los demás sonidos del Mac van a los altavoces del Mac hasta que pausas o paras. Empieza al pulsar Reproducir y tarda unas décimas en arrancar."),
                HelpControl(name: "Siempre en primer plano", key: "⌥⌘T", text: "La torre se queda por encima de las demás ventanas. También en el menú Ventana."),
            ]),
        ])

    static let shortcuts = HelpTopic(
        id: "shortcuts", title: "Atajos de teclado", symbol: "keyboard",
        summary: "Todo lo que se puede hacer con el teclado, por menús.",
        sections: [
            HelpSection(title: "Reproducción (CD)", controls: [
                HelpControl(name: "Reproducir / pausa", key: "Espacio", text: ""),
                HelpControl(name: "Detener", key: "⌘.", text: ""),
                HelpControl(name: "Expulsar / abrir bandeja", key: "⌘E", text: ""),
                HelpControl(name: "Canción siguiente / anterior", key: "⌘→ / ⌘←", text: ""),
                HelpControl(name: "Avance / retroceso rápido", key: "⌥→ / ⌥←", text: ""),
                HelpControl(name: "Subir / bajar volumen", key: "⌘↑ / ⌘↓", text: ""),
                HelpControl(name: "Balance a la izquierda / derecha", key: "⇧⌘← / ⇧⌘→", text: ""),
                HelpControl(name: "Centrar balance", key: "⇧⌘B", text: ""),
                HelpControl(name: "Favorita", key: "F", text: ""),
                HelpControl(name: "Solo favoritas", key: "⇧F", text: ""),
                HelpControl(name: "Aleatorio", key: "S", text: ""),
                HelpControl(name: "Repetir", key: "R", text: ""),
                HelpControl(name: "Cambiar pantalla", key: "D", text: ""),
            ]),
            HelpSection(title: "Ecualizador y válvulas", controls: [
                HelpControl(name: "Abrir el ecualizador", key: "⌥⌘E", text: ""),
                HelpControl(name: "Ecualizador encendido", key: "E", text: ""),
                HelpControl(name: "Ecualizador neutro", key: "⌥⇧⌘E", text: ""),
                HelpControl(name: "Abrir el previo a válvulas", key: "⌥⌘V", text: ""),
                HelpControl(name: "Válvulas encendidas", key: "V", text: ""),
                HelpControl(name: "Más / menos calidez", key: "⌥⌘↑ / ⌥⌘↓", text: ""),
                HelpControl(name: "Crossfeed (auriculares)", key: "C", text: ""),
                HelpControl(name: "Siguiente nivel de crossfeed", key: "⇧C", text: ""),
            ]),
            HelpSection(title: "Archivos", controls: [
                HelpControl(name: "Abrir el reproductor de archivos", key: "⌥⌘M", text: ""),
                HelpControl(name: "Elegir música", key: "⌥⌘O", text: ""),
                HelpControl(name: "Buscar canciones nuevas", key: "⌥⌘R", text: ""),
                HelpControl(name: "Reproducir / pausa", key: "⌥Espacio", text: ""),
                HelpControl(name: "Detener", key: "⌥⌘.", text: ""),
                HelpControl(name: "Canción siguiente / anterior", key: "⌥⌘→ / ⌥⌘←", text: ""),
                HelpControl(name: "Avanzar / retroceder 5 segundos", key: "⇧⌥⌘→ / ⇧⌥⌘←", text: ""),
                HelpControl(name: "Favorita", key: "⌥⌘F", text: ""),
                HelpControl(name: "Cambiar vista", key: "⌥⌘L", text: ""),
                HelpControl(name: "Moverse por la lista", key: "↑ / ↓", text: "Tras pulsar en el reproductor de archivos."),
            ]),
            HelpSection(title: "La app", controls: [
                HelpControl(name: "Ajustes", key: "⌘,", text: ""),
                HelpControl(name: "Esta ayuda", key: "⌘?", text: ""),
                HelpControl(name: "Siempre en primer plano", key: "⌥⌘T", text: ""),
                HelpControl(name: "Cerrar CDPlayer", key: "⌘Q", text: ""),
            ]),
        ])

    static let questions = HelpTopic(
        id: "questions", title: "Preguntas frecuentes", symbol: "questionmark.bubble",
        summary: "Lo que suele extrañar la primera vez.",
        sections: [
            HelpSection(title: "He cerrado el ecualizador (o las válvulas) y el sonido sigue igual", text: [
                "Cerrar el aparato no lo apaga: el sonido sigue como lo dejaste. Para quitar el efecto, pulsa **EQ** o **NEUTRO** en el ecualizador, o apaga **VÁLVULAS** y **CROSSFEED** en el previo.",
            ]),
            HelpSection(title: "¿Cuándo uso CROSSFEED?", text: [
                "Con auriculares, sobre todo en discos antiguos con instrumentos muy a un lado. Empieza en **MEDIO**; si lo notas poco, **FUERTE**; si te parece que el sonido pierde anchura, **SUAVE** o apagado. Con los altavoces, apagado.",
            ]),
            HelpSection(title: "Al pulsar Reproducir tarda un instante", text: [
                "Con el DAC en exclusiva, macOS necesita unas décimas de segundo para apartar los demás sonidos. Además, la primera lectura del CD es de medio segundo.",
            ]),
            HelpSection(title: "No oigo otros programas por el DAC", text: [
                "Está activado el DAC en exclusiva: mientras suena la música, los demás sonidos van a los altavoces del Mac. Pausa la música o apaga la opción en Ajustes.",
            ]),
            HelpSection(title: "Hay un silencio corto entre dos canciones", text: [
                "Las dos canciones tienen distinta calidad (por ejemplo 44,1 y 96 kHz) y el DAC está cambiando de frecuencia. Entre canciones de la misma calidad no hay hueco.",
            ]),
            HelpSection(title: "La pantalla dice ERROR DE LECTURA", text: [
                "El disco tiene una raya o suciedad en ese punto. Limpia el disco y pulsa Reproducir: sigue desde donde se paró.",
            ]),
            HelpSection(title: "Se enciende OVER", text: [
                "La señal se pasa del máximo al llegar al DAC, normalmente por subir bandas del ecualizador. Baja **NIVEL** en el ecualizador o baja esas bandas.",
            ]),
            HelpSection(title: "No salen los títulos del disco", text: [
                "No hay internet, el disco no está en MusicBrainz o la opción está apagada en Ajustes. La app usa entonces los títulos que da macOS.",
            ]),
            HelpSection(title: "¿Cómo consigo el sonido más puro?", text: [
                "Válvulas y crossfeed apagados, ecualizador en NEUTRO, balance centrado y volumen al máximo en la app y en el Mac; regula lo fuerte que suena en el DAC o el amplificador. Si quieres, activa el DAC en exclusiva.",
            ]),
        ])
}
