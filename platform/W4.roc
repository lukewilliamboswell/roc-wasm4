## # roc-wasm4
##
## Build [wasm4](https://wasm4.org) games using Roc
##
interface W4
    exposes [
        Palette,
        Mouse,
        Gamepad,
        Netplay,
        Player,
        Shader,
        screenWidth,
        screenHeight,
        text,
        setPalette,
        getPalette,
        setDrawColors,
        getDrawColors,
        setPrimaryColor,
        setTextColors,
        setShapeColors,
        getGamepad,
        getMouse,
        getNetplay,
        rect,
        oval,
        line,
        hline,
        vline,
        seedRand,
        rand,
        randBetween,
        trace,
        debug,
        saveToDisk,
        loadFromDisk,
        preserveFrameBuffer,
        clearFrameBufferEachUpdate,
        hideGamepadOverlay,
        showGamepadOverlay,
        tone,
        getPixel,
        setPixel,
        runShader,
    ]
    imports [InternalTask, Task.{ Task }, Effect.{ Effect }]

## The [Palette] consists of four colors. There is also `None` which is used to
## represent a transparent or no change color. Each pixel on the screen will be
## drawn using one of these colors.
##
## You may find it helpful to create an alias for your game.
##
## ```
## red = Color2
## green = Color3
##
## W4.setTextColors { fg: red, bg: green }
## ```
##
Palette : [None, Color1, Color2, Color3, Color4]

## Represents the four colors in the [Palette].
DrawColors : {
    primary : Palette,
    secondary : Palette,
    tertiary : Palette,
    quaternary : Palette,
}

## Represents the current state of a [Player] gamepad.
##
## ```
## Gamepad : {
##     button1 : Bool,
##     button2 : Bool,
##     left : Bool,
##     right : Bool,
##     up : Bool,
##     down : Bool,
## }
## ```
##
Gamepad : {
    button1 : Bool,
    button2 : Bool,
    left : Bool,
    right : Bool,
    up : Bool,
    down : Bool,
}

## Represents the current state of the mouse.
##
## ```
## Mouse : {
##     x : I16,
##     y : I16,
##     left : Bool,
##     right : Bool,
##     middle : Bool,
## }
## ```
##
Mouse : {
    x : I16,
    y : I16,
    left : Bool,
    right : Bool,
    middle : Bool,
}

## Represents the current state of [Netplay](https://wasm4.org/docs/guides/multiplayer#netplay).
##
## Netplay connects gamepad inputs over the Internet using WebRTC.
##
## ```
## Netplay : [
##     Enabled Player,
##     Disabled,
## ]
## ```
##
Netplay : [
    Enabled Player,
    Disabled,
]

## Represents [Player].
##
## [WASM-4 supports realtime multiplayer](https://wasm4.org/docs/guides/multiplayer) of up to 4 players, either locally or online.
##
Player : [Player1, Player2, Player3, Player4]

## Represents fragment shader for raw operations with the framebuffer.
##
## ```
## Shader : U8, U8, Palette -> Palette
## ```
##
Shader : U8, U8, Palette -> Palette

screenWidth = 160
screenHeight = 160

## Set the color [Palette] for your game.
##
## ```
## W4.setPalette {
##     color1: 0xffffff,
##     color2: 0xff0000,
##     color3: 0x000ff00,
##     color4: 0x0000ff,
## }
## ```
##
## Warning: this will overwrite the existing [Palette], changing all colors on the screen.
##
setPalette : { color1 : U32, color2 : U32, color3 : U32, color4 : U32 } -> Task {} []
setPalette = \{ color1, color2, color3, color4 } ->
    Effect.setPalette color1 color2 color3 color4
    |> Effect.map Ok
    |> InternalTask.fromEffect

## Get the color [Palette] for your game.
##
## ```
## {color1, color2, color3, color4} <- W4.getPalette |> Task.await
## ```
##
getPalette : Task { color1 : U32, color2 : U32, color3 : U32, color4 : U32 } []
getPalette =
    Effect.getPalette
    |> Effect.map Ok
    |> InternalTask.fromEffect

