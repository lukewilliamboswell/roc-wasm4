# roc-wasm4

Roc platform for the [wasm4](https://wasm4.org) game engine 🎮🕹️👾

The intent for this platform is to have some fun, learn more about Roc and platform development, and contribute something for others to enjoy.

### Setup

Clone this repository.

Make sure you have [roc](https://www.roc-lang.org/install) newer than 2023-1-8, [zig](https://ziglang.org/download/) version 0.11.0, and [w4](https://wasm4.org) in your `PATH` environment variable.

### Run

For the *web runtime* use `zig build run`

For the *native runtime* use `zig build run-native`

The `build.zig` script reports any warnings or errors for the app using `roc check`, it then builds an object file using `roc build --target=wasm32 --no-link` and links this with the host to produce the final `.wasm` game cartridge.

### Snake Demo

- Unix/Macos `zig build -Dapp=examples/snake.roc run`
- Windows `zig build -Dapp=".\examples\snake.roc" run`

![snake demo](/examples/snake.gif)

### Rocci-Bird Demo

Thank you Brendan Hansknecht and Luke DeVault (art) for this demo.

[Link to play online](https://bren077s.itch.io/rocci-bird)

- Unix/Macos `zig build -Dapp=examples/rocci-bird.roc run`
- Windows `zig build -Dapp=".\examples\rocci-bird.roc" run`

![rocci-bird demo](/examples/rocci-bird.gif)

### Sound Demo

- Unix/Macos `zig build -Dapp=examples/sound.roc run`
- Windows `zig build -Dapp=".\examples\sound.roc" run`

![sound demo](/examples/sound.gif)

### Documentation

📖 Platform docs hosted at [lukewilliamboswell.github.io/roc-wasm4/](https://lukewilliamboswell.github.io/roc-wasm4/)

To generate locally use `roc docs platform/main.roc`, and then use a file server `simple-http-server generated-docs/`.

### Distribution

To release a game, first build it with optimizations by adding `-Doptimize=ReleaseSmall`.
Then bundle it [like any other wasm4 game](https://wasm4.org/docs/guides/distribution/) using the generated cartidge located in `zig-out/lib/cart.wasm`.

For example, a web release can be built with:
```shell
w4 bundle zig-out/lib/cart.wasm --title "My Game" --html my-game.html
```

For windows/mac/linux, a bundling command could look like:
```shell
w4 bundle zig-out/lib/cart.wasm --title "My Game" \
    --windows my-game-windows.exe \
    --mac my-game-mac \
    --linux my-game-linux
```
