#![no_std]
#![allow(static_mut_refs)]

mod sprites;
mod wasm4;

use core::panic::PanicInfo;
use wasm4::*;

const SCREEN: i32 = 160;
const PLAYER_X: i32 = 70;
const PLAYER_START_Y: f32 = 40.0;
const PLAYER_START_Y_PIXEL: i32 = 40;
const GRAVITY: f32 = 0.12;
const JUMP_SPEED: f32 = -2.2;
const GAP_HEIGHT: i32 = 40;
const PLANT_TYPES: u32 = 30;
const PLANT_Y: i32 = SCREEN - 22;
const MAX_PIPES: usize = 8;
const MAX_PLANTS: usize = 32;
const PRNG_DEFAULT: u32 = 0x6d2b_79f5;

const COLOR_NONE: u16 = 0;
const COLOR1: u16 = 1;
const COLOR2: u16 = 2;
const COLOR3: u16 = 3;
const COLOR4: u16 = 4;

#[panic_handler]
fn panic(_: &PanicInfo) -> ! {
    loop {}
}

#[derive(Copy, Clone)]
struct Region {
    src_x: u32,
    src_y: u32,
    width: u32,
    height: u32,
}

#[derive(Copy, Clone)]
struct Sprite {
    data: &'static [u8],
    bpp: u32,
    stride: u32,
    region: Region,
}

const fn sprite(data: &'static [u8], bpp: u32, width: u32, height: u32) -> Sprite {
    Sprite {
        data,
        bpp,
        stride: width,
        region: Region {
            src_x: 0,
            src_y: 0,
            width,
            height,
        },
    }
}

const fn sub_sprite(sprite: Sprite, src_x: u32, src_y: u32, width: u32, height: u32) -> Sprite {
    Sprite {
        data: sprite.data,
        bpp: sprite.bpp,
        stride: sprite.stride,
        region: Region {
            src_x: sprite.region.src_x + src_x,
            src_y: sprite.region.src_y + src_y,
            width,
            height,
        },
    }
}

const ROCCI_SPRITE_SHEET: Sprite = sprite(
    &sprites::ROCCI_SPRITE_SHEET_DATA,
    sprites::ROCCI_SPRITE_SHEET_BPP,
    sprites::ROCCI_SPRITE_SHEET_WIDTH,
    sprites::ROCCI_SPRITE_SHEET_HEIGHT,
);
const GROUND_SPRITE: Sprite = sprite(
    &sprites::GROUND_SPRITE_DATA,
    sprites::GROUND_SPRITE_BPP,
    sprites::GROUND_SPRITE_WIDTH,
    sprites::GROUND_SPRITE_HEIGHT,
);
const PIPE_SPRITE: Sprite = sprite(
    &sprites::PIPE_SPRITE_DATA,
    sprites::PIPE_SPRITE_BPP,
    sprites::PIPE_SPRITE_WIDTH,
    sprites::PIPE_SPRITE_HEIGHT,
);
const PLANT_SPRITE_SHEET: Sprite = sprite(
    &sprites::PLANT_SPRITE_SHEET_DATA,
    sprites::PLANT_SPRITE_SHEET_BPP,
    sprites::PLANT_SPRITE_SHEET_WIDTH,
    sprites::PLANT_SPRITE_SHEET_HEIGHT,
);
const HIGH_SCORE_SPRITE_SHEET: Sprite = sprite(
    &sprites::HIGH_SCORE_SPRITE_SHEET_DATA,
    sprites::HIGH_SCORE_SPRITE_SHEET_BPP,
    sprites::HIGH_SCORE_SPRITE_SHEET_WIDTH,
    sprites::HIGH_SCORE_SPRITE_SHEET_HEIGHT,
);

#[derive(Copy, Clone)]
struct Cell {
    frames: u64,
    sprite: Sprite,
}

static IDLE_CELLS: [Cell; 3] = [
    Cell { frames: 17, sprite: sub_sprite(ROCCI_SPRITE_SHEET, 0, 0, 16, 16) },
    Cell { frames: 6, sprite: sub_sprite(ROCCI_SPRITE_SHEET, 16, 0, 16, 16) },
    Cell { frames: 17, sprite: sub_sprite(ROCCI_SPRITE_SHEET, 32, 0, 16, 16) },
];

