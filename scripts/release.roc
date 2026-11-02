#!/usr/bin/env roc-stable
app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst",
	roc: "nightly-2026-10-09-258ab27",
}

import cli.Env
import cli.OsStr
import cli.Path
import cli.Stderr
import cli.Stdout
import src/Process
import src/Release

main! = |args| {
	result = match args.map(OsStr.display) {
		["validate", version] => validate!(version)
		["prepare", version] => prepare!(version)
		_ => Err("usage: blueprint run release -- validate|prepare VERSION")
	}
	match result {
		Ok({}) => Ok({})
		Err(message) => {
			Stderr.line!(message)?
			Err(Exit(1))
		}
	}
}

env! = |name| Env.var_str!(OsStr.from_str(name)).map_err(|_| "missing ${name}")

# Admission has no write authority. The publisher separately rejects existing
# tags, uploads to a draft and compares every downloaded asset before publishing.
validate! = |version| {
	if !Release.valid_version(version) {
		return Err("release_tag must be a three-part SemVer")
	}
	repository = env!("GITHUB_REPOSITORY")?
	default_branch = Process.capture!("gh", ["api", "repos/${repository}", "--jq", ".default_branch"])?
	if env!("GITHUB_REF")? != "refs/heads/${default_branch}" {
		return Err("publish from the default branch")
	}
	sha = Process.capture!("git", ["rev-parse", "HEAD"])?
	tip = Process.capture!("gh", ["api", "repos/${repository}/git/ref/heads/${default_branch}", "--jq", ".object.sha"])?
	if sha != tip {
		return Err("publication must test the current default-branch commit")
	}
	refs = Process.capture!("gh", ["api", "--paginate", "repos/${repository}/git/matching-refs/tags/${version}", "--jq", ".[].ref"])?
	if refs.split_on("\n").contains("refs/tags/${version}") {
		return Err("release tag already exists")
	}
	_ = Path.read_utf8!(Path.utf8("docs/releases/${version}.adoc")).map_err(|_| "author docs/releases/${version}.adoc before publication")?
	output!("sha=${sha}\nprerelease=${if version.contains("-") "true" else "false"}\n")
}

prepare! = |version| {
	if !Release.valid_version(version) or version == "0.0.0" or version.starts_with("0.0.0-") {
		return Err("release version must be nonzero SemVer")
	}
	Process.run!("release-package", ["check-version", version])?
	Env.with_temp_dir!(
		|temporary| {
			Process.run!("roc-stable", ["scripts/bundle.roc", "--", "--output-dir", Path.display(temporary)])?
			Process.run!("release-package", ["build", version, "--platform-bundle", Path.display(temporary)])
		},
	).map_err(|_| "release packaging failed")?
	files = Path.list!(Path.utf8("dist")).map_err(|_| "cannot list dist")?
	archive = match files.map(Path.display).keep_if(|path| path.ends_with(".tar.zst")) {
		[path] => path
		_ => return Err("expected one platform archive in dist")
	}
	name = archive.split_on("/").last() ?? ""
	Process.run!("blueprint", ["run", "docs", "--", version, name])?
	Path.copy!(Path.utf8(".docs-out/roc-wasm4.pdf"), Path.utf8("dist/roc-wasm4-manual-${version}.pdf")).map_err(|_| "cannot stage release manual")?
	notes = Path.read_utf8!(Path.utf8("dist/release-notes.md")).map_err(|_| "cannot read rendered release notes")?
	tooling = Process.capture!("roc-stable", ["version"])?
	Path.write_utf8!(Path.utf8("dist/release-notes.md"), "${notes}\n- Automation compiler: ${tooling}\n").map_err(|_| "cannot record tooling compiler")?
	output!("bundle_name=${name}\nbundle_path=${archive}\n")
}

output! = |text| match Env.var_str!(OsStr.from_str("GITHUB_OUTPUT")) {
	Ok(path) => {
		previous = Path.read_utf8!(Path.utf8(path)).map_err(|_| "cannot read GITHUB_OUTPUT")?
		Path.write_utf8!(Path.utf8(path), "${previous}${text}").map_err(|_| "cannot write GITHUB_OUTPUT")
	}
	Err(_) => Stdout.write!(text).map_err(|_| "cannot print outputs")
}
