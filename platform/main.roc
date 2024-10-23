platform "wasm-4"
    requires { Model } { init! : {} => Model, update! : Model => Model }
    exposes [
        Task,
        W4,
        Sprite,
    ]
    packages {}
    imports []
    provides [initBoxed!, updateBoxed!]

initBoxed! : {} => Box Model
initBoxed! = \{} ->
    init! {}
    |> Box.box

updateBoxed! : Box Model => Box Model
updateBoxed! = \boxedModel ->
    boxedModel
    |> Box.unbox
    |> update!
    |> Box.box
