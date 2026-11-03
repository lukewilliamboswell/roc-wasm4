Examples := [].{
	dependency = "../../platform/main.roc"

	# Compiler-host jobs only build carts. The Linux runtime suite executes
	# them separately. Dependency substitution preserves source headers.
	replacement : List(Str) -> Try(List(Str), Str)
	replacement = |args| match args {
		[] => Ok([])
		["--bundle-url", url] =>
			if url.starts_with("http://127.0.0.1:") and url.ends_with(".tar.zst") {
				Ok(["--replace-dep", "./platform/main.roc", url])
			} else {
				Err("bundle URL must name a loopback .tar.zst archive")
			}
		_ => Err("usage: distribution --build-only [--bundle-url URL]")
	}

	local_header : Str -> Bool
	local_header = |source| source.contains("w4: platform \"../../platform/main.roc\"")
}

expect Examples.replacement([]) == Ok([])
expect Examples.replacement(["--bundle-url", "http://127.0.0.1:8000/hash.tar.zst"]) == Ok(["--replace-dep", "./platform/main.roc", "http://127.0.0.1:8000/hash.tar.zst"])
expect Examples.replacement(["--bundle-url", "https://example.com/hash.tar.zst"]).is_err()
expect Examples.replacement(["--bundle-url"]).is_err()
expect Examples.local_header("app [main] { w4: platform \"../../platform/main.roc\" }")
expect !Examples.local_header("app [main] { w4: platform \"https://example.com/hash.tar.zst\" }")
