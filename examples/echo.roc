app "echo"
    packages {
        pf: "../platform/main.roc",
    }
    imports []
    provides [main] to pf

main : Str -> Str
main = \s -> 
    text =
        if s == "MARCO" then
            "POLO"
        else
            s
    "This is a string\nthat definitely will\nbe long enough to\nforce an allocation\nalso \(text)"

