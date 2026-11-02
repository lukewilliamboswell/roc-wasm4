#!/usr/bin/env roc-stable
app [main!] {
	cli: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst",
	roc: "nightly-2026-10-09-258ab27",
}

import cli.Cmd
import cli.Env
import cli.Path
import cli.Stderr
import cli.Stdout
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
	source = Path.read_utf8!(Path.utf8("tests/spec.json")).map_err(|_| "cannot read runtime expectations")?
	suite : Try({ apps : List({ path : Str, cases : List({ stdout : Str, exit_code : I32 }) }) }, _)
	suite = Json.parse(source)
	found = suite.map_err(|_| "invalid runtime expectations")?
	Process.run!("node", ["examples/support/run-cart.mjs", "--export-tools"])?
	Env.with_temp_dir!(
		|temporary| {
			var $number = 0.U64
			for example in found.apps {
				$number = $number + 1
				output = Path.display(Path.join(temporary, "cart-${$number.to_str()}.wasm"))
				Process.run!("roc", ["build", example.path, "--target=wasm32", "--opt=size", "--output=${output}"])?
				bytes = Path.size_in_bytes!(Path.utf8(output)).map_err(|_| "missing optimized cart")?
				if bytes > 65536 or bytes == 0 {
					return Err("${example.path}: distribution cart must be 1..65536 bytes")
				}
				actual = Process.capture!("node", ["examples/support/run-cart.mjs", output])?
				expected = match example.cases {
					[case] if case.exit_code == 0 => case.stdout.trim()
					_ => return Err("public demos must have one successful runtime case")
				}
				if actual != expected {
					return Err("${example.path}: optimized cart differs from the reviewed runtime expectation")
				}
				Stdout.line!("PASS ${example.path}: ${bytes.to_str()} bytes, sixty optimized frames match").map_err(|_| "cannot report distribution test")?
			}
			Ok({})
		},
	).map_err(|_| "optimized WASM-4 distribution test failed")
}
