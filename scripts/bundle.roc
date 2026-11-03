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
	destination = Path.absolute!(Path.utf8(output)).map_err(|_| "cannot resolve bundle destination")?
	Env.with_temp_dir!(
		|staging| {
			var $members = []
			for source in modules {
				name = source.split_on("/").last() ?? ""
				Path.copy!(Path.utf8(source), Path.join(staging, name)).map_err(|_| "cannot stage platform module")?
				$members = $members.append(name)
			}
			Path.create_all!(Path.join(staging, "targets/wasm32")).map_err(|_| "cannot stage target")?
			Path.copy!(Path.utf8("platform/targets/wasm32/host.wasm"), Path.join(staging, "targets/wasm32/host.wasm")).map_err(|_| "cannot stage host")?
			Path.create_all!(Path.join(staging, "licenses")).map_err(|_| "cannot stage licenses")?
			Path.copy!(Path.utf8("LICENSE.md"), Path.join(staging, "licenses/roc-wasm4-UPL.txt")).map_err(|_| "cannot stage platform license")?
			$members = $members.concat(["targets/wasm32/host.wasm", "licenses/roc-wasm4-UPL.txt"])
			for license in ["wasm4-ISC.txt", "umm_malloc-MIT.txt"] {
				Path.copy!(Path.utf8("licenses/${license}"), Path.join(staging, "licenses/${license}")).map_err(|_| "cannot stage upstream license")?
				$members = $members.append("licenses/${license}")
			}
			code = Cmd.new_str("roc").args_str(["bundle"].concat($members).concat(["--output-dir", Path.display(destination)])).cwd(staging).exec_exit_code!().map_err(|_| "cannot start bundler")?
			if code == 0 Ok({}) else Err("platform bundling failed")
		},
	).map_err(|_| "cannot build licensed platform bundle")
}