## Set the draw colors for the next draw command.
##
## ```
## blue = Color1
## white = Color4
## W4.setDrawColors {
##     primary : blue,
##     secondary : white,
##     tertiary : None,
##     quaternary : None,
## }
## ```
##
## Warning: this will overwrite any existing draw colors that are set.
##
setDrawColors : DrawColors -> Task {} []
setDrawColors = \colors ->
    colors
    |> toColorFlags
    |> Effect.setDrawColors
    |> Effect.map Ok
    |> InternalTask.fromEffect

## Get the currently set draw colors.
##
## ```
## {primary, secondary} <- W4.getDrawColors |> Task.await
## ```
##
getDrawColors : Task DrawColors []
getDrawColors =
    Effect.getDrawColors
    |> Effect.map fromColorFlags
    |> Effect.map Ok
    |> InternalTask.fromEffect

## Helper for primary drawing color.
##
## ```
## blue = Color1
## W4.setPrimaryColor blue
## ```
##
## Warning: this will overwrite any existing draw colors, and sets the
## secondary, tertiary and quaternary values to `None`.
##
setPrimaryColor : W4.Palette -> Task {} []
setPrimaryColor = \primary ->
    setDrawColors {
        primary,
        secondary: None,
        tertiary: None,
        quaternary: None,
    }

## Helper for setting the draw colors for text.
##
## ```
## blue = Color1
## white = Color4
## W4.setTextColors { fg : blue, bg : white }
## ```
##
## Warning: this will overwrite any existing draw colors, and sets the
## tertiary and quaternary values to `None`.
##
setTextColors : { fg : Palette, bg : Palette } -> Task {} []
setTextColors = \{ fg, bg } ->
    setDrawColors {
        primary: fg,
        secondary: bg,
        tertiary: None,
        quaternary: None,
    }

## Helper for colors when drawing a shape.
##
## ```
## blue = Color1
## white = Color4
## W4.setShapeColors { border : blue, fill : white }
## ```
##
## Warning: this will overwrite any existing draw colors, and sets the
## tertiary and quaternary values to `None`.
##
setShapeColors : { border : W4.Palette, fill : W4.Palette } -> Task {} []
setShapeColors = \{ border, fill } ->
    setDrawColors {
        primary: fill,
        secondary: border,
        tertiary: None,
        quaternary: None,
    }

## Draw text to the screen.
##
## ```
## W4.text "Hello, World" {x: 0, y: 0}
## ```
##
## Text color is the Primary draw color.
##
## Background color is the Secondary draw color.
##
## [Refer w4 docs for more information](https://wasm4.org/docs/guides/text)
##
text : Str, { x : I32, y : I32 } -> Task {} []
text = \str, { x, y } ->
    Effect.text str x y
    |> Effect.map Ok
    |> InternalTask.fromEffect

## Draw a rectangle to the screen.
##
## ```
## W4.rect {x: 0, y: 10, width: 40, height: 60}
## ```
##
## Fill color is the Primary draw color.
##
## Border color is the Secondary draw color.
##
## [Refer w4 docs for more information](https://wasm4.org/docs/reference/functions#rect-x-y-width-height)
##
rect : { x : I32, y : I32, width : U32, height : U32 } -> Task {} []
rect = \{ x, y, width, height } ->
    Effect.rect x y width height
    |> Effect.map Ok
    |> InternalTask.fromEffect

## Draw an oval to the screen.
##
## ```
## W4.oval {x, y, width: 20, height: 30}
## ```
##
## Fill color is the Primary draw color.
##
## Border color is the Secondary draw color.
##
## [Refer w4 docs for more information](https://wasm4.org/docs/reference/functions#oval-x-y-width-height)
##
oval : { x : I32, y : I32, width : U32, height : U32 } -> Task {} []
oval = \{ x, y, width, height } ->
    Effect.oval x y width height
    |> Effect.map Ok
    |> InternalTask.fromEffect

