#!/usr/bin/env roc-stable
app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst",
	roc: "nightly-2026-10-09-258ab27",
}

import cli.Path
import cli.OsStr
import cli.Stderr
import src/Process

main! = |args| {
	match check!(args.map(OsStr.display)) {
		Ok({}) => Ok({})
		Err(message) => {
			Stderr.line!(message)?
			Err(Exit(1))
		}
	}
}

check! = |args| {
	prebuilt = match args {
		[] => Bool.False
		["--prebuilt-host"] => Bool.True
		_ => return Err("usage: blueprint run check [-- --prebuilt-host]")
	}
	declaration = Path.read_utf8!(Path.utf8("Blueprint.roc")).map_err(|_| "cannot read tool declaration")?
	version = match declaration.split_on("zig_version = \"") {
		[_, rest] => rest.split_on("\"").first() ?? ""
		_ => return Err("expected one Zig version declaration")
	}
	minimum = Path.read_utf8!(Path.utf8("build.zig.zon")).map_err(|_| "cannot read Zig build minimum")?
	if version == "" or !minimum.contains(".minimum_zig_version = \"${version}\"") {
		return Err("build.zig.zon minimum must equal Blueprint's Zig version")
	}
	for path in [".roc-version", ".github/roc-nightly.json"] {
		if Path.exists!(Path.utf8(path)).map_err(|_| "cannot inspect ${path}")? {
			return Err("remove obsolete compiler pin ${path}")
		}
	}
	for definition in ["repository_policy", "script_policy", "example_policy"] {
		Process.run!("blueprint", ["run", "policy", "--", "--definition", definition])?
	}
	Process.run!("roc", ["version"])?
	Process.run!("roc", ["fmt", "--check", "platform", "examples", "benchmarks"])?
	if !prebuilt {
		Process.run!("zig", ["version"])?
	}
	Process.run!("roc-stable", ["test", "scripts/src/Release.roc"])?
	Process.run!("roc-stable", ["test", "scripts/src/Examples.roc"])?
	for file in ["bundle", "check_all", "release", "release_test", "glue", "docs", "distribution", "cross_build", "host_fingerprint", "sbom", "sidecars"] {
		Process.run!("roc-stable", ["check", "scripts/${file}.roc"])?
	}
	Process.run!("roc-stable", ["fmt", "--check", "scripts", "Blueprint.roc"])?
	if prebuilt {
		if !(Path.is_file!(Path.utf8("platform/targets/wasm32/host.wasm")) ?? Bool.False) {
			return Err("prebuilt host is missing")
		}
	} else {
		Process.run!("zig", ["build", "-Doptimize=ReleaseSmall"])?
		Process.run!("zig", ["build", "test"])?
	}
	Process.run!("blueprint", ["run", "release-test", "--", "test-examples"])?
	Process.run!("blueprint", ["run", "distribution"])?
	files = Path.list!(Path.utf8("platform")).map_err(|_| "cannot list platform")?
	for file in files {
		name = Path.display(file)
		if name.ends_with(".roc") {
			Process.run!("roc", ["check", name])?
		}
	}
	Process.run!("roc", ["test", "platform/main.roc"])?
	Process.run!("roc", ["check", "benchmarks/rocci-bird-trace/main.roc"])
}
