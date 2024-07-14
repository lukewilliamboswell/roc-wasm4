# roc-wasm4

Roc platform for the [wasm4](https://wasm4.org) game engine 🎮🕹️👾

The intent for this platform is to have some fun, learn more about Roc and platform development, and contribute something for others to enjoy.

### Setup

1. Clone this repository.

2. Make sure you have the following in your `PATH` environment variable
- [roc](https://www.roc-lang.org/install),
- [zig](https://ziglang.org/download/) version **0.11.0**
- [w4](https://wasm4.org)

### Run

For the *web runtime* use `zig build run`

For the *native runtime* use `zig build run-native` (Note: native can often be much slower than web especially for non-optimized builds)

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

### Drum Roll

Thank you Isaac Van Doren for this demo.

[Link to source code](https://github.com/isaacvando/roc-drum-machine), and [play online](https://isaacvando.github.io/roc-drum-machine/)

![drum roll](/examples/drum-roll.gif)

### Documentation

📖 Platform docs hosted at [lukewilliamboswell.github.io/roc-wasm4/](https://lukewilliamboswell.github.io/roc-wasm4/)

To generate locally use `roc docs platform/main.roc`, and then use a file server `simple-http-server generated-docs/`.

### Hot Reloading

Well it isn't perfect, hot reloading can be quite nice when developing a game. For this, I suggest using the [entr](https://github.com/eradman/entr) command line tool.

In one terminal run the build command: `find . -name "*.roc" -o -name "*.zig" | entr -ccr zig build -Dapp=<app>`.

In another terminal run wasm4: `w4 run zig-out/lib/cart.wasm --hot`.

If the hot reloading breaks (which it often does when changing the data layout or state), simply press `R` to reload the cart.

### Distribution

To release a game, first build it with optimizations by adding `-Doptimize=ReleaseSmall`.
Then bundle it [like any other wasm4 game](https://wasm4.org/docs/guides/distribution/) using the generated cartidge located in `zig-out/lib/cart.wasm`.
If your cartidge is too large, you can try lowering the dynamic memory space with `-Dmem-size=<size>`. The default is `40960` bytes.

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
