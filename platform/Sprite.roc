interface Sprite
    exposes [Sprite, new, blit, blitSub]
    imports [InternalTask, Task.{ Task }, Effect.{ Effect }]

## Represents a [sprite](https://en.wikipedia.org/wiki/Sprite_(computer_graphics)) for drawing to the screen.
##
## A sprite is simply a list of bytes that are either encoded with 1 bit per pixel `BPP1` or 2 bits per pixel `BPP2`.
##
## [Refer w4 docs for more information](https://wasm4.org/docs/guides/sprites)
Sprite := {
    data : List U8,
    bpp : [BPP1, BPP2],
    width : U32,
    height : U32,
}

## Create [Sprite] to be drawn or [blit](https://en.wikipedia.org/wiki/Bit_blit) to the screen.
##
## ```
## fruitSprite = Sprite.new {
##     data: [0x00, 0xa0, 0x02, 0x00, 0x0e, 0xf0, 0x36, 0x5c, 0xd6, 0x57, 0xd5, 0x57, 0x35, 0x5c, 0x0f, 0xf0],
##     bpp: BPP2,
##     width: 8,
##     height: 8,
## }
## ```
new :
    {
        data : List U8,
        bpp : [BPP1, BPP2],
        width : U32,
        height : U32,
    }
    -> Sprite
new = @Sprite

## Draw a [Sprite] to the framebuffer
##
## ```
## {} <- Sprite.blit fruitSprite { x: 0, y: 0, flags: [FlipX, Rotate] } |> Task.await
## ```
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

## Draw a sub-region of a larger [Sprite] to the framebuffer. Similar to [blit] but with additional parameters.
##
## ```
## {} <- Sprite.blitSub {
##        x: 0,
##        y: 0,
##        srcX: 0,
##        srcY: 0,
##        width: 8,
##        height: 8,
##        flags: [FlipX, Rotate],
##    } |> Task.await
## ```
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
