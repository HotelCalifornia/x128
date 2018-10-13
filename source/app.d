module app;

import std.algorithm;
import std.array;
import std.conv : to;
import std.format : format;
import std.math : approxEqual;
import std.regex;
import std.stdio;
import std.typecons : Flag, Nullable;
import std.uni : toLower;

import discord.w;

import vibe.vibe;
import vibe.data.bson;
import vibe.data.json;
import vibe.data.serialization : name;
import vibe.db.mongo.mongo;

alias cmd_fn_t = void delegate(Snowflake, string[]) @safe;
/**
 * Main Bot class
 */
class X128 : DiscordGateway {
  /**
  * Template containing common fields for database documents
  */
  template WholesomeT() {
    struct {
      @name("_id") BsonObjectID id;
      int neutral;
      int positive;
      int negative;
    }
  }

  /**
   * Schema for user document in database
   */
  struct WholesomeUser {
    mixin WholesomeT;

    private struct Usr {
      Snowflake uid;
      string name;
    }

    Usr usr; /** Stores the user's ID and name */
  }

  /**
   * Schema for channel document in database
   */
  struct WholesomeChannel {
    mixin WholesomeT;

    private struct Chnl {
      Snowflake cid;
      string name;
    }

    Chnl chnl; /** Stores the channel's ID and name */
  }

  /**
   * Representation of a bot command.
   */
  struct Command {
    cmd_fn_t fn; /** command function */
    string help_msg; /** short description of the command to display for the help message */
    string usage; /** describe the usage of the command, e.g. `<: cmd arg1 [opt_arg2]` */
  }

  /**
    * Ping command
    *
    * Replies with 'pong'
    *
    * @param channel_id the ID of the channel in which to reply
    */
  void ping(Snowflake channel_id, string[] _) @safe {
    sendMessage(channel_id, "pong");
  }

  /**
   * Help command
   *
   * Lists all available commands and their help messages
   *
   * @param channel_id the ID of the channel in which to send the message
   * @param args optionally specify the name of a command to get more detail
   */
  void help(Snowflake channel_id, string[] args) @safe {
    if (args.length > 0) {
      if (args[0] in commands)
        sendMessage(channel_id, format("`%s`: %s\nUsage:\n```\n%s\n```",
            args[0], commands[args[0]].help_msg, commands[args[0]].usage));
      else
        sendMessage(channel_id, format("No such command `%s`", args[0]));

      return;
    }
    string[] msg;
    foreach (cmd; commands.byPair()) {
      msg ~= format("`%s`: %s", cmd.key, cmd.value.help_msg);
    }
    // TODO: make fancy embed?
    sendMessage(channel_id, msg.join("\n"));
  }

  /**
   * Wholesomeness summary command
   *
   * Print out a summary detailing the overall wholesomeness of the channel or
   * of a user
   *
   * @param channel_id the channel to check and in which send the message
   * @param args optionally specify a user about which to generate the summary
   */
  void summary(Snowflake channel_id, string[] args) @safe {
    auto channels = db.getCollection("local.channels");
    const auto channel = channels.findOne!WholesomeChannel(["chnl.cid" : channel_id.toString()]);
    if (channel.isNull) {
      sendMessage(channel_id, "I don't have enough data about this channel yet!");
    }
    else {
      if (args.length == 0) { // channel summary
        const int totalMessages = channel.positive + channel.negative + channel.neutral;
        const float pctPositive = (channel.positive / cast(float) totalMessages) * 100;
        const float pctNeutral = (channel.neutral / cast(float) totalMessages) * 100;
        const float pctNegative = (channel.negative / cast(float) totalMessages) * 100;
        // man I really don't like the way it formats lines like this
        const float wholesomeness = cast(float)(channel.positive - channel.negative) / cast(float)(
            totalMessages - channel.neutral);

        int color;
        string desc;
        string name;
        if (wholesomeness >= 0.95) { // super wholesome
          color = 0x00FF00;
          desc = "Amazing! You really don't need me here!";
          name = "Super Wholesome";
        }
        else if (0.50 < wholesomeness && wholesomeness < 0.95) { // mostly wholesome
          color = 0x006300;
          desc = "That's pretty wholesome! Keep it up!";
          name = "Mostly Wholesome";
        }
        else if (approxEqual(wholesomeness, 0)) { // super neutral (need to check before mostly neutral)
          color = 0xFFFFFF;
          desc = "May I present the new Supreme Justices of the United States of America?";
          name = "Super Neutral";
        }
        else if (-0.50 <= wholesomeness && wholesomeness <= 0.50) { // mostly neutral
          color = 0xFFFF00;
          desc = "What is this, a channel full of judges? Could be worse...";
          name = "Mostly Neutral";
        }
        else if (-0.95 < wholesomeness && wholesomeness < -0.50) { // mostly toxic
          color = 0xFF8800;
          desc = "This channel is pretty toxic... You can do better.";
          name = "Mostly Toxic";
        }
        else { // super toxic
          color = 0xFF0000;
          desc = "You guys are really horrible. There's probably no hope.";
          name = "Super Toxic";
        }
        Embed embed = {
        title:
          format("Channel summary for #%s", x128.channel(channel_id).get.name),
        description : desc, color : color, fields
            : [
            Embed.Field("Overall Wholesomeness", format("%f%% (%s)", wholesomeness * 100,
                name)), Embed.Field("Positive", format("%d (%2f%%)", channel.positive,
                pctPositive), true), Embed.Field("Neutral", format("%d (%2f%%)", channel.neutral,
                pctNeutral), true), Embed.Field("Negative",
                format("%d (%2f%%)", channel.negative, pctNegative), true)]
        };
        x128.channel(channel_id).sendMessage("", Nullable!Snowflake.init,
            No.tts, cast(Nullable!Embed) embed);
      }
    }
  }

