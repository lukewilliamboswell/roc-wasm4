interface Sprite
    exposes [Sprite, new, blit, blitSub]
    imports [InternalTask.{ Task }, Effect.{ Effect }]

# TODO: add api docs
# TODO: add functionality to modify a sprite

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

blit : Sprite, { x : I32, y : I32, flags ? List [FlipX, FlipY, Rotate] } -> Task {} []
blit = \@Sprite { data, bpp, width, height }, { x, y, flags ? [] } ->

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
    |> InternalTask.fromEffect

blitSub : Sprite, { x : I32, y : I32, srcX : U32, srcY : U32, width : U32, height : U32, flags ? List [FlipX, FlipY, Rotate] } -> Task {} []
blitSub = \@Sprite { data, bpp, width: stride }, { x, y, srcX, srcY, width, height, flags ? [] } ->

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

    Effect.blitSub data x y width height srcX srcY stride combined
    |> Effect.map Ok
    |> InternalTask.fromEffect
