app [main, Model] { w4: platform "../platform/main.roc" }

import w4.Task exposing [Task]
import w4.W4

Program : {
    init : Task Model [],
    update : Model -> Task Model [],
}

Model : {}

main : Program
main = { init, update }

init : Task Model []
init =

    savedData = W4.loadFromDisk!

    saves =
        when List.first savedData is
            Ok v -> v
            Err _ -> 0
    W4.trace! "Game has been loaded $(Inspect.toStr saves) times"

    # Ignore save failures
    _ = W4.saveToDisk [Num.addWrap saves 1] |> Task.result!
    setColorPalette!
    setDrawColors!

    palette = W4.getPalette!
    W4.trace! (Inspect.toStr palette)

    colors = W4.getDrawColors!
    W4.trace! (Inspect.toStr colors)

    W4.tone! {
        startFreq: 262,
        endFreq: 523,
        channel: Pulse1 Quarter,
        sustainTime: 60,
        decayTime: 30,
    }

update : Model -> Task Model []
update = \model ->

    # Get inputs
    { button1, button2, left, right, up, down } = W4.getGamepad! Player1
    mouse = W4.getMouse!
    # Draw the gamepad state
    W4.setTextColors! { fg: red, bg: green }
    "X: $(Inspect.toStr button1)" |> W4.text! { x: 0, y: 0 }
    W4.setTextColors! { fg: blue, bg: white }
    "Z: $(Inspect.toStr button2)" |> W4.text! { x: 0, y: 8 }
    "L: $(Inspect.toStr left)" |> W4.text! { x: 0, y: 16 }
    "R: $(Inspect.toStr right)" |> W4.text! { x: 0, y: 24 }
    "U: $(Inspect.toStr up)" |> W4.text! { x: 0, y: 32 }
    "D: $(Inspect.toStr down)" |> W4.text! { x: 0, y: 40 }
    W4.setTextColors! { fg: None, bg: None }
    "THIS IS TRASPARENT" |> W4.text! { x: 0, y: 48 }
    W4.setTextColors! { fg: blue, bg: white }
    "Mouse X: $(Inspect.toStr mouse.x)" |> W4.text! { x: 0, y: 56 }
    "Mouse Y: $(Inspect.toStr mouse.y)" |> W4.text! { x: 0, y: 64 }
    "Mouse L: $(Inspect.toStr mouse.left)" |> W4.text! { x: 0, y: 72 }
    "Mouse R: $(Inspect.toStr mouse.right)" |> W4.text! { x: 0, y: 80 }
    "Mouse M: $(Inspect.toStr mouse.middle)" |> W4.text! { x: 0, y: 88 }
    W4.line! { x: 110, y: 10 } { x: 150, y: 50 }
    W4.hline! { x: 5, y: 52, len: 150 }
    W4.vline! { x: 80, y: 100, len: 10 }
    W4.oval! { x: 70, y: 120, width: 20, height: 50 }

    # Return the model for next frame
    Task.ok model

# Set the color pallet
white = Color1
red = Color2
green = Color3
blue = Color4

setColorPalette : Task {} []
setColorPalette =
    W4.setPalette {
        color1: 0xffffff,
        color2: 0xff0000,
        color3: 0x000ff00,
        color4: 0x0000ff,
    }

setDrawColors : Task {} []
setDrawColors =
    W4.setDrawColors {
        primary: white,
        secondary: red,
        tertiary: green,
        quaternary: blue,
    }
