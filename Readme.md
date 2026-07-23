# Arcade core for DECO16 games (Caveman Ninja and Crude Buster for now)

## General description
This repo contains an HDL  wrapper for the games Caveman Ninja, Crude Buster and Vapor Trail (Crude Buster is also known in the West as 'Two Crude Dudes').
The HDL loosely represents the DECO16 board; since some chips haven't been decapped, they have been made using MAME information.
PLDs of this board exist but weren't used and the respective PLD functions are absorbed in the HDL.
It was built with AI through JTFRAME and then converted to the MiSTer template with the intent of making Caveman Ninja and Crude Buster playable on the MiSTer.
It is not a preservation effort since it does not add anything on top of what MAME already delivers, for now with an extra bugs.

If you don't like the idea that this is built on top of mame without additional hardware verification and research, don't use it.
If one better, more researched core will come out with free sources this one will be deprecated.

## Known bugs and limitations
Of all the games on the variations of similar hardware this core runs only Caveman Ninja, Crude Buster and Vapor Trail for now.
- Audio seems unbalanced and could use some better mixing.
- The second level of caveman ninja has background broken toward the end of game
- The core is too complex. Deciding to mix 4-5 games in the same core with all the variance of the deco boards was a mistake.

## Thanks
Many people, knowingly or not, contributed to this work.
- @jotego for the all the modules used and the framework ( this core was primed with JTCOP )
- @sorgelig for developing and maintaining MiSTer
- @rmonic79 for providing the Analog resizer
- @TheJesusFish for helping setting up the repo and guidance
- A bunch of people for moving me into just doing it
- Claude, the AI, for doing all I asked almost correctly and quickly




