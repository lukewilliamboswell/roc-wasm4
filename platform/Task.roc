interface Task
    exposes [
        Task,
        toEffect,
        ok,
        err,
        await,
        mapErr,
        onErr,
        attempt,
        map,
        fromResult,
        fromEffect,
        text,
    ]
    imports [
        Effect.{ Effect },
    ]

Task ok err := Effect (Result ok err)

ok : a -> Task a *
ok = \a -> @Task (Effect.always (Ok a))

err : a -> Task * a
err = \a -> @Task (Effect.always (Err a))

fromEffect : Effect (Result ok err) -> Task ok err
fromEffect = \effect -> @Task effect

toEffect : Task ok err -> Effect (Result ok err)
toEffect = \@Task effect -> effect

await : Task a b, (a -> Task c b) -> Task c b
await = \task, transform ->
    effect = Effect.after
        (toEffect task)
        \result ->
            when result is
                Ok a -> transform a |> toEffect
                Err b -> err b |> toEffect

    fromEffect effect

map : Task a c, (a -> b) -> Task b c
map = \task, transform ->
    effect = Effect.after
        (toEffect task)
        \result ->
            when result is
                Ok a -> ok (transform a) |> toEffect
                Err b -> err b |> toEffect

    fromEffect effect

mapErr : Task c a, (a -> b) -> Task c b
mapErr = \task, transform ->
    effect = Effect.after
        (toEffect task)
        \result ->
            when result is
                Ok c -> ok c |> toEffect
                Err a -> err (transform a) |> toEffect

    fromEffect effect

onErr : Task a b, (b -> Task a c) -> Task a c
onErr = \task, transform ->
    effect = Effect.after
        (toEffect task)
        \result ->
            when result is
                Ok a -> ok a |> toEffect
                Err b -> transform b |> toEffect

    fromEffect effect

attempt : Task a b, (Result a b -> Task c d) -> Task c d
attempt = \task, transform ->
    effect = Effect.after
        (toEffect task)
        \result ->
            transform result |> toEffect

    fromEffect effect

fromResult : Result a b -> Task a b
fromResult = \result ->
    when result is
        Ok a -> ok a
        Err b -> err b

text : Str, I32, I32 -> Task {} []
text = \str, x, y ->
    Effect.text str x y
    |> Effect.map (\{} -> Ok {})
    |> fromEffect