## Draw a line between two points to the screen.
##
## ```
## W4.line {x: 0, y: 0}, {x: 10, y: 10}
## ```
##
## Line color is the Primary draw color.
##
## [Refer w4 docs for more information](https://wasm4.org/docs/reference/functions#line-x1-y1-x2-y2)
##
line : { x : I32, y : I32 }, { x : I32, y : I32 } -> Task {} []
line = \{ x: x1, y: y1 }, { x: x2, y: y2 } ->
    Effect.line x1 y1 x2 y2
    |> Effect.map Ok
    |> InternalTask.fromEffect

## Draw a horizontal line starting at (x, y) with len to the screen.
##
## ```
## W4.hline {x: 10, y: 20, len: 30}
## ```
##
## Line color is the Primary draw color.
##
## [Refer w4 docs for more information](https://wasm4.org/docs/reference/functions#line-x1-y1-x2-y2)
##
hline : { x : I32, y : I32, len : U32 } -> Task {} []
hline = \{ x, y, len } ->
    Effect.hline x y len
    |> Effect.map Ok
    |> InternalTask.fromEffect

## Draw a vertical line starting at (x, y) with len to the screen.
##
## ```
## W4.vline {x: 10, y: 20, len: 30}
## ```
##
## Line color is the Primary draw color.
##
## [Refer w4 docs for more information](https://wasm4.org/docs/reference/functions#line-x1-y1-x2-y2)
##
vline : { x : I32, y : I32, len : U32 } -> Task {} []
vline = \{ x, y, len } ->
    Effect.vline x y len
    |> Effect.map Ok
    |> InternalTask.fromEffect

## Get the controls for a [Gamepad].
##
## ```
## {button1,button2,left,right,up,down} <- W4.getGamepad Player1 |> Task.await
## ```
##
getGamepad : Player -> Task Gamepad []
getGamepad = \player ->

    gamepadNumber =
        when player is
            Player1 -> 1
            Player2 -> 2
            Player3 -> 3
            Player4 -> 4

    Effect.getGamepad gamepadNumber
    |> Effect.map \flags ->
        Ok {
            # 1 BUTTON_1
            button1: Num.bitwiseAnd 0b0000_0001 flags > 0,
            # 2 BUTTON_2
            button2: Num.bitwiseAnd 0b0000_0010 flags > 0,
            # 16 BUTTON_LEFT
            left: Num.bitwiseAnd 0b0001_0000 flags > 0,
            # 32 BUTTON_RIGHT
            right: Num.bitwiseAnd 0b0010_0000 flags > 0,
            # 64 BUTTON_UP
            up: Num.bitwiseAnd 0b0100_0000 flags > 0,
            # 128 BUTTON_DOWN
            down: Num.bitwiseAnd 0b1000_0000 flags > 0,
        }
    |> InternalTask.fromEffect

## Get the current [Mouse] position.
##
## ```
## {x,y,left,right,middle} <- W4.getMouse |> Task.await
## ```
##
getMouse : Task Mouse []
getMouse =
    Effect.getMouse
    |> Effect.map \{ x, y, buttons } ->
        Ok {
            x: x,
            y: y,
            # 1 MOUSE_LEFT
            left: Num.bitwiseAnd 0b0000_0001 buttons > 0,
            # 2 MOUSE_RIGHT
            right: Num.bitwiseAnd 0b0000_0010 buttons > 0,
            # 4 MOUSE_MIDDLE
            middle: Num.bitwiseAnd 0b0000_0100 buttons > 0,
        }
    |> InternalTask.fromEffect