  Command[string] commands; /** map of command names -> commands */
  /**
    * Constructor
    *
    * @param token the bot's token
    */
  this(string token) {
    super(token);
    commands = ["ping" : Command(&ping, "replies with pong", ":> ping"), "help" : Command(&help,
        "prints this message. if a command is specified, print a message describing its use",
        ":> help [command]"), "summary" : Command(&summary, "print a summary of the wholesomeness of the current channel. if a user is specified, summarize their wholesomeness instead",
        ":> summary [user]")];
  }

  /**
    * Utility function for sending a message
    *
    * @param channel_id the channel in which to send the message
    * @param msg the message to send
    */
  void sendMessage(Snowflake channel_id, string msg) @safe {
    x128.channel(channel_id).sendMessage(msg);
  }

  /**
    * Utility function for generating a mongodb update object
    *
    * @param sentiment the sentiment string returned from the NLP server
    * @param old the record being updated
    *
    * @return an object that can be passed into a mongodb update function
    */
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
    default:
      assert(0); // should never ever happen
    }
    upd[sentiment.toLower()] = newVal;
    return upd;
  }

  /**
    * Push a new user with sentiment values or update an existing one
    *
    * @param sentiment the sentiment string returned by the NLP server
    * @param author the author of the message that was just analyzed
    */
  void userSentiment(string sentiment, User author) @safe {
    auto users = db.getCollection("local.users");

    auto user = users.findOne!WholesomeUser(["usr.uid" : author.id]);
    if (user.isNull) {
      WholesomeUser usr = {
      id:
        BsonObjectID.generate(), usr : {uid:
        author.id, name : author.username}
      };
      users.insert(usr);
      user = users.findOne!WholesomeUser(["usr.uid" : author.id]);
    }
    users.update(["usr.uid" : author.id], ["$set" : sentimentIncr!WholesomeUser(sentiment, user)]);
  }

  /**
    * Push a new channel with sentiment values or update an existing one
    *
    * @param sentiment the sentiment string returned by the NLP server
    * @param user TBD
    * @param chnl the channel to insert or update
    */
  void channelSentiment(string sentiment, User user, Channel chnl) @safe {
    auto channels = db.getCollection("local.channels");
    auto channel = channels.findOne!WholesomeChannel(["chnl.cid" : chnl.id]);
    if (channel.isNull) {
      WholesomeChannel tchnl = {
      id:
        BsonObjectID.generate(), chnl : {cid:
        chnl.id, name : chnl.name}
      };
      channels.insert(tchnl);
      channel = channels.findOne!WholesomeChannel(["chnl.cid" : chnl.id.toString()]);
    }

    channels.update(["chnl.cid" : chnl.id.toString()], ["$set"
        : sentimentIncr!WholesomeChannel(sentiment, channel)]);
  }

  override void onMessageCreate(Message m) {
    super.onMessageCreate(m);

    // don't process messages from this bot
    if (m.author.id == this.info.user.id)
      return;

    if (m.content.startsWith(":>")) { // hotword
      auto args = m.content.split(" ")[1 .. $];
      if ((args[0] in commands) !is null) { // valid command
        commands[args[0]].fn(m.channel_id, args[1 .. $]);
      }
      else {
        sendMessage(m.channel_id,
            format("Unknown command `%s`. Run `:> help` for a list of available commands", args[0]));
      }
    }
    else { // sentiment analysis
      requestHTTP(format(`http://localhost:%s/`, nlpPort), (scope HTTPClientRequest req) {
        req.method = HTTPMethod.POST;
        req.writeJsonBody(replaceAll(m.content, regex(r"[\U00010000-\U0010ffff]", "g"), ""));
      }, (scope HTTPClientResponse res) {
        auto json = res.readJson();

        sendMessage(m.channel_id, json["sentences"].get!(Json[])[0]["sentiment"].get!string);
        auto sentiment = json["sentences"].get!(Json[])[0]["sentiment"].get!string;
        userSentiment(sentiment, m.author);
        channelSentiment(sentiment, m.author, x128.channel(m.channel_id).get());
      });
    }
  }
}

DiscordBot x128; /** main bot instance */
string nlpPort = "9000"; /** port on which the NLP server is running. can be overridden by command line arguments */
MongoClient db; /** mongo database instance */

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
