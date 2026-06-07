app [main] {
    w4: platform "../platform/main.roc",
}

import w4.W4
import w4.Sprite

GamepadState : {
    button1 : Bool,
    button2 : Bool,
    left : Bool,
    right : Bool,
    up : Bool,
    down : Bool,
}

Model : {
    arrow_sprite : Sprite,
    arrow_idx : U64,
    last_gamepad_state : GamepadState,
    values : List((Str, U32, U32)),
}

starting_values = [
    ("FREQ1", 440, 1000),
    ("FREQ2", 0, 1000),
    ("ATTCK", 0, 255),
    ("DECAY", 0, 255),
    ("SUSTN", 60, 255),
    ("RLEAS", 0, 255),
    (" PEAK", 100, 100),
    ("VOLUM", 100, 100),
    ("CHNNL", 0, 3),
    (" MODE", 0, 3),
    ("  PAN", 0, 2),
]

main = {
    init!: || {
        arrow_sprite = Sprite.new({
            data: [
                0b00001000,
                0b00001100,
                0b01111110,
                0b01111111,
                0b01111110,
                0b00001100,
                0b00001000,
                0b00000000,
            ],
            bpp: BPP1,
            width: 8,
            height: 8,
        })

        {
            arrow_sprite,
            arrow_idx: 0,
            last_gamepad_state: empty_gamepad,
            values: starting_values,
        }
    },
    update!: |model| update!(model),
}

empty_gamepad : GamepadState
empty_gamepad = {
    button1: Bool.False,
    button2: Bool.False,
    left: Bool.False,
    right: Bool.False,
    up: Bool.False,
    down: Bool.False,
}

update! : Model => Model
update! = |model| {
    x : I32
    x = 20
    y : I32
    y = 30
    spacing : I32
    spacing = 10

    var $index = 0.U64
    for (name, value, max_value) in model.values {
        draw_control!(name, x, y + U64.to_i32_wrap($index) * spacing, value, max_value)
        $index = $index + 1
    }

    W4.set_primary_color!(Color2)
    W4.text!("Arrows: Adjust\nX: Play tone", { x, y: 8 })
    W4.set_draw_colors!({ primary: None, secondary: Color4, tertiary: None, quaternary: None })
    Sprite.blit!(model.arrow_sprite, {
        x: x - 8 - 4,
        y: y + U64.to_i32_wrap(model.arrow_idx) * spacing,
        flags: [],
    })

    gamepad = W4.get_gamepad!(Player1)

    pressed_this_frame = {
        left: gamepad.left and !model.last_gamepad_state.left,
        right: gamepad.right and !model.last_gamepad_state.right,
        up: gamepad.up and !model.last_gamepad_state.up,
        down: gamepad.down and !model.last_gamepad_state.down,
        button1: gamepad.button1 and !model.last_gamepad_state.button1,
        button2: gamepad.button2 and !model.last_gamepad_state.button2,
    }

    arrow_idx =
        if pressed_this_frame.down and pressed_this_frame.up {
            model.arrow_idx
        } else if pressed_this_frame.down {
            U64.min(model.arrow_idx + 1, List.len(model.values) - 1)
        } else if pressed_this_frame.up {
            sub_saturating_u64(model.arrow_idx, 1)
        } else {
            model.arrow_idx
        }

    (name, val, max_value) = match List.get(model.values, arrow_idx) {
        Ok(v) => v
        Err(_) => { crash "arrow is always within bounds of the control list" }
    }

    (step, step_gamepad) =
        if max_value // 100 == 0 {
            (1, pressed_this_frame)
        } else {
            (max_value // 100, gamepad)
        }

    values =
        if step_gamepad.right {
            next = U32.min(val + step, max_value)
            set_value_or_crash(model.values, arrow_idx, (name, next, max_value))
        } else if step_gamepad.left {
            set_value_or_crash(model.values, arrow_idx, (name, sub_saturating_u32(val, step), max_value))
        } else {
            model.values
        }

    if pressed_this_frame.button1 {
        play_sound!(values)
    } else {
        {}
    }

    { ..model, arrow_idx, values, last_gamepad_state: gamepad }
}

draw_control! : Str, I32, I32, U32, U32 => {}
draw_control! = |name, x, y, value, max_value| {
    meter_width : U32
    meter_width = 50

    W4.set_primary_color!(Color2)
    W4.rect!({ x: 5 * 8 + x + 4, y, width: meter_width + 2, height: 8 })

    W4.set_primary_color!(Color3)
    W4.rect!({
        x: 5 * 8 + x + 4 + 1,
        y: y + 1,
        width: value * meter_width // max_value,
        height: 6,
    })

    W4.set_primary_color!(Color4)
    W4.text!(name, { x, y })
    W4.text!(U32.to_str(value), { x: 5 * 8 + x + 4 + U32.to_i32_wrap(meter_width) + 2 + 4, y })
}

play_sound! : List((Str, U32, U32)) => {}
play_sound! = |values| {
    match values {
        [(_, start_freq, _), (_, end_freq, _), (_, attack_time, _), (_, decay_time, _), (_, sustain_time, _), (_, release_time, _), (_, peak_volume, _), (_, volume, _), (_, channel_val, _), (_, mode_val, _), (_, pan_val, _)] => {
            mode = match mode_val {
                0 => Eighth
                1 => Quarter
                2 => Half
                3 => ThreeQuarters
                _ => { crash "impossible mode" }
            }

            channel = match channel_val {
                0 => Pulse1(mode)
                1 => Pulse2(mode)
                2 => Triangle
                3 => Noise
                _ => { crash "impossible channel" }
            }

            pan = match pan_val {
                0 => Center
                1 => Left
                2 => Right
                _ => { crash "impossible pan" }
            }

            W4.tone!({
                start_freq: U32.to_u16_wrap(start_freq),
                end_freq: U32.to_u16_wrap(end_freq),
                attack_time: U32.to_u8_wrap(attack_time),
                decay_time: U32.to_u8_wrap(decay_time),
                sustain_time: U32.to_u8_wrap(sustain_time),
                release_time: U32.to_u8_wrap(release_time),
                peak_volume: U32.to_u8_wrap(peak_volume),
                volume: U32.to_u8_wrap(volume),
                channel,
                pan,
            })
        }

        _ => { crash "invalid number of values for playing sounds" }
    }
}

set_value_or_crash : List((Str, U32, U32)), U64, (Str, U32, U32) -> List((Str, U32, U32))
set_value_or_crash = |values, index, value| {
    match List.set(values, index, value) {
        Ok(next_values) => next_values
        Err(_) => { crash "arrow is always within bounds of the control list" }
    }
}

sub_saturating_u64 : U64, U64 -> U64
sub_saturating_u64 = |x, y| if x < y { 0 } else { x - y }

sub_saturating_u32 : U32, U32 -> U32
sub_saturating_u32 = |x, y| if x < y { 0 } else { x - y }
