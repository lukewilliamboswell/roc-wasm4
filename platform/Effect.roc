hosted Effect
    exposes [
        Effect,
        after,
        map,
        always,
        forever,
        loop,
        text,
        setPalette,
        getPalette,
        setDrawColors,
        readGamepad,
        readMouse,
        rect,
        rand,
        randRangeLessThan,
        blit,
        trace,
        diskw,
        diskr,
    ]
    imports []
    generates Effect with [after, map, always, forever, loop]

text : Str, I32, I32 -> Effect {}
setPalette : U32, U32, U32, U32 -> Effect {}
getPalette : Effect { color1 : U32, color2 : U32, color3 : U32, color4 : U32 }
setDrawColors : U16 -> Effect {}
readGamepad : U8 -> Effect U8
readMouse : Effect { x : i16, y : i16, buttons : U8 }
rect : I32, I32, U32, U32 -> Effect {}
rand : Effect I32
randRangeLessThan : I32, I32 -> Effect I32
blit : List U8, I32, I32, U32, U32, U32 -> Effect {}
trace : Str -> Effect {}
diskw : List U8 -> Effect Bool
diskr : Effect (List U8)
