# Arcade core for DECO16 games: Caveman Ninja, Crude Buster, Vaportrail, Edward Randy Cliffhanger.

## General description
This repo contains an HDL  wrapper for the games Caveman Ninja, Crude Buster and Vapor Trail (Crude Buster is also known in the West as 'Two Crude Dudes').
The HDL loosely represents the DECO16 board; since some chips haven't been decapped, they have been made using MAME information.
PLDs of this board exist but weren't used and the respective PLD functions are absorbed in the HDL.
It was built with AI through JTFRAME and then converted to the MiSTer template with the intent of making Caveman Ninja and Crude Buster playable on the MiSTer.
It is not a preservation effort since it does not add anything on top of what MAME already delivers.

If you don't like the idea that this is built on top of mame without additional hardware verification and research, don't use it.
If one better, more researched core will come out with free sources this one will be deprecated.

## Known bugs and limitations
Of all the games on the variations of similar hardware this core runs only Caveman Ninja, Crude Buster, Edward Randy Cliffhanger, Vapor Trail and Dark seal.
- Audio seems a bit unbalanced .
- The core is too complex. Deciding to mix 5 games in the same core with all the variance of the deco boards was a mistake.

## Thanks
Many people, knowingly or not, contributed to this work.
- @jotego for the all the modules used and the framework ( this core was primed with JTCOP )
- @sorgelig for developing and maintaining MiSTer
- @rmonic79 for providing the Analog resizer
- @Boogerman for pointing out the bad implementation of the deco104 and suggesting a better approach
- @TheJesusFish for helping setting up the repo and guidance
- A bunch of people for moving me into just doing it
- Claude, the AI, for doing all I asked almost correctly and quickly




