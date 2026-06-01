# Haptico

iOS приложение, которое превращает аудио в тактильную обратную связь (вибрации).

## Как работает

### 1. Анализ аудио
Аудио разбивается на компоненты через FFT (Fast Fourier Transform):

- **Beats** - удары ритма (downbeats и regular beats)
- **Onsets** - атаки звуков (percussive/tonal)
- **Bass** - басовые частоты (sub-bass 20-80 Hz, mid-bass 80-250 Hz)
- **Pitch** - высота тона (80-1200 Hz)
- **RMS** - общая энергия звука
- **Centroid** - яркость звука (центр масс спектра)
- **BPM** - темп трека

### 2. Генерация AHAP паттернов
Каждый аудио-компонент мапится на тактильные параметры:

**Короткие события (Transients):**
- Downbeats → мощные удары (intensity: 1.0, sharpness: 1.0)
- Regular beats → четкие удары (intensity: 0.75, sharpness: 0.9)
- Percussive onsets → резкие удары (intensity: 0.85, sharpness: 1.0)
- Tonal onsets → мягкие удары (intensity: 0.65, sharpness: 0.4-0.8)

**Непрерывные события (Continuous):**
- RMS → фоновая пульсация (intensity: 0.6, sharpness: 0.3)
- Sub-bass → низкочастотный рамбл (intensity: 0.8, sharpness: 0.1)

### 3. Синхронизированное воспроизведение
`SynchronizedPlayer` обеспечивает синхронизацию аудио и тактильной обратной связи с точностью до фрейма.

## DSP Pipeline

```
Audio File → FFT → Feature Extraction → AHAP Generation → Haptic Playback
                         ↓
            [Beat, Onset, Bass, Pitch, RMS, Centroid]
```

## Требования

- iOS 16.0+

## Использование

1. **Demo Track** - встроенный трек "Polina" by BabyCute
2. **Import** - загрузка своих аудио/видео файлов (MP3, MP4, M4A, WAV)
