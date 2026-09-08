# roc-wasm4

A Roc platform for building [WASM-4](https://wasm4.org) games.

roc-wasm4 gives Roc apps a high-level `W4` API for drawing, input, audio, disk persistence, netplay state, and sprites. Most apps should use a released roc-wasm4 platform bundle directly from GitHub Releases.

## Requirements

- [Roc](https://www.roc-lang.org/install), available as `roc`; use the compiler declared in the example you build
- [WASM-4 CLI](https://wasm4.org), available as `w4`
- A roc-wasm4 `.tar.zst` platform bundle URL from the [GitHub Releases page](https://github.com/lukewilliamboswell/roc-wasm4/releases)

## Quick Start

Copy the [basic example](examples/basic/main.roc) into your own application directory.
Its header declares the compiler and released platform bundle it uses. Keep those
entries when adapting the example into your own game.

Build the example and run it with WASM-4:

```shell
roc version
roc build examples/basic/main.roc --output=basic.wasm
w4 run basic.wasm
```

For the native WASM-4 runtime, use `w4 run-native basic.wasm`. Native can be much slower than the web runtime, especially for non-optimized builds.

## Platform API

The platform exposes:

- `w4.W4` for WASM-4 drawing, input, audio, disk, random, and utility APIs
- `w4.Sprite` for sprite data and blitting helpers
- `w4.Host` for low-level hosted effects, mostly intended for platform internals

Platform API docs are hosted at [lukewilliamboswell.github.io/roc-wasm4/](https://lukewilliamboswell.github.io/roc-wasm4/).

## Examples

This repository includes several example apps:

- `examples/basic/main.roc`: drawing, text, input, mouse, trace, and tone basics
- `examples/snake/main.roc`: a small playable snake game
- `examples/rocci-bird/main.roc`: a Rocci Bird demo by Brendan Hansknecht with art by Luke DeVault
- `examples/sound/main.roc`: a tone parameter playground

Each application lives in its own directory and uses a released platform bundle.
Copy the whole directory when starting a game. Install the compiler in its `roc`
header before building; the header does not install it.

Contributors testing platform source changes can use the local path shown in [CONTRIBUTING.md](CONTRIBUTING.md).

Then build and run the app:

```shell
roc version
roc build examples/snake/main.roc --output=snake.wasm
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