## Get the [Netplay] status.
##
## ```
## netplay <- W4.getNetplay |> Task.await
## when netplay is
##     Enabled Player1 -> # ..
##     Enabled Player2 -> # ..
##     Enabled Player3 -> # ..
##     Enabled Player4 -> # ..
##     Disabled -> # ..
## ```
##
## Note: All WASM-4 games that support local multiplayer automatically support netplay.
## There are no additional steps developers need to take to make their games netplay-ready.
## Netplay can be used to implement advanced features such as non-shared screen multiplayer
##
## [Refer w4 docs for more information](https://wasm4.org/docs/guides/multiplayer)
##
getNetplay : Task Netplay []
getNetplay =
    Effect.getNetplay
    |> Effect.map \flags ->
        enabled = Num.bitwiseAnd 0b0000_0100 flags > 0
        if enabled then
            player =
                when Num.bitwiseAnd 0b0000_0011 flags is
                    0 -> Player1
                    1 -> Player2
                    2 -> Player3
                    3 -> Player4
                    _ -> crash "It is impossible for this value to be greater than 3"
            Ok (Enabled player)
        else
            Ok Disabled
    |> InternalTask.fromEffect

## Seeds the global pseudo-random number generator.
##
## ```
## {} <- W4.seedRand framesSinceStart |> Task.await
## ```
##
## Wasm4 exposes no way to seed a random number generator.
## As such, anything random will be exactly the same on every run by default.
## To work around this, it is suggested to count the number of frames the user is on
## the title screen before starting the game and use that to seed the prng.
##
seedRand : U64 -> Task {} []
seedRand = \s ->
    Effect.seedRand s
    |> Effect.map Ok
    |> InternalTask.fromEffect

## Generate a pseudo-random number.
##
## ```
## # pseudo-random number between Num.minI32 and Num.maxI32 (inclusive of both)
## i <- W4.rand |> Task.await
## ```
##
## Warning: Wasm4 exposes no way to seed a random number generator.
## As such, anything random will be exactly the same on every run by default.
## To work around this, it is suggested to count the number of frames the user is on
## the title screen before starting the game and use that to seed the prng.
##
rand : Task I32 []
rand =
    Effect.rand
    |> Effect.map Ok
    |> InternalTask.fromEffect

## Generate a pseudo-random number in the range.
##
## The range has an inclusive start and exclusive end.
##
## ```
## # random number in the range 0-99
## i <- W4.randBetween {start: 0, before: 100} |> Task.await
## ```
##
## Warning: Wasm4 exposes no way to seed a random number generator.
## As such, anything random will be exactly the same on every run by default.
## To work around this, it is suggested to count the number of frames the user is on
## the title screen before starting the game and use that to seed the prng.
##
randBetween : { start : I32, before : I32 } -> Task I32 []
randBetween = \{ start, before } ->
    Effect.randRangeLessThan start before
    |> Effect.map Ok
    |> InternalTask.fromEffect

## Prints a message to the debug console.
##
## ```
## W4.trace "Hello, World"
## ```
##
## [Refer w4 docs for more information](https://wasm4.org/docs/guides/trace)
##
trace : Str -> Task {} []
trace = \str ->
    Effect.trace str
    |> Effect.map Ok
    |> InternalTask.fromEffect

## Prints a message with a debug formatting of the value to the console.
##
## ```
## W4.debug "my int" 7
## ```
##
debug : Str, val -> Task {} [] where val implements Inspect.Inspect
debug = \msg, val ->
    trace "$(msg): $(Inspect.toStr val)"

## Saves data to persistent storage. Any previously saved data on the disk is replaced.
##
## Returns `Err SaveFailed` on failure.
##
## ```
## result <- W4.saveToDisk [0x10] |> Task.attempt
## when result is
##    Ok {} -> # success
##    Err SaveFailed -> # handle failure
## ```
##
## Games can persist up to 1024 bytes of data.
##
## [Refer w4 docs for more information](https://wasm4.org/docs/guides/diskw)
##
saveToDisk : List U8 -> Task {} [SaveFailed]
saveToDisk = \data ->
    Effect.diskw data
    |> Effect.map \succeeded ->
        if succeeded then
            Ok {}
        else
            Err SaveFailed
    |> InternalTask.fromEffect

## Gets all saved data from persistent storage.
##
## ```
## data <- W4.loadFromDisk |> Task.await
## ```
##
## Games can persist up to 1024 bytes of data.
##
## [Refer w4 docs for more information](https://wasm4.org/docs/guides/diskw)
##
loadFromDisk : Task (List U8) []
loadFromDisk =
    Effect.diskr
    |> Effect.map Ok
    |> InternalTask.fromEffect

