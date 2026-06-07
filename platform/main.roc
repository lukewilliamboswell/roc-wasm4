platform ""
    requires { [Model : model] for main : { init! : () => model, update! : model => model } }
    exposes [W4, Sprite, Host]
    packages {}
    provides { init_for_host! : "init_for_host", update_for_host! : "update_for_host" }
    targets: {
        files: "targets/",
        static_lib: {
            wasm32: ["libhost.a", app],
        }
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
