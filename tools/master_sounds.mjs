#!/usr/bin/env node
/**
 * Masters the bundled UI sounds to a fixed peak level.
 *
 * The Android low-latency path (SoundPool) applies the gain when a sample is
 * loaded, not when it is replayed, so `AudioPlayer.setVolume` never reached the
 * mix: every release played the files at whatever level they were written at,
 * no matter what the Dart constant said. The gain therefore lives in the
 * assets, where it is applied once and cannot be skipped by the platform.
 *
 * Usage:
 *   node tools/master_sounds.mjs             # report the current peaks
 *   node tools/master_sounds.mjs --apply     # normalise to TARGETS
 *
 * Normalising to a target peak is idempotent: running --apply twice produces
 * the same files, so a re-master can never compound by accident.
 */
import { readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '..');

/**
 * Target peak per sound, in dBFS. The tap is the quietest because it fires on
 * every press; the chime is allowed to be the most present because it plays
 * once per completed step.
 */
const TARGETS = {
  click: -24,
  toggle: -24,
  success: -21,
  timer: -26,
};

const FILES = ['click', 'toggle', 'success', 'timer'];

function readHeader(buffer) {
  if (buffer.toString('ascii', 0, 4) !== 'RIFF' || buffer.toString('ascii', 8, 12) !== 'WAVE') {
    throw new Error('not a RIFF/WAVE file');
  }
  let offset = 12;
  let bits = 0;
  let channels = 0;
  while (offset + 8 <= buffer.length) {
    const id = buffer.toString('ascii', offset, offset + 4);
    const size = buffer.readUInt32LE(offset + 4);
    if (id === 'fmt ') {
      channels = buffer.readUInt16LE(offset + 10);
      bits = buffer.readUInt16LE(offset + 22);
    }
    if (id === 'data') {
      return { dataOffset: offset + 8, dataSize: size, bits, channels };
    }
    offset += 8 + size + (size % 2);
  }
  throw new Error('no data chunk');
}

function peakOf(buffer, offset, size) {
  let peak = 0;
  for (let i = 0; i + 1 < size; i += 2) {
    const value = Math.abs(buffer.readInt16LE(offset + i));
    if (value > peak) peak = value;
  }
  return peak;
}

const apply = process.argv.includes('--apply');
const db = (peak) => (peak === 0 ? '-inf' : (20 * Math.log10(peak / 32768)).toFixed(1));

for (const name of FILES) {
  const path = resolve(root, 'assets/sounds', `${name}.wav`);
  const buffer = readFileSync(path);
  const { dataOffset, dataSize, bits, channels } = readHeader(buffer);
  if (bits !== 16 || channels !== 1) {
    throw new Error(`${name}.wav must be 16-bit mono, got ${bits}-bit / ${channels}ch`);
  }

  const before = peakOf(buffer, dataOffset, dataSize);
  if (!apply) {
    console.log(`${name.padEnd(8)} peak ${String(before).padStart(5)}  ${db(before)} dBFS`);
    continue;
  }

  const target = 32768 * Math.pow(10, TARGETS[name] / 20);
  const gain = before === 0 ? 1 : target / before;
  for (let i = 0; i + 1 < dataSize; i += 2) {
    const scaled = Math.round(buffer.readInt16LE(dataOffset + i) * gain);
    buffer.writeInt16LE(Math.max(-32768, Math.min(32767, scaled)), dataOffset + i);
  }
  const after = peakOf(buffer, dataOffset, dataSize);
  writeFileSync(path, buffer);
  console.log(
    `${name.padEnd(8)} ${db(before)} -> ${db(after)} dBFS  (gain ${gain.toFixed(3)})`,
  );
}