static FLAP_CELLS: [Cell; 3] = [
    Cell { frames: 6, sprite: sub_sprite(ROCCI_SPRITE_SHEET, 16, 0, 16, 16) },
    Cell { frames: 12, sprite: sub_sprite(ROCCI_SPRITE_SHEET, 32, 0, 16, 16) },
    Cell { frames: 1, sprite: sub_sprite(ROCCI_SPRITE_SHEET, 0, 0, 16, 16) },
];

static FALL_CELLS: [Cell; 2] = [
    Cell { frames: 10, sprite: sub_sprite(ROCCI_SPRITE_SHEET, 48, 0, 16, 16) },
    Cell { frames: 10, sprite: sub_sprite(ROCCI_SPRITE_SHEET, 64, 0, 16, 16) },
];

static HIGH_SCORE_CELLS: [Cell; 4] = [
    Cell { frames: 5, sprite: sub_sprite(HIGH_SCORE_SPRITE_SHEET, 0, 0, 32, 16) },
    Cell { frames: 5, sprite: sub_sprite(HIGH_SCORE_SPRITE_SHEET, 32, 0, 32, 16) },
    Cell { frames: 5, sprite: sub_sprite(HIGH_SCORE_SPRITE_SHEET, 64, 0, 32, 16) },
    Cell { frames: 5, sprite: sub_sprite(HIGH_SCORE_SPRITE_SHEET, 96, 0, 32, 16) },
];

#[derive(Copy, Clone)]
enum AnimationState {
    Completed,
    RunOnce,
    Loop,
}

#[derive(Copy, Clone)]
struct Animation {
    last_updated: u64,
    index: usize,
    cells: &'static [Cell],
    state: AnimationState,
}

#[derive(Copy, Clone)]
struct Player {
    y: f32,
    y_vel: f32,
}

#[derive(Copy, Clone)]
struct Pipe {
    x: i32,
    gap_start: i32,
}

#[derive(Copy, Clone)]
struct Plant {
    x: i32,
    kind: u32,
}

const EMPTY_PIPE: Pipe = Pipe { x: 0, gap_start: 0 };
const EMPTY_PLANT: Plant = Plant { x: 0, kind: 0 };

#[derive(Copy, Clone)]
struct Pipes {
    items: [Pipe; MAX_PIPES],
    len: usize,
}

#[derive(Copy, Clone)]
struct Plants {
    items: [Plant; MAX_PLANTS],
    len: usize,
}

impl Pipes {
    const fn empty() -> Self {
        Self { items: [EMPTY_PIPE; MAX_PIPES], len: 0 }
    }

    fn push(&mut self, pipe: Pipe) {
        if self.len < MAX_PIPES {
            self.items[self.len] = pipe;
            self.len += 1;
        }
    }
}

impl Plants {
    const fn empty() -> Self {
        Self { items: [EMPTY_PLANT; MAX_PLANTS], len: 0 }
    }

    fn push(&mut self, plant: Plant) {
        if self.len < MAX_PLANTS {
            self.items[self.len] = plant;
            self.len += 1;
        }
    }
}

#[derive(Copy, Clone)]
enum Mode {
    Title,
    Game,
    GameOver,
}

#[derive(Copy, Clone)]
struct State {
    mode: Mode,
    frame_count: u64,
    plants: Plants,
    rocci_idle_anim: Animation,
    score: u8,
    max_score: u8,
    high_score: u8,
    new_high_score: bool,
    player: Player,
    last_flap: bool,
    rocci_flap_anim: Animation,
    rocci_fall_anim: Animation,
    high_score_anim: Animation,
    pipes: Pipes,
    last_pipe_generated: u64,
    last_plant_generated: u64,
    ground_x: i32,
}

const INITIAL_ANIM: Animation = Animation {
    last_updated: 0,
    index: 0,
    cells: &IDLE_CELLS,
    state: AnimationState::Loop,
};

