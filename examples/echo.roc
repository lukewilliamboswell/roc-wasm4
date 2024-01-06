app "minimal"
    packages {
        w4: "../platform/main.roc",
    }
    imports [
        w4.Task.{ Task },
    ]
    provides [main, Model] to w4

Program : {
    init : Task Model [],
    update : Model -> Task Model [],
}

Model : Str

main : Program
main = { init, update }

init : Task Model []
init =

    # Set the color pallet
    {} <- Task.setPallet 0xfff6d3 0xf9a875 0xeb6b6f 0x7c3f58 |> Task.await

    Task.ok "Test123"

update : Model -> Task Model []
update = \model ->
    next = Str.concat model "1."

    # Set draw colors
    {} <- Task.setDrawColors { primary: Second } |> Task.await

    # Draw some text
    {} <- Task.text next 0 0 |> Task.await

    Task.ok next
