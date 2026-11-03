// Linux browser adapter for the immutable examples suite. This executes the
// unmodified official WASM-4 web runtime, including its real drawing and audio
// imports. Blueprint supplies each locked executable and Playwright companions.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { realpath, mkdir, symlink, rename, lstat, writeFile, chmod } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { delimiter, dirname, join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { spawnSync, spawn } from 'node:child_process';
import { createServer } from 'node:http';

async function tool(name) {
    for (const directory of ['/tmp/roc-wasm4-runtime-tools', ...(process.env.PATH ?? '').split(delimiter)]) {
        const candidate = join(directory, name);
        if (existsSync(candidate)) return realpath(candidate);
    }
    throw new Error(`Missing ${name}; run through the Blueprint runtime environment`);
}

if (process.argv[2] === '--tool-identities') {
    console.log(JSON.stringify({ node: process.versions.node, openssl: process.versions.openssl, v8: process.versions.v8, shared_openssl: process.config.variables.node_shared_openssl }));
    process.exit(0);
}

if (process.argv[2] === '--export-tools') {
    const directory = '/tmp/roc-wasm4-runtime-tools';
    await mkdir(directory, { recursive: true, mode: 0o700 });
    const info = await lstat(directory);
    assert(info.isDirectory() && info.uid === process.getuid(), 'runtime directory must belong to this user');
    // Resolve the current Blueprint environment, never an old exported link.
    for (const name of ['node', 'wasm4-playwright', 'w4-archive', 'wasm4-chromium-archive']) {
        const search = (process.env.PATH ?? '').split(delimiter).map(dir => join(dir, name));
        const source = search.find(path => existsSync(path));
        assert(source, `missing ${name} in Blueprint runtime`);
        const temporary = join(directory, `${name}.${process.pid}`);
        await symlink(await realpath(source), temporary);
        await rename(temporary, join(directory, name));
    }
    const w4 = spawnSync('unzip', ['-p', join(directory, 'w4-archive'), 'w4'], { maxBuffer: 64000000, timeout: 30000 });
    assert.equal(w4.status, 0, w4.stderr?.toString());
    await writeFile(join(directory, 'w4'), w4.stdout, { mode: 0o755 });
    await chmod(join(directory, 'w4'), 0o755);
    const chromium = spawnSync('unzip', ['-q', '-o', join(directory, 'wasm4-chromium-archive'), '-d', join(directory, 'chromium')], { timeout: 60000 });
    assert.equal(chromium.status, 0, chromium.stderr?.toString());
    const temporary = join(directory, `chromium.${process.pid}`);
    await symlink(join(directory, 'chromium/chrome-headless-shell-linux64/chrome-headless-shell'), temporary);
    await rename(temporary, join(directory, 'wasm4-chromium'));
    process.exit(0);
}

