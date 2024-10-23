hosted Effect
    exposes [
        text!,
        setPalette!,
        getPalette!,
        setDrawColors!,
        getDrawColors!,
        getGamepad!,
        getMouse!,
        getNetplay!,
        rect!,
        oval!,
        line!,
        hline!,
        vline!,
        seedRand!,
        rand!,
        randRangeLessThan!,
        blit!,
        blitSub!,
        trace!,
        diskw!,
        diskr!,
        setPreserveFrameBuffer!,
        setHideGamepadOverlay!,
        tone!,
        getPixel!,
        setPixel!,
    ]
    imports []

text! : Str, I32, I32 => {}
setPalette! : U32, U32, U32, U32 => {}
getPalette! : {} => { color1 : U32, color2 : U32, color3 : U32, color4 : U32 }
setDrawColors! : U16 => {}
getDrawColors! : {} => U16
getGamepad! : U8 => U8
getMouse! : {} => { x : i16, y : i16, buttons : U8 }
getNetplay! : {} => U8
rect! : I32, I32, U32, U32 => {}
oval! : I32, I32, U32, U32 => {}
line! : I32, I32, I32, I32 => {}
hline! : I32, I32, U32 => {}
vline! : I32, I32, U32 => {}
seedRand! : U64 => {}
rand! : {} => I32
randRangeLessThan! : I32, I32 => I32
blit! : List U8, I32, I32, U32, U32, U32 => {}
blitSub! : List U8, I32, I32, U32, U32, U32, U32, U32, U32 => {}
trace! : Str => {}
diskw! : List U8 => Bool
diskr! : {} => List U8
setPreserveFrameBuffer! : Bool => {}
setHideGamepadOverlay! : Bool => {}
tone! : U32, U32, U16, U8 => {}
getPixel! : U8, U8 => U8
setPixel! : U8, U8, U8 => {}
