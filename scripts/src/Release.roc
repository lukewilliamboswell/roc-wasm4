Release := [].{
	valid_version : Str -> Bool
	valid_version = |value| match value.split_on("-") {
		[core] => core_version(core)
		[core, suffix] => core_version(core) and suffix.split_on(".").all(|part| !part.is_empty() and part.to_utf8().all(|byte| (byte >= 48 and byte <= 57) or (byte >= 65 and byte <= 90) or (byte >= 97 and byte <= 122)) and (!digits(part) or number(part)))
		_ => Bool.False
	}

	digits = |text| !text.is_empty() and text.to_utf8().all(|byte| byte >= 48 and byte <= 57)
	number = |text| digits(text) and (text == "0" or !text.starts_with("0"))
	core_version = |text| {
		parts = text.split_on(".")
		parts.len() == 3 and parts.all(number)
	}
}

expect Release.valid_version("0.8.0")
expect Release.valid_version("0.8.0-rc.1")
expect !Release.valid_version("0.8.0-")
expect !Release.valid_version("0.8.0-rc.01")
expect !Release.valid_version("v0.8.0")
expect !Release.valid_version("0.08.0")
expect !Release.valid_version("0.8")
expect !Release.valid_version("0.8.0/../../other")
