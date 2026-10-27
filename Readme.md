# Arcade core for DECO16 games: Caveman Ninja, Crude Buster, Vaportrail, Edward Randy Cliffhanger.

## General description
This repo contains an HDL  wrapper for the games Caveman Ninja, Crude Buster and Vapor Trail (Crude Buster is also known in the West as 'Two Crude Dudes' or just 'Two Crude').
The HDL loosely represents the DECO16 board; since some chips haven't been decapped, they have been made using MAME information.
PLDs of this board exist but weren't used and the respective PLD functions are absorbed in the HDL.
Built with heavy AI assistance via JTFRAME, it was later converted to the MiSTer template to make Caveman Ninja and Crude Buster playable on the platform.
The core was originally written in June 2026 but entirely rewritten in August 2026 by applying best practices learned while contributing code to Jotego's JTFRAME framework.

If a better, more researched core will come out with free sources this one will be deprecated.

## Known bugs and limitations
- Out of all the games designed for variations of similar hardware, this core runs only Caveman Ninja, Crude Buster, Edward Randy: Cliffhanger, and Vapor Trail. The game Dark Seal is covered in a separate core created by Umberto Parisi.
- Audio seems a bit unbalanced.
- Deciding to mix five games into the same core, given all the variance of the DECO boards, was a mistake.

## Thanks
Many people, knowingly or not, contributed to this work.
- @jotego for the all the modules used and the framework ( this core was primed with JTCOP )
- @sorgelig for developing and maintaining MiSTer
- @rmonic79 for providing the Analog resizer
- @Boogerman for pointing out the bad implementation of the deco104 and suggesting a better approach
- @TheJesusFish for helping setting up the repo and guidance
- A bunch of people for moving me into just doing it
- Claude, the AI, for doing all I asked almost correctly and quickly




