app "snake"
    packages {
        w4: "../platform/main.roc",
    }
    imports [
        w4.Task.{ Task },
        w4.W4,
    ]
    provides [main, Model] to w4

Program : {
    init : Task Model [],
    update : Model -> Task Model [],
}

Model : {}

main : Program
main = { init, update }

init : Task Model []
init =

    {} <- setColorPallet |> Task.await
    {} <- setDrawColors |> Task.await

    Task.ok {}

update : Model -> Task Model []
update = \model ->

    # Read gamepad
    # { button1, button2, left, right, up, down } <- W4.readGamepad Player1 |> Task.await

    # Draw the gamepad state
    {} <- W4.textColor { fg: red, bg: green } |> Task.await
    {} <- "SNAKE" |> W4.text { x: 0, y: 0 } |> Task.await

    # Return the model for next frame
    Task.ok model

# Set the color pallet
white = Color1
red = Color2
green = Color3
blue = Color4

setColorPallet : Task {} []
setColorPallet =
    W4.setPallet {
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
