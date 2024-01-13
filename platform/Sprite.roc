interface Sprite
    exposes [Sprite, SubRegion, new, blit, sub, subOrCrash]
    imports [InternalTask, Task.{ Task }, Effect.{ Effect }]

## Represents a [sprite](https://en.wikipedia.org/wiki/Sprite_(computer_graphics)) for drawing to the screen.
##
## A sprite is simply a list of bytes that are either encoded with 1 bit per pixel `BPP1` or 2 bits per pixel `BPP2`.
##
## [Refer w4 docs for more information](https://wasm4.org/docs/guides/sprites)
Sprite := {
    data : List U8,
    bpp : [BPP1, BPP2],
    stride : U32,
    region : SubRegion,
}

## A subregion of a [Sprite]
SubRegion : { srcX : U32, srcY : U32, width : U32, height : U32 }

## Create a [Sprite] to be drawn or [blit](https://en.wikipedia.org/wiki/Bit_blit) to the screen.
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
new = \{ data, bpp, width, height } ->
    @Sprite {
        data,
        bpp,
        stride: width,
        region: {
            srcX: 0,
            srcY: 0,
            width,
            height,
        },
    }

## Draw a [Sprite] to the framebuffer.
##
## ```
## {} <- Sprite.blit fruitSprite { x: 0, y: 0, flags: [FlipX, Rotate] } |> Task.await
## ```
##
## [Refer w4 docs for more information](https://wasm4.org/docs/reference/functions#blit-spriteptr-x-y-width-height-flags)
blit : Sprite, { x : I32, y : I32, flags ? List [FlipX, FlipY, Rotate] } -> Task {} []
blit = \@Sprite { data, bpp, stride, region }, { x, y, flags ? [] } ->
    { srcX, srcY, width, height } = region

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

## Creates a [Sprite] referencing a subregion of the current [Sprite].
## This will return an error if the subregion does not fit in the current [Sprite].
##
## ```
## subSpriteResult = Sprite.sub sprite { srcX: 20, srcY: 0, width: 20, height: 20 }
## ```
##
## Note: If your program should never generate an invalid subregion,
## [subOrCrash] is enables avoiding the result and simpler code.
##
sub : Sprite, SubRegion -> Result Sprite [OutOfBounds]
sub = \@Sprite sprite, subRegion ->
    currentRegion = sprite.region

    outOfBoundX = subRegion.srcX + subRegion.width > currentRegion.width
    outOfBoundY = subRegion.srcY + subRegion.height > currentRegion.height

    if outOfBoundX || outOfBoundY then
        Err OutOfBounds
    else
        newRegion = {
            srcX: currentRegion.srcX + subRegion.srcX,
            srcY: currentRegion.srcY + subRegion.srcY,
            width: subRegion.width,
            height: subRegion.height,
        }
        Ok (@Sprite { sprite & region: newRegion })

## Equivalent to the [sub] function, but will crash on error.
## This is really useful for static sprite sheet data that needs subSprites extracted.
##
## ```
## subSpriteResult = Sprite.sub sprite { srcX: 20, srcY: 0, width: 20, height: 20 }
## ```
##
## Warning: Will crash if the subregion is not contained within the sprite.
##
subOrCrash : Sprite, SubRegion -> Sprite
subOrCrash = \sprite, subRegion ->
    when sub sprite subRegion is
        Ok x ->
            x

        Err OutOfBounds ->
            crash "Out of bounds subregion when generating subsprite"
