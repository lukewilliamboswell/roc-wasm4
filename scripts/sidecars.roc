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
import src/Process
import src/Release

Sidecar : { name : Str, path : Str, size : U64, sha256 : Str, format : Str }

Subject : { name : Str, path : Str, size : U64, sha256 : Str, target : Str, version : Str, url : Str, inventory_sha256 : Str, sidecars : List(Sidecar) }

Envelope : {
	format : Str,
	source : { server : Str, repository : Str, commit : Str },
	producer : { workflow : Str, run_id : Str, run_attempt : Str },
	generator : { tool : Str, tool_sha256 : Str, compiler : Str, generator : Str, blueprint : Str, created : Str },
	subjects : List(Subject),
	dependencies : List({ component : Str, origin : Str, state : Str, detail : Str }),
	coverage : List({ scope : Str, status : Str, detail : Str }),
}

main! = |args| {
	result = match args.map(OsStr.display) {
		["--suppliers"] => suppliers!()
		[version] if Release.valid_version(version) => generate!(version)
		_ => Err("usage: blueprint run sbom-sidecars -- VERSION | blueprint run sbom-suppliers")
	}
	match result {
		Ok({}) => Ok({})
		Err(message) => {
			Stderr.line!(message)?
			Err(Exit(1))
		}
	}
}

optional! = |name, fallback| Ok(Env.var_str!(OsStr.from_str(name)) ?? fallback)

adapter! = || {
	paths = Env.var_str!(OsStr.from_str("PATH")).map_err(|_| "missing adapter PATH")?
	for directory in paths.split_on(":") {
		candidate = "${directory}/automation-sbom-sidecars"
		if Path.exists!(Path.utf8(candidate)) ?? Bool.False {
			return Process.capture!("realpath", [candidate])
		}
	}
	Err("locked shared SBOM adapter is missing")
}

run! = |script, entries| {
	var $command = Cmd.new_str("python3").args_str([script]).env("PYTHONDONTWRITEBYTECODE", "1")
	for (name, value) in entries {
		$command = $command.env(OsStr.from_str(name), OsStr.from_str(value))
	}
	code = $command.exec_exit_code!().map_err(|_| "shared SBOM adapter did not complete")?
	if code == 0 Ok({}) else Err("shared SBOM adapter rejected the candidate")
}

common! = || {
	workspace = Path.absolute!(Path.utf8(".")).map_ok(Path.display).map_err(|_| "cannot resolve workspace")?
	temporary = "${workspace}/.zig-cache/sbom-runtime"
	Path.create_all!(Path.utf8(temporary)).map_err(|_| "cannot create SBOM scratch")?
	Ok([
		("GITHUB_WORKSPACE", workspace),
		("GITHUB_SERVER_URL", optional!("GITHUB_SERVER_URL", "https://github.com")?),
		("GITHUB_REPOSITORY", optional!("GITHUB_REPOSITORY", "lukewilliamboswell/roc-wasm4")?),
		("RUNNER_TEMP", temporary),
		("RUNNER_OS", "Linux"),
		("RUNNER_ARCH", "X64"),
		("INPUT_TARGET", "source"),
	])
}

suppliers! = || {
	script = (adapter!()?).drop_suffix("/sbom-sidecars/sbom_sidecars.py")
	output = ".zig-cache/sbom-suppliers.outputs"
	Path.create_all!(Path.utf8(".zig-cache")).map_err(|_| "cannot create supplier scratch")?
	Path.write_utf8!(Path.utf8(output), "").map_err(|_| "cannot prepare supplier outputs")?
	run!(
		"${script}/fetch-dependency-sboms/fetch_dependency_sboms.py",
		(common!()?).concat([
			("GITHUB_OUTPUT", output),
			("INPUT_COMPOSITION", "sbom/base.json"),
			("INPUT_OUTPUT", "sbom/imports.json"),
		]),
	)
}

value! = |output, key| {
	text = Path.read_utf8!(Path.utf8(output)).map_err(|_| "cannot read shared adapter outputs")?
	match text.split_on("\n").keep_if(|line| line.starts_with("${key}=")) {
		[line] => Ok(line.drop_prefix("${key}="))
		_ => Err("shared adapter did not return one ${key}")
	}
}

