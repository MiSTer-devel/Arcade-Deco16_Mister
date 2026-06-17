# Arcade core for Deco16 games (Caveman Ninja and Crude Busters for now)

## General description
This repo contains an hdl wrapper for the Caveman Ninja and Crude Buster games.
The HDL loosely represent the Deco16 board, since some chips aren't decapped, they have been made with mame informations.
PLDs of this board exists but weren't used and the respective pld functions are absorbed in the HDL.
It was built with AI through JTFRAME and then converted to MiSTer template with the intent of making Caveman Ninja and Crude Buster playable on the MiSTer.
It is not a preservation effort since it does not add anything on top of what MAME already delivers, for now with extra bugs.

If you don't like the idea this could be a lower quality core don't use it.

## Known bugs and limitations
Of all the games on the variations of similar hardware this core runs only Caveman Ninja and Crude Buster for now.
- Audio seems unbalanced and could use some better mixing
- ~Occasionally I can see some sprite missing lines in busy scenes~ This has been fixed
- ~At the end of the first level I can trigger a bug where the platform on the right of the boss does not goes down as it should.~ This has been fixed

## Thanks
Many people, knowingly or not, contributed to this work.
- @jotego for the all the modules used and the framework ( this core was primed with JTCOP )
- @sorgelig for developing and maintaining MiSTer
- A bunch of people for moving me into just doing it
- @rmonic79 for providing some code that didn't get used at the end
- Claude, the AI, for doing all I asked almost correctly and quickly




