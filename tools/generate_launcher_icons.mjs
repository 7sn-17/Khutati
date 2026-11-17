#!/usr/bin/env node
// Generates every Android launcher icon slot from icon.png.
//
// Android does not scale one bitmap for all slots: legacy launchers read
// density-specific square/round icons, and API 26+ adaptive icons need a
// 108dp foreground whose artwork stays inside the 72dp safe zone, plus a
// background layer. Shipping a single xxxhdpi bitmap leaves every other
// density upscaled or mis-cropped.
//
// Dependency-free on purpose (Node zlib only): the build machines and this
// repo do not carry ImageMagick, and regenerating icons must stay reproducible.
import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';

const SOURCE = 'icon.png';
const RES = 'android/app/src/main/res';
const PREVIEW_ONLY = process.argv.includes('--preview');

// Android legacy icon sizes in dp; one PNG per density.
const LEGACY = [
  ['mdpi', 48],
  ['hdpi', 72],
  ['xhdpi', 96],
  ['xxhdpi', 144],
  ['xxxhdpi', 192],
];

// Adaptive layers are 108dp squares; the visible mask is 72dp (safe zone) for
// the foreground. Android crops the outer 18dp on every side.
const ADAPTIVE = [
  ['mdpi', 108],
  ['hdpi', 162],
  ['xhdpi', 216],
  ['xxhdpi', 324],
  ['xxxhdpi', 432],
];

/* -------------------------------------------------------------------------- */
/* PNG decode / encode (8-bit, non-interlaced)                                */
/* -------------------------------------------------------------------------- */

function decodePng(file) {
  const b = fs.readFileSync(file);
  if (b.toString('hex', 0, 8) !== '89504e470d0a1a0a') {
    throw new Error(`${file} is not a PNG`);
  }

  let offset = 8;
  let width = 0;
  let height = 0;
  let bitDepth = 0;
  let colorType = 0;
  const idat = [];

  while (offset < b.length) {
    const length = b.readUInt32BE(offset);
    const type = b.toString('ascii', offset + 4, offset + 8);
    const data = b.subarray(offset + 8, offset + 8 + length);
    if (type === 'IHDR') {
      width = data.readUInt32BE(0);
      height = data.readUInt32BE(4);
      bitDepth = data[8];
      colorType = data[9];
      if (data[12] !== 0) throw new Error('interlaced PNG is not supported');
    } else if (type === 'IDAT') {
      idat.push(data);
    } else if (type === 'IEND') {
      break;
    }
    offset += length + 12;
  }

  if (bitDepth !== 8) throw new Error(`bit depth ${bitDepth} is not supported`);
  if (colorType !== 2) {
    throw new Error(`colour type ${colorType} is not supported (need RGB)`);
  }

  const bpp = 3;
  const stride = width * bpp;
  const raw = zlib.inflateSync(Buffer.concat(idat));
  const pixels = Buffer.alloc(width * height * bpp);

  for (let y = 0; y < height; y++) {
    const filter = raw[y * (stride + 1)];
    const rowIn = raw.subarray(y * (stride + 1) + 1, (y + 1) * (stride + 1));
    const rowOut = pixels.subarray(y * stride, (y + 1) * stride);
    const prev = y > 0 ? pixels.subarray((y - 1) * stride, y * stride) : null;

    for (let x = 0; x < stride; x++) {
      const a = x >= bpp ? rowOut[x - bpp] : 0;
      const up = prev ? prev[x] : 0;
      const left = x >= bpp && prev ? prev[x - bpp] : 0;
      let value = rowIn[x];
      if (filter === 1) value = (value + a) & 0xff;
      else if (filter === 2) value = (value + up) & 0xff;
      else if (filter === 3) value = (value + ((a + up) >> 1)) & 0xff;
      else if (filter === 4) value = (value + paeth(a, up, left)) & 0xff;
      else if (filter !== 0) throw new Error(`bad filter ${filter}`);
      rowOut[x] = value;
    }
  }

  return { width, height, pixels, bpp };
}

function paeth(a, b, c) {
  const p = a + b - c;
  const pa = Math.abs(p - a);
  const pb = Math.abs(p - b);
  const pc = Math.abs(p - c);
  if (pa <= pb && pa <= pc) return a;
  if (pb <= pc) return b;
  return c;
}

