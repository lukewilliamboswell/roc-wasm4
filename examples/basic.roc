app [main] { w4: platform "https://github.com/lukewilliamboswell/roc-wasm4/releases/download/0.5/sZGj6cG7ted2RNohpqvQwqb7pvBd5C5zotA5XXyJZnA.tar.zst" }

import w4.W4

Model : {}

white = Color1
red = Color2
green = Color3
blue = Color4

set_color_palette! : () => {}
set_color_palette! = || {
    W4.set_palette!({
        color1: 0xffffff,
        color2: 0xff0000,
        color3: 0x00ff00,
        color4: 0x0000ff,
    })
}

set_draw_colors! : () => {}
set_draw_colors! = || {
    W4.set_draw_colors!({
        primary: white,
        secondary: red,
        tertiary: green,
        quaternary: blue,
    })
}

main = {
    init!: || {
        set_color_palette!()
        set_draw_colors!()
        W4.trace!("basic example started")
        W4.tone!({
            start_freq: 262,
            end_freq: 523,
            channel: Pulse1(Quarter),
            pan: Center,
            attack_time: 0,
            decay_time: 30,
            sustain_time: 60,
            release_time: 0,
            volume: 100,
            peak_volume: 0,
        })
        {}
    },
    update!: |model| {
        gamepad = W4.get_gamepad!(Player1)
        mouse = W4.get_mouse!()

        W4.set_text_colors!({ fg: red, bg: green })
        W4.text!("X: ${Str.inspect(gamepad.button1)}", { x: 0, y: 0 })
        W4.set_text_colors!({ fg: blue, bg: white })
        W4.text!("Z: ${Str.inspect(gamepad.button2)}", { x: 0, y: 8 })
        W4.text!("L: ${Str.inspect(gamepad.left)}", { x: 0, y: 16 })
        W4.text!("R: ${Str.inspect(gamepad.right)}", { x: 0, y: 24 })
        W4.text!("U: ${Str.inspect(gamepad.up)}", { x: 0, y: 32 })
        W4.text!("D: ${Str.inspect(gamepad.down)}", { x: 0, y: 40 })
        W4.text!("Mouse X: ${Str.inspect(mouse.x)}", { x: 0, y: 56 })
        W4.text!("Mouse Y: ${Str.inspect(mouse.y)}", { x: 0, y: 64 })
        W4.text!("Mouse L: ${Str.inspect(mouse.left)}", { x: 0, y: 72 })

        W4.line!({ x: 110, y: 10 }, { x: 150, y: 50 })
        W4.hline!({ x: 5, y: 52, len: 150 })
        W4.vline!({ x: 80, y: 100, len: 10 })
        W4.oval!({ x: 70, y: 120, width: 20, height: 50 })

        model
    },
}
