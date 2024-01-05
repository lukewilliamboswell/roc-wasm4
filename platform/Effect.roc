hosted Effect
    exposes [
        Effect,
        after,
        map,
        always,
        forever,
        loop,
        text,
    ]
    imports []
    generates Effect with [after, map, always, forever, loop]

text : Str, I32, I32 -> Effect {}