const INITIAL_STATE: State = State {
    mode: Mode::Title,
    frame_count: 0,
    plants: Plants::empty(),
    rocci_idle_anim: INITIAL_ANIM,
    score: 0,
    max_score: 0,
    high_score: 0,
    new_high_score: false,
    player: Player { y: PLAYER_START_Y, y_vel: JUMP_SPEED },
    last_flap: false,
    rocci_flap_anim: INITIAL_ANIM,
    rocci_fall_anim: INITIAL_ANIM,
    high_score_anim: INITIAL_ANIM,
    pipes: Pipes::empty(),
    last_pipe_generated: 0,
    last_plant_generated: 0,
    ground_x: 0,
};

static mut STATE: State = INITIAL_STATE;
static mut PRNG_STATE: u32 = PRNG_DEFAULT;

#[no_mangle]
pub extern "C" fn start() {
    set_palette();
    let frame_count = load_rand_from_disk();
    seed_rand(frame_count);
    let plants = starting_plants();
    unsafe {
        STATE = INITIAL_STATE;
        init_title_screen(&mut STATE, frame_count, plants);
    }
}

#[no_mangle]
pub extern "C" fn update() {
    unsafe {
        STATE.frame_count = STATE.frame_count.wrapping_add(1);
        match STATE.mode {
            Mode::Title => run_title_screen(&mut STATE),
            Mode::Game => run_game(&mut STATE),
            Mode::GameOver => run_game_over(&mut STATE),
        }
    }
}

fn init_title_screen(state: &mut State, frame_count: u64, plants: Plants) {
    state.mode = Mode::Title;
    state.frame_count = frame_count;
    state.plants = plants;
    state.rocci_idle_anim = create_rocci_idle_anim(frame_count);
}

fn run_title_screen(state: &mut State) {
    state.rocci_idle_anim = update_animation(state.frame_count, state.rocci_idle_anim);

    set_text_colors();
    text("Rocci Bird!!!", 32, 12);
    text("Click to start!", 24, 72);
    draw_ground(0);
    draw_plants(state.plants);

    let shift = idle_shift(state.frame_count, state.rocci_idle_anim);
    draw_animation(state.rocci_idle_anim, PLAYER_X, PLAYER_START_Y_PIXEL + shift, 0);

    if flap_pressed() {
        init_game(state);
    }
}

fn init_game(state: &mut State) {
    let frame_count = state.frame_count;
    save_rand_to_disk(frame_count);
    seed_rand(frame_count);
    play_tone(FLAP_TONE);

    state.mode = Mode::Game;
    state.score = 0;
    state.max_score = 0;
    state.player = Player { y: PLAYER_START_Y, y_vel: JUMP_SPEED };
    state.last_pipe_generated = frame_count;
    state.pipes = Pipes::empty();
    state.last_plant_generated = frame_count.saturating_sub(4);
    state.last_flap = true;
    state.rocci_flap_anim = create_rocci_flap_anim(frame_count);
    state.ground_x = 0;
}

