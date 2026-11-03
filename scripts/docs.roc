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
	result = match args.map(OsStr.display) {
		[] => build!("unreleased", "")
		[version, bundle] => build!(version, bundle)
		_ => Err("usage: blueprint run docs [-- VERSION BUNDLE_NAME]")
	}
	match result {
		Ok({}) => Ok({})
		Err(message) => {
			Stderr.line!(message)?
			Err(Exit(1))
		}
	}
}

build! = |version, bundle| {
	staging = ".zig-cache/docs-input"
	if Path.exists!(Path.utf8(staging)).map_err(|_| "cannot inspect documentation input")? {
		Path.delete_all!(Path.utf8(staging)).map_err(|_| "cannot clear generated documentation input")?
	}
	Path.create_all!(Path.utf8(staging)).map_err(|_| "cannot create documentation input")?
	url = if version == "unreleased" "https://github.com/lukewilliamboswell/roc-wasm4/releases/latest" else "https://github.com/lukewilliamboswell/roc-wasm4/releases/download/${version}/${bundle}"
	copy!("docs", staging, url)?
	release = if version == "unreleased" {
		"= Development preview\n\nThis preview describes the working tree. Choose a https://github.com/lukewilliamboswell/roc-wasm4/releases[published release] for an immutable platform and its matching examples.\n"
	} else {
		base = "https://github.com/lukewilliamboswell/roc-wasm4/releases/download/${version}"
		"= Release ${version}\n\nUse this release's link:${base}/${bundle}[platform bundle] and link:${base}/roc-wasm4-examples-${version}.zip[examples archive]. The link:${base}/roc-wasm4-docs-${version}.zip[API archive] restores this release's reference. Download the link:${base}/roc-wasm4-manual-${version}.pdf[PDF manual]. Each asset has checked SPDX and CycloneDX sidecars beside it.\n"
	}
	Path.write_utf8!(Path.utf8("${staging}/release.adoc"), release).map_err(|_| "cannot write release links")?
	Process.run!("roc-docs", ["build", "--workspace", ".", "--docs-directory", staging, "--pdf-filename", "roc-wasm4.pdf", "--site-url", "https://lukewilliamboswell.github.io/roc-wasm4/", "--docs-version", version, "--api-entrypoint", "platform/main.roc"])
}

copy! = |from, to, url| {
	Path.create_all!(Path.utf8(to)).map_err(|_| "cannot create ${to}")?
	entries = Path.list!(Path.utf8(from)).map_err(|_| "cannot list ${from}")?
	for entry in entries {
		name = Path.filename(entry).map_ok(Path.display).map_err(|_| "invalid documentation name")?
		destination = "${to}/${name}"
		match Path.type!(entry).map_err(|_| "cannot inspect documentation input")? {
			IsDir => copy!(Path.display(entry), destination, url)?
			IsFile if name.ends_with(".adoc") => {
				text = Path.read_utf8!(entry).map_err(|_| "cannot read manual source")?
				Path.write_utf8!(Path.utf8(destination), text.replace_each("{package-url}", url).replace_each("{platform-url}", url)).map_err(|_| "cannot prepare release documentation")?
			}
			IsFile => Path.copy!(entry, Path.utf8(destination)).map_err(|_| "cannot copy documentation input")?
			_ => return Err("documentation inputs must be regular files")
		}
	}
	Ok({})
}
