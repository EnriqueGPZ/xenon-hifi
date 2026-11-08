# El sonido: el camino, los algoritmos y la calidad

*[Read in English](SOUND.md)*

Esta página explica paso a paso qué hace XENON con el sonido y cómo se comprueba cada cosa. En corto: **con las válvulas y el crossfeed apagados, el ecualizador plano y el volumen al máximo, la música llega a tu DAC exactamente como está en el disco o en el archivo, a su propia frecuencia.** Todo lo que añade la app es opcional, y las pruebas lo miden.

## El camino

```
CD (.aiff de macOS) ───┐                                                         ┌─► medidores
                       ├─► lector ─► reproductor ─► válvulas + crossfeed ─► ecualizador ─► mezclador (volumen) ─► Core Audio ─► DAC
FLAC/ALAC/WAV/AIFF/MP3 ┘  (antisaltos)  (balance)          (TP-4)             (EQ-10)
```

Por dentro todo va en **coma flotante de 32 bits**, el formato propio del audio de macOS. Un número de 32 bits en coma flotante guarda exactamente cualquier muestra de 16 o 24 bits, así que llevar la música así no pierde nada.

## 1. Leer la música

**CD.** Con un CD de audio, macOS enseña cada pista como un archivo `.aiff` con las muestras exactas del disco, a 44,1 kHz y 16 bits. XENON lee esos archivos directamente, con su propio lector de AIFF (`CDPlayerKit/CDTrackReader.swift`), sin pasar por un reproductor que adivine o convierta.

**Memoria antisaltos.** Los lectores de CD USB van rápidos con lecturas grandes y muy lentos con muchas pequeñas. La app lee el disco **de 2 en 2 segundos** (medio segundo en la primera lectura, para que empiece enseguida) y tiene unos **12 segundos preparados por delante** de lo que suena. Nada más lee el disco mientras suena: los medidores escuchan el sonido que ya está sonando. Si una lectura falla (una raya, un cable flojo), lo reintenta 3 veces. Si sigue fallando, suena todo lo ya leído y se para en el punto exacto con «ERROR DE LECTURA».

**Archivos.** FLAC, ALAC, WAV, AIFF y MP3 los descodifica **el propio Mac** (`CDPlayerKit/FileTrackReader.swift`), a la frecuencia del archivo y sin convertirla. Un FLAC de 16 o 24 bits sale idéntico al original, y las pruebas lo comprueban. Los archivos mono suenan por los dos canales.

## 2. El DAC a la frecuencia de la música

Antes de cada canción, la app pone tu DAC a la frecuencia de esa canción (`Player/OutputDevice.swift`): 44,1 kHz para un CD, 96 kHz para un archivo de 96 kHz, etc. Sin esto, macOS convertiría todo en silencio a la frecuencia que tuviera puesta el DAC. Entre canciones de frecuencia distinta hay un silencio breve mientras el DAC cambia; entre canciones de la misma frecuencia, no hay hueco.

Si el DAC cambia de frecuencia, se desenchufa o vuelve, macOS reinicia el motor de audio y tira lo que tenía en cola. XENON vuelve a leer la música desde el segundo exacto donde iba.

**El DAC en exclusiva (opcional).** Con *Ajustes ▸ Sonido ▸ Usar el DAC en exclusiva*, XENON se queda el DAC para él solo mientras suena la música (el *hog mode* de Core Audio, `ExclusiveOutput` en `Player/OutputDevice.swift`). Ningún aviso, vídeo u otro programa se mezcla con la música ni le cambia la frecuencia. macOS manda los demás sonidos a otra salida (los altavoces del Mac) hasta que pausas o paras; entonces el DAC queda libre, y si la app se cierra, macOS lo libera solo. Al coger el DAC, macOS cambia la salida predeterminada del sistema y AVAudioEngine la sigue un momento después, así que XENON espera unos 0,3 s y entonces fija su motor al DAC: es la pequeña pausa al pulsar Reproducir. Viene apagado, y se ha probado con un DAC USB; usa una función estándar de macOS, así que otros DAC deberían comportarse igual.

## 3. Balance

Funciona como el de un amplificador: en el centro los dos canales quedan a su nivel completo, y al girar solo baja el contrario. En el centro no toca el sonido.

## 4. Las válvulas (TP-4)

Un modelo por software de **una etapa de triodo de hi-fi**, como las de ECC88 o 12AU7 de un previo a válvulas (`CDPlayerKit/Tube.swift`).

