app [main, Model] {
    w4: platform "../platform/main.roc",
}

import w4.Task exposing [Task]
import w4.W4 exposing [Gamepad]
import w4.Sprite exposing [Sprite]

Program : {
    init : Task Model [],
    update : Model -> Task Model [],
}

Model : {
    frameCount : U64,
    snake : Snake,
    fruit : Fruit,
    fruitSprite : Sprite,
    gameStarted : Bool,
}

main : Program
main = { init, update }

init : Task Model []
init =
    setColorPalette!

    fruitSprite = Sprite.new {
        data: [0x00, 0xa0, 0x02, 0x00, 0x0e, 0xf0, 0x36, 0x5c, 0xd6, 0x57, 0xd5, 0x57, 0x35, 0x5c, 0x0f, 0xf0],
        bpp: BPP2,
        width: 8,
        height: 8,
    }

    Task.ok {
        frameCount: 0,
        snake: startingSnake,
        fruit: { x: 0, y: 0 },
        fruitSprite,
        gameStarted: Bool.false,
    }

update : Model -> Task Model []
update = \prev ->
    # Update frame count
    model = { prev & frameCount: prev.frameCount + 1 }

    if !model.gameStarted then
        runTitleScreen model
    else if snakeIsDead model.snake then
        runEndScreen model
    else
        runGame model

runTitleScreen : Model -> Task Model []
runTitleScreen = \model ->
    W4.text! "Press X to start!" { x: 15, y: 72 }

    gamepad = W4.getGamepad! Player1

    if gamepad.button1 then
        # Seed the randomness with number of frames since the start of the game.
        # This makes the game feel like it is truely randomly seeded cause players won't always start on the same frame.
        W4.seedRand! model.frameCount

        # Generate the starting fruit.
        fruit = getRandomFruit! startingSnake

        Task.ok { model & gameStarted: Bool.true, fruit }
    else
        Task.ok model

runEndScreen : Model -> Task Model []
runEndScreen = \model ->
    drawGame! model
    W4.setTextColors! { fg: blue, bg: white }
    W4.text! "Game Over!" { x: 40, y: 72 }
    Task.ok model

runGame : Model -> Task Model []
runGame = \model ->

    # Get gamepad
    gamepad = W4.getGamepad! Player1

    # Update snake
    (snake, ate) =
        updateSnake model.snake gamepad model.frameCount model.fruit

    fruitTask =
        when ate is
            AteFruit ->
                getRandomFruit snake

            DidNotEat ->
                Task.ok model.fruit

    fruit = fruitTask!

    next = { model & snake, fruit }
    drawGame! next

    # Return model for next frame
    Task.ok next

drawGame : Model -> Task {} []
drawGame = \model ->
    # Draw fruit
    W4.setDrawColors! {
        primary: None,
        secondary: orange,
        tertiary: green,
        quaternary: blue,
    }

    Sprite.blit! model.fruitSprite { x: model.fruit.x * 8, y: model.fruit.y * 8 }
    # Draw snake body
    W4.setShapeColors! { border: blue, fill: green }
    drawSnakeBody! model.snake
    # Draw snake head
    W4.setShapeColors! { border: blue, fill: blue }
    drawSnakeHead model.snake

# Set the color pallet
white = Color1
orange = Color2
green = Color3
blue = Color4

setColorPalette : Task {} []
setColorPalette =
    W4.setPalette {
        color1: 0xfbf7f3,
        color2: 0xe5b083,
        color3: 0x426e5d,
        color4: 0x20283d,
    }

Point : { x : I32, y : I32 }
Dir : [Up, Down, Left, Right]

Fruit : Point

Snake : {
    body : List Point,
    head : Point,
    direction : Dir,
}

startingSnake : Snake
startingSnake = {
    body: [{ x: 1, y: 0 }, { x: 0, y: 0 }],
    head: { x: 2, y: 0 },
    direction: Right,
}

drawSnakeBody : Snake -> Task {} []
drawSnakeBody = \snake ->
    List.walk snake.body (Task.ok {}) \task, part ->
        task!

        W4.rect { x: (part.x * 8), y: (part.y * 8), width: 8, height: 8 }

drawSnakeHead : Snake -> Task {} []
drawSnakeHead = \snake ->
    W4.rect { x: (snake.head.x * 8), y: (snake.head.y * 8), width: 8, height: 8 }

updateSnake : Snake, Gamepad, U64, Fruit -> (Snake, [AteFruit, DidNotEat])
updateSnake = \s0, { left, right, up, down }, frameCount, fruit ->
    # Always record direction changes
    s1 =
        if left && !right then
            { s0 & direction: Left }
        else if right && !left then
            { s0 & direction: Right }
        else if up && !down then
            { s0 & direction: Up }
        else if down && !up then
            { s0 & direction: Down }
        else
            s0

    # Only move every 0.25 seconds (15 of 60 frames)
    s2 =
        if (frameCount % 15) == 0 then
            moveSnake s1
        else
            s1

    if s2.head == fruit then
        (growSnake s2, AteFruit)
    else
        (s2, DidNotEat)

moveSnake : Snake -> Snake
moveSnake = \prev ->

    head =
        when prev.direction is
            Up -> { x: prev.head.x, y: (prev.head.y + 20 - 1) % 20 }
            Down -> { x: prev.head.x, y: (prev.head.y + 1) % 20 }
            Left -> { x: (prev.head.x + 20 - 1) % 20, y: prev.head.y }
            Right -> { x: (prev.head.x + 1) % 20, y: prev.head.y }

    walkBody : Point, List Point, List Point -> List Point
    walkBody = \last, remaining, newBody ->
        when remaining is
            [] -> newBody
            [curr, ..] ->
                walkBody curr (List.dropFirst remaining 1) (List.append newBody last)

    body = walkBody prev.head prev.body []

    { prev & head, body }

growSnake : Snake -> Snake
growSnake = \{ head, body, direction } ->
    tail = List.last body |> Result.withDefault head
    { head, body: List.append body tail, direction }

snakeIsDead : Snake -> Bool
snakeIsDead = \{ head, body } ->
    List.contains body head

getRandomFruit : Snake -> Task Fruit []
getRandomFruit = \{ head, body } ->
    # Will the perf of this be bad with a large snake?
    # The better alternative may be to have a free square list and randomly select one.
    Task.loop {} \{} ->
        x = W4.randBetween! { start: 0, before: 20 }
        y = W4.randBetween! { start: 0, before: 20 }

        fruit = { x, y }
        if fruit == head || List.contains body fruit then
            Step {} |> Task.ok
        else
            Done fruit |> Task.ok
