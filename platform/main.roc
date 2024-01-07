platform "wasm-4"
    requires { Model } { main : _ }
    exposes [
        Task,
        W4,
        Sprite,
    ]
    packages {}
    imports [Task.{ Task }]
    provides [mainForHost]

# TODO add to annotation for main from app when no longer UNUSED DEFINITION
# Program : {
#     init : Model,
#     update : Model -> Task Model [],
# }

ProgramForHost : {
    init : Task (Box Model) [],
    update : Box Model -> Task (Box Model) [],
}

mainForHost : ProgramForHost
mainForHost = { init, update }

init : Task (Box Model) []
init = main.init |> Task.map Box.box

update : Box Model -> Task (Box Model) []
update = \boxedModel ->
    model <- main.update (Box.unbox boxedModel) |> Task.await

    model
    |> Box.box
    |> Task.ok