- **Por qué suena cálido.** Un triodo amplifica un poco más una mitad de la onda que la otra. Esa curvatura desigual añade sobre todo **armónicos pares**, en especial el 2º (una octava por encima). El oído los oye como calidez y cuerpo, no como distorsión.
- **La curva.** Una tangente hiperbólica con sesgo, `tanh(u + b) − tanh(b)`, el modelo clásico de un triodo cerca de su punto de trabajo. Se calcula como `tanh(u) / (1 + t·tanh(u))` con `t = tanh(b) = 0,5`: es la misma curva, pero con cuentas más limpias. Está ajustada a **ganancia 1 con sonido flojo**, así que el volumen no cambia y solo cambia el color.
- **CALIDEZ** decide cuánto se empuja la válvula. Al 100 %, un tono a −6 dBFS recibe un **4 % de 2º armónico (−28 dB)**, y el 3º queda al menos 20 dB por debajo. Al 50 %, más o menos la mitad. Los pasajes flojos reciben mucho menos, como en una etapa real.
- **Sobremuestreo, para que no aparezca nada falso.** Una curva crea armónicos nuevos más agudos. A frecuencia de CD, los que pasan de 22 kHz se doblarían hacia la zona audible como tonos falsos (aliasing). Por eso la etapa trabaja a **4 veces la frecuencia hasta 48 kHz, 2 veces hasta 96 kHz y 1 vez por encima**. Los filtros son polifásicos de sinc con ventana (ventana de Kaiser, β 8,96, 64 coeficientes por fase). A cambio, retrasan el sonido 1,5 ms.
- **Filtro de continua.** La curvatura desigual también añade un pequeño desplazamiento fijo. Solo lo que *añade* la curva pasa por un filtro de 2 Hz que lo quita; la música en sí no se filtra ahí.
- **Apagado es apagado.** Apagada, la etapa devuelve el sonido intacto, bit a bit. Al encender o apagar hace un fundido de 30 ms, así que nunca da un chasquido.
- **El brillo** sigue el nivel RMS de cada canal entre −40 y −10 dBFS, y las válvulas tardan 4 segundos en calentarse.

Lo que miden las pruebas (`Tests/CDPlayerKitTests/TubeTests.swift`):

| Comprobación | Resultado exigido |
|---|---|
| Apagado | idéntico bit a bit a la entrada |
| Nivel del sonido flojo | dentro de 0,05 dB |
| Nivel con música | dentro de 0,3 dB |
| 2º armónico, tono a −6 dBFS, CALIDEZ 100 % | entre −32 y −24 dB |
| 3º armónico | más de 20 dB por debajo del 2º |
| Tono de 14,1 kHz a 44,1 kHz: tonos falsos doblados | por debajo de −80 dB |
| Tono de 18 kHz | nivel dentro de 0,1 dB |
| Encender/apagar | sin chasquidos |

Con un álbum real de 24 bits y 176,4 kHz y CALIDEZ al 100 %, el nivel medio cambió unos 0,01 dB.

### Crossfeed (TP-4), para auriculares

Con altavoces, cada oído oye los dos: el altavoz izquierdo llega también al oído derecho, rodeando la cabeza, unas décimas de milisegundo más tarde, más flojo y sin agudos. Con auriculares cada oído oye solo su canal, así que la música suena dentro de la cabeza, y lo que va mezclado a un solo lado (muy típico en los discos estéreo de los 60) suena pegado a una oreja. CROSSFEED pasa a cada oído un poco del otro canal, como haría la cabeza (`CDPlayerKit/Crossfeed.swift`):

```
izquierdo = L + g · (graves(R) − graves(L))
derecho   = R + g · (graves(L) − graves(R))
```

