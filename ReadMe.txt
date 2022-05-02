https://forums.alliedmods.net/showthread.php?t=64661

Description:
Shows a left side menu when you die or at the end of the round, saying who you did and took damage from and how much, including how many hits and who killed you. You will also see where you hit a person and where they hit you

Background:
Well, we had this before we went to SourceMod and I thought it would be nice to have again.

Planned changes:
Maybe translations ...

Change log:
1.0.0 - First Version
1.0.1 - Added number of hits done/taken
1.0.2 - Added hitbox info
1.0.3 - Added coloring, Info about who you killed
1.1.0 - Added option so you can turn damage report on and off, and also decide if it should be printed in menu or chat.
Use /damage_report help to get info
Big thanks to death_beam team since I used their code to learn about KeyValues!
1.1.1 - Stripped chat output. Resetting damage data on round start
1.1.2 - Added total dmg taken/given and X indicator for kill/killed
1.1.3 - Removed errors in log from translation stuff that was not completed
1.1.5 - Added support to show again the last report that was shown to a player (/last_damage_report or /ldr)
1.1.6 - Fixed saving of settings on map end
1.1.7 - Fixed problem with corrupted settingsfile.
1.1.8 - Added most kills info
1.1.9 - Fixed memory leak
1.1.10 - Checking if player still ingame before trying to display.
1.1.11 - Sometimes it seems that the settings for the users isnt written to file. Forcing this more often now.
1.1.12 - Making sure damage data is not shown to surviving players if they have switched it off.
1.1.13 - Added extra option, /damage_report long|short - If hitboxdata should be shown or not


Screenshots: