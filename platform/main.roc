platform ""
    requires { [Model : model] for main : { init! : () => model, update! : model => model } }
    exposes [W4, Sprite, Host]
    packages {}
    provides { init_for_host! : "init_for_host", update_for_host! : "update_for_host" }
    targets: {
        inputs: "targets/",
        wasm32: {
            inputs: ["host.wasm", app],
            output: Shared,
            import_memory: True,
            minimum_memory: 65536,
            maximum_memory: 65536,
            initial_stack_size: 14752,
            global_base: 6592,
        },
    }

import W4
import Sprite
import Host

init_for_host! : () => Box(Model)
init_for_host! = || {
    init_fn! = main.init!
    Box.box(init_fn!())
}

update_for_host! : Box(Model) => Box(Model)
update_for_host! = |boxed| {
    update_fn! = main.update!
    Box.box(update_fn!(Box.unbox(boxed)))
}
