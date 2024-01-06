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
        setPallet,
        setDrawColors,
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

setPallet : U32, U32, U32, U32 -> Task {} []
setPallet = \a, b, c, d ->
    Effect.setPallet a b c d
    |> Effect.map Ok
    |> fromEffect

setDrawColors :
    {
        primary ? [First, Second, Third, Fourth],
        secondary ? [First, Second, Third, Fourth],
        tertiary ? [First, Second, Third, Fourth],
        quaternary ? [First, Second, Third, Fourth],
    }
    -> Task {} []
setDrawColors = \{ primary ? First, secondary ? Second, tertiary ? Third, quaternary ? Fourth } ->

    toHex = \pos ->
        when pos is
            First -> 0x1
            Second -> 0x2
            Third -> 0x3
            Fourth -> 0x4

    a = toHex primary
    b = toHex secondary |> Num.shiftLeftBy 2
    c = toHex tertiary |> Num.shiftLeftBy 4
    d = toHex quaternary |> Num.shiftLeftBy 6

    0x0u16
    |> Num.bitwiseOr a
    |> Num.bitwiseOr b
    |> Num.bitwiseOr c
    |> Num.bitwiseOr d
    |> Effect.setDrawColors
    |> Effect.map Ok
    |> fromEffect
