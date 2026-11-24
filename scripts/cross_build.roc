#!/usr/bin/env roc-stable
app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.1/7brgwR8YUqfeGrkdfF1V4GPPN7DnP7ftqub9KcrTEZtr.tar.zst",
	roc: "nightly-2026-11-23-b5c77fc",
}

import cli.Cmd
import cli.Env
import cli.OsStr
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
	server = Cmd.new("python3").args(["-m", "http.server", "8000", "--bind", "127.0.0.1", "--directory", "dist"]).stdout(Null).stderr(Inherit).manage_tree(Bool.True).spawn!().map_err(|_| "cannot start loopback adapter")?
	url = "http://127.0.0.1:8000/${bundle}"
	result = Env.with_temp_dir!(
		|temporary| {
			Process.run!("curl", ["--fail", "--silent", "--show-error", "--retry", "10", "--retry-connrefused", "--retry-delay", "1", "--max-time", "15", url, "--output", Path.display(Path.join(temporary, "probe.tar.zst"))])?
			output = Cmd.new("roc-stable").args(["scripts/distribution.roc", "--", "--build-only", "--bundle-url", OsStr.from_str(url)]).env("ROC_CACHE_DIR", Path.to_os_str(Path.join(temporary, "cache"))).inherit_stdio().run!().map_err(|_| "cannot run isolated candidate build")?
			if (output.status == Exited(0)) Ok({}) else Err("isolated candidate build failed")
		},
	).map_err(|_| "candidate cross-build failed")
	closed = server.close!().map_err(|_| "cannot close loopback adapter")
	result?
	closed
}
