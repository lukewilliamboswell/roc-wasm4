import cli.Cmd
import cli.Stdout

Process := [].{
	run! : Str, List(Str) => Try({}, Str)
	run! = |program, args| {
		Stdout.line!("+ ${program} ${Str.join_with(args, " ")}").map_err(|_| "cannot print command")?
		match Cmd.new_str(program).args_str(args).exec_exit_code!() {
			Ok(0) => Ok({})
			Ok(code) => Err("${program} exited with ${code.to_str()}")
			Err(_) => Err("cannot start ${program}")
		}
	}
	capture! : Str, List(Str) => Try(Str, Str)
	capture! = |program, args| {
		result = Cmd.new_str(program).args_str(args).run!().map_err(|_| "cannot start ${program}")?
		match result.status {
			Exited(0) => Ok(Str.from_utf8_lossy(result.stdout_bytes).trim())
			_ => Err("${program} failed: ${Str.from_utf8_lossy(result.stderr_bytes)}")
		}
	}

}
