#!/usr/bin/env swipl

:- multifile user:message_hook/3.
user:message_hook(initialization_error(_,X,_),Kind,_) :- print_message(Kind,X),halt(1).
user:message_hook(string(S),_,_) :- format(user_error,'ERROR: ~w~n', [S]).

/*
running this takes a while because it first does just a load to find compile errors, and then runs swipl again to actually execute goal. Maybe next version will consult Script directly, but idk how to eval() a goal, except by parsing it first..

maybe use:
https://www.swi-prolog.org/pldoc/man?section=protocol

*/

shell2(Cmd) :-
	shell2(Cmd, _).

shell2(Cmd_In, Exit_Status) :-
	flatten([Cmd_In], Cmd_Flat),
	atomic_list_concat(Cmd_Flat, Cmd),
	format(user_error, '~w\n\n', [Cmd]),
	shell(Cmd, Exit_Status).

maybe_halt_on_err :- 
	opts(Opts),
	memberchk(halt_on_problems(Halt), Opts),
	(	Halt = true
	->	halt_on_problems
	;	true).

halt_on_problems :-
	get_flag(err_file, Err_File),
	opts(Opts),
	(	(memberchk(problem_lines_whitelist(Whitelist_File), Opts), nonvar(Whitelist_File))
	->	Err_Grep = ['grep -E -i "Warn|err" ', Err_File, ' | grep -q -v -x -F -f ', Whitelist_File]
	;	Err_Grep = ['grep -q -E -i "Warn|err" ', Err_File]
	),
	(	shell2(Err_Grep, 0)
	 ->	(
			format(user_error, "that's an error, halting.\n", []),
	 		halt(1)
		)
	;	true).

maybe_clean_terminal :-
	opts(Opts),
	memberchk(clear_terminal(Clear), Opts),
	(
		Clear = true
	->
		(
			shell2('timeout 0.1 reset'),
			shell2('echo "\e[3J" 1>&2'),
			shell2('timeout 0.1 reset')
		)
	;
		true
	).

x :-

	tmp_file_stream(text, Err_File, Stream),
	set_flag(err_file, Err_File),
	close(Stream),

	Spec = [
		[opt(viewer), type(atom), shortflags([v]), longflags([viewer])]
		,[opt(debug), type(boolean), default(true), shortflags([d]), longflags([debug])]
		,[opt(halt_on_problems), type(boolean), default(true), shortflags([h]), longflags([halt_on_problems])]
		,[opt(problem_lines_whitelist), type(atom), longflags([problem_lines_whitelist])]
		,[opt(clear_terminal), type(boolean), default(false), shortflags([c]), longflags([clear_terminal])]
		,[opt(script), type(atom), shortflags([s]), longflags([script])]
		,[opt(goal), type(atom), shortflags([g]), longflags([goal])]
	],
	format(user_error, 'dev_runner: starting...\n', []),
	opt_arguments(Spec, Opts, Args),
	(Args = [] -> true ; throw(string('no positional arguments accepted'))),
	assert(opts(Opts)),
	opts(Opts),
	memberchk(debug(Debug), Opts),
	memberchk(viewer(Viewer), Opts),
	memberchk(script(Script), Opts),
	(nonvar(Script)->true;throw(string('--script needed'))),
	(	Debug = true
	->	Optimization = ''
	;	Optimization = '-O'),
	% todo for python rewrite:  --tty=true -q? pipe goal (not rpc message) to swipl. get gtrace working.
	atomic_list_concat(['swipl ', Optimization, ' -s ', Script], Load_Cmd),
	%maybe_clean_terminal,
	/* make forces compilation of dcg's or something. Ideally, we would have two steps: 1)compile 2) run the compiled file. But for this i'd like to review what kind of dcg declaration errors 'make' reported that just loading the prolog file didnt, because we would lose that reporting.  */
	format(user_error, 'dev_runner: checking syntax...\n', []),
	shell2([Load_Cmd, ' -g "make,halt."  2>&1  |  tee ', Err_File, ' | head -n 150 1>&2']),
	maybe_halt_on_err,
	format(user_error, 'dev_runner: syntax seems ok...\n', []),
	memberchk(goal(Goal), Opts),
	(	nonvar(Goal)
	->	(
			format(user_error, 'dev_runner: running swipl...\n', []),
			(	nonvar(Viewer)
			->	Redirection = [' 2>&1  1> arrr.xml | tee ', Err_File]
			;	Redirection = ''),
			atomic_list_concat([':- [', Script, '].\n', Goal], Goal_file_contents),
			write_file(loc(absolute_path, '/app/server_root/goal'), Goal_file_contents),
			shell2(['swipl ', Optimization, ' ', '/app/server_root/goal', ' -g "', Goal, '." -c ']),
			(	nonvar(Viewer)
			->	(maybe_halt_on_err, shell2([Viewer, ' arrr.xml']))
			;	true),
			shell2(['ls -trlhs /app/server_root/']),
			shell2(['/app/server_root/a.out']),
			(	nonvar(Viewer)
			->	(maybe_halt_on_err, shell2([Viewer, ' arrr.xml']))
			;	true),
			halt
		)
	;	shell2([Load_Cmd],Exit),halt(Exit)).

:- initialization(x).

write_file(loc(absolute_path, Path), Text) :-
	setup_call_cleanup(
		open(Path, write, Stream),
		write(Stream, Text),
		close(Stream)).