module app;

import std.algorithm;
import std.array;
import std.conv : to;
import std.format : format;
/* import std.socket : InternetAddress, Socket, SocketException, SocketSet, TcpSocket; */
import std.regex;
import std.stdio;
import std.typecons : Nullable;
import std.uni : toLower;

import discord.w;

import vibe.vibe;
import vibe.data.bson;
import vibe.data.json;
import vibe.data.serialization : name;
import vibe.db.mongo.mongo;

alias cmd_fn_t = void delegate(Snowflake, string[]) @safe;

class X128 : DiscordGateway {
	template WholesomeT() {
		struct {
			@name("_id") BsonObjectID id;
			int neutral = 0;
			int positive = 0;
			int negative = 0;
		}
	}
	struct WholesomeUser {
		mixin WholesomeT;

		struct Usr {
			Snowflake uid;
			string name;
		}
		Usr usr;
	}
	struct WholesomeChannel {
		mixin WholesomeT;

		struct Chnl {
			Snowflake cid;
			string name;
		}
		Chnl chnl;
	}
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
	void summary(Snowflake channel_id, string[] args) @safe {
		auto channels = db.getCollection("local.channels");
		auto channel = channels.findOne!WholesomeChannel(["chnl.cid": channel_id.toString()]);
		if (channel.isNull) {
			sendMessage(channel_id, "I don't have enough data about this channel yet!");
		} else {
			
		}
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

	Bson sentimentIncr(W)(string sentiment, W old) @safe {
		Bson upd = Bson.emptyObject;
		int newVal;
		switch (sentiment) {
			case "Neutral":
				newVal = old.neutral + 1;
				break;
			case "Positive":
				newVal = old.positive + 1;
				break;
			case "Negative":
				newVal = old.negative + 1;
				break;
			default: assert(0); // should never ever happen
		}
		upd[sentiment.toLower()] = newVal;
		return upd;
	}

	void userSentiment(string sentiment, User author) @safe {
		auto users = db.getCollection("local.users");

		/* sendMessage(m.channel_id, json["sentences"].get!(Json[])[0]["sentiment"].get!string); */
		auto user = users.findOne!WholesomeUser(["usr.uid": author.id.toString()]);
		if (user.isNull) {
			WholesomeUser usr = { id: BsonObjectID.generate(), usr: { uid: author.id, name: author.username } };
			users.insert(usr);
			user = users.findOne!WholesomeUser(["usr.uid": author.id.toString()]);
		}
		/* writeln(user.toString()); */
		/* writeln(upd); */
		users.update(["usr.uid": author.id.toString()], ["$set": sentimentIncr!WholesomeUser(sentiment, user)]);
	}

	void channelSentiment(string sentiment, User user, Channel chnl) @safe {
		auto channels = db.getCollection("local.channels");
		auto channel = channels.findOne!WholesomeChannel(["chnl.cid": chnl.id]);
		if (channel.isNull) {
			WholesomeChannel tchnl = { id: BsonObjectID.generate(), chnl: { cid: chnl.id, name: chnl.name } };
			channels.insert(tchnl);
			channel = channels.findOne!WholesomeChannel(["chnl.cid": chnl.id.toString()]);
		}

		channels.update(["chnl.cid": chnl.id.toString()], ["$set": sentimentIncr!WholesomeChannel(sentiment, channel)]);
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
					auto users = db.getCollection("local.users");

					sendMessage(m.channel_id, json["sentences"].get!(Json[])[0]["sentiment"].get!string);
					auto sentiment = json["sentences"].get!(Json[])[0]["sentiment"].get!string;
					userSentiment(sentiment, m.author);
					channelSentiment(sentiment, m.author, x128.channel(m.channel_id).get());
				}
			);
		}
	}
}

DiscordBot x128;
string nlpPort = "9000";
MongoClient db;

void main(string[] args) {
	if (args.length <= 1) {
		writeln("Usage: ", args[0], " token [NLP server port (default 9000)]");
		return;
	}
	if (args.length > 2) {
		nlpPort = args[2];
	}
	db = connectMongoDB("127.0.0.1");
	x128 = makeBot!X128(args[1]);

	while (x128.gateway.connected) {
		sleep(10.msecs);
	}
}
