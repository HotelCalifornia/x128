module app;

import std.algorithm;
import std.array;
import std.conv : to;
import std.format : format;
/* import std.socket : InternetAddress, Socket, SocketException, SocketSet, TcpSocket; */
import std.regex;
import std.stdio;

import discord.w;

import vibe.vibe;
import vibe.data.json;

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

	override void onMessageCreate(Message m) {
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
		} else { // sentiment analysis
			requestHTTP(format(`http://localhost:%s/`, nlpPort),
				(scope HTTPClientRequest req) {
					req.method = HTTPMethod.POST;
					req.writeJsonBody(replaceAll(m.content, regex(r"[\U00010000-\U0010ffff]", "g"), ""));
				},
				(scope HTTPClientResponse res) {
					auto json = res.readJson();
					sendMessage(m.channel_id, json["sentences"].get!(Json[])[0]["sentiment"].get!string);
				}
			);
		}
	}
}

DiscordBot x128;
string nlpPort = "9000";

void main(string[] args) {
	if (args.length <= 1) {
		writeln("Usage: ", args[0], " token [NLP server port (default 9000)]");
		return;
	}
	if (args.length > 2) {
		nlpPort = args[2];
	}
	x128 = makeBot!X128(args[1]);

	while (x128.gateway.connected) {
		sleep(10.msecs);
	}
}
