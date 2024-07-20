platform "glue"
    requires {} { main : _ }
    exposes []
    packages {}
    imports []
    provides [glueTypes]

# for now, zig glue doesn't generate types for our platform, but it is used to
# generate the roc_std library files list.zig, utils.zig, str.zig etc
glueTypes : {}
glueTypes = main