read_envelope! = |file| {
	text = Path.read_utf8!(Path.utf8(file)).map_err(|_| "cannot read SBOM transfer envelope")?
	decoded : Try(Envelope, _)
	decoded = Json.parse(text)
	decoded.map_err(|_| "unsupported SBOM transfer envelope")
}

generate! = |version| {
	Process.run!("blueprint", ["run", "sbom", "--", version])?
	script = adapter!()?
	files = Path.list!(Path.utf8("dist")).map_err(|_| "cannot list release candidates")?
	bundle = match files.map(Path.display).keep_if(|file| file.ends_with(".tar.zst")) {
		[file] => file
		_ => return Err("expected one platform bundle")
	}
	identity = (common!()?).concat([
		("GITHUB_WORKFLOW_REF", optional!("GITHUB_WORKFLOW_REF", "lukewilliamboswell/roc-wasm4/.github/workflows/release.yml@refs/heads/migration/end-to-end")?),
		("GITHUB_RUN_ID", optional!("GITHUB_RUN_ID", "1")?),
		("GITHUB_RUN_ATTEMPT", optional!("GITHUB_RUN_ATTEMPT", "1")?),
		("INPUT_VERSION", version),
		("INPUT_AUTHOR", "Person: Luke Boswell"),
		("INPUT_SPDX_2_3", "true"),
	])
	for (kind, file) in [("bundle", bundle), ("examples", "dist/roc-wasm4-examples-${version}.zip"), ("api", "dist/roc-wasm4-docs-${version}.zip"), ("manual", "dist/roc-wasm4-manual-${version}.pdf")] {
		output = ".zig-cache/sbom-${kind}.outputs"
		Path.write_utf8!(Path.utf8(output), "").map_err(|_| "cannot prepare SBOM outputs")?
		run!(
			script,
			identity.concat([
				("GITHUB_OUTPUT", output),
				("INPUT_FILES", file),
				("INPUT_COMPOSITION", "dist/sbom/composition-${kind}.json"),
				("INPUT_IMPORTS", "sbom/imports.json"),
			]),
		)?
		Path.copy!(Path.utf8(value!(output, "inventory")?), Path.utf8("${file}.inventory.json")).map_err(|_| "cannot retain per-subject inventory")?
		Path.copy!(Path.utf8(value!(output, "evidence")?), Path.utf8("dist/sbom/evidence-${kind}.json")).map_err(|_| "cannot retain SBOM transfer evidence")?
	}
	first = read_envelope!("dist/sbom/evidence-bundle.json")?
	var $all = first
	for kind in ["examples", "api", "manual"] {
		next = read_envelope!("dist/sbom/evidence-${kind}.json")?
		if next.source != first.source or next.producer != first.producer or next.generator != first.generator or next.dependencies != first.dependencies {
			return Err("SBOM groups disagree on producer, tool or locked dependencies")
		}
		$all = { ..$all, subjects: $all.subjects.concat(next.subjects), coverage: $all.coverage.concat(next.coverage.map(|entry| { ..entry, scope: "${kind}:${entry.scope}" })) }
	}
	Path.write_utf8!(Path.utf8("dist/sbom-evidence.json"), Json.to_str($all)).map_err(|_| "cannot write combined transfer evidence")?
	var $assets = []
	for subject in $all.subjects {
		$assets = $assets.concat([subject.path, "${subject.path}.inventory.json"]).concat(subject.sidecars.map(|sidecar| sidecar.path))
	}
	subjects = $all.subjects.map(|subject| subject.path)
	output = Env.var_str!(OsStr.from_str("GITHUB_OUTPUT")) ?? ""
	if output != "" {
		previous = Path.read_utf8!(Path.utf8(output)) ?? ""
		Path.write_utf8!(Path.utf8(output), "${previous}assets<<WASM4_ASSETS\n${Str.join_with($assets, "\n")}\nWASM4_ASSETS\nsubjects<<WASM4_SUBJECTS\n${Str.join_with(subjects, "\n")}\nWASM4_SUBJECTS\n").map_err(|_| "cannot export exact release paths")?
	}
	Ok({})
}
