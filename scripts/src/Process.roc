import cli.Cmd
import cli.OsStr
import cli.Stdout

Process := [].{
	run! : Str, List(Str) => Try({}, Str)
	run! = |program, args| {
		Stdout.line!("+ ${program} ${Str.join_with(args, " ")}").map_err(|_| "cannot print command")?
		match Cmd.new(OsStr.from_str(program)).args(args.map(OsStr.from_str)).inherit_stdio().run!() {
			Ok({ status: Exited(0), .. }) => Ok({})
			Ok({ status: Exited(code), .. }) => Err("${program} exited with ${code.to_str()}")
			Ok({ status: Signaled(signal), .. }) => Err("${program} was killed by signal ${signal.to_str()}")
			Err(_) => Err("cannot start ${program}")
		}
	}
	capture! : Str, List(Str) => Try(Str, Str)
	capture! = |program, args| {
		result = Cmd.new(OsStr.from_str(program)).args(args.map(OsStr.from_str)).run!().map_err(|_| "cannot start ${program}")?
		match result.status {
			Exited(0) => Ok(Str.from_utf8_lossy(result.stdout_bytes).trim())
			_ => Err("${program} failed: ${Str.from_utf8_lossy(result.stderr_bytes)}")
		}
	}

}