## Set a flag to keep the framebuffer between frames.
##
## This can be helpful if you only want to update part of the screen.
##
preserveFrameBuffer : Task {} []
preserveFrameBuffer =
    Effect.setPreserveFrameBuffer Bool.true
    |> Effect.map Ok
    |> InternalTask.fromEffect

## Set a flag to clear the framebuffer between frames.
clearFrameBufferEachUpdate : Task {} []
clearFrameBufferEachUpdate =
    Effect.setPreserveFrameBuffer Bool.false
    |> Effect.map Ok
    |> InternalTask.fromEffect

## Set a flag to hide the game overlay.
hideGamepadOverlay : Task {} []
hideGamepadOverlay =
    Effect.setHideGamepadOverlay Bool.true
    |> Effect.map Ok
    |> InternalTask.fromEffect

## Set a flag to show the game overlay.
showGamepadOverlay : Task {} []
showGamepadOverlay =
    Effect.setHideGamepadOverlay Bool.false
    |> Effect.map Ok
    |> InternalTask.fromEffect

## Get the color for an individual pixel in the framebuffer.
getPixel : { x : U8, y : U8 } -> Task Palette []
getPixel = \{ x, y } ->
    Effect.getPixel x y
    |> Effect.map extractColor
    |> Effect.map Ok
    |> InternalTask.fromEffect

## Set the color for an individual pixel in the framebuffer.
setPixel : { x : U8, y : U8 }, Palette -> Task {} []
setPixel = \{ x, y }, color ->
    bits =
        when color is
            None -> 0x0
            Color1 -> 0x1
            Color2 -> 0x2
            Color3 -> 0x3
            Color4 -> 0x4

    Effect.setPixel x y bits
    |> Effect.map Ok
    |> InternalTask.fromEffect

# Run a fragment [Shader] on the raw framebuffer.
runShader : Shader -> Task {} []
runShader = \shader ->
    Task.loop (0, 0) \(x, y) ->
        if x == screenWidth && y == screenHeight then
            Task.ok (Done {})
        else if x == screenWidth then
            (0, (y + 1))
            |> Step
            |> Task.ok
        else
            color <- getPixel { x, y } |> Task.await
            newColor = shader x y color
            {} <- setPixel { x, y } newColor |> Task.await
            ((x + 1), y)
            |> Step
            |> Task.ok

## Plays a tone sound.
##
## Please refer to the [wasm4 audio docs](https://wasm4.org/docs/guides/audio/).
##
## The sound.roc example app along with the [wasm4 sound tools](https://wasm4.org/docs/guides/audio/#sound-tool) can be quite helpful to play with.
tone :
    {
        startFreq ? U16,
        endFreq ? U16,
        channel ? [
            Pulse1 [Eighth, Quarter, Half, ThreeQuarters],
            Pulse2 [Eighth, Quarter, Half, ThreeQuarters],
            Triangle,
            Noise,
        ],
        pan ? [Center, Left, Right],
        sustainTime ? U8,
        releaseTime ? U8,
        decayTime ? U8,
        attackTime ? U8,
        volume ? U8,
        peakVolume ? U8,
    }
    -> Task {} []
