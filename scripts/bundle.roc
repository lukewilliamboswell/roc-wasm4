#!/usr/bin/env roc-stable
app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst",
	roc: "nightly-2026-10-09-258ab27",
}

import cli.OsStr
import cli.Path
import cli.Stderr
import src/Process

main! = |args| {
	result = bundle!(args.map(OsStr.display))
	match result {
		Ok({}) => Ok({})
		Err(message) => {
			Stderr.line!(message)?
			Err(Exit(1))
		}
	}
}

bundle! = |args| {
	output = match args {
		[] => "."
		["--output-dir", directory] => directory
		_ => return Err("usage: blueprint run bundle [-- --output-dir DIR]")
	}
	Path.create_all!(Path.utf8(output)).map_err(|_| "cannot create bundle output")?
	files = Path.list!(Path.utf8("platform")).map_err(|_| "cannot list platform")?
	modules = files.map(Path.display).keep_if(|path| path.ends_with(".roc"))
	if !(Path.exists!(Path.utf8("platform/targets/wasm32/host.wasm")).map_err(|_| "cannot inspect host")?) {
		return Err("Run blueprint run build-host before bundling")
	}
	Process.run!("roc", ["bundle"].concat(modules).concat(["platform/targets/wasm32/host.wasm", "--output-dir", output]))
}
