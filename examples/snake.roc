app "snake"
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
    snake : Snake,
    fruit : Fruit,
    fruitSprite : Sprite,
}

main : Program
main = { init, update }

init : Task Model []
init =
    {} <- setColorPalette |> Task.await

    startingFruit <- getRandomFruit startingSnake |> Task.await

    fruitSprite = Sprite.new {
        data: [0x00, 0xa0, 0x02, 0x00, 0x0e, 0xf0, 0x36, 0x5c, 0xd6, 0x57, 0xd5, 0x57, 0x35, 0x5c, 0x0f, 0xf0],
        bpp: BPP2,
        width: 8,
        height: 8,
    }

    Task.ok {
        frameCount: 0,
        snake: startingSnake,
        fruit: startingFruit,
        fruitSprite,
    }

update : Model -> Task Model []
update = \model ->
    if snakeIsDead model.snake then
        {} <- drawGame model |> Task.await
        {} <- W4.setTextColors { fg: blue, bg: white } |> Task.await
        # TODO: maybe count and display score under game over message.
        {} <- W4.text "Game Over!" { x: 40, y: 72 } |> Task.await
        Task.ok model
    else
        runGame model

runGame : Model -> Task Model []
runGame = \prev ->

    # Read gamepad
    gamepad <- W4.readGamepad Player1 |> Task.await

    # Update frame
    model = { prev & frameCount: prev.frameCount + 1 }

    # Update snake
    (snake, ate) =
        updateSnake model.snake gamepad model.frameCount model.fruit

    fruitTask =
        when ate is
            AteFruit ->
                getRandomFruit snake

            DidNotEat ->
                Task.ok model.fruit
    fruit <- fruitTask |> Task.await

    next = { model & snake, fruit }

    {} <- drawGame next |> Task.await

    # Return model for next frame
    Task.ok next

drawGame : Model -> Task {} []
drawGame = \model ->
    # Draw fruit
    {} <- W4.setDrawColors {
            primary: None,
            secondary: orange,
            tertiary: green,
            quaternary: blue,
        }
        |> Task.await
    {} <- Sprite.blit model.fruitSprite { x: model.fruit.x * 8, y: model.fruit.y * 8 } |> Task.await

    # Draw snake body
    {} <- W4.setShapeColors { border: blue, fill: green } |> Task.await
    {} <- drawSnakeBody model.snake |> Task.await

    # Draw snake head
    {} <- W4.setShapeColors { border: blue, fill: blue } |> Task.await
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
        {} <- task |> Task.await

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
            [curr, .. as rest] ->
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
        x <- W4.randRangeLessThan 0 20 |> Task.await
        y <- W4.randRangeLessThan 0 20 |> Task.await

        fruit = { x, y }
        if fruit == head || List.contains body fruit then
            Step {} |> Task.ok
        else
            Done fruit |> Task.ok

