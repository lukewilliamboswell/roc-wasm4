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

Model : [
    TitleScreen TitleScreenState,
    Game GameState,
    GameOver GameOverState,
]

main : Program
main = { init, update }

init : Task Model []
init =
    # Lospec palette: Candy Cloud [2-BIT] Palette
    palette = {
        color1: 0xe6e6c0,
        color2: 0xb494b7,
        color3: 0x42436e,
        color4: 0x26013f,
    }

    {} <- W4.setPalette palette |> Task.await

    frameCount = 0
    Task.ok
        (
            TitleScreen {
                frameCount,
                rocciIdleAnim: createRocciIdleAnim frameCount,
                grassSprite: createGrassSprite {},
                pipeSprite: createPipeSprite {},
            }
        )

update : Model -> Task Model []
update = \model ->
    when model is
        TitleScreen state ->
            state
            |> updateFrameCount
            |> runTitleScreen

        Game state ->
            state
            |> updateFrameCount
            |> runGame

        GameOver state ->
            state
            |> updateFrameCount
            |> runGameOver

updateFrameCount : { frameCount : U64 }a -> { frameCount : U64 }a
updateFrameCount = \prev ->
    { prev & frameCount: Num.addWrap prev.frameCount 1 }

# ===== Title Screen ======================================

TitleScreenState : {
    frameCount : U64,
    rocciIdleAnim : Animation,
    grassSprite : Sprite,
    pipeSprite : Sprite,
}

