#!/usr/bin/env roc-stable
app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst",
	roc: "nightly-2026-10-09-258ab27",
}

import cli.OsStr
import cli.Path
import cli.Stderr
import src/Process
import src/Release

Component : { id : Str, name : Str, version : Str, producer : Str, license : Str, license_url : Str, identity : Str, download : Str, sha256 : Str, modified : Str, target : Str, origin : Str }

Edge : { from : Str, to : Str, relation : Str, scope : Str, basis : Str }

Coverage : { scope : Str, component : Str, aspect : Str, status : Str, reason : Str, contact : Str }

Disposition : { input : Str, component : Str, reason : Str }

Unavailable : { component : Str, reason : Str, contact : Str }

Composition : { profile : Str, components : List(Component), relationships : List(Edge), coverage : List(Coverage), inputs : List(Disposition), imported_documents : List(Str), unavailable_sboms : List(Unavailable) }

contact = "https://github.com/lukewilliamboswell/roc-wasm4/security/policy"

repository = "https://github.com/lukewilliamboswell/roc-wasm4"

main! = |args| {
	result = match args.map(OsStr.display) {
		[version] if Release.valid_version(version) => prepare!(version)
		_ => Err("usage: blueprint run sbom -- VERSION")
	}
	match result {
		Ok({}) => Ok({})
		Err(message) => {
			Stderr.line!(message)?
			Err(Exit(1))
		}
	}
}

component = |id, name, version, license, identity, download, digest, modified| {
	{ id, name, version, producer: "Person: Luke Boswell and contributors", license, license_url: "", identity, download, sha256: digest, modified, target: "", origin: "reviewed" }
}

edge = |from, to, relation, scope, basis| { from, to, relation, scope, basis }

gap = |scope, owner, aspect, reason| { scope, component: owner, aspect, status: "incomplete", reason, contact }

hash! = |file| Ok((Process.capture!("sha256sum", [file])?).split_on(" ").first() ?? "")

