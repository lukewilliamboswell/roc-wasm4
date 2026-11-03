#!/usr/bin/env roc-stable
app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst",
	roc: "nightly-2026-10-09-258ab27",
}

import cli.Cmd
import cli.Env
import cli.Path
import cli.Stderr
import src/Process

main! = |_args| {
	match run!() {
		Ok({}) => Ok({})
		Err(message) => {
			Stderr.line!(message)?
			Err(Exit(1))
		}
	}
}

run! = || {
	entries = Path.list!(Path.utf8("dist")).map_err(|_| "missing candidate directory")?
	bundle = match entries.keep_if(|path| Path.display(path).ends_with(".tar.zst")) {
		[file] => Path.filename(file).map_ok(Path.display).map_err(|_| "invalid candidate filename")?
		_ => return Err("expected one candidate bundle")
	}
	# Python supplies only a platform HTTP adapter. Roc owns admission, bounded
	# readiness, compiler invocation and unconditional child cleanup.
	server = Cmd.new_str("python3").args_str(["-m", "http.server", "8000", "--bind", "127.0.0.1", "--directory", "dist"]).stdout(Null).stderr(Inherit).manage_tree(Bool.True).spawn!().map_err(|_| "cannot start loopback adapter")?
	url = "http://127.0.0.1:8000/${bundle}"
	result = Env.with_temp_dir!(
		|temporary| {
			Process.run!("curl", ["--fail", "--silent", "--show-error", "--retry", "10", "--retry-connrefused", "--retry-delay", "1", "--max-time", "15", url, "--output", Path.display(Path.join(temporary, "probe.tar.zst"))])?
			code = Cmd.new_str("roc-stable").args_str(["scripts/distribution.roc", "--", "--build-only", "--bundle-url", url]).env("ROC_CACHE_DIR", Path.to_os_str(Path.join(temporary, "cache"))).exec_exit_code!().map_err(|_| "cannot run isolated candidate build")?
			if code == 0 Ok({}) else Err("isolated candidate build failed")
		},
	).map_err(|_| "candidate cross-build failed")
	closed = server.close!().map_err(|_| "cannot close loopback adapter")
	result?
	closed
}
