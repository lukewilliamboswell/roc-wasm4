# Tools run on a fixed compiler; the platform uses the nightly roc on PATH.
app [config] { pf: platform "https://github.com/lukewilliamboswell/roc-blueprint/releases/download/0.11.0/EuSPs8vc71qJNFg29YzegvVRL1bR9pKqUYDHFiSCPTQ1.tar.zst" }

import pf.Recipes

config = [
	Name("roc-wasm4"),
	Systems(["x86_64-linux", "aarch64-linux", "aarch64-darwin", "x86_64-darwin", "x86_64-windows"]),
	Environment(
		"scripts",
		[
			Programs([Fetch("roc-stable", Recipes.roc_nightly(tooling.compiler))]),
			# Every bundle the scripts depend on, including dependencies of
			# dependencies: `roc-stable deps scripts/check_all.roc` lists them.
			RocPackages([
				"https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst",
			]),
			Expect(["git"]),
		],
	),
	Environment(
		"dev",
		[
			Extend("scripts"),
			# The exact Zig release that builds the host; build.zig.zon and
			# runtime/sources.json name the same version.
			Programs([
				Fetch(
					"zig",
					|system| match system {
						"x86_64-linux" => Archive("https://ziglang.org/download/0.16.0/zig-x86_64-linux-0.16.0.tar.xz", TarXz, "zig-x86_64-linux-0.16.0/zig")
						"aarch64-linux" => Archive("https://ziglang.org/download/0.16.0/zig-aarch64-linux-0.16.0.tar.xz", TarXz, "zig-aarch64-linux-0.16.0/zig")
						"aarch64-darwin" => Archive("https://ziglang.org/download/0.16.0/zig-aarch64-macos-0.16.0.tar.xz", TarXz, "zig-aarch64-macos-0.16.0/zig")
						"x86_64-darwin" => Archive("https://ziglang.org/download/0.16.0/zig-x86_64-macos-0.16.0.tar.xz", TarXz, "zig-x86_64-macos-0.16.0/zig")
						"x86_64-windows" => Archive("https://ziglang.org/download/0.16.0/zig-x86_64-windows-0.16.0.zip", Zip, "zig-x86_64-windows-0.16.0/zig.exe")
						_ => Unavailable
					},
				),
			]),
			Expect(["roc", "sha256sum", "tar", "gzip", "zip", "unzip", "gh"]),
		],
	),
	Environment(
		"docs",
		[
			Programs([
				Fetch(
					"roc-docs",
					|system| match system {
						"x86_64-darwin" | "x86_64-windows" => Unavailable
						_ => Recipes.file("https://github.com/lukewilliamboswell/roc-automation/releases/download/tools-0.9.0/roc-docs-{system}")(system)
					},
				),
			]),
			Expect(["roc"]),
		],
	),
	Task("docs", [Use("docs"), Run(["roc-docs", "build", "--workspace", ".", "--pdf-filename", "roc-wasm4.pdf", "--site-url", "https://lukewilliamboswell.github.io/roc-wasm4/", "--api-entrypoint", "platform/main.roc"])]),
	Environment(
		"policy",
		[
			Programs([
				Fetch(
					"roc-policy",
					|system| match system {
						"x86_64-darwin" | "x86_64-windows" => Unavailable
						_ => Recipes.file("https://github.com/lukewilliamboswell/roc-automation/releases/download/tools-0.9.0/roc-policy-{system}")(system)
					},
				),
			]),
		],
	),
	Task("policy", [Use("policy"), Run(["roc-policy", "check", "--root", "."])]),

	Shell("default", [Use("dev")]),
	Task("check", [Use("dev"), Run(["roc-stable", "scripts/check_all.roc"])]),
	Task("build-host", [Use("dev"), Run(["zig", "build", "-Doptimize=ReleaseSmall"])]),
	Environment("examples", [Extend("scripts"), Expect(["roc", "python3"])]),
	Task("examples", [Use("examples"), Run(["roc-stable", "scripts/examples.roc", "--"])]),
	Task("glue", [Use("dev"), Run(["roc-stable", "scripts/glue.roc", "--"])]),
	Task("release", [Use("dev"), Run(["roc-stable", "scripts/release.roc", "--"])]),
	Task("bundle", [Use("dev"), Run(["roc-stable", "scripts/bundle.roc", "--"])]),
	Task("format-scripts", [Use("scripts"), Run(["roc-stable", "fmt", "scripts", "Blueprint.roc"])]),
	Task("tooling-version", [Use("scripts"), Run(["roc-stable", "version"])]),
]

# Both the fetched script compiler and the policy check read this value.
tooling = { compiler: "nightly-2026-10-09-258ab27" }

repository_policy = {
	schema_version: 1,
	roots: ["platform", "examples"],
	rules: [{ kind: NoCompilerPin, scope: "platform" }, { kind: NoCompilerPin, scope: "examples" }],
}

script_policy = {
	schema_version: 1,
	roots: ["scripts"],
	rules: [{ kind: CompilerPin, scope: "scripts", value: tooling.compiler }],
}

example_policy = {
	schema_version: 1,
	roots: ["examples"],
	rules: [{ kind: Dependency, scope: "examples", name: "w4", value: "../../platform/main.roc" }],
}
