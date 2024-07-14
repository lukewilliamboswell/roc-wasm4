#!/usr/bin/env bash

## This script is used to re-generate the glue type for Roc. For now this is limited to the std library.

# https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/
set -euxo pipefail

# remove previous generated code
rm -rf platform/roc/

# regenerate builtins
roc glue glue.roc platform/ platform/main-glue.roc
