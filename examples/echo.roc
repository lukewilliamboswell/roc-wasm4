app "echo"
    packages {
        pf: "../platform/main.roc",
    }
    imports []
    provides [main] to pf

main : Str -> Str
main = \s -> 
    if s == "MARCO" then
        "POLO"
    else
        s

