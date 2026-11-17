#!/usr/bin/env node
/**
 * Keeps the compile-time AppInfo in sync with pubspec.yaml.
 *
 * The update checker compares the installed build number with the release
 * manifest. A mismatch here would show a permanent "update available" prompt or
 * hide a real one, so CI fails instead of shipping a lie.
 */
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '..');
const pubspec = readFileSync(resolve(root, 'pubspec.yaml'), 'utf8');
const appInfo = readFileSync(resolve(root, 'lib/core/app_info.dart'), 'utf8');

const pub = /^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$/m.exec(pubspec);
const dartName = /static const String versionName = '([^']+)'/.exec(appInfo);
const dartBuild = /static const int buildNumber = (\d+)/.exec(appInfo);

if (!pub || !dartName || !dartBuild) {
  console.error('FAIL  could not read the version from pubspec.yaml or lib/core/app_info.dart');
  process.exit(1);
}

const expectedName = pub[1];
const expectedBuild = Number(pub[2]);

if (dartName[1] !== expectedName || Number(dartBuild[1]) !== expectedBuild) {
  console.error(
    `FAIL  AppInfo is ${dartName[1]}+${dartBuild[1]} but pubspec.yaml is ${expectedName}+${expectedBuild}`,
  );
  process.exit(1);
}

console.log(`PASS  AppInfo matches pubspec.yaml (${expectedName}+${expectedBuild})`);
