#!/usr/bin/env node
/**
 * Synthesises `assets/sounds/click.wav` — the tap sound.
 *
 * The old asset was a hard click: a bright, fast transient that reads as
 * "mechanical" on a phone speaker and gets tiring after a few taps. This is a
 * wooden tick instead: a low body around 210 Hz that drops slightly as it
 * decays, one quiet partial for the "wood" edge, a 1.6 ms attack ramp so the
 * first sample is never a step, and a 26 ms decay tail. The result is a soft
 * "tok" — tactile rather than audible.
 *
 * Usage:
 *   node tools/synth_click.mjs
 *   node tools/master_sounds.mjs --apply    # normalise to the -35 dBFS target
 */
import { writeFileSync } from 'node:fs';
import { resolve } from 'node:path';

const SAMPLE_RATE = 22050;
const DURATION = 0.09;
const FRAMES = Math.round(SAMPLE_RATE * DURATION);

/** Peak the synth aims for before mastering; the master pass sets the real level. */
const SYNTH_PEAK = 0.95;

function writeWav(path, samples, sampleRate) {
  const frames = samples.length;
  const buffer = Buffer.alloc(44 + frames * 2);
  buffer.write('RIFF', 0, 'ascii');
  buffer.writeUInt32LE(36 + frames * 2, 4);
  buffer.write('WAVE', 8, 'ascii');
  buffer.write('fmt ', 12, 'ascii');
  buffer.writeUInt32LE(16, 16);
  buffer.writeUInt16LE(1, 20); // PCM
  buffer.writeUInt16LE(1, 22); // mono
  buffer.writeUInt32LE(sampleRate, 24);
  buffer.writeUInt32LE(sampleRate * 2, 28); // byte rate
  buffer.writeUInt16LE(2, 32); // block align
  buffer.writeUInt16LE(16, 34); // bits per sample
  buffer.write('data', 36, 'ascii');
  buffer.writeUInt32LE(frames * 2, 40);
  for (let i = 0; i < frames; i++) {
    const clamped = Math.max(-1, Math.min(1, samples[i]));
    buffer.writeInt16LE(Math.round(clamped * 32767), 44 + i * 2);
  }
  writeFileSync(path, buffer);
}

const samples = new Float32Array(FRAMES);
let phase = 0;
let peak = 0;

for (let i = 0; i < FRAMES; i++) {
  const t = i / SAMPLE_RATE;

  // The body glides down from 210 Hz to about 172 Hz: a struck piece of wood
  // drops in pitch as it rings, a pure sine does not.
  const frequency = 210 * (1 - 0.18 * Math.min(1, t / 0.06));
  phase += (2 * Math.PI * frequency) / SAMPLE_RATE;

  const body = Math.sin(phase) * Math.exp(-t / 0.026);
  const partial = Math.sin(phase * 2.02) * Math.exp(-t / 0.011) * 0.22;
  // A step at sample 0 is itself a click; 1.6 ms of ramp removes it.
  const attack = Math.min(1, t / 0.0016);

  const value = (body + partial) * attack;
  samples[i] = value;
  if (Math.abs(value) > peak) peak = Math.abs(value);
}

if (peak > 0) {
  const gain = SYNTH_PEAK / peak;
  for (let i = 0; i < FRAMES; i++) samples[i] *= gain;
}

const path = resolve(import.meta.dirname, '..', 'assets/sounds/click.wav');
writeWav(path, samples, SAMPLE_RATE);
console.log(
  `click.wav  ${FRAMES} frames  ${(FRAMES / SAMPLE_RATE * 1000).toFixed(0)} ms  ` +
    `${SAMPLE_RATE} Hz 16-bit mono  (synth peak ${SYNTH_PEAK})`,
);
