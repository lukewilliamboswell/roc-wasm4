app [main] {
    w4: platform "../platform/main.roc",
}

import w4.W4
import w4.Sprite

Model : {
    frame_count : U64,
    snake : Snake,
    fruit : Fruit,
    fruit_sprite : Sprite,
    game_started : Bool,
}

Point : { x : I32, y : I32 }
Dir : [Up, Down, Left, Right]
Fruit : Point
GamepadState : {
    button1 : Bool,
    button2 : Bool,
    left : Bool,
    right : Bool,
    up : Bool,
    down : Bool,
}

Snake : {
    body : List(Point),
    head : Point,
    direction : Dir,
}

main = {
    init!: || {
        set_color_palette!()

        fruit_sprite = Sprite.new({
            data: [0x00, 0xa0, 0x02, 0x00, 0x0e, 0xf0, 0x36, 0x5c, 0xd6, 0x57, 0xd5, 0x57, 0x35, 0x5c, 0x0f, 0xf0],
            bpp: BPP2,
            width: 8,
            height: 8,
        })

        {
            frame_count: 0,
            snake: starting_snake,
            fruit: { x: 0, y: 0 },
            fruit_sprite,
            game_started: Bool.False,
        }
    },
    update!: |prev| update!(prev),
}

update! : Model => Model
update! = |prev| {
    model = { ..prev, frame_count: prev.frame_count + 1 }

    if !model.game_started {
        run_title_screen!(model)
    } else if snake_is_dead(model.snake) {
        run_end_screen!(model)
    } else {
        run_game!(model)
    }
}

run_title_screen! : Model => Model
run_title_screen! = |model| {
    W4.text!("Press X to start!", { x: 15, y: 72 })

    gamepad = W4.get_gamepad!(Player1)

    if gamepad.button1 {
        W4.seed_rand!(model.frame_count)
        fruit = get_random_fruit!(starting_snake)

        { ..model, game_started: Bool.True, fruit }
    } else {
        model
    }
}

run_end_screen! : Model => Model
run_end_screen! = |model| {
    draw_game!(model)
    W4.set_text_colors!({ fg: blue, bg: white })
    W4.text!("Game Over!", { x: 40, y: 72 })
    model
}

run_game! : Model => Model
run_game! = |model| {
    gamepad = W4.get_gamepad!(Player1)
    (snake, ate) = update_snake(model.snake, gamepad, model.frame_count, model.fruit)

    fruit = match ate {
        AteFruit => get_random_fruit!(snake)
        DidNotEat => model.fruit
    }

    next = { ..model, snake, fruit }
    draw_game!(next)

    next
}

draw_game! : Model => {}
draw_game! = |model| {
    W4.set_draw_colors!({
        primary: None,
        secondary: orange,
        tertiary: green,
        quaternary: blue,
    })

    Sprite.blit!(model.fruit_sprite, {
        x: model.fruit.x * 8,
        y: model.fruit.y * 8,
        flags: Sprite.Flags.default(),
    })

    W4.set_shape_colors!({ border: blue, fill: green })
    draw_snake_body!(model.snake)

    W4.set_shape_colors!({ border: blue, fill: blue })
    draw_snake_head!(model.snake)
}

white = Color1
orange = Color2
green = Color3
blue = Color4

set_color_palette! : () => {}
set_color_palette! = || {
    W4.set_palette!({
        color1: 0xfbf7f3,
        color2: 0xe5b083,
        color3: 0x426e5d,
        color4: 0x20283d,
    })
}

starting_snake : Snake
starting_snake = {
    body: [{ x: 1, y: 0 }, { x: 0, y: 0 }],
    head: { x: 2, y: 0 },
    direction: Right,
}

draw_snake_body! : Snake => {}
draw_snake_body! = |snake| {
    for part in snake.body {
        W4.rect!({ x: part.x * 8, y: part.y * 8, width: 8, height: 8 })
    }
}

draw_snake_head! : Snake => {}
draw_snake_head! = |snake| {
    W4.rect!({ x: snake.head.x * 8, y: snake.head.y * 8, width: 8, height: 8 })
}

update_snake : Snake, GamepadState, U64, Fruit -> (Snake, [AteFruit, DidNotEat])
update_snake = |s0, { left, right, up, down, .. }, frame_count, fruit| {
    s1 =
        if left and !right {
            { ..s0, direction: Left }
        } else if right and !left {
            { ..s0, direction: Right }
        } else if up and !down {
            { ..s0, direction: Up }
        } else if down and !up {
            { ..s0, direction: Down }
        } else {
            s0
        }

    s2 =
        if frame_count % 15 == 0 {
            move_snake(s1)
        } else {
            s1
        }

    if s2.head == fruit {
        (grow_snake(s2), AteFruit)
    } else {
        (s2, DidNotEat)
    }
}

move_snake : Snake -> Snake
move_snake = |prev| {
    head = match prev.direction {
        Up => { x: prev.head.x, y: (prev.head.y + 20 - 1) % 20 }
        Down => { x: prev.head.x, y: (prev.head.y + 1) % 20 }
        Left => { x: (prev.head.x + 20 - 1) % 20, y: prev.head.y }
        Right => { x: (prev.head.x + 1) % 20, y: prev.head.y }
    }

    var $body = []
    var $last = prev.head

    for curr in prev.body {
        $body = List.append($body, $last)
        $last = curr
    }

    { ..prev, head, body: $body }
}

grow_snake : Snake -> Snake
grow_snake = |{ head, body, direction }| {
    tail = match List.last(body) {
        Ok(point) => point
        Err(_) => head
    }

    { head, body: List.append(body, tail), direction }
}

snake_is_dead : Snake -> Bool
snake_is_dead = |{ head, body, .. }| List.contains(body, head)

get_random_fruit! : Snake => Fruit
get_random_fruit! = |{ head, body, .. }| {
    var $fruit = head
    var $done = Bool.False

    while !$done {
        x = W4.rand_between!({ start: 0, before: 20 })
        y = W4.rand_between!({ start: 0, before: 20 })
        candidate = { x, y }

        if candidate == head or List.contains(body, candidate) {
            {}
        } else {
            $fruit = candidate
            $done = Bool.True
        }
    }

    $fruit
}