tone = \{ startFreq ? 0, endFreq ? 0, channel ? Pulse1 Eighth, pan ? Center, sustainTime ? 0, releaseTime ? 0, decayTime ? 0, attackTime ? 0, volume ? 100, peakVolume ? 0 } ->
    freq =
        Num.toU32 endFreq
        |> Num.shiftLeftBy 16
        |> Num.bitwiseOr (Num.toU32 startFreq)

    duration =
        Num.toU32 attackTime
        |> Num.shiftLeftBy 24
        |> Num.bitwiseOr (Num.toU32 releaseTime |> Num.shiftLeftBy 16)
        |> Num.bitwiseOr (Num.toU32 decayTime |> Num.shiftLeftBy 8)
        |> Num.bitwiseOr (Num.toU32 sustainTime)

    volumeBits =
        Num.toU16 peakVolume
        |> Num.shiftLeftBy 8
        |> Num.bitwiseOr (Num.toU16 volume)

    panBits =
        when pan is
            Center -> 0
            # pub const TONE_PAN_LEFT: u32 = 16;
            Left -> 16
            # pub const TONE_PAN_RIGHT: u32 = 32;
            Right -> 32

    convertMode = \m ->
        when m is
            # pub const TONE_MODE1: u32 = 0;
            Eighth -> 0
            # pub const TONE_MODE2: u32 = 4;
            Quarter -> 4
            # pub const TONE_MODE3: u32 = 8;
            Half -> 8
            # pub const TONE_MODE4: u32 = 12;
            ThreeQuarters -> 12

    (channelBits, modeBits) =
        when channel is
            # pub const TONE_PULSE1: u32 = 0;
            Pulse1 mode -> (0, convertMode mode)
            # pub const TONE_PULSE2: u32 = 1;
            Pulse2 mode -> (1, convertMode mode)
            # pub const TONE_TRIANGLE: u32 = 2;
            Triangle -> (2, 0)
            # pub const TONE_NOISE: u32 = 3;
            Noise -> (3, 0)

    flags =
        panBits
        |> Num.bitwiseOr modeBits
        |> Num.bitwiseOr channelBits

    Effect.tone freq duration volumeBits flags
    |> Effect.map Ok
    |> InternalTask.fromEffect

# HELPERS ------

toColorFlags : DrawColors -> U16
toColorFlags = \{ primary, secondary, tertiary, quaternary } ->

    pos1 =
        when primary is
            None -> 0x0
            Color1 -> 0x1
            Color2 -> 0x2
            Color3 -> 0x3
            Color4 -> 0x4

    pos2 =
        when secondary is
            None -> 0x00
            Color1 -> 0x10
            Color2 -> 0x20
            Color3 -> 0x30
            Color4 -> 0x40

    pos3 =
        when tertiary is
            None -> 0x000
            Color1 -> 0x100
            Color2 -> 0x200
            Color3 -> 0x300
            Color4 -> 0x400

    pos4 =
        when quaternary is
            None -> 0x0000
            Color1 -> 0x1000
            Color2 -> 0x2000
            Color3 -> 0x3000
            Color4 -> 0x4000

    0
    |> Num.bitwiseOr pos1
    |> Num.bitwiseOr pos2
    |> Num.bitwiseOr pos3
    |> Num.bitwiseOr pos4

expect toColorFlags { primary: Color2, secondary: Color4, tertiary: None, quaternary: None } == 0x0042
expect toColorFlags { primary: Color1, secondary: Color2, tertiary: Color3, quaternary: Color4 } == 0x4321

extractColor = \pos ->
    when pos is
        0x0 -> None
        0x1 -> Color1
        0x2 -> Color2
        0x3 -> Color3
        0x4 -> Color4
        _ -> crash "got invalid draw color from the host"

fromColorFlags : U16 -> DrawColors
fromColorFlags = \flags ->
    pos1 = Num.bitwiseAnd 0x000F flags |> Num.toU8
    pos2 = Num.bitwiseAnd 0x00F0 flags |> Num.shiftRightZfBy 4 |> Num.toU8
    pos3 = Num.bitwiseAnd 0x0F00 flags |> Num.shiftRightZfBy 8 |> Num.toU8
    pos4 = Num.bitwiseAnd 0xF000 flags |> Num.shiftRightZfBy 12 |> Num.toU8

    primary = extractColor pos1
    secondary = extractColor pos2
    tertiary = extractColor pos3
    quaternary = extractColor pos4

    { primary, secondary, tertiary, quaternary }

expect
    res = fromColorFlags 0x0042
    res == { primary: Color2, secondary: Color4, tertiary: None, quaternary: None }
expect fromColorFlags 0x4321 == { primary: Color1, secondary: Color2, tertiary: Color3, quaternary: Color4 }

