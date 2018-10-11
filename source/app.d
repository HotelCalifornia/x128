module app;

import std.algorithm;
import std.array;
import std.format;
import std.stdio;

import discord.w;

alias cmd_fn_t = void delegate(Snowflake, string[]) @safe;

class X128 : DiscordGateway {
	struct Command {
		cmd_fn_t fn;
		string help_msg;
	}

	void ping(Snowflake channel_id, string[] args) @safe {
		sendMessage(channel_id, "pong");
	}
	void help(Snowflake channel_id, string[] args) @safe {
		string[] msg;
		foreach (cmd; commands.byPair()) {
			msg ~= format("`%s`: %s", cmd.key, cmd.value.help_msg);
		}
		// TODO: make fancy embed?
		sendMessage(channel_id, msg.join("\n"));
	}

	Command[string] commands;
	this(string token) {
		super(token);
		commands = [
			"ping": Command(&ping, "replies with pong"),
			"help": Command(&help, "prints this message")
		];
	}

	void sendMessage(Snowflake channel_id, string msg) @safe {
		x128.channel(channel_id).sendMessage(msg);
	}

	override void onMessageCreate(Message m) @safe {
		super.onMessageCreate(m);

		// don't process messages from this bot
		if (m.author.id == this.info.user.id) return;

		if (m.content.startsWith(":>")) { // hotword
			auto args = m.content.split(" ")[1 .. $];
			if ((args[0] in commands) !is null) { // valid command
				commands[args[0]].fn(m.channel_id, args[1 .. $]);
			} else {
				sendMessage(m.channel_id, format("Unknown command `%s`. Run `:> help` for a list of available commands", args[0]));
			}
		}
	}
}

DiscordBot x128;

void main(string[] args) {
	if (args.length <= 1) {
		writeln("Usage: ", args[0], " [token]");
		return;
	}
	x128 = makeBot!X128(args[1]);

	while (x128.gateway.connected) {
		sleep(10.msecs);
	}
}