const CRC_TABLE = (() => {
  const table = new Int32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    table[n] = c;
  }
  return table;
})();

function crc32(buffer) {
  let c = 0xffffffff;
  for (let i = 0; i < buffer.length; i++) {
    c = CRC_TABLE[(c ^ buffer[i]) & 0xff] ^ (c >>> 8);
  }
  return (c ^ 0xffffffff) >>> 0;
}

function chunk(type, data) {
  const length = Buffer.alloc(4);
  length.writeUInt32BE(data.length);
  const typeBuf = Buffer.from(type, 'ascii');
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(Buffer.concat([typeBuf, data])));
  return Buffer.concat([length, typeBuf, data, crc]);
}

function encodePng({ width, height, pixels, bpp }) {
  const colorType = bpp === 4 ? 6 : 2;
  const stride = width * bpp;
  const raw = Buffer.alloc((stride + 1) * height);
  for (let y = 0; y < height; y++) {
    raw[y * (stride + 1)] = 0;
    pixels.copy(raw, y * (stride + 1) + 1, y * stride, (y + 1) * stride);
  }

  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8;
  ihdr[9] = colorType;
  ihdr[10] = 0;
  ihdr[11] = 0;
  ihdr[12] = 0;

  return Buffer.concat([
    Buffer.from('89504e470d0a1a0a', 'hex'),
    chunk('IHDR', ihdr),
    chunk('IDAT', zlib.deflateSync(raw, { level: 9 })),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}

/* -------------------------------------------------------------------------- */
/* Resampling                                                                 */
/* -------------------------------------------------------------------------- */

/** Area-average downscale to width x height, preserving RGB. */
function resize(source, width, height) {
  const { pixels, width: sw, height: sh, bpp } = source;
  const out = Buffer.alloc(width * height * bpp);

  for (let y = 0; y < height; y++) {
    const sy0 = (y * sh) / height;
    const sy1 = ((y + 1) * sh) / height;
    for (let x = 0; x < width; x++) {
      const sx0 = (x * sw) / width;
      const sx1 = ((x + 1) * sw) / width;
      let r = 0;
      let g = 0;
      let b = 0;
      let total = 0;

      for (let sy = Math.floor(sy0); sy < Math.ceil(sy1); sy++) {
        const wy = Math.min(sy + 1, sy1) - Math.max(sy, sy0);
        for (let sx = Math.floor(sx0); sx < Math.ceil(sx1); sx++) {
          const wx = Math.min(sx + 1, sx1) - Math.max(sx, sx0);
          const weight = wx * wy;
          const i = (sy * sw + sx) * bpp;
          r += pixels[i] * weight;
          g += pixels[i + 1] * weight;
          b += pixels[i + 2] * weight;
          total += weight;
        }
      }

      const o = (y * width + x) * bpp;
      out[o] = Math.round(r / total);
      out[o + 1] = Math.round(g / total);
      out[o + 2] = Math.round(b / total);
    }
  }

  return { width, height, pixels: out, bpp };
}

/* -------------------------------------------------------------------------- */
/* Icon composition                                                           */
/* -------------------------------------------------------------------------- */

function averageCorners(image) {
  const { pixels, width, height, bpp } = image;
  const samples = [];
  const patch = Math.max(2, Math.round(Math.min(width, height) * 0.02));
  for (const [x0, y0] of [
    [0, 0],
    [width - patch, 0],
    [0, height - patch],
    [width - patch, height - patch],
  ]) {
    let r = 0;
    let g = 0;
    let b = 0;
    for (let y = y0; y < y0 + patch; y++) {
      for (let x = x0; x < x0 + patch; x++) {
        const i = (y * width + x) * bpp;
        r += pixels[i];
        g += pixels[i + 1];
        b += pixels[i + 2];
      }
    }
    const n = patch * patch;
    samples.push([r / n, g / n, b / n]);
  }
  return [0, 1, 2].map((c) =>
    Math.round(samples.reduce((sum, s) => sum + s[c], 0) / samples.length),
  );
}

/** Source artwork centred on a square canvas, scaled to `content` of it. */
function compose({ source, canvas, content, background }) {
  const out = Buffer.alloc(canvas * canvas * 4);
  for (let i = 0; i < canvas * canvas; i++) {
    out[i * 4] = background[0];
    out[i * 4 + 1] = background[1];
    out[i * 4 + 2] = background[2];
    out[i * 4 + 3] = 255;
  }

  const inner = Math.round(canvas * content);
  const art = resize(source, inner, inner);
  const offset = Math.floor((canvas - inner) / 2);

  for (let y = 0; y < inner; y++) {
    for (let x = 0; x < inner; x++) {
      const s = (y * inner + x) * 3;
      const d = ((y + offset) * canvas + x + offset) * 4;
      out[d] = art.pixels[s];
      out[d + 1] = art.pixels[s + 1];
      out[d + 2] = art.pixels[s + 2];
      out[d + 3] = 255;
    }
  }

  return { width: canvas, height: canvas, pixels: out, bpp: 4 };
}

/** Circular mask centred on the canvas, keeping [fraction] of its width. */
function maskCircle(image, fraction) {
  const { width, height, pixels } = image;
  const out = Buffer.from(pixels);
  const radius = (width * fraction) / 2;
  const center = width / 2;
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const dx = x + 0.5 - center;
      const dy = y + 0.5 - center;
      if (Math.hypot(dx, dy) > radius) out[(y * width + x) * 4 + 3] = 0;
    }
  }
  return { width, height, pixels: out, bpp: 4 };
}

