# roc-wasm4

Roc platform for the [wasm4](https://wasm4.org) game engine 🎮🕹️👾

The intent for this platform is to have some fun, learn more about Roc and platform development, and contribute something for others to enjoy.

### Setup

1. Clone this repository.

2. Make sure you have the following in your `PATH` environment variable
- [roc](https://www.roc-lang.org/install),
- [zig](https://ziglang.org/download/) version **0.16.0**
- [w4](https://wasm4.org)

### Run

Build the WASM-4 host library once:

```shell
zig build
```

Then build a game cart with Roc and run it with WASM-4:

```shell
roc build examples/snake.roc --target=wasm32
w4 run snake.wasm
```

For the native WASM-4 runtime, use `w4 run-native snake.wasm`. Native can be much slower than web, especially for non-optimized builds.

The `build.zig` script builds `platform/targets/wasm32/libhost.a`. Roc then links that static library with the app when you run `roc build <app>.roc --target=wasm32`.

The complete `roc build` experience for WASM-4 still needs upstream Roc support for platform-configured import memory, exports, and GC linker settings. That work is tracked in [roc-lang/roc#9538](https://github.com/roc-lang/roc/issues/9538).

### Manual Link Workaround

While Roc's own wasm linker support is being finished, use the manual linker script for carts that can be compiled to a Roc wasm32 object:

```shell
scripts/link_wasm4.sh examples/basic.roc basic.wasm
w4 run basic.wasm
```

The script builds `platform/targets/wasm32/libhost.a`, asks Roc for a `--no-link` wasm32 object, then links with `zig wasm-ld` using WASM-4-compatible memory imports, `start`/`update` exports, and a data base above the WASM-4 framebuffer.

### Snake Demo

- Unix/Macos `zig build && roc build examples/snake.roc --target=wasm32 && w4 run snake.wasm`
- Windows `zig build && roc build .\examples\snake.roc --target=wasm32 && w4 run snake.wasm`

![snake demo](/examples/snake.gif)

### Rocci-Bird Demo

Thank you Brendan Hansknecht and Luke DeVault (art) for this demo.

[Link to play online](https://bren077s.itch.io/rocci-bird)

- Unix/Macos `zig build && roc build examples/rocci-bird.roc --target=wasm32 && w4 run rocci-bird.wasm`
- Windows `zig build && roc build .\examples\rocci-bird.roc --target=wasm32 && w4 run rocci-bird.wasm`

![rocci-bird demo](/examples/rocci-bird.gif)

### Sound Demo

- Unix/Macos `zig build && roc build examples/sound.roc --target=wasm32 && w4 run sound.wasm`
- Windows `zig build && roc build .\examples\sound.roc --target=wasm32 && w4 run sound.wasm`

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

In one terminal run the build command: `find . -name "*.roc" -o -name "*.zig" | entr -ccr sh -c 'zig build && roc build examples/snake.roc --target=wasm32'`.

In another terminal run wasm4: `w4 run snake.wasm --hot`.

If the hot reloading breaks (which it often does when changing the data layout or state), simply press `R` to reload the cart.

### Distribution

To release a game, first build the host with optimizations and then build the Roc app for size:

```shell
zig build -Doptimize=ReleaseSmall
roc build examples/snake.roc --target=wasm32 --opt=size
```

Then bundle it [like any other wasm4 game](https://wasm4.org/docs/guides/distribution/) using the generated cartridge, for example `snake.wasm`.
If your cartridge is too large, you can try lowering the dynamic memory space with `-Dmem-size=<size>`. The default is `40960` bytes.

For example, a web release can be built with:
```shell
w4 bundle snake.wasm --title "My Game" --html my-game.html
```

For windows/mac/linux, a bundling command could look like:
```shell
w4 bundle snake.wasm --title "My Game" \
    --windows my-game-windows.exe \
    --mac my-game-mac \
    --linux my-game-linux
```

To package this platform as a Roc archive, run `./bundle.sh`. It writes a `.tar.zst` file in the repository root.
