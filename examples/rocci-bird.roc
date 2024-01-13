app "rocci-bird"
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
    frameCount : U64,
    rocciAnim : Animation,
    gameStarted : Bool,
}

main : Program
main = { init, update }

init : Task Model []
init =
    # Lospec palette: ST GameBoy Remake Palette
    palette = {
        color1: 0xcb91f2,
        color2: 0x5d3eb3,
        color3: 0x210f66,
        color4: 0x0a0a1a,
    }
    # With actual roc colors. Though palette doesn't quite work yet.
    # Roc bird is too light compared to background.
    # palette = {
    #     color1: 0xcb91f2,
    #     color2: 0x8a66de,
    #     color3: 0x6c3bdc,
    #     color4: 0x0a0a1a,
    # }

    {} <- W4.setPalette palette |> Task.await

    Task.ok {
        frameCount: 0,
        rocciAnim: createRocciAnim {},
        gameStarted: Bool.false,
    }

update : Model -> Task Model []
update = \prev ->
    # Update frame count
    model = { prev & frameCount: Num.addWrap prev.frameCount 1 }

    if !model.gameStarted then
        runTitleScreen model
    else
        runGame model

runTitleScreen : Model -> Task Model []
runTitleScreen = \prev ->
    model = {prev & rocciAnim: updateAnimation prev.frameCount prev.rocciAnim }

    {} <- W4.text "Rocci Bird!!!" { x: 32, y: 12 } |> Task.await
    {} <- W4.text "Press X to start!" { x: 16, y: 72 } |> Task.await

    shift = 
        (model.frameCount // 15 + 1) % 2
        |> Num.toI32
    {} <- drawAnimation model.rocciAnim { x : 70, y: 40 + shift } |> Task.await
    gamepad <- W4.getGamepad Player1 |> Task.await

    if gamepad.button1 then
        # Seed the randomness with number of frames since the start of the game.
        # This makes the game feel like it is truely randomly seeded cause players won't always start on the same frame.
        {} <- W4.seedRand model.frameCount |> Task.await

        Task.ok { model & gameStarted: Bool.true }
    else
        Task.ok model

runGame : Model -> Task Model []
runGame = \model ->

    # Return model for next frame
    Task.ok model

AnimationState: [Completed, RunOnce, Loop]
Animation : {
    framesPerUpdate: U64,
    index: U64,
    cells: List Sprite,
    state: AnimationState
}

updateAnimation : U64, Animation -> Animation
updateAnimation = \frameCount, anim ->
    if frameCount % anim.framesPerUpdate != 0 then
        anim
    else
        nextIndex = wrappedInc anim.index (List.len anim.cells |> Num.toU64)
        when anim.state is
            Completed ->
                anim
            Loop -> 
                { anim & index: nextIndex }
            RunOnce -> 
                if nextIndex == 0 then
                    { anim & index: nextIndex, state: Completed }
                else
                    { anim & index: nextIndex }



drawAnimation : Animation, { x: I32, y: I32, flags ? List [FlipX, FlipY, Rotate] } -> Task {} []
drawAnimation = \anim, params ->
    when List.get anim.cells (Num.toNat anim.index) is
        Ok sprite ->
            Sprite.blit sprite params
        Err _ ->
            crash "animation cell out of bounds at index: \(anim.index |> Num.toStr)"

wrappedInc = \val, count ->
    next = val + 1
    if next == count then
        0
    else
        next


createRocciAnim : {} -> Animation
createRocciAnim = \{} ->
    {
        framesPerUpdate: 10,
        index: 0,
        state: Loop,
        cells: [
        Sprite.new {
            data: [
                0x55,0x55,0x55,0x55,0x55,
                0x40,0x01,0x55,0x55,0x55,
                0x50,0x00,0x25,0x55,0x55,
                0x54,0x00,0x29,0x55,0x55,
                0x55,0x00,0x2a,0x54,0x25,
                0x55,0x40,0x2a,0x90,0x29,
                0x55,0x50,0x2a,0xa0,0x15,
                0x55,0x54,0x2a,0xa8,0x15,
                0x55,0x55,0x82,0xaa,0x15,
                0x55,0x55,0x80,0x00,0x55,
                0x55,0x55,0x80,0x01,0x55,
                0x55,0x56,0x80,0x15,0x55,
                0x55,0x56,0x80,0x55,0x55,
                0x55,0x56,0x85,0x55,0x55,
                0x55,0x56,0x95,0x55,0x55,
                0x55,0x5a,0xa5,0x55,0x55,
                0x55,0x5a,0x95,0x55,0x55,
                0x55,0x5a,0x55,0x55,0x55,
                0x55,0x59,0x55,0x55,0x55,
                0x55,0x55,0x55,0x55,0x55,
            ],
            bpp: BPP2,
            width: 20,
            height: 20,
        },
        Sprite.new {
            data: [
                0x55,0x55,0x55,0x55,0x55,
                0x54,0x55,0x55,0x55,0x55,
                0x50,0x55,0x55,0x55,0x55,
                0x50,0x15,0x55,0x55,0x55,
                0x40,0x15,0x55,0x54,0x25,
                0x40,0x05,0x55,0x50,0x29,
                0x40,0x00,0x55,0x40,0x15,
                0x40,0x00,0x2a,0x80,0x15,
                0x40,0x02,0xaa,0xaa,0x15,
                0x50,0x0a,0xaa,0xa0,0x55,
                0x54,0x2a,0xaa,0x01,0x55,
                0x55,0x2a,0x80,0x15,0x55,
                0x55,0x56,0x80,0x55,0x55,
                0x55,0x56,0x85,0x55,0x55,
                0x55,0x56,0x95,0x55,0x55,
                0x55,0x5a,0xa5,0x55,0x55,
                0x55,0x5a,0x95,0x55,0x55,
                0x55,0x5a,0x55,0x55,0x55,
                0x55,0x59,0x55,0x55,0x55,
                0x55,0x55,0x55,0x55,0x55,
            ],
            bpp: BPP2,
            width: 20,
            height: 20,
        },
        Sprite.new {
            data: [
                0x55,0x55,0x55,0x55,0x55,
                0x55,0x55,0x55,0x55,0x55,
                0x55,0x55,0x55,0x55,0x55,
                0x55,0x55,0x55,0x55,0x55,
                0x55,0x55,0x55,0x54,0x25,
                0x55,0x55,0x55,0x50,0x29,
                0x55,0x55,0x55,0x40,0x15,
                0x40,0x15,0x55,0x00,0x15,
                0x50,0x00,0x2a,0xaa,0x15,
                0x54,0x00,0xaa,0xa0,0x55,
                0x55,0x00,0xaa,0x81,0x55,
                0x55,0x40,0xaa,0x15,0x55,
                0x55,0x50,0xa0,0x55,0x55,
                0x55,0x56,0x85,0x55,0x55,
                0x55,0x56,0x95,0x55,0x55,
                0x55,0x5a,0xa5,0x55,0x55,
                0x55,0x5a,0x95,0x55,0x55,
                0x55,0x5a,0x55,0x55,0x55,
                0x55,0x59,0x55,0x55,0x55,
                0x55,0x55,0x55,0x55,0x55,
            ],
            bpp: BPP2,
            width: 20,
            height: 20,
        },
        ]
    }