/** Circular mask for legacy round icons (transparent outside the circle). */
function round(image) {
  const { width, height, pixels } = image;
  const out = Buffer.from(pixels);
  const radius = width / 2;
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const dx = x + 0.5 - radius;
      const dy = y + 0.5 - radius;
      if (Math.hypot(dx, dy) > radius - 0.5) out[(y * width + x) * 4 + 3] = 0;
    }
  }
  return { width, height, pixels: out, bpp: 4 };
}

function writePng(file, image) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, encodePng(image));
  console.log(`${file}  ${image.width}x${image.height}`);
}

function hex([r, g, b]) {
  return `#${[r, g, b].map((v) => v.toString(16).padStart(2, '0')).join('')}`;
}

/* -------------------------------------------------------------------------- */

const source = decodePng(SOURCE);
const background = averageCorners(source);
console.log(`source ${source.width}x${source.height}, corner ${hex(background)}`);

if (PREVIEW_ONLY) {
  const legacy = compose({ source, canvas: 512, content: 1, background });
  writePng('build/icon-preview.png', legacy);
  writePng('build/icon-round-preview.png', round(legacy));
  const adaptive = compose({
    source,
    canvas: 512,
    content: 74 / 108,
    background,
  });
  writePng(
    'build/icon-adaptive-preview.png',
    maskCircle(adaptive, 72 / 108),
  );
  process.exit(0);
}

// Legacy icons: the full artwork, padded slightly so nothing touches the edge
// once a launcher applies its own square/rounded mask.
for (const [density, size] of LEGACY) {
  const square = compose({
    source,
    canvas: size,
    content: 1,
    background,
  });
  writePng(`${RES}/mipmap-${density}/ic_launcher.png`, square);
  writePng(`${RES}/mipmap-${density}/ic_launcher_round.png`, round(square));
}

// Adaptive layers: the artwork is 74dp of the 108dp canvas. The logo's
// farthest point (the arrow tip) sits ~35dp from the centre, inside the 36dp
// radius of the 72dp visible circle, and the artwork's square edge falls in
// the 18dp parallax margin, so no seam shows. The background is a flat colour
// resource matching the artwork's corners in case a launcher exposes it.
for (const [density, size] of ADAPTIVE) {
  const foreground = compose({
    source,
    canvas: size,
    content: 74 / 108,
    background,
  });
  writePng(`${RES}/mipmap-${density}/ic_launcher_foreground.png`, foreground);
}

const adaptiveXml = `<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
</adaptive-icon>
`;
fs.mkdirSync(`${RES}/mipmap-anydpi-v26`, { recursive: true });
fs.writeFileSync(`${RES}/mipmap-anydpi-v26/ic_launcher.xml`, adaptiveXml);
fs.writeFileSync(`${RES}/mipmap-anydpi-v26/ic_launcher_round.xml`, adaptiveXml);
fs.rmSync(`${RES}/mipmap-anydpi-v26/ic_launcher_background.png`, {
  force: true,
});
console.log(`adaptive background colour ${hex(background)}`);
