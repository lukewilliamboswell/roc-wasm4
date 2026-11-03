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
import src/Process

main! = |_args| {
	match fingerprint!() {
		Ok(value) => match Env.var_str!(OsStr.from_str("GITHUB_OUTPUT")) {
			Ok(path) => {
				previous = Path.read_utf8!(Path.utf8(path))?
				Path.write_utf8!(Path.utf8(path), "${previous}fingerprint=${value}\n")
			}
			Err(_) => Stdout.line!(value)
		}
		Err(message) => {
			Stderr.line!(message)?
			Err(Exit(1))
		}
	}
}

fingerprint! = || {
	report = Process.capture!("blueprint", ["lock", "show", "--json"])?
	parsed : Try({ fetched : List({ name : Str, system : Str, sha256 : Str }) }, _)
	parsed = Json.parse(report)
	pins = parsed.map_err(|_| "cannot decode locked host toolchain")?
	zig = match pins.fetched.keep_if(|pin| pin.name == "zig" and pin.system == "x86_64-linux") {
		[pin] => pin.sha256
		_ => return Err("expected one locked Linux Zig toolchain")
	}
	files = Process.capture!("git", ["ls-files", "-z", "src", "build.zig", "build.zig.zon"])?
	hashes = Process.capture!("sha256sum", files.split_on("\u(0)").keep_if(|path| path != ""))?
	# Source and exact tool bytes, target and every fixed build option. Tooling,
	# manual and example changes do not invalidate this fingerprint.
	material = "${hashes}\nzig=${zig}\nwasm32-freestanding-none ReleaseSmall mem-size=32768 zero-on-alloc=false trace-allocs=false\n"
	ran = Cmd.new_str("sha256sum").stdin(Bytes(material.to_utf8())).run!().map_err(|_| "cannot hash host inputs")?
	match ran.status {
		Exited(0) => Ok(Str.from_utf8_lossy(ran.stdout_bytes).split_on(" ").first() ?? "")
		_ => Err("host fingerprint failed")
	}
}