const cart = process.argv[2];
assert(cart && process.argv.length === 3, 'usage: node run-cart.mjs CART.wasm');
let browser;
let server;
let runtimeProcess;
try {
    // The shared runner builds development carts. The official developer
    // runtime executes these even when unoptimized code exceeds the 64 KiB
    // distribution limit; release-size validation is a separate product check.
    server = createServer();
    await new Promise((done, reject) => { server.once('error', reject); server.listen(0, '127.0.0.1', done); });
    const port = server.address().port;
    await new Promise(done => server.close(done));
    server = undefined;
    runtimeProcess = spawn(await tool('w4'), ['run', '--no-open', '--no-qr', '--port', String(port), resolve(cart)], { stdio: ['ignore', 'pipe', 'pipe'] });
    let startup = '';
    runtimeProcess.stdout.on('data', bytes => { startup = (startup + bytes).slice(-100000); });
    runtimeProcess.stderr.on('data', bytes => { startup = (startup + bytes).slice(-100000); });
    for (let attempt = 0; ; attempt++) {
        try { if ((await fetch(`http://127.0.0.1:${port}/`)).ok) break; } catch {}
        assert(attempt < 100 && runtimeProcess.exitCode === null, `WASM-4 server failed: ${startup}`);
        await new Promise(done => setTimeout(done, 50));
    }
    const playwright = await import(pathToFileURL(join(dirname(await tool('wasm4-playwright')), 'index.mjs')).href);
    browser = await playwright.chromium.launch({ executablePath: await tool('wasm4-chromium'), headless: true, args: ['--no-sandbox', '--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
    const context = await browser.newContext();
    const page = await context.newPage();
    const failures = [];
    page.on('pageerror', error => failures.push(error.message));
    page.on('console', message => { if (message.type() === 'warning' || message.type() === 'error') console.error(message.text()); });
    // Stop the animation loop before runtime initialization. We drive exactly
    // sixty frames below; wall-clock speed cannot change the game state.
    await page.addInitScript(() => {
        window.requestAnimationFrame = () => 0;
        window.__wasm4Traces = [];
        window.__wasm4Imports = {};
        const instantiate = WebAssembly.instantiate.bind(WebAssembly);
        WebAssembly.instantiate = (bytes, imports) => {
            for (const [name, implementation] of Object.entries(imports.env ?? {})) {
                if (typeof implementation !== 'function') continue;
                imports.env[name] = (...args) => {
                    window.__wasm4Imports[name] = (window.__wasm4Imports[name] ?? 0) + 1;
                    const log = console.log;
                    if (name.startsWith('trace')) console.log = (...messages) => { window.__wasm4Traces.push(messages.join(' ')); log(...messages); };
                    try { return implementation(...args); } finally { console.log = log; }
                };
            }
            return instantiate(bytes, imports);
        };
    });
    await page.goto(`http://127.0.0.1:${port}/`, { waitUntil: 'load' });
    // Animation is deliberately disabled above, so readiness must use a timer.
    // Playwright's default animation-frame polling can otherwise stop forever.
    await page.waitForFunction(() => document.querySelector('wasm4-app')?.runtime?.wasm, undefined, { polling: 25 });
    const result = await page.evaluate(async () => {
        const runtime = document.querySelector('wasm4-app').runtime;
        const snapshots = [];
        const snapshot = () => Array.from(new Uint8Array(runtime.memory.buffer, 0xa0, 6400));
        runtime.setMouse(80, 80, 0);
        for (let frame = 0; frame < 60; frame++) {
            // Exercise button presses and release, then let the game advance.
            runtime.setGamepad(0, frame >= 20 && frame < 30 ? 1 : 0);
            runtime.setMouse(80, 80, frame >= 20 && frame < 30 ? 1 : 0);
            runtime.update();
            await Promise.resolve();
            if (runtime.pauseState !== 0) throw new Error(`WASM-4 runtime paused/crashed on frame ${frame}`);
            if (frame === 19 || frame === 29 || frame === 59) snapshots.push(snapshot());
        }
        runtime.composite();
        return { frames: 60, snapshots, memoryBytes: runtime.memory.buffer.byteLength, palette: Array.from(new Uint32Array(runtime.memory.buffer, 4, 4)), trace: window.__wasm4Traces, imports: window.__wasm4Imports };
    });
    assert.deepEqual(failures, [], `browser exceptions: ${failures.join('; ')}`);
    assert.equal(result.memoryBytes, 65536, 'WASM-4 linear memory must stay one page');
    assert(result.snapshots.every(frame => frame.some(byte => byte !== 0)), 'cart produced a blank framebuffer');
    assert(!result.trace.some(line => /panic|canary|overflow|crash|out of memory/i.test(line)), `host failure trace: ${result.trace.join('; ')}`);
    const hashes = result.snapshots.map(frame => createHash('sha256').update(Uint8Array.from(frame)).digest('hex'));
    console.log(JSON.stringify({ frames: result.frames, framebuffer_sha256: hashes, palette: result.palette, trace: result.trace, imports: result.imports }));
} finally {
    if (browser) await browser.close();
    if (server) await new Promise(done => server.close(done));
    if (runtimeProcess && runtimeProcess.exitCode === null) {
        const stopped = new Promise(done => runtimeProcess.once('exit', done));
        runtimeProcess.kill('SIGTERM');
        await stopped;
    }
}