fn run_game(state: &mut State) {
    let gamepad = unsafe { *GAMEPAD1 };
    let mouse = unsafe { *MOUSE_BUTTONS };
    let flap = (gamepad & (BUTTON_1 | BUTTON_UP)) != 0 || (mouse & MOUSE_LEFT) != 0;

    let (y_vel, next_anim) =
        if !state.last_flap && flap && flap_allowed(state.frame_count, state.rocci_flap_anim) {
            play_tone(FLAP_TONE);
            let mut anim = state.rocci_flap_anim;
            anim.index = 0;
            anim.state = AnimationState::RunOnce;
            (JUMP_SPEED, anim)
        } else {
            (
                state.player.y_vel + GRAVITY,
                update_animation(state.frame_count, state.rocci_flap_anim),
            )
        };

    let previous_pipes = state.pipes;
    let pipe = maybe_generate_pipe(state.last_pipe_generated, state.frame_count);
    let last_pipe_generated = if pipe.is_some() { state.frame_count } else { state.last_pipe_generated };
    let mut pipes = update_pipes(previous_pipes);
    if let Some(new_pipe) = pipe {
        pipes.push(new_pipe);
    }

    let plant = maybe_generate_plant(state.last_plant_generated, state.frame_count);
    let last_plant_generated = if plant.is_some() { state.frame_count } else { state.last_plant_generated };
    let mut plants = update_plants(state.plants);
    if let Some(new_plant) = plant {
        plants.push(new_plant);
    }

    let gain_point = count_passed_pipes(previous_pipes);
    let y = state.player.y + y_vel;
    let score = state.score.saturating_add(gain_point);
    state.rocci_flap_anim = next_anim;
    state.player = Player { y, y_vel };
    state.score = score;
    if score > state.max_score {
        state.max_score = score;
    }
    state.last_flap = flap;
    state.last_pipe_generated = last_pipe_generated;
    state.pipes = pipes;
    state.last_plant_generated = last_plant_generated;
    state.plants = plants;
    state.ground_x = (state.ground_x - 1) % SCREEN;

    if gain_point > 0 {
        play_tone(POINT_TONE);
    }

    draw_pipes(state.pipes);
    draw_ground(state.ground_x);
    draw_plants(state.plants);

    let y_pixel = (state.player.y as i32).min(134);
    let collided = player_collided(y_pixel, state.rocci_flap_anim.index);
    draw_animation(state.rocci_flap_anim, PLAYER_X, y_pixel, 0);
    draw_score(state.score, 68, 4);

    if collided || y >= 134.0 {
        play_tone(DEATH_TONE);
        init_game_over(state);
    }
}

fn init_game_over(state: &mut State) {
    let high_score_on_disk = load_high_score_from_disk();
    state.new_high_score = state.max_score > high_score_on_disk;
    state.high_score = if state.new_high_score { state.max_score } else { high_score_on_disk };
    save_high_score_to_disk(state.high_score);
    state.mode = Mode::GameOver;
    state.rocci_fall_anim = create_rocci_fall_anim(state.frame_count);
    state.high_score_anim = create_high_score_anim(state.frame_count);
}

fn run_game_over(state: &mut State) {
    let y_vel = state.player.y_vel + GRAVITY;
    state.rocci_fall_anim = update_animation(state.frame_count, state.rocci_fall_anim);
    state.high_score_anim = update_animation(state.frame_count, state.high_score_anim);
    state.player = Player { y: (state.player.y + y_vel).min(134.0), y_vel };

    draw_pipes(state.pipes);
    draw_ground(state.ground_x);
    draw_plants(state.plants);

    draw_animation(state.rocci_fall_anim, PLAYER_X, state.player.y as i32, 0);
    set_shape_colors(COLOR4, COLOR1);
    rect(16, 52, 136, 32);
    set_text_colors();
    text("Game Over!", 44, 56);
    text("Right to restart", 20, 72);
    text("Art by Luke DeVault", 4, 151);

    set_shape_colors(COLOR4, COLOR1);
    rect(66, 2, 28, 12);
    draw_score(state.score, 68, 4);

    if state.new_high_score {
        draw_animation(state.high_score_anim, 64, 0, 0);
    }

    set_shape_colors(COLOR4, COLOR1);
    rect(54, 18, 52, 12);
    set_text_colors();
    text("HS:", 57, 20);
    draw_score(state.high_score, 80, 20);

    let gamepad = unsafe { *GAMEPAD1 };
    let mouse = unsafe { *MOUSE_BUTTONS };
    if (mouse & MOUSE_RIGHT) != 0 || (gamepad & (BUTTON_2 | BUTTON_RIGHT)) != 0 {
        let plants = starting_plants();
        init_title_screen(state, state.frame_count, plants);
    }
}

fn flap_pressed() -> bool {
    let gamepad = unsafe { *GAMEPAD1 };
    let mouse = unsafe { *MOUSE_BUTTONS };
    (gamepad & (BUTTON_1 | BUTTON_UP)) != 0 || (mouse & MOUSE_LEFT) != 0
}

