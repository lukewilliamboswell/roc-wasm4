interface W4
    exposes [
        Pallet,
        text,
        textColor,
        setPallet,
        setDrawColors,
        readGamepad,
        rect,
    ]
    imports [
        Task.{ Task },
        Effect.{ Effect },
    ]

Pallet : [None, Color1, Color2, Color3, Color4]

DrawColors : {
    primary : Pallet,
    secondary : Pallet,
    tertiary : Pallet,
    quaternary : Pallet,
}

GamePad : {
    button1 : Bool,
    button2 : Bool,
    left : Bool,
    right : Bool,
    up : Bool,
    down : Bool,
}

## Draw text to the screen.
##
## ```
## {} <- "Hello World" |> Task.textColor { fg: blue, bg: white } |> Task.await
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

setPallet : { color1 : U32, color2 : U32, color3 : U32, color4 : U32 } -> Task {} []
setPallet = \{ color1, color2, color3, color4 } ->
    Effect.setPallet color1 color2 color3 color4
    |> Effect.map Ok
    |> Task.fromEffect

setDrawColors : DrawColors -> Task {} []
setDrawColors = \colors ->
    colors
    |> toColorFlags
    |> Effect.setDrawColors
    |> Effect.map Ok
    |> Task.fromEffect

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

rect : I32, I32, U32, U32 -> Task {} []
rect = \x, y, width, height ->
    Effect.rect x y width height
    |> Effect.map Ok
    |> Task.fromEffect

textColor : { fg : Pallet, bg : Pallet } -> Task {} []
textColor = \{ fg, bg } ->
    setDrawColors {
        primary: fg,
        secondary: bg,
        tertiary: None,
        quaternary: None,
    }

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
