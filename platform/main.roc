platform "wasm-4"
    requires { Model } { main : Program Model _ }
    exposes [
        Task,
        W4,
        Sprite,
    ]
    packages {}
    imports []
    provides [init!, update!]

import W4 exposing [Program]

init! : {} => Box Model
init! = \{} ->
    main.init! {}
    |> \result ->
        when result is
            Ok m -> Box.box m
            Err err ->
                crash (Inspect.toStr err)

update! : Box Model => Box Model
update! = \boxedModel ->
    boxedModel
    |> Box.unbox
    |> main.update!
    |> \result ->
        when result is
            Ok m -> Box.box m
            Err err ->
                crash (Inspect.toStr err)