fn player_collided(player_y: i32, anim_index: usize) -> bool {
    if player_y >= -1 {
        on_screen_collided(player_y, anim_index)
    } else {
        get_pixel((PLAYER_X + 13) as u8, 0) != COLOR1 as u8
    }
}

fn on_screen_collided(player_y: i32, anim_index: usize) -> bool {
    const BASE_POINTS: [(i32, i32); 8] = [
        (11, 2),
        (13, 3),
        (3, 5),
        (11, 6),
        (9, 8),
        (5, 9),
        (7, 10),
        (5, 12),
    ];

    for (x, y) in BASE_POINTS {
        if get_pixel((PLAYER_X + x) as u8, (player_y + y) as u8) != COLOR1 as u8 {
            return true;
        }
    }
    if anim_index == 2 {
        get_pixel((PLAYER_X + 2) as u8, (player_y + 1) as u8) != COLOR1 as u8
            || get_pixel((PLAYER_X + 7) as u8, (player_y + 1) as u8) != COLOR1 as u8
    } else if anim_index == 1 {
        get_pixel((PLAYER_X + 2) as u8, (player_y + 2) as u8) != COLOR1 as u8
    } else {
        false
    }
}

fn draw_pipes(pipes: Pipes) {
    let mut i = 0;
    while i < pipes.len {
        draw_pipe(pipes.items[i]);
        i += 1;
    }
}

fn draw_pipe(pipe: Pipe) {
    set_sprite_colors();
    blit_sprite(PIPE_SPRITE, pipe.x, pipe.gap_start - SCREEN, BLIT_FLIP_Y);
    blit_sprite(PIPE_SPRITE, pipe.x, pipe.gap_start + GAP_HEIGHT, 0);
}

fn update_pipes(pipes: Pipes) -> Pipes {
    let mut out = Pipes::empty();
    let mut i = 0;
    while i < pipes.len {
        let mut pipe = pipes.items[i];
        pipe.x -= 1;
        if pipe.x >= -20 {
            out.push(pipe);
        }
        i += 1;
    }
    out
}

fn maybe_generate_pipe(last_generated: u64, frame_count: u64) -> Option<Pipe> {
    if frame_count.wrapping_sub(last_generated) > 90 {
        let gap_start = rand_between(0, 16);
        Some(Pipe { x: SCREEN, gap_start: gap_start * 5 + 10 })
    } else {
        None
    }
}

fn count_passed_pipes(pipes: Pipes) -> u8 {
    let mut count = 0;
    let mut i = 0;
    while i < pipes.len {
        if pipes.items[i].x == PLAYER_X - 2 {
            count += 1;
        }
        i += 1;
    }
    count
}

fn random_plant(x: i32) -> Plant {
    Plant { x, kind: (rand_i32() as u32) % PLANT_TYPES }
}

fn starting_plants() -> Plants {
    let mut plants = Plants::empty();
    let mut i = 0;
    while i <= 14 {
        plants.push(random_plant(i * 12));
        i += 1;
    }
    plants
}

fn update_plants(plants: Plants) -> Plants {
    let mut out = Plants::empty();
    let mut i = 0;
    while i < plants.len {
        let mut plant = plants.items[i];
        plant.x -= 1;
        if plant.x >= -12 {
            out.push(plant);
        }
        i += 1;
    }
    out
}

fn maybe_generate_plant(last_generated: u64, frame_count: u64) -> Option<Plant> {
    if frame_count.wrapping_sub(last_generated) > 12 {
        Some(random_plant(SCREEN))
    } else {
        None
    }
}

fn draw_plants(plants: Plants) {
    let mut i = 0;
    while i < plants.len {
        let plant = plants.items[i];
        let sprite = sub_sprite(PLANT_SPRITE_SHEET, plant.kind * 12, 0, 12, 12);
        set_sprite_colors();
        blit_sprite(sprite, plant.x, PLANT_Y, 0);
        i += 1;
    }
}

fn save_rand_to_disk(frame_count: u64) {
    let high_score = load_high_score_from_disk();
    let data = [(frame_count & 0xff) as u8, high_score];
    unsafe {
        diskw(data.as_ptr(), data.len() as u32);
    }
}

