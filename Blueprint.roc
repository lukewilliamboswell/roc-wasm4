# Tools run on a fixed compiler; the platform uses the nightly roc on PATH.
app [config] { pf: platform "https://github.com/lukewilliamboswell/roc-blueprint/releases/download/0.11.0/EuSPs8vc71qJNFg29YzegvVRL1bR9pKqUYDHFiSCPTQ1.tar.zst" }

import pf.Recipes

zig_version = "0.16.0"

config = [
	Name("roc-wasm4"),
	Systems(["x86_64-linux"]),
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
			# the build minimum is checked against this declaration.
			Programs([
				Fetch(
					"zig",
					|system| match system {
						"x86_64-linux" => Archive("https://ziglang.org/download/${zig_version}/zig-x86_64-linux-${zig_version}.tar.xz", TarXz, "zig-x86_64-linux-${zig_version}/zig")
						"aarch64-linux" => Archive("https://ziglang.org/download/${zig_version}/zig-aarch64-linux-${zig_version}.tar.xz", TarXz, "zig-aarch64-linux-${zig_version}/zig")
						"aarch64-darwin" => Archive("https://ziglang.org/download/${zig_version}/zig-aarch64-macos-${zig_version}.tar.xz", TarXz, "zig-aarch64-macos-${zig_version}/zig")
						"x86_64-darwin" => Archive("https://ziglang.org/download/${zig_version}/zig-x86_64-macos-${zig_version}.tar.xz", TarXz, "zig-x86_64-macos-${zig_version}/zig")
						"x86_64-windows" => Archive("https://ziglang.org/download/${zig_version}/zig-x86_64-windows-${zig_version}.zip", Zip, "zig-x86_64-windows-${zig_version}/zig.exe")
						_ => Unavailable
					},
				),
			]),
			Expect(["roc", "sha256sum", "tar", "zstd", "gzip", "zip", "unzip", "gh"]),
		],
	),
	Environment(
		"docs",
		[
			Extend("scripts"),
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
	Task("docs", [Use("docs"), Run(["roc-stable", "scripts/docs.roc", "--"])]),
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

	Environment("release-tools", [Extend("scripts"), Programs([Fetch("release-package", Recipes.file("https://github.com/lukewilliamboswell/roc-automation/releases/download/tools-0.9.0/release-package-{system}"))]), Expect(["roc", "git", "gh", "tar", "zstd", "unzip", "zip", "chmod", "touch", "env"])]),
	Environment(
		"runtime",
		[
			Extend("release-tools"),
			Programs([
				Fetch("node", |system| if system == "x86_64-linux" Archive("https://nodejs.org/dist/v24.11.0/node-v24.11.0-linux-x64.tar.xz", TarXz, "node-v24.11.0-linux-x64/bin/node") else Unavailable),
				Fetch("w4-archive", Recipes.file("https://github.com/aduros/wasm4/releases/download/v2.7.1/w4-linux.zip")),
				Fetch("wasm4-playwright", |system| if system == "x86_64-linux" Archive("https://registry.npmjs.org/playwright-core/-/playwright-core-1.64.1.tgz", TarGz, "package/cli.js") else Unavailable),
				Fetch("wasm4-chromium-archive", Recipes.file("https://storage.googleapis.com/chrome-for-testing-public/156.0.8078.4/linux64/chrome-headless-shell-linux64.zip")),
			]),
		],
	),
	Environment("release-test", [Extend("runtime")]),
	Environment("release-build", [Extend("dev"), Programs([Fetch("release-package", Recipes.file("https://github.com/lukewilliamboswell/roc-automation/releases/download/tools-0.9.0/release-package-{system}"))])]),
	Task("release-package", [Use("release-build"), Run(["release-package"])]),
	Task("release-test", [Use("release-test"), Run(["roc-stable", "scripts/release_test.roc", "--"])]),
	Task("distribution", [Use("runtime"), Run(["roc-stable", "scripts/distribution.roc"])]),
	Task("runtime-tools", [Use("runtime"), Run(["node", "--version"])]),
	Task("runtime", [Use("runtime"), Run(["node", "examples/support/run-cart.mjs"])]),
	Task("nightly-prerequisites", [Use("runtime"), Run(["node", "examples/support/run-cart.mjs", "--export-tools"])]),

	Shell("default", [Use("dev")]),
	Task("check", [Use("release-build"), Run(["roc-stable", "scripts/check_all.roc"])]),
	Task("build-host", [Use("dev"), Run(["zig", "build", "-Doptimize=ReleaseSmall"])]),
	Task("glue", [Use("dev"), Run(["roc-stable", "scripts/glue.roc", "--"])]),
	Task("release", [Use("release-build"), Run(["roc-stable", "scripts/release.roc", "--"])]),
	Task("bundle", [Use("dev"), Run(["roc-stable", "scripts/bundle.roc", "--"])]),
	Task("format-scripts", [Use("scripts"), Run(["roc-stable", "fmt", "scripts", "Blueprint.roc"])]),
	Task("tooling-version", [Use("scripts"), Run(["roc-stable", "version"])]),
]

# Both the fetched script compiler and the policy check read this value.
tooling = { compiler: "nightly-2026-10-09-258ab27" }

repository_policy = {
	schema_version: 1,
	roots: ["platform", "examples", "benchmarks"],
	rules: [{ kind: NoCompilerPin, scope: "platform" }, { kind: NoCompilerPin, scope: "examples" }, { kind: NoCompilerPin, scope: "benchmarks" }],
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
