#!/usr/bin/env node
/**
 * Synthesises `assets/sounds/timer.wav` — the focus start/stop cue.
 *
 * The previous asset was a filtered-noise whoosh. On a phone speaker that reads
 * as "air escaping" rather than as a signal, and it competes with the room.
 * This is a soft mallet instead: one warm note at 392 Hz that settles to 370 Hz
 * over 80 ms, a quiet octave for body, an 8 ms raised-cosine attack so the
 * first sample is never a step, and a 20 ms cosine tail so the end is not a
 * cut. About a quarter of a second: long enough to register, short enough to
 * press twice.
 *
 * Usage:
 *   node tools/synth_timer.mjs
 *   node tools/master_sounds.mjs --apply    # normalise to the -24 dBFS target
 */
import { writeFileSync } from 'node:fs';
import { resolve } from 'node:path';

const SAMPLE_RATE = 22050;
const DURATION = 0.26;
const FRAMES = Math.round(SAMPLE_RATE * DURATION);

/** Peak the synth aims for before mastering; the master pass sets the level. */
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
const total = DURATION;
let phase = 0;
let peak = 0;

for (let i = 0; i < FRAMES; i++) {
  const t = i / SAMPLE_RATE;

  // A struck mallet settles in pitch as it rings; a fixed sine sounds synthetic.
  const glide = Math.min(1, t / 0.08);
  const frequency = 392 - 22 * glide;
  phase += (2 * Math.PI * frequency) / SAMPLE_RATE;

  const body = Math.sin(phase) * Math.exp(-t / 0.085);
  const octave = Math.sin(phase * 2) * Math.exp(-t / 0.045) * 0.16;

  // 8 ms raised-cosine attack: no step at sample 0, no click.
  const attack = 0.5 - 0.5 * Math.cos((Math.PI * Math.min(1, t / 0.008)));
  // 20 ms cosine release: the tail reaches zero instead of being cut.
  const releaseStart = total - 0.02;
  const release = t < releaseStart
    ? 1
    : 0.5 + 0.5 * Math.cos((Math.PI * (t - releaseStart)) / 0.02);

  const value = (body + octave) * attack * release;
  samples[i] = value;
  if (Math.abs(value) > peak) peak = Math.abs(value);
}

if (peak > 0) {
  const gain = SYNTH_PEAK / peak;
  for (let i = 0; i < FRAMES; i++) samples[i] *= gain;
}

const path = resolve(import.meta.dirname, '..', 'assets/sounds/timer.wav');
writeWav(path, samples, SAMPLE_RATE);
console.log(
  `timer.wav  ${FRAMES} frames  ${(FRAMES / SAMPLE_RATE * 1000).toFixed(0)} ms  ` +
    `${SAMPLE_RATE} Hz 16-bit mono  (synth peak ${SYNTH_PEAK})`,
);