fn load_rand_from_disk() -> u64 {
    let mut data = [0u8; 2];
    let got = unsafe { diskr(data.as_mut_ptr(), data.len() as u32) };
    if got >= 1 { data[0] as u64 } else { 0 }
}

fn save_high_score_to_disk(high_score: u8) {
    let rand = load_rand_from_disk() as u8;
    let data = [rand, high_score];
    unsafe {
        diskw(data.as_ptr(), data.len() as u32);
    }
}

fn load_high_score_from_disk() -> u8 {
    let mut data = [0u8; 2];
    let got = unsafe { diskr(data.as_mut_ptr(), data.len() as u32) };
    if got >= 2 { data[1] } else { 0 }
}

fn update_animation(frame_count: u64, mut anim: Animation) -> Animation {
    let frames_per_update = anim.cells[anim.index].frames;
    if frame_count.wrapping_sub(anim.last_updated) < frames_per_update {
        anim
    } else {
        let next_index = wrapped_inc(anim.index, anim.cells.len());
        anim.last_updated = frame_count;
        match anim.state {
            AnimationState::Completed => anim,
            AnimationState::Loop => {
                anim.index = next_index;
                anim
            }
            AnimationState::RunOnce => {
                if next_index == 0 {
                    anim.state = AnimationState::Completed;
                } else {
                    anim.index = next_index;
                }
                anim
            }
        }
    }
}

fn draw_animation(anim: Animation, x: i32, y: i32, flags: u32) {
    set_sprite_colors();
    blit_sprite(anim.cells[anim.index].sprite, x, y, flags);
}

fn wrapped_inc(value: usize, count: usize) -> usize {
    let next = value + 1;
    if next == count { 0 } else { next }
}

fn idle_shift(frame_count: u64, anim: Animation) -> i32 {
    if anim.index == 2 || (anim.index == 1 && frame_count.wrapping_sub(anim.last_updated) > 3) {
        0
    } else {
        1
    }
}

fn create_rocci_idle_anim(frame_count: u64) -> Animation {
    Animation { last_updated: frame_count, index: 0, state: AnimationState::Loop, cells: &IDLE_CELLS }
}

fn flap_allowed(frame_count: u64, anim: Animation) -> bool {
    if anim.index == 2 {
        true
    } else if anim.index == 1 {
        frame_count.wrapping_sub(anim.last_updated) > 6
    } else {
        false
    }
}

fn create_rocci_flap_anim(frame_count: u64) -> Animation {
    Animation { last_updated: frame_count, index: 2, state: AnimationState::Completed, cells: &FLAP_CELLS }
}

fn create_rocci_fall_anim(frame_count: u64) -> Animation {
    Animation { last_updated: frame_count, index: 0, state: AnimationState::Loop, cells: &FALL_CELLS }
}

fn create_high_score_anim(frame_count: u64) -> Animation {
    Animation { last_updated: frame_count, index: 0, state: AnimationState::Loop, cells: &HIGH_SCORE_CELLS }
}

fn draw_score(score: u8, base_x: i32, y: i32) {
    set_text_colors();
    let x = if score < 10 { base_x + 8 } else if score < 100 { base_x + 4 } else { base_x };
    let mut buf = [0u8; 3];
    let len = if score >= 100 {
        buf[0] = b'0' + score / 100;
        buf[1] = b'0' + (score / 10) % 10;
        buf[2] = b'0' + score % 10;
        3
    } else if score >= 10 {
        buf[0] = b'0' + score / 10;
        buf[1] = b'0' + score % 10;
        2
    } else {
        buf[0] = b'0' + score;
        1
    };
    text(&buf[..len], x, y);
}

fn draw_ground(x: i32) {
    set_ground_colors();
    blit_sprite(GROUND_SPRITE, x, SCREEN - 13, 0);
    blit_sprite(GROUND_SPRITE, x + SCREEN, SCREEN - 13, 0);
}

fn set_palette() {
    unsafe {
        *PALETTE = [0xe6e6c0, 0xb494b7, 0x42436e, 0x26013f];
    }
}

