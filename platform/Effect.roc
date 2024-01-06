hosted Effect
    exposes [
        Effect,
        after,
        map,
        always,
        forever,
        loop,
        text,
        setPallet,
        setDrawColors,
        readGamepad,
    ]
    imports []
    generates Effect with [after, map, always, forever, loop]

text : Str, I32, I32 -> Effect {}
setPallet : U32, U32, U32, U32 -> Effect {}
setDrawColors : U16 -> Effect {}
readGamepad : U8 -> Effect U8