- `graves` es un filtro suave (6 dB por octava a 650–700 Hz): los agudos apenas cruzan, y su fase retrasa lo que cruza `1/(2π·corte)`, unos **0,23 ms** en los graves, parecido a lo que tarda el sonido en rodear la cabeza. No hace falta un retardo aparte.
- Solo cruza la **diferencia** entre canales, así que lo que es igual en los dos (una voz en el centro) sale **idéntico bit a bit**: ni más fuerte ni con más graves. En los graves, un sonido mezclado del todo a un lado llega al otro oído `feed` dB más bajo que al suyo: `g = a/(1+a)` con `a = 10^(−feed/20)`.
- Tres niveles clásicos: **SUAVE** (Jan Meier, 650 Hz, 9,5 dB), **MEDIO** (Chu Moy, 700 Hz, 6 dB), **FUERTE** (Bauer, 700 Hz, 4,5 dB). Viene apagado.
- Va en el eslabón del previo, tras las válvulas. El ecualizador trata igual los dos canales, así que suena igual que si fuera el último. Apagado no toca nada; encender, apagar o cambiar de nivel hace un fundido de 30 ms.
- Medido en las pruebas: apagado es idéntico, el centro es idéntico, el otro oído queda `feed` dB más bajo (±0,3 dB) en los graves, un tono de 10 kHz cruza más de 20 dB más bajo, el retraso es de 0,23 ms, encenderlo con música no da chasquido y funciona a 192 kHz.

## 5. El ecualizador (EQ-10)

- **Diez bandas separadas una octava** (de 31 Hz a 16 kHz, las frecuencias ISO), ±12 dB en pasos de 0,5 dB, más un control NIVEL de 0 a −12 dB para dejar sitio cuando se suben bandas.
- **Los filtros** son los de Apple (`AVAudioUnitEQ`): filtros de campana de fase mínima (biquads), de una octava de ancho. Medidos contra el *Audio EQ Cookbook* (la referencia clásica de estos filtros), la curva coincide en **±0,01 dB**. Las dos bandas de los extremos pueden ser **estanterías** (graves en 63 Hz, agudos en 8 kHz, pendiente estándar S = 1), medidas en 0,03 dB.
- **Plano es bit a bit.** Con todas las bandas a 0 dB, la salida es idéntica bit a bit a la entrada. Tras medio segundo en plano, el ecualizador se aparta del todo.
- **Sin chasquidos.** Cada cambio pasa por una rampa de 6 pasos, una décima de segundo. Para cambiar una banda de campana a estantería, primero se lleva a 0 dB, se cambia y se vuelve.
- **Descartado:** los filtros de fase lineal. Producen eco previo y retraso, y nada demostró que sonaran mejor aquí.

## 6. Volumen

La perilla de volumen es **digital**: multiplica las muestras, en coma flotante de 32 bits, después del ecualizador. Por debajo del máximo, las muestras cambian; es lo que hace cualquier volumen digital. Para la señal más limpia, deja la perilla al máximo y también el volumen del Mac para ese DAC, y ajusta lo fuerte que suena en el DAC o el amplificador.

## 7. Los medidores enseñan lo que oyes

Las barras, las agujas, el brillo de las válvulas y las luces OVER escuchan **después del ecualizador**. Los medidores de pico y OVER escuchan donde el sonido llega al DAC, tras el balance y el volumen.

- **Barras de espectro.** Una FFT de 2048 puntos (ventana de Hann, con Accelerate de Apple), repartida en 24 bandas separadas por igual en octavas, de 40 Hz a 16 kHz. Llevan un pequeño realce hacia los agudos para que las barras altas también se muevan, como en un analizador real.
- **Vúmetros.** Nivel RMS, con **0 VU = −16 dBFS**. La aguja tiene la inercia de un VU real: alcanza el 99 % de un salto en 0,3 s. La escala está impresa en voltaje, como la de un medidor de verdad.
- **OVER.** Cuenta *golpes*, como los medidores de estudio: una racha de muestras por encima del máximo cuenta 1, aunque cruce bloques. La luz se queda encendida 2 segundos. No cuenta el pico real entre muestras (*true peak*), que se encendería con masters altos aun con el ecualizador plano.

## Qué es bit a bit, exactamente

Con **las válvulas y el crossfeed apagados, el ecualizador plano, el balance en el centro y el volumen al máximo**, cada etapa de la app deja pasar el sonido sin tocarlo, y las pruebas lo demuestran una por una. La música sale de XENON tal como entró, a su propia frecuencia. Desde ahí, Core Audio se la entrega a tu DAC en el formato del propio DAC.

Límite conocido: los WAV/AIFF de 32 bits *enteros* (rarísimos) no salen idénticos, porque el motor trabaja en coma flotante de 32 bits.

## Lo que más se nota

La app mantiene la señal limpia, pero lo que oyes es tu **DAC, tu amplificador y tus auriculares o altavoces**. XENON les entrega la música intacta a su propia frecuencia, y solo le da color cuando tú lo pides.