prepare! = |version| {
	base_text = Path.read_utf8!(Path.utf8("sbom/base.json")).map_err(|_| "cannot read reviewed SBOM base")?
	parsed : Try(Composition, _)
	parsed = Json.parse(base_text)
	base = parsed.map_err(|_| "invalid reviewed SBOM composition")?
	expected = Path.read_utf8!(Path.utf8("sbom/node-tools.json")).map_err(|_| "missing reviewed Node component evidence")?
	actual = Process.capture!("blueprint", ["run", "runtime-tools"])?
	if actual != expected.trim() {
		return Err("locked Node's bundled OpenSSL/V8 identities differ from reviewed SBOM metadata")
	}
	commit = Process.capture!("git", ["rev-parse", "HEAD"])?
	compiler_version = Process.capture!("roc", ["version"])?
	binary = Process.capture!("sh", ["-c", "command -v roc"])?
	compiler_hash = hash!(binary)?
	compiler_base = component("product-compiler", "Roc compiler executable", compiler_version, "UPL-1.0", "urn:roc-wasm4:compiler:${compiler_hash}", "NOASSERTION", compiler_hash, "Hash of the unpacked compiler executable on PATH; official nightly selection and archive verification are recorded by setup-roc")
	compiler = { ..compiler_base, producer: "Organization: Roc contributors" }
	Path.create_all!(Path.utf8("dist/sbom")).map_err(|_| "cannot create SBOM composition directory")?
	for (kind, root, description) in [("bundle", "platform", "Roc source modules and compiled wasm32 host"), ("examples", "examples", "Four games, companion modules, runtime adapter and illustration files"), ("api", "platform", "Versioned compiler-generated API reference and its static assets"), ("manual", "docs", "Rendered PDF manual with subset font data")] {
		first_party = component("first-party", "roc-wasm4 ${kind}", version, "UPL-1.0", "${repository}/tree/${commit}/${root}", "${repository}/archive/${commit}.tar.gz", "", "${description}; selected content of the source revision, not the complete repository")
		var $components = base.components.concat([first_party, compiler])
		var $edges = base.relationships.concat([edge("Subject", "first-party", "contains", "", description), edge("Subject", "product-compiler", "dependsOn", "build", "Compiler used for the platform, games and API extraction; it is not shipped in the subject")])
		var $coverage = base.coverage.append(gap("source-and-build-context", "Subject", "dependencies", "Locked tools and current compiler are recorded. OS-provided archive tools, system libraries and the Blueprint bootstrap/configuration compiler are not fully inventoried."))
		if kind == "bundle" {
			host = component("wasm32-host", "host.wasm", commit, "UPL-1.0 AND MIT AND ISC", "${repository}/blob/${commit}/src/host.zig", "NOASSERTION", hash!("platform/targets/wasm32/host.wasm")?, "Compiled from the reviewed Zig host and generated ABI with the locked Zig toolchain")
			allocator = component("allocator", "umm_malloc-derived Zig allocator", commit, "UPL-1.0 AND MIT", "${repository}/blob/${commit}/src/allocator.zig", "https://raw.githubusercontent.com/lukewilliamboswell/roc-wasm4/${commit}/src/allocator.zig", hash!("src/allocator.zig")?, "Zig rewrite with alignment handling; original upstream umm_malloc revision was not recorded. Ralph Hempel's MIT notice accompanies the bundle.")
			$components = $components.concat([host, allocator])
			$edges = $edges.concat([edge("Subject", "wasm32-host", "contains", "", "Exact host.wasm bytes are included in the bundle"), edge("wasm32-host", "allocator", "contains", "", "Host allocation services compile and exercise this allocator implementation"), edge("wasm32-host", "tool-zig", "dependsOn", "build", "Locked Zig archive provides the compiler and standard library used by the host")])
			$coverage = $coverage.append(gap("optimized-host-closure", "wasm32-host", "assembly", "The allocator is known, but exact optimized Zig standard-library/compiler-runtime contributions have not been enumerated. Source imports are not claimed as a complete binary closure."))
		} else if kind == "examples" {
			art_base = component("rocci-bird-art", "Rocci Bird artwork", commit, "NOASSERTION", "${repository}/tree/${commit}/examples/rocci-bird", "NOASSERTION", "", "Artwork credited to Luke DeVault; the original asset revision and license were not recorded in this repository")
			art = { ..art_base, producer: "Person: Luke DeVault" }
			$components = $components.append(art)
			$edges = $edges.concat([edge("first-party", "rocci-bird-art", "contains", "", "The example embeds sprite artwork credited in the repository README"), edge("Subject", "wasm32-platform", "dependsOn", "runtime", "Archived game headers declare this release's exact platform bundle")])
			platform_component = component("wasm32-platform", "roc-wasm4 platform", version, "UPL-1.0 AND MIT AND ISC", "urn:roc-wasm4:platform:${version}", "${repository}/releases/tag/${version}", "", "Exact dependency URL and hash are recorded in the archived spec.json and game headers")
			$components = $components.append(platform_component)
			$coverage = $coverage.append(gap("example-art-provenance", "first-party", "assembly", "Companion source files are archived completely, but licenses and original upstream revisions for illustrations and embedded artwork are not fully documented."))
		} else if kind == "manual" {
			fonts = Path.list!(Path.utf8(".docs-out/site/_roc-docs/fonts")).map_err(|_| "cannot inspect emitted font inputs")?
			for font_path in fonts.keep_if(|path| Path.display(path).ends_with(".ttf")) {
				file_name = Path.filename(font_path).map_ok(Path.display).map_err(|_| "invalid font name")?
				name = file_name.drop_suffix(".ttf")
				digest = hash!(".docs-out/site/_roc-docs/fonts/${name}.ttf")?
				font_base = component("font-${name}", name, "sha256-${digest}", "OFL-1.1", "urn:roc-wasm4:font:${name}:${digest}", "NOASSERTION", digest, "Exact original font input extracted by the locked roc-docs binary; the PDF embeds transformed/subset data")
				producer = if name.starts_with("Inter-") "Organization: The Inter Project Authors" else if name.starts_with("FiraCode-") "Organization: The Fira Code Project Authors" else if name.starts_with("Merriweather-") "Organization: The Merriweather Project Authors" else return Err("review the upstream producer for new font ${name}")
				font = { ..font_base, producer }
				$components = $components.append(font)
				$edges = $edges.append(edge("Subject", "font-${name}", "dependsOn", "build", "Manual rendering uses this exact font input; the complete original font file is not asserted to be contained in the PDF"))
			}
			$coverage = $coverage.append(gap("pdf-subsets", "Subject", "assembly", "The exact PDF and original font inputs are hashed; embedded subset/font-object membership is not separately enumerated."))
		} else {
			$coverage = $coverage.append(gap("api-generated-assets", "Subject", "assembly", "The API ZIP is hashed and archived completely. Compiler-generated HTML, CSS, JavaScript and logo assets are not individually inventoried."))
		}
		composition = { ..base, components: $components, relationships: $edges, coverage: $coverage }
		Path.write_utf8!(Path.utf8("dist/sbom/composition-${kind}.json"), Json.to_str(composition)).map_err(|_| "cannot write ${kind} composition")?
	}
	Ok({})
}
