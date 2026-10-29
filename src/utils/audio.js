/**
 * Tiny Web Audio helper so the rest timer can beep without shipping an asset.
 * Browsers block audio until a user gesture, so call unlockAudio() from a click
 * handler (logging a set) before relying on playBeep().
 */

let context = null;

const getContext = () => {
  if (typeof window === 'undefined') return null;
  const AudioCtor = window.AudioContext || window.webkitAudioContext;
  if (!AudioCtor) return null;
  if (!context) context = new AudioCtor();
  if (context.state === 'suspended') context.resume();
  return context;
};

export const unlockAudio = () => {
  getContext();
};

export const playBeep = ({ frequency = 880, duration = 0.18, times = 2 } = {}) => {
  const audio = getContext();
  if (!audio) return;

  for (let i = 0; i < times; i += 1) {
    const start = audio.currentTime + i * 0.3;
    const oscillator = audio.createOscillator();
    const gain = audio.createGain();

    oscillator.type = 'sine';
    oscillator.frequency.value = frequency;

    // Ramps instead of hard starts: a square edge clicks on phone speakers.
    gain.gain.setValueAtTime(0.0001, start);
    gain.gain.exponentialRampToValueAtTime(0.25, start + 0.015);
    gain.gain.exponentialRampToValueAtTime(0.0001, start + duration);

    oscillator.connect(gain).connect(audio.destination);
    oscillator.start(start);
    oscillator.stop(start + duration + 0.02);
  }
};

export const vibrate = (pattern = [120, 60, 120]) => {
  if (typeof navigator !== 'undefined' && typeof navigator.vibrate === 'function') {
    navigator.vibrate(pattern);
  }
};
