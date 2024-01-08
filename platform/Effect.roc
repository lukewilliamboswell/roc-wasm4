hosted Effect
    exposes [
        Effect,
        after,
        map,
        always,
        forever,
        loop,
        text,
        # TODO: pick between get and read or some other name (just be consistent)?
        setPalette,
        getPalette,
        setDrawColors,
        getDrawColors,
        readGamepad,
        readMouse,
        readNetplay,
        rect,
        oval,
        line,
        hline,
        vline,
        rand,
        randRangeLessThan,
        blit,
        blitSub,
        trace,
        diskw,
        diskr,
        setPerserveFrameBuffer,
        setHideGamepadOverlay,
        tone,
    ]
    imports []
    generates Effect with [after, map, always, forever, loop]

text : Str, I32, I32 -> Effect {}
setPalette : U32, U32, U32, U32 -> Effect {}
getPalette : Effect { color1 : U32, color2 : U32, color3 : U32, color4 : U32 }
setDrawColors : U16 -> Effect {}
getDrawColors : Effect U16
readGamepad : U8 -> Effect U8
readMouse : Effect { x : i16, y : i16, buttons : U8 }
readNetplay : Effect U8
rect : I32, I32, U32, U32 -> Effect {}
oval : I32, I32, U32, U32 -> Effect {}
line : I32, I32, I32, I32 -> Effect {}
hline : I32, I32, U32 -> Effect {}
vline : I32, I32, U32 -> Effect {}
rand : Effect I32
randRangeLessThan : I32, I32 -> Effect I32
blit : List U8, I32, I32, U32, U32, U32 -> Effect {}
blitSub : List U8, I32, I32, U32, U32, U32, U32, U32, U32 -> Effect {}
trace : Str -> Effect {}
diskw : List U8 -> Effect Bool
diskr : Effect (List U8)
setPerserveFrameBuffer : Bool -> Effect {}
setHideGamepadOverlay : Bool -> Effect {}
tone : U32, U32, U16, U8 -> Effect {}
