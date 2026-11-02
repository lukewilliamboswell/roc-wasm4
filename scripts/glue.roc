#!/usr/bin/env roc-stable
app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst",
	roc: "nightly-2026-10-09-258ab27",
}

import cli.Env
import cli.OsStr
import cli.Path
import cli.Stderr
import src/Process

main! = |args| {
	result = match args.map(OsStr.display) {
		[] => generate!(Bool.False)
		["--update"] => generate!(Bool.True)
		_ => Err("usage: blueprint run glue [-- --update]")
	}
	match result {
		Ok({}) => Ok({})
		Err(message) => {
			Stderr.line!(message)?
			Err(Exit(1))
		}
	}
}

# Fetch the source for the installed official nightly, admit its release digest,
# and regenerate the binding without rebuilding or mutating the host.
generate! = |update| {
	version = Process.capture!("roc", ["version"])?
	prefix = "Roc compiler version nightly-"
	if !version.starts_with(prefix) {
		return Err("glue requires an official Roc nightly")
	}
	suffix = version.drop_prefix(prefix)
	if !suffix.to_utf8().all(|byte| (byte >= 48 and byte <= 57) or (byte >= 97 and byte <= 102) or byte == 45) {
		return Err("unexpected nightly identity")
	}
	tag = "nightly-${suffix}"
	asset = "roc_nightly-source-${suffix}.tar.gz"
	digest = Process.capture!("gh", ["api", "repos/roc-lang/nightlies/releases/tags/${tag}", "--jq", ".assets[] | select(.name == \"${asset}\") | .digest"])?
	expected = digest.drop_prefix("sha256:")
	if expected.count_utf8_bytes() != 64 or !expected.to_utf8().all(|byte| (byte >= 48 and byte <= 57) or (byte >= 97 and byte <= 102)) {
		return Err("nightly source asset has no valid SHA-256 digest")
	}
	Env.with_temp_dir!(
		|scratch| {
			directory = Path.display(scratch)
			archive = Path.display(Path.join(scratch, asset))
			Process.run!("gh", ["release", "download", tag, "--repo", "roc-lang/nightlies", "--pattern", asset, "--dir", directory])?
			actual = Process.capture!("sha256sum", [archive])?
			if !(actual.starts_with("${expected} ")) {
				return Err("nightly source digest mismatch")
			}
			Process.run!("tar", ["-xzf", archive, "-C", directory, "--strip-components=1", "${asset.drop_suffix(".tar.gz")}/src/glue"])?
			generated = Path.join(scratch, "generated")
			Path.create_all!(generated).map_err(|_| "cannot create glue output")?
			Process.run!("roc", ["glue", "${directory}/src/glue/src/ZigGlue.roc", Path.display(generated), "platform/main.roc"])?
			binding = Path.join(generated, "roc_platform_abi.zig")
			# Normalize only the final newline, which varies across glue versions.
			text = Path.read_utf8!(binding).map_err(|_| "cannot read generated glue")?
			normalized = "${text.trim_end()}\n"
			Path.write_utf8!(binding, normalized).map_err(|_| "cannot normalize generated glue")?
			if update {
				bytes = Path.read_bytes!(binding).map_err(|_| "cannot read generated glue")?
				Path.write_bytes!(Path.utf8("src/roc_platform_abi.zig"), bytes).map_err(|_| "cannot update committed glue")
			} else {
				Process.run!("git", ["diff", "--no-index", "--exit-code", "src/roc_platform_abi.zig", Path.display(binding)])
			}
		},
	).map_err(|_| "host ABI differs or generation failed; run blueprint run glue -- --update and review")
}