runTitleScreen : TitleScreenState -> Task Model []
runTitleScreen = \prev ->
    state = { prev &
        rocciIdleAnim: updateAnimation prev.frameCount prev.rocciIdleAnim,
    }

    {} <- setTextColors |> Task.await
    {} <- W4.text "Rocci Bird!!!" { x: 32, y: 12 } |> Task.await
    {} <- W4.text "Press X to start!" { x: 16, y: 72 } |> Task.await

    {} <- setSpriteColors |> Task.await
    {} <- drawPipe state.pipeSprite { x: 140, gapStart: 50 } |> Task.await
    {} <- Sprite.blit state.grassSprite { x: 0, y: W4.screenHeight - 20 } |> Task.await

    shift =
        (state.frameCount // halfRocciIdleAnimTime + 1) % 2 |> Num.toI32

    {} <- drawAnimation state.rocciIdleAnim { x: 70, y: 40 + shift } |> Task.await
    gamepad <- W4.getGamepad Player1 |> Task.await
    mouse <- W4.getMouse |> Task.await

    start = gamepad.button1 || gamepad.up || mouse.left

    if start then
        # Seed the randomness with number of frames since the start of the game.
        # This makes the game feel like it is truely randomly seeded cause players won't always start on the same frame.
        {} <- W4.seedRand state.frameCount |> Task.await

        Task.ok (initGame state)
    else
        Task.ok (TitleScreen state)

# ===== Main Game =========================================

GameState : {
    frameCount : U64,
    rocciFlapAnim : Animation,
    grassSprite : Sprite,
    player : {
        y : F32,
        yVel : F32,
    },
}

initGame : { frameCount : U64, grassSprite : Sprite }* -> Model
initGame = \{ frameCount, grassSprite } ->
    Game {
        frameCount,
        rocciFlapAnim: createRocciFlapAnim frameCount,
        grassSprite,
        player: {
            y: 60,
            yVel: 0.5,
        },
    }

# With out explicit typing `f32`, roc fails to compile this.
# TODO: finetune gravity and jump speed
gravity = 0.10f32
jumpSpeed = -3f32

runGame : GameState -> Task Model []
runGame = \prev ->
    gamepad <- W4.getGamepad Player1 |> Task.await
    mouse <- W4.getMouse |> Task.await

    # TODO: add timeout for press.
    flap = gamepad.button1 || gamepad.up || mouse.left

    (yVel, nextAnim) =
        if flap then
            anim = prev.rocciFlapAnim
            (
                jumpSpeed,
                { anim & index: 0, state: RunOnce },
            )
        else
            (
                prev.player.yVel + gravity,
                updateAnimation prev.frameCount prev.rocciFlapAnim,
            )

    y = prev.player.y + yVel
    state = { prev &
        rocciFlapAnim: nextAnim,
        player: { y, yVel },
    }

    {} <- setSpriteColors |> Task.await
    {} <- Sprite.blit state.grassSprite { x: 0, y: W4.screenHeight - 20 } |> Task.await

    yPixel = Num.floor state.player.y
    {} <- drawAnimation state.rocciFlapAnim { x: 20, y: yPixel } |> Task.await

    if y < 115 then
        Task.ok (Game state)
    else
        Task.ok (initGameOver state)

# ===== Game Over =========================================

GameOverState : {
    frameCount : U64,
    rocciFallAnim : Animation,
    grassSprite : Sprite,
    player : {
        y : F32,
        yVel : F32,
    },
}

initGameOver : { frameCount : U64, grassSprite : Sprite, player : { y : F32, yVel : F32 } }* -> Model
initGameOver = \{ frameCount, grassSprite, player } ->
    GameOver {
        frameCount,
        rocciFallAnim: createRocciFallAnim frameCount,
        grassSprite,
        player,
    }

runGameOver : GameOverState -> Task Model []
runGameOver = \prev ->
    yVel = prev.player.yVel + gravity
    nextAnim = updateAnimation prev.frameCount prev.rocciFallAnim

    y =
        next = prev.player.y + yVel
        if next > 128 then
            128
        else
            next

    state = { prev &
        rocciFallAnim: nextAnim,
        player: { y, yVel },
    }

    {} <- setTextColors |> Task.await
    {} <- W4.text "Game Over!" { x: 44, y: 12 } |> Task.await

    {} <- setSpriteColors |> Task.await
    {} <- Sprite.blit state.grassSprite { x: 0, y: W4.screenHeight - 20 } |> Task.await

    yPixel = Num.floor state.player.y
    {} <- drawAnimation state.rocciFallAnim { x: 20, y: yPixel } |> Task.await

    Task.ok (GameOver state)

# ===== Animations ========================================

AnimationState : [Completed, RunOnce, Loop]
Animation : {
    lastUpdated : U64,
    index : U64,
    cells : List { frames : U64, sprite : Sprite },
    state : AnimationState,
}

updateAnimation : U64, Animation -> Animation
updateAnimation = \frameCount, anim ->
    framesPerUpdate =
        when List.get anim.cells (Num.toNat anim.index) is
            Ok { frames } ->
                frames

            Err _ ->
                crash "animation cell out of bounds at index: \(anim.index |> Num.toStr)"

    if frameCount - anim.lastUpdated < framesPerUpdate then
        anim
    else
        nextIndex = wrappedInc anim.index (List.len anim.cells |> Num.toU64)
        when anim.state is
            Completed ->
                { anim & lastUpdated: frameCount }

            Loop ->
                { anim & index: nextIndex, lastUpdated: frameCount }

            RunOnce ->
                if nextIndex == 0 then
                    { anim & state: Completed, lastUpdated: frameCount }
                else
                    { anim & index: nextIndex, lastUpdated: frameCount }

drawAnimation : Animation, { x : I32, y : I32, flags ? List [FlipX, FlipY, Rotate] } -> Task {} []
drawAnimation = \anim, { x, y, flags ? [] } ->
    when List.get anim.cells (Num.toNat anim.index) is
        Ok { sprite } ->
            Sprite.blit sprite { x, y, flags }

        Err _ ->
            crash "animation cell out of bounds at index: \(anim.index |> Num.toStr)"

wrappedInc = \val, count ->
    next = val + 1
    if next == count then
        0
    else
        next

# ===== Misc Drawing and Color ============================
gapHeight = 40

drawPipe : Sprite, { x : I32, gapStart : I32 } -> Task {} []
drawPipe = \sprite, { x, gapStart } ->
    {} <- Sprite.blit sprite { x, y: gapStart - W4.screenHeight, flags: [FlipY] } |> Task.await
    Sprite.blit sprite { x, y: gapStart + gapHeight }

setTextColors : Task {} []
setTextColors =
    W4.setTextColors { fg: Color4, bg: None }

setSpriteColors : Task {} []
setSpriteColors =
    W4.setDrawColors { primary: None, secondary: Color2, tertiary: Color3, quaternary: Color4 }

halfRocciIdleAnimTime = 20

rocciSpriteSheet = Sprite.new {
    data: [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x15, 0x54, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x05, 0x55, 0x60, 0x00, 0x00, 0x05, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x55, 0x68, 0x00, 0x00, 0x05, 0x40, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x55, 0x6a, 0x01, 0x60, 0x15, 0x40, 0x00, 0x01, 0x60, 0x00, 0x00, 0x00, 0x01, 0x60, 0x00, 0x15, 0x6a, 0x85, 0x68, 0x15, 0x50, 0x00, 0x05, 0x68, 0x00, 0x00, 0x00, 0x05, 0x68, 0x00, 0x05, 0x6a, 0xa5, 0x40, 0x15, 0x55, 0x00, 0x15, 0x40, 0x00, 0x00, 0x00, 0x15, 0x40, 0x00, 0x01, 0x6a, 0xa9, 0x40, 0x15, 0x55, 0x6a, 0x95, 0x40, 0x15, 0x40, 0x00, 0x55, 0x40, 0x00, 0x00, 0x96, 0xaa, 0x40, 0x15, 0x56, 0xaa, 0xaa, 0x40, 0x05, 0x55, 0x6a, 0xaa, 0x40, 0x00, 0x00, 0x95, 0x55, 0x00, 0x05, 0x5a, 0xaa, 0xa5, 0x00, 0x01, 0x55, 0xaa, 0xa5, 0x00, 0x00, 0x00, 0x95, 0x54, 0x00, 0x01, 0x6a, 0xaa, 0x54, 0x00, 0x00, 0x55, 0xaa, 0x94, 0x00, 0x00, 0x02, 0x95, 0x40, 0x00, 0x00, 0x6a, 0x95, 0x40, 0x00, 0x00, 0x15, 0xaa, 0x40, 0x00, 0x00, 0x02, 0x95, 0x00, 0x00, 0x00, 0x02, 0x95, 0x00, 0x00, 0x00, 0x05, 0xa5, 0x00, 0x00, 0x00, 0x02, 0x90, 0x00, 0x00, 0x00, 0x02, 0x90, 0x00, 0x00, 0x00, 0x02, 0x90, 0x00, 0x00, 0x00, 0x02, 0x80, 0x00, 0x00, 0x00, 0x02, 0x80, 0x00, 0x00, 0x00, 0x02, 0x80, 0x00, 0x00, 0x00, 0x0a, 0xa0, 0x00, 0x00, 0x00, 0x0a, 0xa0, 0x00, 0x00, 0x00, 0x0a, 0xa0, 0x00, 0x00, 0x00, 0x0a, 0x80, 0x00, 0x00, 0x00, 0x0a, 0x80, 0x00, 0x00, 0x00, 0x0a, 0x80, 0x00, 0x00, 0x00, 0x0a, 0x00, 0x00, 0x00, 0x00, 0x0a, 0x00, 0x00, 0x00, 0x00, 0x0a, 0x00, 0x00, 0x00, 0x00, 0x08, 0x00, 0x00, 0x00, 0x00, 0x08, 0x00, 0x00, 0x00, 0x00, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
    bpp: BPP2,
    width: 60,
    height: 20,
}

createRocciIdleAnim : U64 -> Animation
createRocciIdleAnim = \frameCount -> {
    lastUpdated: frameCount,
    index: 0,
    state: Loop,
    cells: [
        { frames: 17, sprite: Sprite.subOrCrash rocciSpriteSheet { srcX: 0, srcY: 0, width: 20, height: 20 } },
        { frames: 6, sprite: Sprite.subOrCrash rocciSpriteSheet { srcX: 20, srcY: 0, width: 20, height: 20 } },
        { frames: 17, sprite: Sprite.subOrCrash rocciSpriteSheet { srcX: 40, srcY: 0, width: 20, height: 20 } },
    ],
}

createRocciFlapAnim : U64 -> Animation
createRocciFlapAnim = \frameCount -> {
    lastUpdated: frameCount,
    index: 2,
    state: Completed,
    cells: [
        # TODO: finetune timing and add eventual fall animation.
        { frames: 6, sprite: Sprite.subOrCrash rocciSpriteSheet { srcX: 20, srcY: 0, width: 20, height: 20 } },
        { frames: 17, sprite: Sprite.subOrCrash rocciSpriteSheet { srcX: 40, srcY: 0, width: 20, height: 20 } },
        { frames: 17, sprite: Sprite.subOrCrash rocciSpriteSheet { srcX: 0, srcY: 0, width: 20, height: 20 } },
    ],
}

rocciFallSpriteSheet = Sprite.new {
    data: [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x08, 0x04, 0x00, 0x00, 0x00, 0x02, 0x01, 0x00, 0x00, 0x00, 0x28, 0x14, 0x00, 0x00, 0x00, 0x0a, 0x05, 0x00, 0x00, 0x00, 0xa8, 0x54, 0x00, 0x00, 0x00, 0x2a, 0x15, 0x00, 0x00, 0x00, 0x28, 0x54, 0x00, 0x00, 0x00, 0x0a, 0x55, 0x00, 0x00, 0x00, 0x29, 0x54, 0x00, 0x00, 0x00, 0x2a, 0x55, 0x00, 0x00, 0x00, 0x59, 0x54, 0x00, 0x00, 0x00, 0x1a, 0x55, 0x00, 0x00, 0x00, 0x5a, 0x54, 0x00, 0x00, 0x00, 0x5a, 0x55, 0x00, 0x00, 0x01, 0x5a, 0x54, 0x00, 0x00, 0x01, 0x5a, 0x54, 0x00, 0x00, 0x01, 0x5a, 0x90, 0x00, 0x00, 0x01, 0x6a, 0x54, 0x00, 0x00, 0x01, 0x6a, 0x90, 0x00, 0x00, 0x01, 0x6a, 0x90, 0x00, 0x00, 0x01, 0x6a, 0x80, 0x00, 0x00, 0x01, 0x6a, 0x80, 0x00, 0x00, 0x01, 0x6a, 0x80, 0x00, 0x00, 0x01, 0xaa, 0x80, 0x00, 0x00, 0x01, 0xaa, 0x00, 0x00, 0x00, 0x00, 0xaa, 0x00, 0x00, 0x00, 0x00, 0xa8, 0x00, 0x00, 0x00, 0x00, 0xa8, 0x00, 0x00, 0x00, 0x00, 0x54, 0x00, 0x00, 0x00, 0x00, 0x54, 0x00, 0x00, 0x00, 0x00, 0x50, 0x00, 0x00, 0x00, 0x00, 0x50, 0x00, 0x00, 0x00, 0x0a, 0x50, 0x00, 0x00, 0x00, 0x0a, 0x50, 0x00, 0x00, 0x00, 0x02, 0x40, 0x00, 0x00, 0x00, 0x02, 0x40, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
    bpp: BPP2,
    width: 40,
    height: 20,
}

createRocciFallAnim : U64 -> Animation
createRocciFallAnim = \frameCount -> {
    lastUpdated: frameCount,
    index: 0,
    state: Loop,
    cells: [
        # TODO: finetune timing.
        { frames: 10, sprite: Sprite.subOrCrash rocciFallSpriteSheet { srcX: 0, srcY: 0, width: 20, height: 20 } },
        { frames: 10, sprite: Sprite.subOrCrash rocciFallSpriteSheet { srcX: 20, srcY: 0, width: 20, height: 20 } },
    ],
}

createGrassSprite : {} -> Sprite
createGrassSprite = \{} ->
    Sprite.new {
        data: [0x00, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x20, 0x80, 0x00, 0x00, 0x82, 0x00, 0x00, 0x00, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x08, 0x00, 0x02, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x80, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02, 0x22, 0x00, 0x00, 0x02, 0x08, 0x00, 0x00, 0x00, 0x20, 0x82, 0x00, 0x2a, 0x00, 0x00, 0x00, 0x28, 0x00, 0x08, 0x80, 0x02, 0x82, 0x00, 0x00, 0x06, 0x11, 0x11, 0x00, 0x02, 0xb2, 0xb0, 0x00, 0x00, 0xa0, 0x02, 0x00, 0x00, 0xa0, 0x00, 0x00, 0x02, 0xaa, 0x00, 0x00, 0x02, 0x28, 0x00, 0x01, 0x04, 0x2a, 0x88, 0x00, 0x95, 0xc0, 0x00, 0x08, 0x20, 0x08, 0x08, 0x00, 0x0a, 0x0a, 0x28, 0x00, 0x91, 0x44, 0x66, 0x00, 0x09, 0x6d, 0x5c, 0x00, 0x02, 0x82, 0x08, 0x00, 0x02, 0x0b, 0x00, 0x20, 0x0a, 0xea, 0x00, 0xa0, 0x0a, 0xae, 0x00, 0x44, 0x51, 0xae, 0xa8, 0x00, 0x39, 0xa0, 0x00, 0x28, 0xa8, 0x20, 0x08, 0x00, 0x28, 0x08, 0xa0, 0x01, 0x45, 0x19, 0x18, 0x40, 0x03, 0xef, 0xeb, 0x00, 0x0a, 0x0a, 0x2a, 0x00, 0x08, 0x20, 0xc0, 0x88, 0x2b, 0xae, 0x82, 0x20, 0x2b, 0xba, 0x81, 0x11, 0x16, 0xba, 0xba, 0x00, 0xbe, 0xde, 0x00, 0xba, 0xba, 0xa0, 0x0a, 0xa0, 0x2a, 0x2a, 0xb8, 0x04, 0x5a, 0x6a, 0x79, 0x10, 0x29, 0xbe, 0x68, 0x00, 0x2b, 0xaa, 0xae, 0x80, 0x31, 0x81, 0xc0, 0x80, 0x2b, 0xba, 0xa2, 0x1c, 0xae, 0xba, 0xa0, 0x66, 0x6a, 0xba, 0xeb, 0x82, 0x5b, 0x95, 0xc0, 0xba, 0xea, 0xe8, 0x0b, 0x80, 0xae, 0xae, 0xea, 0x01, 0x6b, 0xaa, 0xea, 0x40, 0x96, 0x97, 0x96, 0x00, 0xae, 0xae, 0xba, 0xa0, 0x31, 0x85, 0x70, 0xa0, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xfe, 0xaf, 0xea, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xab, 0x5b, 0xea, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xab, 0xfa, 0xbf, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xbe, 0xae, 0xbe, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0xf5, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x44, 0x44, 0x44, 0x44, 0x44, 0x44, 0x44, 0x44, 0x44, 0x44, 0x44, 0x44, 0x44, 0x44, 0x44, 0x44, 0x44, 0x44, 0x44, 0x44, 0x44, 0x44, 0x44, 0x44, 0x44, 0x44, 0x44, 0x44, 0x44, 0x44, 0x44, 0x44, 0x44, 0x44, 0x44, 0x44, 0x44, 0x44, 0x44, 0x44, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x65, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x59, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x95, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x45, 0x14, 0x51, 0x85, 0x14, 0x51, 0x49, 0x14, 0x91, 0x45, 0x18, 0x51, 0x54, 0x51, 0x49, 0x24, 0x51, 0x46, 0x14, 0x51, 0x46, 0x15, 0x14, 0x61, 0x45, 0x14, 0x92, 0x45, 0x14, 0x61, 0x46, 0x14, 0x55, 0x14, 0x51, 0x45, 0x14, 0x61, 0x51, 0x45, 0x65, 0x66, 0x56, 0x56, 0x59, 0x56, 0x59, 0x56, 0x55, 0x65, 0x65, 0x56, 0x59, 0x56, 0x59, 0x95, 0x59, 0x59, 0x55, 0x99, 0x59, 0x59, 0x55, 0x95, 0x96, 0x55, 0x99, 0x55, 0x95, 0x95, 0x59, 0x55, 0x96, 0x55, 0x59, 0x59, 0x95, 0x95, 0x96, 0x55, 0x95, 0x95, 0x99, 0x66, 0x65, 0x99, 0x65, 0x96, 0x95, 0x96, 0x59, 0x59, 0x65, 0x99, 0x65, 0xa5, 0x65, 0x96, 0x56, 0x56, 0x65, 0x99, 0x96, 0x59, 0x99, 0x66, 0x5a, 0x56, 0x59, 0x65, 0x96, 0x56, 0x59, 0x66, 0x65, 0x65, 0x66, 0x59, 0x99, 0x59, 0xa6, 0x9a, 0x5a, 0x69, 0x6a, 0x5a, 0x66, 0xa5, 0xa6, 0x9a, 0x9a, 0x6a, 0x6a, 0x5a, 0x65, 0x69, 0xa6, 0xa6, 0x9a, 0x69, 0x69, 0xa5, 0xa6, 0x9a, 0x5a, 0x96, 0x56, 0x9a, 0x6a, 0x6a, 0xa6, 0x9a, 0x9a, 0x96, 0xa9, 0xa6, 0x96, 0x9a, 0x5a, 0x69, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa, 0xaa],
        bpp: BPP2,
        width: 160,
        height: 20,
    }

createPipeSprite : {} -> Sprite
createPipeSprite = \{} ->
    Sprite.new {
        data: [0x0a, 0xaa, 0xaa, 0xab, 0xf0, 0x25, 0x55, 0x55, 0x55, 0x5c, 0x26, 0x96, 0x6a, 0x9a, 0xac, 0x36, 0x96, 0x6a, 0x66, 0xac, 0x36, 0x96, 0x6a, 0x9a, 0xac, 0x0f, 0xff, 0xff, 0xff, 0xf0, 0x03, 0x65, 0x9a, 0x66, 0xc0, 0x03, 0x65, 0x9a, 0x9a, 0xc0, 0x03, 0x65, 0x9a, 0x66, 0xc0, 0x03, 0x65, 0x9a, 0x9a, 0xc0, 0x03, 0x65, 0x9a, 0x66, 0xc0, 0x03, 0x65, 0x9a, 0x9a, 0xc0, 0x03, 0x65, 0x9a, 0x66, 0xc0, 0x03, 0x65, 0x9a, 0x9a, 0xc0, 0x03, 0x65, 0x9a, 0x66, 0xc0, 0x03, 0x65, 0x9a, 0x9a, 0xc0, 0x03, 0x65, 0x9a, 0x66, 0xc0, 0x03, 0x65, 0x9a, 0x9a, 0xc0, 0x03, 0x65, 0x9a, 0x66, 0xc0, 0x03, 0x65, 0x9a, 0x9a, 0xc0, 0x03, 0x65, 0x9a, 0x66, 0xc0, 0x03, 0x65, 0x9a, 0x9a, 0xc0, 0x03, 0x65, 0x9a, 0x66, 0xc0, 0x03, 0x65, 0x9a, 0x9a, 0xc0, 0x03, 0x65, 0x9a, 0x66, 0xc0, 0x03, 0x65, 0x9a, 0x9a, 0xc0, 0x03, 0x65, 0x9a, 0x66, 0xc0, 0x03, 0x65, 0x9a, 0x9a, 0xc0, 0x03, 0x65, 0x9a, 0x66, 0xc0, 0x03, 0x65, 0x9a, 0x9a, 0xc0, 0x03, 0x65, 0x9a, 0x66, 0xc0, 0x03, 0x65, 0x9a, 0x9a, 0xc0, 0x03, 0x65, 0x9a, 0x66, 0xc0, 0x03, 0x65, 0x9a, 0x9a, 0xc0, 0x03, 0x65, 0x9a, 0x66, 0xc0, 0x03, 0x65, 0x9a, 0x9a, 0xc0, 0x03, 0x65, 0x9a, 0x66, 0xc0, 0x03, 0x65, 0x9a, 0x9a, 0xc0, 0x03, 0x65, 0x9a, 0x66, 0xc0, 0x03, 0x65, 0x9a, 0x9a, 0xc0, 0x03, 0x65, 0x9a, 0x66, 0xc0, 0x03, 0x65, 0x9a, 0x9a, 0xc0, 0x03, 0x65, 0x9a, 0x66, 0xc0, 0x03, 0x65, 0x9a, 0x9a, 0xc0, 0x03, 0x65, 0x9a, 0x66, 0xc0, 0x03, 0x65, 0x9a, 0x9a, 0xc0, 0x03, 0x65, 0x9a, 0x66, 0xc0, 0x03, 0x65, 0x9a, 0x9a, 0xc0, 0x03, 0x65, 0x9a, 0x66, 0xc0, 0x03, 0x65, 0x9a, 0x9a, 0xc0, 0x03, 0x65, 0x9a, 0x66, 0xc0, 0x03, 0x65, 0x9a, 0x9a, 0xc0, 0x03, 0x65, 0x9a, 0x66, 0xc0, 0x03, 0x65, 0x9a, 0x9a, 0xc0, 0x03, 0x65, 0x9a, 0x66, 0xc0, 0x03, 0x65, 0x9a, 0x9a, 0xc0, 0x03, 0x65, 0x9a, 0x66, 0xc0, 0x03, 0x65, 0x9a, 0x9a, 0xc0, 0x03, 0x65, 0x9a, 0x66, 0xc0, 0x03, 0x65, 0x9a, 0x9a, 0xc0, 0x03, 0x65, 0x9a, 0x66, 0xc0, 0x03, 0x65, 0x9a, 0x9a, 0xc0, 0x03, 0x65, 0x9a, 0x66, 0xc0, 0x03, 0x65, 0x9a, 0x9a, 0xc0, 0x03, 0x65, 0x9a, 0x66, 0xc0, 0x03, 0x65, 0x9a, 0x9a, 0xc0, 0x03, 0x65, 0x9a, 0x66, 0xc0, 0x03, 0x65, 0x9a, 0x9a, 0xc0, 0x03, 0x65, 0x9a, 0x66, 0xc0, 0x03, 0x65, 0x9a, 0x9a, 0xc0, 0x03, 0x65, 0x9a, 0x66, 0xc0, 0x03, 0x65, 0x9a, 0x9a, 0xc0, 0x03, 0x65, 0x9a, 0x66, 0xc0, 0x03, 0x65, 0x9a, 0x9a, 0xc0, 0x03, 0x65, 0x9a, 0x66, 0xc0, 0x03, 0x65, 0x9a, 0x9a, 0xc0, 0x03, 0x65, 0x9a, 0x66, 0xc0, 0x03, 0x65, 0x9a, 0x9a, 0xc0, 0x03, 0x65, 0x9a, 0x66, 0xc0, 0x03, 0x65, 0x9a, 0x9a, 0xc0, 0x03, 0x65, 0x9a, 0x66, 0xc0, 0x03, 0x65, 0x9a, 0x9a, 0xc0, 0x03, 0x65, 0x9a, 0x66, 0xc0, 0x03, 0x65, 0x9a, 0x9a, 0xc0, 0x03, 0x65, 0x9a, 0x66, 0xc0, 0x03, 0x65, 0x9a, 0x9a, 0xc0, 0x03, 0x65, 0x9a, 0x66, 0xc0, 0x03, 0x65, 0x9a, 0x9a, 0xc0, 0x03, 0x65, 0x9a, 0x66, 0xc0, 0x03, 0x65, 0x9a, 0x9a, 0xc0, 0x03, 0x65, 0x9a, 0x66, 0xc0, 0x03, 0x65, 0x9a, 0x9a, 0xc0, 0x03, 0x65, 0x9a, 0x66, 0xc0, 0x03, 0x65, 0x9a, 0x9a, 0xc0, 0x03, 0x65, 0x9a, 0x66, 0xc0, 0x03, 0x65, 0x9a, 0x9a, 0xc0, 0x03, 0x65, 0x9a, 0x66, 0xc0, 0x03, 0x65, 0x9a, 0x9a, 0xc0, 0x03, 0x65, 0x9a, 0x66, 0xc0, 0x03, 0x65, 0x9a, 0x9a, 0xc0, 0x03, 0x65, 0x9a, 0x66, 0xc0, 0x03, 0x65, 0x9a, 0x9a, 0xc0, 0x03, 0x65, 0x9a, 0x66, 0xc0, 0x03, 0x65, 0x9a, 0x9a, 0xc0, 0x03, 0x65, 0x9a, 0x66, 0xc0, 0x03, 0x65, 0x9a, 0x9a, 0xc0, 0x03, 0x65, 0x9a, 0x66, 0xc0, 0x03, 0x65, 0x9a, 0x9a, 0xc0, 0x03, 0x65, 0x9a, 0x66, 0xc0, 0x03, 0x65, 0x9a, 0x9a, 0xc0, 0x03, 0x65, 0x9a, 0x66, 0xc0, 0x03, 0x65, 0x9a, 0x9a, 0xc0, 0x03, 0x65, 0x9a, 0x66, 0xc0, 0x03, 0x65, 0x9a, 0x9a, 0xc0, 0x03, 0x65, 0x9a, 0x66, 0xc0, 0x03, 0x65, 0x9a, 0x9a, 0xc0, 0x03, 0x65, 0x9a, 0x66, 0xc0, 0x03, 0x65, 0x9a, 0x9a, 0xc0, 0x03, 0x65, 0x9a, 0x66, 0xc0, 0x03, 0x65, 0x9a, 0x9a, 0xc0, 0x03, 0x65, 0x9a, 0x66, 0xc0, 0x03, 0x65, 0x9a, 0x9a, 0xc0, 0x03, 0x65, 0x9a, 0x66, 0xc0, 0x03, 0x65, 0x9a, 0x9a, 0xc0, 0x03, 0x65, 0x9a, 0x66, 0xc0, 0x03, 0x65, 0x9a, 0x9a, 0xc0, 0x03, 0x65, 0x9a, 0x66, 0xc0, 0x03, 0x65, 0x9a, 0x9a, 0xc0, 0x03, 0x65, 0x9a, 0x66, 0xc0, 0x03, 0x65, 0x9a, 0x9a, 0xc0, 0x03, 0x65, 0x9a, 0x66, 0xc0, 0x03, 0x65, 0x9a, 0x9a, 0xc0, 0x03, 0x65, 0x9a, 0x66, 0xc0, 0x03, 0x65, 0x9a, 0x9a, 0xc0, 0x03, 0x65, 0x9a, 0x66, 0xc0, 0x03, 0x65, 0x9a, 0x9a, 0xc0, 0x03, 0x65, 0x9a, 0x66, 0xc0, 0x03, 0x65, 0x9a, 0x9a, 0xc0, 0x03, 0x65, 0x9a, 0x66, 0xc0, 0x03, 0x65, 0x9a, 0x9a, 0xc0, 0x03, 0x65, 0x9a, 0x66, 0xc0, 0x03, 0x65, 0x9a, 0x9a, 0xc0, 0x03, 0x65, 0x9a, 0x66, 0xc0, 0x03, 0x65, 0x9a, 0x9a, 0xc0, 0x03, 0x65, 0x9a, 0x66, 0xc0, 0x03, 0x65, 0x9a, 0x9a, 0xc0, 0x03, 0x65, 0x9a, 0x66, 0xc0, 0x03, 0x65, 0x9a, 0x9a, 0xc0, 0x03, 0x65, 0x9a, 0x66, 0xc0, 0x03, 0x65, 0x9a, 0x9a, 0xc0, 0x03, 0x65, 0x9a, 0x66, 0xc0, 0x03, 0x65, 0x9a, 0x9a, 0xc0, 0x03, 0x65, 0x9a, 0x66, 0xc0, 0x03, 0x65, 0x9a, 0x9a, 0xc0, 0x03, 0x65, 0x9a, 0x66, 0xc0, 0x03, 0x65, 0x9a, 0x9a, 0xc0, 0x03, 0x65, 0x9a, 0x66, 0xc0, 0x03, 0x65, 0x9a, 0x9a, 0xc0, 0x03, 0x65, 0x9a, 0x66, 0xc0, 0x03, 0x65, 0x9a, 0x9a, 0xc0],
        bpp: BPP2,
        width: 20,
        height: 160,
    }
