app "sound"
    packages {
        w4: "../platform/main.roc",
    }
    imports [
        w4.Task.{ Task },
        w4.W4.{ Gamepad },
        w4.Sprite.{ Sprite },
    ]
    provides [main, Model] to w4

Program : {
    init : Task Model [],
    update : Model -> Task Model [],
}

Model : {
    arrowSprite : Sprite,
    arrowIdx : U64,
    lastGamepadState : Gamepad,
    values : List (Str, U32, U32),
}

startingValues = [
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

main : Program
main = { init, update }

init : Task Model []
init =
    arrowSprite = Sprite.new {
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
    }

    Task.ok {
        arrowSprite,
        arrowIdx: 0,
        lastGamepadState: {
            button1: Bool.false,
            button2: Bool.false,
            left: Bool.false,
            right: Bool.false,
            up: Bool.false,
            down: Bool.false,
        },
        values: startingValues,
    }

update : Model -> Task Model []
update = \model ->
    # These type annotations are required. Otherwise roc fails to compile.
    x : I32
    x = 20
    y : I32
    y = 30
    spacing : I32
    spacing = 10

    drawControls =
        List.walkWithIndex model.values (Task.ok {}) \task, (name, value, max), index ->
            {} <- task |> Task.await
            drawControl name x (y + (Num.toI32 index) * spacing) value max
    {} <- drawControls |> Task.await

    {} <- W4.setPrimaryColor Color2 |> Task.await
    {} <- W4.text "Arrows: Adjust\nX: Play tone" { x, y: 8 } |> Task.await

    {} <- W4.setDrawColors { primary: None, secondary: Color4, tertiary: None, quaternary: None } |> Task.await
    {} <- Sprite.blit model.arrowSprite { x: x - 8 - 4, y: y + (Num.toI32 model.arrowIdx) * spacing } |> Task.await

    gamepad <- W4.getGamepad Player1 |> Task.await

    pressedThisFrame = {
        left: gamepad.left && !model.lastGamepadState.left,
        right: gamepad.right && !model.lastGamepadState.right,
        up: gamepad.up && !model.lastGamepadState.up,
        down: gamepad.down && !model.lastGamepadState.down,
        button1: gamepad.button1 && !model.lastGamepadState.button1,
        button2: gamepad.button2 && !model.lastGamepadState.button2,
    }

    arrowIdx =
        if pressedThisFrame.down && pressedThisFrame.up then
            model.arrowIdx
        else if pressedThisFrame.down then
            min (model.arrowIdx + 1) (List.len model.values - 1)
        else if pressedThisFrame.up then
            Num.subSaturated model.arrowIdx 1
        else
            model.arrowIdx

    (name, val, max) =
        when List.get model.values arrowIdx is
            Ok v -> v
            Err _ -> crash "Arrow is always within bounds of array"

    (step, stepGamepad) =
        if max // 100 == 0 then
            (1, pressedThisFrame)
        else
            (max // 100, gamepad)

    values =
        if stepGamepad.right then
            next = min (val + step) max
            List.set model.values arrowIdx (name, next, max)
        else if stepGamepad.left then
            List.set model.values arrowIdx (name, Num.subSaturated val step, max)
        else
            model.values

    soundTask =
        if pressedThisFrame.button1 then
            playSound values
        else
            Task.ok {}
    {} <- soundTask |> Task.await

    Task.ok { model & arrowIdx, values, lastGamepadState: gamepad }

drawControl : Str, I32, I32, U32, U32 -> Task {} []
drawControl = \name, x, y, value, max ->
    meterWidth : U32
    meterWidth = 50
    {} <- W4.setPrimaryColor Color2 |> Task.await
    {} <- W4.rect { x: (5 * 8 + x + 4), y, width: (meterWidth + 2), height: 8 } |> Task.await

    {} <- W4.setPrimaryColor Color3 |> Task.await
    {} <- W4.rect { x: (5 * 8 + x + 4 + 1), y: (y + 1), width: ((value * meterWidth) // max), height: 6 } |> Task.await

    {} <- W4.setPrimaryColor Color4 |> Task.await
    {} <- W4.text name { x, y } |> Task.await

    {} <- W4.text (Num.toStr value) { x: 5 * 8 + x + 4 + (Num.toI32 meterWidth) + 2 + 4, y } |> Task.await
    Task.ok {}

playSound : List (Str, U32, U32) -> Task {} []
playSound = \values ->
    when values is
        [(_, startFreq, _), (_, endFreq, _), (_, attackTime, _), (_, decayTime, _), (_, sustainTime, _), (_, releaseTime, _), (_, peakVolume, _), (_, volume, _), (_, channelVal, _), (_, modeVal, _), (_, panVal, _)] ->
            mode =
                when modeVal is
                    0 -> Eighth
                    1 -> Quarter
                    2 -> Half
                    3 -> ThreeQuarters
                    _ -> crash "impossible mode"

            channel =
                when channelVal is
                    0 -> Pulse1 mode
                    1 -> Pulse2 mode
                    2 -> Triangle
                    3 -> Noise
                    _ -> crash "impossible channel"

            pan =
                when panVal is
                    0 -> Center
                    1 -> Left
                    2 -> Right
                    _ -> crash "impossible pan"

            W4.tone {
                startFreq: Num.toU16 startFreq,
                endFreq: Num.toU16 endFreq,
                attackTime: Num.toU8 attackTime,
                decayTime: Num.toU8 decayTime,
                sustainTime: Num.toU8 sustainTime,
                releaseTime: Num.toU8 releaseTime,
                peakVolume: Num.toU8 peakVolume,
                volume: Num.toU8 volume,
                channel,
                pan,
            }

        _ ->
            crash "Invalid number of values for playing sounds"

min = \x, y ->
    if x < y then
        x
    else
        y
