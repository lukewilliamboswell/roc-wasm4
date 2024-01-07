app "snake"
    packages {
        w4: "../platform/main.roc",
    }
    imports [
        w4.Task.{ Task },
        w4.W4,
    ]
    provides [main, Model] to w4

Program : {
    init : Task Model [],
    update : Model -> Task Model [],
}

Model : {
    snake : Snake,
}

main : Program
main = { init, update }

init : Task Model []
init =
    {} <- setColorPallet |> Task.await

    Task.ok { snake: startingSnake }

update : Model -> Task Model []
update = \{ snake } ->

    # Snake body
    {} <- setRectColors { border: blue, fill: green } |> Task.await
    {} <- drawSnakeBody snake |> Task.await

    # Snake head
    {} <- setRectColors { border: blue, fill: blue } |> Task.await
    {} <- drawSnakeHead snake |> Task.await

    Task.ok { snake }

# Set the color pallet
# white = Color1
# orange = Color2
green = Color3
blue = Color4

setColorPallet : Task {} []
setColorPallet =
    W4.setPallet {
        color1: 0xfbf7f3,
        color2: 0xe5b083,
        color3: 0x426e5d,
        color4: 0x20283d,
    }

Point : { x : I32, y : I32 }
Dir : [Up, Down, Left, Right]

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

        W4.rect (part.x * 8) (part.y * 8) 8 8

drawSnakeHead : Snake -> Task {} []
drawSnakeHead = \snake ->
    W4.rect (snake.head.x * 8) (snake.head.y * 8) 8 8

setRectColors : { border : W4.Pallet, fill : W4.Pallet } -> Task {} []
setRectColors = \{ border, fill } ->
    W4.setDrawColors { primary: fill, secondary: border, tertiary: None, quaternary: None }

