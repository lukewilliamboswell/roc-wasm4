#!/usr/bin/env roc-stable
app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst",
	roc: "nightly-2026-10-09-258ab27",
}

import cli.Cmd
import cli.Env
import cli.OsStr
import cli.Path
import cli.Stderr
import cli.Stdout
import src/Examples

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
	replacement = Examples.replacement(args)?
	entries = Path.list!(Path.utf8("examples")).map_err(|_| "cannot list examples")?
	var $apps = []
	for entry in entries {
		example = Path.join(entry, "main.roc")
		if Path.is_file!(example) ?? Bool.False {
			$apps = $apps.append(example)
		}
	}
	if $apps.is_empty() {
		return Err("no examples found")
	}
	Env.with_temp_dir!(
		|scratch| {
			var $count = 0.U64
			for example in $apps {
				source = Path.read_utf8!(example).map_err(|_| "cannot read example")?
				if !Examples.local_header(source) {
					return Err("${Path.display(example)} must use the working-tree platform")
				}
				$count = $count + 1
				Stdout.line!("[${$count.to_str()}/${$apps.len().to_str()}] ${Path.display(example)} (build only; WASM-4 runtime required)").map_err(|_| "cannot print progress")?
				output = Path.display(Path.join(scratch, "cart-${$count.to_str()}.wasm"))
				for arguments in [["check", Path.display(example)], ["build", Path.display(example), "--target=wasm32", "--output=${output}"]] {
					match Cmd.new_str("roc").args_str(arguments.concat(replacement)).env("ROC_CACHE_DIR", Path.to_os_str(Path.join(scratch, "cache"))).exec_exit_code!() {
						Ok(0) => {}
						_ => return Err("example command failed: ${Path.display(example)}")
					}
				}
				size = Path.size_in_bytes!(Path.utf8(output)).map_err(|_| "cart was not produced")?
				if size == 0 {
					return Err("empty cart")
				}
			}
			Stdout.line!("PASS ${$count.to_str()} carts checked and built; runtime execution not tested").map_err(|_| "cannot print summary")
		},
	).map_err(|_| "example validation failed")
}