fn set_text_colors() {
    set_draw_colors(COLOR4, COLOR_NONE, COLOR_NONE, COLOR_NONE);
}

fn set_sprite_colors() {
    set_draw_colors(COLOR_NONE, COLOR2, COLOR3, COLOR4);
}

fn set_ground_colors() {
    set_draw_colors(COLOR1, COLOR2, COLOR3, COLOR4);
}

fn set_shape_colors(border: u16, fill: u16) {
    set_draw_colors(fill, border, COLOR_NONE, COLOR_NONE);
}

fn set_draw_colors(primary: u16, secondary: u16, tertiary: u16, quaternary: u16) {
    unsafe {
        *DRAW_COLORS = primary | (secondary << 4) | (tertiary << 8) | (quaternary << 12);
    }
}

fn blit_sprite(sprite: Sprite, x: i32, y: i32, flags: u32) {
    let region = sprite.region;
    blit_sub(
        sprite.data,
        x,
        y,
        region.width,
        region.height,
        region.src_x,
        region.src_y,
        sprite.stride,
        sprite.bpp | flags,
    );
}

fn get_pixel(x: u8, y: u8) -> u8 {
    if x as i32 >= SCREEN || y as i32 >= SCREEN {
        return 0;
    }
    let idx = ((SCREEN as u32 * y as u32 + x as u32) >> 2) as usize;
    let shift = (x & 0x3) << 1;
    let byte = unsafe { (*FRAMEBUFFER)[idx] };
    ((byte >> shift) & 0x3) + 1
}

#[derive(Copy, Clone)]
struct Tone {
    start_freq: u16,
    end_freq: u16,
    channel: u8,
    mode: u8,
    pan: u8,
    attack_time: u8,
    sustain_time: u8,
    decay_time: u8,
    release_time: u8,
    volume: u8,
    peak_volume: u8,
}

const FLAP_TONE: Tone = Tone {
    start_freq: 700,
    end_freq: 870,
    channel: 0,
    mode: 4,
    pan: 0,
    attack_time: 10,
    sustain_time: 0,
    decay_time: 5,
    release_time: 3,
    volume: 10,
    peak_volume: 20,
};

const POINT_TONE: Tone = Tone {
    start_freq: 995,
    end_freq: 1000,
    channel: 1,
    mode: 8,
    pan: 0,
    attack_time: 0,
    sustain_time: 0,
    decay_time: 10,
    release_time: 10,
    volume: 25,
    peak_volume: 75,
};

const DEATH_TONE: Tone = Tone {
    start_freq: 170,
    end_freq: 40,
    channel: 3,
    mode: 0,
    pan: 0,
    attack_time: 0,
    sustain_time: 20,
    decay_time: 40,
    release_time: 0,
    volume: 100,
    peak_volume: 0,
};

fn play_tone(t: Tone) {
    let freq = ((t.end_freq as u32) << 16) | t.start_freq as u32;
    let duration = ((t.attack_time as u32) << 24)
        | ((t.decay_time as u32) << 16)
        | ((t.release_time as u32) << 8)
        | t.sustain_time as u32;
    let volume = ((t.peak_volume as u32) << 8) | t.volume as u32;
    let flags = (t.pan | t.mode | t.channel) as u32;
    tone(freq, duration, volume, flags);
}

fn seed_rand(seed: u64) {
    let seed = seed as u32;
    unsafe {
        PRNG_STATE = if seed == 0 { PRNG_DEFAULT } else { seed };
    }
}

fn next_random_u32() -> u32 {
    unsafe {
        let mut x = PRNG_STATE;
        x ^= x << 13;
        x ^= x >> 17;
        x ^= x << 5;
        PRNG_STATE = if x == 0 { PRNG_DEFAULT } else { x };
        PRNG_STATE
    }
}

fn rand_i32() -> i32 {
    next_random_u32() as i32
}

fn rand_between(start: i32, before: i32) -> i32 {
    if start >= before {
        return start;
    }
    let span = (before - start) as u32;
    start + (next_random_u32() % span) as i32
}
