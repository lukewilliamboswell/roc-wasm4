platform "wasm-4"
    requires {Model} { main : _ }
    exposes [
        Task,
    ]
    packages {}
    imports [Task.{ Task }]
    provides [mainForHost]

# TODO add to annotation for main from app when no longer UNUSED DEFINITION
# Program : {
#     init : Model,
#     update : Model -> Task Model [],
# }

OptionalModel : [None, Some (Box Model)]

mainForHost : OptionalModel -> Task OptionalModel []
mainForHost = \optional ->
    when optional is 
        None ->
            main.init
            |> Box.box
            |> Some
            |> Task.ok
        Some boxedModel ->
            model <- main.update (Box.unbox boxedModel) |> Task.await

            model
            |> Box.box
            |> Some
            |> Task.ok
        