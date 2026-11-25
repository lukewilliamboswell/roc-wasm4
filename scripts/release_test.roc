#!/usr/bin/env roc-stable
app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.1/7brgwR8YUqfeGrkdfF1V4GPPN7DnP7ftqub9KcrTEZtr.tar.zst",
	roc: "nightly-2026-11-25-d5a4f1e",
}

import cli.OsStr
import cli.Stderr
import src/Process

main! = |args| {
	result = run!(args.map(OsStr.display))
	match result {
		Ok({}) => Ok({})
		Err(message) => {
			Stderr.line!(message)?
			Err(Exit(1))
		}
	}
}

run! = |args| {
	Process.run!("node", ["examples/support/run-cart.mjs", "--export-tools"])?
	Process.run!("release-package", args)
}
