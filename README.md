# Guitar Tiles

Clone Hero chart dosyalarini oynatan, 5 seritli dokunmatik/tik tabanli ritim oyunu prototipi (Godot 4.x).

## Nasil Calistirilir

1. Godot 4.7+ ile projeyi ac
2. `songs/` klasorune `.chart` veya `.sng` dosyalarini koy
3. Projeyi calistir — menu ekraninda sarkilar listelenir
4. Bir sarki sec ve "Play" tikla

Proje kokunde `notes.chart` varsa menude de gorunur.

## Dosya Yapisi

```
songs/               <- sarki dosyalarini buraya koy
  sarki.sng          <- Clone Hero .sng paketi
  sarki/
    notes.chart      <- veya acik chart dosyasi
    song.ogg         <- ses dosyasi (opsiyonel)
scripts/
  chart_parser.gd    <- .chart dosyasi parser (BPM degisimli tick->ms)
  sng_loader.gd      <- .sng paketi acici (XOR sifre cozme)
  game.gd            <- oynanis mantigi
  menu.gd            <- sarki secim menusu
scenes/
  game.tscn          <- oyun sahnesi
  menu.tscn          <- menu sahnesi
```

## Kontroller

- **Dokunmatik / Fare**: Ekranin 5 serit bolgesine tikla/dokun
- **Klavye**: A-S-D-F-G veya 1-2-3-4-5 tuslari (serit 0-4)
- **Offset slider**: Sag altta, cihaz gecikme telafisi icin +-200 ms

## Ses Formatlari

- `.ogg` (Vorbis) ve `.mp3` desteklenir
- `.opus` Godot tarafindan desteklenmez — `.ogg`'a donusturmeniz gerekir
- Ses dosyasi chart ile ayni klasorde `song.ogg`, `song.mp3`, `guitar.ogg` veya `audio.ogg` olarak aranir

## Bilinen Eksikler

- Sustain (uzun) notalar sadece gorsel, tutma mekanigi yok
- Lyric gosterimi henuz yok (parse ediliyor ama goruntulenmyor)
- Zorluk secimi yok (sadece ExpertSingle)
- Coklu ses kanali destegi yok (sadece ana ses dosyasi calinir)
- Skor tablosu / sonuc ekrani yok
- .sng icindeki opus ses dosyasi icin otomatik donusum yok
