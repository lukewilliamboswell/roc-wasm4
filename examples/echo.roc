app "minimal"
    packages {
        w4: "../platform/main.roc",
    }
    imports [
        w4.Task.{Task}
    ]
    provides [main, Model] to w4

Program : {
    init : Task Model [],
    update : Model -> Task Model [],
}

Model : {}

main : Program
main = {init,update}

init : Task Model []
init = Task.ok {}

update : Model -> Task Model []
update = \model ->
    Task.ok model