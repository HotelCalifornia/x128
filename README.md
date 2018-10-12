# x128

big sister to [HotelCalifornia/x64](https://github.com/HotelCalifornia/x64)

# requirements

- all the stuff required to build a Dlang program ([check it out](https://dlang.org))
- you may need to have libssl1.0-dev installed. apparently there's a different workaround but this one seems to work 🤷‍♀️ ([vibe-d/vibe.d#1651](https://github.com/vibe-d/vibe.d/issues/1651))
- some version of the Stanfod Core NLP project (probably >= 3.9.1, [downloads](https://stanfordnlp.github.io/CoreNLP/history.html))
- mongodb

# running

- `./runserver /path/to/coreNLP/root` to start the NLP server (note no trailing slash)
- `dub build` to build the D app
- `./x128 $TOKEN` to start the bot
