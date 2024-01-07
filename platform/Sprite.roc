interface Sprite
    exposes [Sprite, new, blit]
    imports [Task.{ Task }, Effect.{ Effect }]

Sprite := {
    data : List U8,
    bpp : [BPP1, BPP2],
    width : U32,
    height : U32,
}

new :
    {
        data : List U8,
        bpp : [BPP1, BPP2],
        width : U32,
        height : U32,
    }
    -> Sprite
new = @Sprite

blit : { x : I32, y : I32, flags : List [FlipX, FlipY, Rotate] }, Sprite -> Task {} []
blit = \{ x, y, flags }, @Sprite { data, bpp, width, height } ->

    format =
        when bpp is
            BPP1 -> 0
            BPP2 -> 1

    combined =
        List.walk flags format \state, flag ->
            when flag is
                FlipX -> Num.bitwiseOr state 2
                FlipY -> Num.bitwiseOr state 4
                Rotate -> Num.bitwiseOr state 8

    Effect.blit data x y width height combined
    |> Effect.map Ok
    |> Task.fromEffect
