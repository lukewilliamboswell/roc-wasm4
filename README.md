# roc-wasm4

A Roc platform for building [WASM-4](https://wasm4.org) games.

roc-wasm4 gives Roc apps a high-level `W4` API for drawing, input, audio, disk persistence, netplay state, and sprites. Most apps should use a released roc-wasm4 platform bundle directly from GitHub Releases.

## Requirements

- [Roc](https://www.roc-lang.org/install) new-compiler nightly, available as `roc`
- [WASM-4 CLI](https://wasm4.org), available as `w4`
- A roc-wasm4 `.tar.zst` platform bundle URL from the [GitHub Releases page](https://github.com/lukewilliamboswell/roc-wasm4/releases)

## Quick Start

Create `app.roc` and point `platform` at a released `.tar.zst` bundle:

```roc
app [main] {
    w4: platform "https://github.com/lukewilliamboswell/roc-wasm4/releases/download/0.5/sZGj6cG7ted2RNohpqvQwqb7pvBd5C5zotA5XXyJZnA.tar.zst",
}

import w4.W4

Model : {}

main = {
    init!: || {},
    update!: |model| {
        W4.text!("Hello from Roc!", { x: 8, y: 8 })
        model
    },
}
```

Build the cart and run it with WASM-4:

```shell
roc build app.roc
w4 run app.wasm
```

Because roc-wasm4 only declares a `wasm32` target, `roc build app.roc` defaults to writing `app.wasm`.

For the native WASM-4 runtime, use `w4 run-native app.wasm`. Native can be much slower than the web runtime, especially for non-optimized builds.

## Platform API

The platform exposes:

- `w4.W4` for WASM-4 drawing, input, audio, disk, random, and utility APIs
- `w4.Sprite` for sprite data and blitting helpers
- `w4.Host` for low-level hosted effects, mostly intended for platform internals

Platform API docs are hosted at [lukewilliamboswell.github.io/roc-wasm4/](https://lukewilliamboswell.github.io/roc-wasm4/).

## Examples

This repository includes several example apps:

- `examples/basic.roc`: drawing, text, input, mouse, trace, and tone basics
- `examples/snake.roc`: a small playable snake game
- `examples/rocci-bird.roc`: a Rocci Bird demo by Brendan Hansknecht with art by Luke DeVault
- `examples/sound.roc`: a tone parameter playground

The checked-in examples use the local platform path so contributors can test source changes. To use one as a starting point outside this repository, replace:

```roc
w4: platform "../platform/main.roc"
```

with a released bundle URL:

```roc
w4: platform "https://github.com/lukewilliamboswell/roc-wasm4/releases/download/<tag>/<bundle>.tar.zst"
```

Then build and run the app:

```shell
roc build snake.roc
w4 run snake.wasm
```

![snake demo](/examples/snake.gif)

[Play Rocci Bird online](https://bren077s.itch.io/rocci-bird).

![rocci-bird demo](/examples/rocci-bird.gif)

![sound demo](/examples/sound.gif)

Drum Roll is a separate demo by Isaac Van Doren. [Source](https://github.com/isaacvando/roc-drum-machine) and [play online](https://isaacvando.github.io/roc-drum-machine/).

![drum roll](/examples/drum-roll.gif)

## Game Distribution

For a smaller game cart, build the Roc app with size-oriented optimizations:

```shell
roc build app.roc --opt=size
```

Bundle the generated cart with the WASM-4 CLI:

```shell
w4 bundle app.wasm --title "My Game" --html my-game.html
```

For native bundles:

```shell
w4 bundle app.wasm --title "My Game" \
    --windows my-game-windows.exe \
    --mac my-game-mac \
    --linux my-game-linux
```

## Contributing

Source-build setup, local checks, docs generation, and release maintenance are covered in [CONTRIBUTING.md](CONTRIBUTING.md).
