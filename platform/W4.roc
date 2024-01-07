interface W4
    exposes [
        Palette,
        Sprite,
        Mouse,
        GamePad,
        text,
        setTextColors,
        setPalette,
        getPalette,
        setDrawColors,
        readGamepad,
        readMouse,
        rect,
        setRectColors,
        screenWidth,
        screenHeight,
        rand,
        randRangeLessThan,
        trace,
    ]
    imports [Task.{ Task }, Effect.{ Effect }]

Palette : [None, Color1, Color2, Color3, Color4]

DrawColors : {
    primary : Palette,
    secondary : Palette,
    tertiary : Palette,
    quaternary : Palette,
}

GamePad : {
    button1 : Bool,
    button2 : Bool,
    left : Bool,
    right : Bool,
    up : Bool,
    down : Bool,
}

Mouse : {
    x : I16,
    y : I16,
    left : Bool,
    right : Bool,
    middle : Bool,
}

Sprite := {
    data : List U8,
    bpp : [BPP1, BPP2],
    width : U32,
    height : U32,
}

screenWidth = 160
screenHeight = 160

setPalette : { color1 : U32, color2 : U32, color3 : U32, color4 : U32 } -> Task {} []
setPalette = \{ color1, color2, color3, color4 } ->
    Effect.setPalette color1 color2 color3 color4
    |> Effect.map Ok
    |> Task.fromEffect

getPalette : Task { color1 : U32, color2 : U32, color3 : U32, color4 : U32 } []
getPalette =
    Effect.getPalette
    |> Effect.map Ok
    |> Task.fromEffect

setDrawColors : DrawColors -> Task {} []
setDrawColors = \colors ->
    colors
    |> toColorFlags
    |> Effect.setDrawColors
    |> Effect.map Ok
    |> Task.fromEffect

## Draw text to the screen.
##
## ```
## W4.text "Hello, World" {x: 0, y: 0}
## ```
##
## Text color is the Primary draw color
## Background color is the Secondary draw color
##
## [Refer w4 docs for more information](https://wasm4.org/docs/guides/text)
text : Str, { x : I32, y : I32 } -> Task {} []
text = \str, { x, y } ->
    Effect.text str x y
    |> Effect.map Ok
    |> Task.fromEffect

## Helper for colors when drawing text
setTextColors : { fg : Palette, bg : Palette } -> Task {} []
setTextColors = \{ fg, bg } ->
    setDrawColors {
        primary: fg,
        secondary: bg,
        tertiary: None,
        quaternary: None,
    }

## Draw a rectangle to the screen.
##
## ```
## W4.rect x y width height
## ```
##
## Text color is the Primary draw color
## Background color is the Secondary draw color
##
## [Refer w4 docs for more information](https://wasm4.org/docs/reference/functions#rect-x-y-width-height)
rect : I32, I32, U32, U32 -> Task {} []
rect = \x, y, width, height ->
    Effect.rect x y width height
    |> Effect.map Ok
    |> Task.fromEffect

## Helper for colors when drawing a rectangle
setRectColors : { border : W4.Palette, fill : W4.Palette } -> Task {} []
setRectColors = \{ border, fill } ->
    setDrawColors {
        primary: fill,
        secondary: border,
        tertiary: None,
        quaternary: None,
    }

## Read the controls for a GamePad
readGamepad : [Player1, Player2, Player3, Player4] -> Task GamePad []
readGamepad = \player ->

    gamepadNumber =
        when player is
            Player1 -> 1
            Player2 -> 2
            Player3 -> 3
            Player4 -> 4

    Effect.readGamepad gamepadNumber
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
    |> Task.fromEffect

## Read the mouse input
readMouse : Task Mouse []
readMouse =
    Effect.readMouse
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
    |> Task.fromEffect

## Generate a psuedo-random number
rand : Task I32 []
rand =
    Effect.rand
    |> Effect.map Ok
    |> Task.fromEffect

## Generate a psuedo-random number in specified range
## The range has an inclusive start and exclusive end
randRangeLessThan : I32, I32 -> Task I32 []
randRangeLessThan = \start, end ->
    Effect.randRangeLessThan start end
    |> Effect.map Ok
    |> Task.fromEffect

## Prints a message to the debug console.
##
## ```
## W4.trace "Hello, World"
## ```
##
## [Refer w4 docs for more information](https://wasm4.org/docs/guides/trace)
trace : Str -> Task {} []
trace = \str ->
    Effect.trace str
    |> Effect.map Ok
    |> Task.fromEffect

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
