# Heist Crew: what the big heist games do, and what to steal

**Researched:** 2026-09-25
**For:** Heist Crew (4-player co-op PvE stealth heists, neon Miami, kids roughly 7-14, PC and phone)
**Status:** Research only. Nothing here is approved to build. Per Rule #12, Malachi picks which ideas to build.

## How this was researched

- **Primary sources:** each game's fandom wiki. The HTML pages sit behind Cloudflare, so I pulled the raw wikitext through the MediaWiki API (`<wiki>.fandom.com/api.php?action=parse&prop=wikitext`). Where this report gives a number (a price, a threshold, a limit), it was copied from that wikitext.
- **Other sources:** web search results (DevForum, Roblox Creator Hub docs, Roblox Support, guide sites). These are noted wherever I used them.
- **One game could not be identified: "The Heist (Ruby's)".** No Roblox game by that name turned up. What I did find:
  - Notoriety was originally called *Heist*, and it has its own old wiki (`heist-roblox-game.fandom.com`).
  - There is a separate Roblox game called "HEISTS" (place 1468955878).
  - "The Ruby Heist" is an itch.io game, not a Roblox game.

  If Malachi meant a different game, it still needs to be researched.
- **What I did not do:** I did not play these games or watch the videos frame by frame. The notes on UI and HUD come from wiki descriptions of how the HUD works, not from screenshots I checked myself.

---

## Part 1: Game-by-game breakdown

### 1. Entry Point (Cishshato), co-op stealth/loud FPS

- **Why it sticks:** Every mission starts in stealth. If the alarm goes off, the mission switches to a loud phase instead of failing (the only exceptions are a few stealth-only paid maps). So one map gives you two kinds of fun, and a mistake leads to a firefight rather than a game-over screen. Each of the 10 free missions can be played either way. [Detection](https://entry-point.fandom.com/wiki/Detection), [Missions](https://entry-point.fandom.com/wiki/Missions)
- **Core loop:** Pick a mission and difficulty, then play it with up to 4 players. You get contract pay plus a bonus for extra loot bagged, and XP. XP buys perk points, and perks unlock new abilities. There are also separate XP bonuses for "no alarm" and "nobody killed". [Experience/Loot](https://entry-point.fandom.com/wiki/Experience)
- **Stealth HUD (the gold standard):**
  - A **curved bar** appears for each NPC and fills while that NPC can see you. A faint **wind sound** gets louder as the bar fills.
  - At **33%** the NPC turns to face you. At **66%** they walk over to investigate and a **grey "?" or radio icon** appears over their head. At **100%** they raise the alarm.
  - Cameras use the same bar. Items fall into three tiers (safe, suspicious, dangerous), and guards pick up suspicious items.
  - When the alarm goes off, a banner names the cause ("Breaking glass set off the alarm!", "(player) set off a metal detector!").

  Source: [Detection](https://entry-point.fandom.com/wiki/Detection)
- **Team comms without voice:** Tap or hold **F to "spot"** an NPC. Every teammate then sees a marker through walls for about 2 seconds, colour-coded: white for civilians, red for guards, blue for objective NPCs. [Detection#Spotting](https://entry-point.fandom.com/wiki/Detection)
- **Onboarding:** There is a prologue cutscene ("Black Dawn") before you create a character. You pick a primary class (Thief, Mercenary, Engineer or Hacker), and it **cannot be changed later**. Hybrid classes come from a second class perk. [Roblox wiki: Entry Point](https://roblox.fandom.com/wiki/Player:Cishshato/Entry_Point), [Perks](https://entry-point.fandom.com/wiki/Perks)
- **Progression:** 240 perks. The level cap is 75, or 100 with a gamepass. A **"Pro Bonus"** grows each time you finish a mission (+1% on Rookie, +2% on Professional, and so on, capped at 35%). It **resets to 0** if you fail, disconnect or get kicked. On higher difficulties you pay "deployment costs" for the gear you bring. [Experience](https://entry-point.fandom.com/wiki/Experience)
- **Monetization** ([Gamepasses](https://entry-point.fandom.com/wiki/Gamepasses)): 6 passes, 3,185 R$ in total.
  - Extended Customization, 35 R$
  - Double XP, 300 R$
  - Legends (level cap and slots), 750 R$
  - Expanded Arsenal, 100 R$
  - **Night Heists (3 stealth-only missions), 800 R$**
  - **Freelance Heists, 1,200 R$**

  **Only the lobby host needs the heist pack. Anyone can join the host for free.**
- **Social:** Lobbies of up to 4, plus a separate PvP and "Shadow War" mode.

### 2. Notoriety (Moonstone Games, now "A PAYDAY Experience")

- **Why it sticks:** It is PAYDAY 2 on Roblox.
  - 19 to 22 heists. Some are stealth-only, some loud-only, and some let you choose.
  - Four skill trees (Mastermind, Enforcer, Technician, Ghost) that you can refund at any time, so you can try new builds on the same map.
  - The game was taken down by Starbreeze in September 2023 and came back under official PAYDAY branding in December 2024.

  [General Information](https://notoriety.fandom.com/wiki/Notoriety)
- **Core loop:** Buy or use a contract, then pick heist and difficulty. Pre-planning lets you spend "favors" and money on **assets**. Fill the loot-bag quota, get cash and XP, spend on skills, weapons and masks.
- **Signature mechanic, pagers:** When you take out a guard, their pager goes off. Someone has **8 seconds** to hold-answer it, and the reply takes 8 seconds.
  - Letting go early raises the alarm.
  - The whole team shares **4 pager answers per heist**. The operator gets funnier and angrier as you use them up ("No more messing around!"). The 5th raises the alarm.

  [Pagers](https://notoriety.fandom.com/wiki/Pagers)
- **Masks:** Masks are purely cosmetic, but **you cannot interact with anything until you mask up** (the "Chameleon" skill is the exception). Masks come from **randomized safes** in six rarities, and your first mask is a blank white comedy mask. [Masks](https://notoriety.fandom.com/wiki/Masks), [General Information](https://notoriety.fandom.com/wiki/Notoriety)
- **Detection HUD:** An animated suspicion meter ([Detection](https://notoriety.fandom.com/wiki/Detection)). Your gear has a detection-risk stat from 3 to 75 that you can see in your loadout.
- **Bots:** AI crew members fill lobbies of fewer than 3 players. In stealth they **idle at spawn**. When the heist goes loud they fight, but they **cannot do objectives**. [AI Heisters](https://notoriety.fandom.com/wiki/AI_Heisters) (search snippet)
- **Matchmaking:** **Quickplay** offers 3 heists and matches you into a group of 4 by skill. [Quickplay](https://notoriety.fandom.com/wiki/Quickplay) (search snippet)
- **Prestige ("Infamy"):** Reaching level 100 with $20M lets you go Infamous. You get a roman numeral next to your level, a new colour every 5 infamy levels, a special message at each milestone, and a guaranteed top-rarity safe. [Infamy](https://notoriety.fandom.com/wiki/Infamy)
- **Monetization** ([Gamepasses](https://notoriety.fandom.com/wiki/Gamepasses)):
  - Weapon packs, 49 to 599 R$
  - Double Cash, 499 R$; Double XP, 499 R$; Cheaper Prestige, 119 R$
  - A Tip Jar
  - **Paid heist maps:** Brick Bank 499 R$ and Golden Mask Casino 450 R$. **Only the host needs the map, and Roblox Premium members can host it for free** (the Premium perk helps with Premium engagement payouts).
- **End screen:** The handler (Jade) comments on the result with a line picked at random from a list for success or failure. [Heists](https://notoriety.fandom.com/wiki/Heists)

### 3. Jailbreak (Badimo), open-world cops and robbers

- **Why it sticks:**
  - Robberies **open and close on timers** (in the "Dynamic Robbery System", up to 4 are open at once), so the map always has something new to go do.
  - Each robbery is a small obstacle course. For example, the Jewelry Store has **randomized laser and camera floor variants**, then an escape by zipline or parachute.
  - It has been on the front page for years and was the first Roblox game to reach 100k concurrent players.

  [Robberies](https://jailbreak.fandom.com/wiki/Robberies), [Jewelry Store](https://jailbreak.fandom.com/wiki/Jewelry_Store), [Roblox wiki](https://roblox.fandom.com/wiki/Badimo/Jailbreak)
- **Core loop:** Escape prison (there are several routes: power box, C4 wall, keycard gate, sewer). Rob a place, drive the loot back to base, get cash, buy vehicles and cosmetics. Police players hunt your bounty.
- **HUD and notifications:**
  - A **server-wide toast**: "ROBBERY ALERT: The Jewelry Store is open", with the robbery's icon.
  - Map icons show whether each place is open or closed.
  - Owners of the BOSS pass get a warning **before** a store opens.
- **Mobile:** Smashing a jewelry case is F on PC, the **punch button on mobile**, and R2/RT on console, so one action works on every device.
- **The Mansion (a "special invite" heist):** Getting in requires an **invite letter** that drops from **airdrops** (crates falling from a jet crossing the sky). It is only open at night in game time, holds up to 3 players, and ends in a **boss fight** (the VP/CEO) that rolls a bonus loot table. [search: Mansion guides](https://jailbreakgame.wiki/guides/mansion/)
- **Progression:**
  - **Seasons** give limited-time vehicles and cosmetics for levelling up.
  - **Contracts reset weekly** (every Monday at 1 PM EST since Season 17). Daily XP is capped at 80, or 120 with the pass.
  - The **Season Pass costs 299 R$**: more contracts, more daily XP, and 4 exclusive rewards.
  - **Double XP switches on automatically in the last 5 days of a season.**
  - There are prizes for the top percentage of players.
  - Asimo has said seasons pause after Season 33.

  [Seasons](https://jailbreak.fandom.com/wiki/Seasons), [Contracts](https://jailbreak.fandom.com/wiki/Contracts)
- **Monetization** ([Gamepasses](https://jailbreak.fandom.com/wiki/Gamepasses)):
  - VIP (400 R$, +20% cash)
  - **Bigger Duffel Bag in 4 tiers, from 20 R$, sold *during* a robbery.** Tier 4 means up to 2x robbery cash.
  - Premium Garage, SWAT, BOSS, car stereo
  - **Gamepass gifting**, added in the 2025 Winter Update
  - A **VIP Monthly subscription**, 239 R$/month, added April 2026
- **Social:**
  - **Codes** (ATM codes posted on Twitter/X, including the Crew Battles beta codes)
  - Crews and Crew Battles (timed robbery races), removed in Season 29 and later brought back as a private-server game mode

  [Crew Battles](https://jailbreak.fandom.com/wiki/Crew_Battles)

### 4. Mad City (Schwifty Studios), Chapter 1, Chapter 2, and Season X

- **Why it sticks:** It is Jailbreak plus **superpowers**. Heroes have powers (Inferno, Proton, Frostbite and others). When a hero dies they can drop a **power crystal**, and a criminal who picks it up becomes a **Villain** with that power. On top of that there are boss fights (Chris P. Bacon, meteors) and seasonal map themes. [Roblox wiki: Mad City](https://roblox.fandom.com/wiki/Schwifty_Studios/Mad_City), [Chapter 2](https://mad-city.fandom.com/wiki/Chapter_2)
- **Heist map-marker states:**
  - **coloured** = open
  - **flashing red/blue plus an alarm sound** = a robbery is happening
  - **grey** = closed

  You can only run one heist at a time. **Mini-heists** (cafe, gas station, convenience store) give quick cash without XP. [Heists](https://mad-city.fandom.com/wiki/Heists)
- **Small loot objects:** Luggage, ATMs and cash registers you **hold E for 5 seconds** to grab ($500 to $600 each), which respawn after 1 to 5 minutes. They keep your hands busy between heists. [Heist Objects](https://mad-city.fandom.com/wiki/Heist_Objects)
- **Progression:** Seasonal rank with a reward **every 5 levels**. **Rank resets each season, but cash and unlocked items carry over.** Chapter 2 added up to 5 prestiges past Rank 100.
- **Monetization** ([Game passes](https://mad-city.fandom.com/wiki/Gamepasses)):
  - VIP, 1,000 R$: doubles heist cash, lets you bypass team limits, chat tag, vehicle skin
  - Double XP
  - Heavy Weapons, 400 R$
  - **Emote Packs**, 200 R$ each
  - Mobile Customization, 100 R$
- **Cautionary tale:** Chapter 2 rebuilt the map, UI and heists all at once, and players had "mixed reactions". Development was **halted in June 2024**, and **Chapter 1 was re-released** as its own game in September 2024. **Lesson: don't tear up a working core loop in one big update.**

### 5. Robbery-simulator tycoons (Robbery Simulator, Bank Robbery Simulator, Robbing and Heist Tycoon)

- **Robbery Simulator (Voldex)** ([Roblox wiki](https://roblox.fandom.com/wiki/Voldex_Services/Robbery_Simulator)):
  - You spawn in a **tunnel with signposted mini-tutorial steps**, and the first store (the Dollar Store) is right there.
  - **Each guard has a red circle around them.** If you step in, you go to jail and **lose everything you are carrying**. That is the simplest stealth rule a 7-year-old could learn.
  - Upgrades: **Gloves** let you steal faster, **Bags** carry more, and **Keys** unlock new areas.
  - Passes: 2x speed, 2x cash, infinite bag.
- **Bank Robbery Simulator (HD Games):** Robbing banks earns diamonds, and diamonds **hatch pets**, which is the standard simulator retention hook. Codes are handed out for free diamonds and coins. [Roblox page](https://www.roblox.com/games/7081641016/Bank-Robbery-Simulator), [Pocket Tactics codes](https://www.pockettactics.com/bank-robbery-simulator/codes)
- **Robbing Tycoon and Heist Tycoon:** You **build your own bank** with defences and raid other players' banks. [Heist Tycoon](https://www.roblox.com/games/11103424163/Heist-Tycoon)
- **Takeaway:** These games prove that kids love "number goes up" and upgrades for bag size and speed. The circle-around-the-guard idea is the most readable stealth rule in the whole genre.

### 6. Piggy (MiniToon), escape horror, and a lesson in kid-friendly UX

- **Why it sticks:**
  - **Episodic chapters** (12 per Book) released over time, each one a YouTube event.
  - Very short rounds.
  - **Vote for the map, then vote for the mode** (6 of 7 modes are offered each round).
  - A Bots mode for playing solo.

  [Roblox wiki: Piggy](https://roblox.fandom.com/wiki/Piggy_Dev_Team/Piggy), [Piggy (Game)](https://piggy.fandom.com/wiki/Piggy_(Game))
- **Economy:**
  - **Piggy Tokens** come from escaping (15, or 30 with the 2x Tokens pass), from catching players, and from event quests.
  - Token bundles range from **40 R$ for 50 tokens to 3,915 R$ for 5,000 tokens**.
  - Tokens buy skins, traps and bundles.
  - **Badge and secret skins** come from environmental puzzles and events.

  [search: Piggy Tokens](https://piggy.fandom.com/wiki/Piggy_Tokens), [Skins](https://piggy.fandom.com/wiki/Skins)
- **Takeaway:** A short round, an obvious goal ("escape"), voting as the whole lobby UI, and cosmetic-only spending.

### 7. Non-Roblox references

- **PAYDAY 2 and 3**
  - **Casing mode:** Heists start **unmasked**. Civilians ignore you, and guards only react if you trespass or do something illegal. Putting the mask on is a one-way commitment that the HUD announces. PAYDAY 3 lets you do more while unmasked (lockpicking, looping cameras).
  - In the Alesso and White House heists, you **take the mask off to blend in and escape**.
  - **CrimeFest-style community events:** rewards unlock for *everyone* as a shared goal is reached (for example, community-group member milestones).

  [Payday Stealth](https://payday.fandom.com/wiki/Stealth), [Social Stealth](https://payday.fandom.com/wiki/Social_Stealth), [Community Events](https://payday.fandom.com/wiki/Hype_Train)
- **GTA Online heists**
  - A **planning board**. Setup and prep missions happen before the finale.
  - **Choosing an approach** (Diamond Casino: Silent and Sneaky / Big Con / Aggressive).
  - The leader **sets each player's payout cut**.
  - **Elite Challenges:** bonus objectives such as a time limit, no deaths, or everyone in masks. Doing them all pays a bonus of $50k to $100k.
  - Since 14 July 2026, the **first completion each week pays more (about 1.5x)**.

  [Heists in GTA Online](https://gta.fandom.com/wiki/Heists_in_GTA_Online), [GTABase heist guide](https://www.gtabase.com/gta-online/jobs/heists/)

### 8. Platform facts that matter

- **Onboarding (Roblox Creator Hub):**
  - Show controls on screen.
  - Keep early levels fast.
  - A/B test tutorial steps ("shorter dialogue vs a guided arrow").
  - Give starter currency.
  - **Keep short, mid and long-term goals visible.**
  - End onboarding with a celebration.

  [Onboarding docs](https://create.roblox.com/docs/production/game-design/onboarding)
- **Retention benchmarks (guide site, not official):** D1 is good at 20%, great at 30%, excellent at 40%+. Players decide within the first 2 to 5 minutes, so the player should be *doing* something within about 10 seconds. [ROLearn](https://rolearn.dev/guidance/first-week-retention-optimization/)
- **Inviting friends:**
  - `SocialService:PromptGameInvite()`, checked first with `CanSendGameInviteAsync()`.
  - Roblox has a built-in **Friend Invite Reward System**, which shows a reward tooltip on the Roblox logo menu.

  [SocialService docs](https://create.roblox.com/docs/reference/engine/classes/SocialService#PromptGameInvite), [Roblox Support](https://en.help.roblox.com/hc/en-us/articles/36639668871700-Friend-Invite-Reward-System)
- **Paid random items (loot boxes):**
  - Anything random bought directly or indirectly with Robux must **show its odds before purchase**.
  - It is restricted for some users, such as UK users under 18.
  - Roblox rolled out Korea-driven odds disclosure worldwide in 2026.

  [Creator Hub policy](https://create.roblox.com/docs/production/monetization/paid-random-items), [DevForum UK update](https://devforum.roblox.com/t/update-on-paid-random-items-restriction-for-uk-users-under-18/3072183), [TechTimes](https://www.techtimes.com/articles/319148/20260626/koreas-loot-box-rules-push-roblox-disclose-item-odds-worldwide.htm)

---

## Part 2: TOP 15 IDEAS FOR HEIST CREW

**Rank** is the overall build order I would suggest (1 = do first). **Effort** is S (under a day), M (a few days) or L (a week or more). **Kid** rates how well the idea fits a 7-14 audience (★★★ = great).

### (a) Gameplay

**#1. "Blown cover" becomes a Hot Pursuit phase, not a fail** *(Entry Point, Notoriety, PAYDAY)*. Rank 1 · Effort M · Kid ★★★
- **What:** When the alarm goes off, the heist switches to a louder second act instead of failing:
  - The music changes.
  - Cops start arriving in waves, and doors lock down.
  - Your payout multiplier drops (for example, stealth pays 1.5x and pursuit pays 1.0x).
  - You can still bag loot and reach the getaway.
- **Why for us:** Instant fail is the #1 rage-quit moment for young kids. A two-act heist doubles what each map offers without building a new one. It also feeds the getaway, because a pursuit escape makes the cinematic more exciting.
- **Jail and breakout** become the "downed" state inside pursuit, rather than the end of the run.

**#2. Casing mode: start unmasked, then "MASK UP"** *(PAYDAY 2/3, Notoriety)*. Rank 3 · Effort M · Kid ★★★
- **What:** Every heist starts with the crew walking in unmasked as customers:
  - They can scout public areas and ping guards and cameras.
  - Pressing a big **MASK UP** button plays a short camera shot of the mask snapping on.
  - Only then can they interact with loot, keycards and drills.
  - Guards treat unmasked players in staff-only areas as trespassers ("Hey, you can't be back here!") and walk them out, instead of instantly detecting them.
- **Why for us:** It gives the jewelry store and bank a calm planning phase. The mask-up moment is also where your **masks with powers** and **mask cosmetics** get shown off every single run, which makes them a better purchase.

**#3. Team "Cover Story" budget** *(Notoriety pagers, Entry Point radio answers)*. Rank 6 · Effort S · Kid ★★★
- **What:** When a guard is knocked out or tied up, their radio buzzes ("Guard 3, report in?"). A crew member **holds the button for 3 seconds** to fake an answer ("All good here!").
  - The **whole crew shares 3 answers**, shown as 3 walkie-talkie icons on the HUD.
  - The dispatcher gets funnier and more suspicious each time.
  - Using a 4th starts Hot Pursuit (#1).
- **Why for us:** It is a tension mechanic that makes the crew talk to each other ("don't take out another one!"). It fits the **Lookout** role naturally: the Lookout could answer 1 extra, or answer faster.

**#4. Randomized layouts every run** *(Jailbreak jewelry-store floor variants, Entry Point's random-painting safe)*. Rank 7 · Effort M · Kid ★★
- **What:** Each run shuffles where the keycard spawns, which laser pattern is on each floor (2 to 3 variants per room), the vault code location, and guard patrol sets. V3 already shuffles loot and has a jackpot, so extend that to *objectives*.
- **Why for us:** With 4 heists, kids will memorize everything in a week. Variants make replaying a heist feel new at almost no art cost.

**#5. Heist stars / Elite challenges** *(GTA Online Elite Challenges, Entry Point no-alarm and no-kill XP bonuses, Notoriety bag quota)*. Rank 2 · Effort S · Kid ★★★
- **What:** Each heist has **3 stars**, shown on the lobby door and the end screen:
  - Ghost: no alarm
  - Full Bag: all bonus loot
  - Speedrun: under X minutes

  Stars give a bonus payout the first time you earn them, and **total stars unlock the next heist door** (corner store, then villa, then jewelry store, then bank).
- **Why for us:** It is the cheapest replay-value mechanic there is, and 7-year-olds understand stars from every mobile game. It also gives the club lobby a natural progression gate.

### (b) UI/UX

**#6. Per-guard suspicion meter with "?" and "!" stages and an audio swell** *(Entry Point's curved bar and wind sound, Notoriety's meter, Robbery Simulator's red circle)*. Rank 4 · Effort S-M · Kid ★★★
- **What:**
  - A small arc above each guard's head fills while they can see you.
  - **At 33% the guard turns** to face you and a grey "?" appears.
  - **At 66% they walk over** and the icon turns yellow.
  - **At 100% a red "!"** triggers the alarm (#1).
  - A soft rising "whoosh" plays as the meter fills, and a screen-edge vignette points toward the guard watching you.
  - On **Easy / first 3 heists**, also paint the vision cone on the floor (Robbery Simulator's red circle), and fade the floor paint out as players level up.
- **Why for us:** Kids on phones cannot read small text mid-chase, but they can read icons, colour and sound. You already have vision cones, so this makes them *legible*.

**#7. Friendly "what gave you away" banner** *(Entry Point's alarm-cause messages, Notoriety's end-screen quips)*. Rank 8 · Effort S · Kid ★★★
- **What:** When the alarm goes off, show a big banner with the cause: "A camera spotted a mask!", "Someone tripped a laser!", "A guard found a sleeping buddy!". Pair it with a 1-second freeze-frame on what did it. After the heist, the crew's "handler" says a random funny line.
- **Why for us:** It teaches the rules after the fact, which is the best teacher for kids. **Don't name the player who caused it** (Entry Point does), because that invites blame in a kids' lobby.

**#8. Ping / spot and quick-chat wheel** *(Entry Point spotting: F key, 2-second marker through walls, colour-coded)*. Rank 5 · Effort M · Kid ★★★
- **What:** Tap a guard, camera or loot to drop a coloured marker every teammate sees through walls for a few seconds:
  - red: guards and cameras
  - yellow: loot
  - blue: objectives

  Add a 6-option quick-chat wheel ("Wait!", "Go go go!", "Need help!", "Over here!", "Guard!", "Nice!"). On phone, a big "PING" button pings whatever is in front of you.
- **Why for us:** Many under-13 accounts have voice chat off and filtered text chat, so without pings a 4-player co-op game is 4 solo players. It also gives the **Lookout** a real job: camera pings last longer.

**#9. Live heist-door status in the club lobby** *(Mad City marker states, Jailbreak "ROBBERY ALERT" toasts)*. Rank 9 · Effort S · Kid ★★
- **What:** Each heist door shows its state:
  - glowing neon: "3/4 crew, starting in 0:12"
  - flashing: "Crew in progress"
  - a star count

  Server toasts say "A crew is hitting the BANK right now!" and "Heist of the Day: Beach Villa +50%" (see #12).
- **Why for us:** It makes the lobby feel alive and helps kids join groups that are about to start, which also fixes the "empty queue" problem.

**#10. One context button on mobile** *(Jailbreak: the same action on F, the mobile punch button, and R2)*. Rank 10 · Effort S · Kid ★★★
- **What:** One large on-screen **ACTION** button whose icon changes with context (hand to grab, drill icon, keycard icon, mask icon). Use "hold to fill" rings for anything timed. The mini-games need tap-friendly versions with large hit areas.
- **Why for us:** Phones are probably most of the audience. Several small buttons crammed together on a phone screen drive players to quit.

### (c) Progression & retention

**#11. Hot Streak multiplier** *(Entry Point Pro Bonus: grows each successful mission, capped at 35%, resets on fail)*. Rank 11 · Effort S · Kid ★★
- **What:** Each successful heist in a row adds +5% payout, up to +30%. The streak shows as a flame by your name in the lobby. **Kid-safe twist:** failing or disconnecting drops the streak **one step** instead of back to zero (phones disconnect a lot).
- **Why for us:** It gives a reason to play "just one more" and to stick with the same crew.

**#12. Weekly Contracts plus Heist of the Day** *(Jailbreak weekly contracts every Monday and the double-XP final week, GTA's 1.5x first completion each week, Mad City's reward every 5 levels)*. Rank 12 · Effort M · Kid ★★★
- **What:**
  - 5 weekly contracts, the same for everyone, for example "Bag 10 jewels", "Finish the villa as Driver", "Answer 2 cover stories".
  - They pay XP into a **free Crew Pass**, with a cosmetic every 5 levels.
  - One rotating "Heist of the Day" gets +50% payout.
  - An optional paid pass track is covered in (d).
- **Why for us:** Daily rewards bring kids back; contracts give them something to *do* once they are back. The same-for-everyone contracts give kids something to talk about at school.

**#13. Crew Rep prestige with a coloured badge** *(Notoriety Infamy: roman numerals, colour change every 5 levels, milestone messages)*. Rank 14 · Effort M · Kid ★★
- **What:** At max level, "go Legendary". Level resets, and you get a **badge next to your name** (I, II, III...) that changes neon colour every 5 prestiges. Each one gives a mask and a small permanent bonus.
- **Why for us:** It gives long-term players status in the club lobby. Only worth building once you have players at max level, so it comes last.

### (d) Monetization that isn't pay-to-win

**#14. Host-owns-it premium heists that friends play for free, and free for Premium** *(Entry Point Night Heists and Freelance packs, Notoriety Brick Bank and Golden Mask: only the host needs the pass; Notoriety: Premium members host free)*. Rank 13 · Effort S · Kid ★★★
- **What:** Future bonus heists (for example "Yacht Party" or "Casino") are a gamepass, but **only the host needs it**. Anyone in their crew plays for free, and Roblox Premium members can host them for free too.
- **Why for us:**
  - Paying kids become the popular host, and free kids get a taste of the heist.
  - The purchase is social and shareable, not a wall.
  - Premium-free hosting brings Premium players in, which earns **Premium engagement payouts**.
  - Keep all 4 core heists free forever.

**#15. Crew-shared perks and gifting** *(Jailbreak gamepass gifting (2025) and the Duffel Bag sold during a robbery, Mad City VIP)*. Rank 15 · Effort S-M · Kid ★★★
- **What:**
  - **VIP** (roughly 300-400 R$) gives the owner a chat tag, a neon trail, and **+10% heist cash for the whole crew they are in**, not just themselves.
  - Sell a "Bigger Bag" dev product at the moment the player's bag fills up (the Jailbreak pattern), but make it a **cosmetic bag skin plus 1 extra carry slot**, not a cash multiplier.
  - Add **gifting** so kids can buy a pass for a friend.
- **Why for us:** In PvE co-op, a buff that helps the whole crew makes the paying player *welcome*, not resented. Gifting turns one buyer into two.

### (e) Social / viral: honorable mentions just outside the top 15

- **Bring-your-crew invite reward:** Use `PromptGameInvite` plus Roblox's Friend Invite Reward System. When an invited friend finishes their first heist, both players get an exclusive "Crew Founder" mask. Effort S, Kid ★★★.
- **Community heist meter** *(PAYDAY 2 CrimeFest milestones)*: One global "Miami loot" counter. At each goal (for example $1B stolen worldwide), everyone unlocks a reward or a new door opens. Effort M, Kid ★★★. Great for TikTok and YouTube hype.
- **Codes on socials** *(Jailbreak ATM codes, Bank Robbery Simulator)*: Put a code terminal in the club and post codes on TikTok, @shoptankgrip-style. Effort S, Kid ★★★. This is the cheapest acquisition loop on Roblox.
- **Special invite heist from a world event** *(Jailbreak Mansion airdrop invite plus boss fight)*: A neon blimp or supply drop lands in the club at random. Grabbing it gives the crew a one-time invite to a boss heist. Effort L, Kid ★★★.
- **Vote for heist, then modifier** *(Piggy votes for map, then mode)*: In quick-match lobbies, vote on the heist and then a fun modifier ("Low Gravity", "Giant Heads", "Lights Out"). Effort S-M, Kid ★★★.
- **Shareable end card:** After the getaway, show a crew card with the 4 avatars in masks, stars, the payout, and the getaway choice (Boat/Heli/Highway). Kids screenshot these. Effort S.
- **Emote packs** *(Mad City, 200 R$)*: Pure cosmetic, and kids use them in the club lobby. Effort S.
- **Pets / sidekicks** *(Bank Robbery Simulator)*: A cosmetic "crew mascot" that follows you, such as a neon flamingo. Only after the core game is solid.
- **Short onboarding** *(Roblox docs, Robbery Simulator's tunnel signs)*: The first-time tutorial should have the player **grab loot within about 10 seconds** and finish in under 2 minutes. End it with a confetti and cash moment, and don't open with lore cutscenes (Entry Point's prologue is fine for its audience, but not for 7-year-olds).

### Suggested build order at a glance

1. Blown cover becomes Hot Pursuit (#1)
2. Heist stars (#5)
3. MASK UP casing (#2)
4. Suspicion meter UI (#6)
5. Ping and quick-chat (#8)
6. Cover Story budget (#3)
7. Randomized layouts (#4)
8. Friendly alarm banner (#7)
9. Lobby door status (#9)
10. Mobile action button (#10)
11. Hot Streak (#11)
12. Weekly contracts and Heist of the Day (#12)
13. Host-owns premium heists (#14)
14. Crew Rep prestige (#13)
15. Crew-shared VIP and gifting (#15)

If it's cheap enough, add the invite reward and codes early. They are small, and they bring in players.

---

## Part 3: Things these games do that we should NOT copy

1. **Killing guards and bodies as the core verb** (Entry Point, Notoriety, PAYDAY). For 7-14, use knockouts, "sleeping" guards, tie-ups and jail instead of death. Keep it cartoon.
2. **Paid random mask safes** (Notoriety's randomized safes). Loot boxes bought with Robux are **regulated**: odds must be disclosed, and they are restricted for some regions and ages. They are also bad for kids. Sell masks directly, or give random drops only as free earned rewards.
3. **Paywalling core content for everyone** (Entry Point's heist packs cost 800-1,200 R$ each). Only do the host-owns version (#14), and never paywall the 4 base heists.
4. **Stacking cash multipliers** (Jailbreak VIP +20% on top of Duffel Tier 4 at 2x, Mad City VIP at 2x). In PvE this is not unfair to other players, but it breaks your economy and makes free players feel slow. Cap the total paid bonus (for example +25%), and prefer crew-wide bonuses.
5. **Deployment costs / losing money for bringing gear** (Entry Point) and **losing everything you carry on capture** (Robbery Simulator). Too punishing for young kids. Jail should cost time, not saved progress.
6. **Harsh reset to zero on disconnect** (Entry Point's Pro Bonus). Phones and school Wi-Fi drop constantly. Use soft decay.
7. **Stealth-only maps that instantly fail** (Entry Point's Night Heists). See #1.
8. **Top-1% leaderboard prizes and grind-walls** (Jailbreak season top-percentile rewards). Good for sweats, bad for 9-year-olds. Reward completion, not rank.
9. **Rebuilding everything in one mega-update** (Mad City Chapter 2 got mixed reactions, development was halted, and Chapter 1 had to be re-released). Ship in small updates on top of what already works.
10. **Naming the player who blew it in a banner** (Entry Point's "(player) set off a metal detector!"). It invites blame and toxic chat in a kids' lobby. Name the cause instead.
11. **Bots that stand at spawn during stealth** (Notoriety AI crew). If Heist Crew's solo bots are there to fill roles, they must *do* the role (carry bags, answer a cover story, drive) or solo players will feel alone.
12. **Long lore cutscenes and choices you can never undo** before the first heist (Entry Point's prologue and permanent primary class). Let kids try every role, and let them switch roles anytime in the lobby.
13. **Donation "tip jar" passes** (Entry Point's 35 R$ customization pass admits it is a donation pass, and Notoriety has a Tip Jar). They look cheap. Always give the buyer something real.

---

## Sources

- Entry Point: [Detection](https://entry-point.fandom.com/wiki/Detection) · [Missions](https://entry-point.fandom.com/wiki/Missions) · [Gamepasses](https://entry-point.fandom.com/wiki/Gamepasses) · [Experience/Loot](https://entry-point.fandom.com/wiki/Experience) · [Perks](https://entry-point.fandom.com/wiki/Perks) · [Roblox wiki page](https://roblox.fandom.com/wiki/Player:Cishshato/Entry_Point)
- Notoriety: [General Information](https://notoriety.fandom.com/wiki/Notoriety) · [Detection](https://notoriety.fandom.com/wiki/Detection) · [Pagers](https://notoriety.fandom.com/wiki/Pagers) · [Masks](https://notoriety.fandom.com/wiki/Masks) · [Infamy](https://notoriety.fandom.com/wiki/Infamy) · [Gamepasses](https://notoriety.fandom.com/wiki/Gamepasses) · [Heists](https://notoriety.fandom.com/wiki/Heists) · [AI Heisters](https://notoriety.fandom.com/wiki/AI_Heisters) · [Quickplay](https://notoriety.fandom.com/wiki/Quickplay) · [old "Heist" wiki](https://heist-roblox-game.fandom.com/wiki/How_to_Stealth_Heist)
- Jailbreak: [Gamepasses](https://jailbreak.fandom.com/wiki/Gamepasses) · [Seasons](https://jailbreak.fandom.com/wiki/Seasons) · [Contracts](https://jailbreak.fandom.com/wiki/Contracts) · [Robberies](https://jailbreak.fandom.com/wiki/Robberies) · [Jewelry Store](https://jailbreak.fandom.com/wiki/Jewelry_Store) · [Crew Battles](https://jailbreak.fandom.com/wiki/Crew_Battles) · [Bounty](https://jailbreak.fandom.com/wiki/Bounty) · [Mansion guide](https://jailbreakgame.wiki/guides/mansion/) · [Roblox wiki page](https://roblox.fandom.com/wiki/Badimo/Jailbreak)
- Mad City: [Chapter 2](https://mad-city.fandom.com/wiki/Chapter_2) · [Heists](https://mad-city.fandom.com/wiki/Heists) · [Heist Objects](https://mad-city.fandom.com/wiki/Heist_Objects) · [Game passes](https://mad-city.fandom.com/wiki/Gamepasses) · [Roblox wiki page](https://roblox.fandom.com/wiki/Schwifty_Studios/Mad_City)
- Simulators and tycoons: [Robbery Simulator](https://roblox.fandom.com/wiki/Voldex_Services/Robbery_Simulator) · [Bank Robbery Simulator](https://www.roblox.com/games/7081641016/Bank-Robbery-Simulator) · [Heist Tycoon](https://www.roblox.com/games/11103424163/Heist-Tycoon) · [Robbing Tycoon](https://www.roblox.com/games/4932220972/Robbing-Tycoon)
- Piggy: [Roblox wiki page](https://roblox.fandom.com/wiki/Piggy_Dev_Team/Piggy) · [Piggy (Game)](https://piggy.fandom.com/wiki/Piggy_(Game)) · [Piggy Tokens](https://piggy.fandom.com/wiki/Piggy_Tokens) · [Skins](https://piggy.fandom.com/wiki/Skins)
- PAYDAY and GTA: [Payday Stealth](https://payday.fandom.com/wiki/Stealth) · [Social Stealth](https://payday.fandom.com/wiki/Social_Stealth) · [Community Events](https://payday.fandom.com/wiki/Hype_Train) · [GTA Online heists](https://gta.fandom.com/wiki/Heists_in_GTA_Online) · [GTABase heists](https://www.gtabase.com/gta-online/jobs/heists/)
- Platform: [Roblox Onboarding docs](https://create.roblox.com/docs/production/game-design/onboarding) · [SocialService](https://create.roblox.com/docs/reference/engine/classes/SocialService#PromptGameInvite) · [Friend Invite Reward System](https://en.help.roblox.com/hc/en-us/articles/36639668871700-Friend-Invite-Reward-System) · [Paid random items policy](https://create.roblox.com/docs/production/monetization/paid-random-items) · [UK under-18 restriction](https://devforum.roblox.com/t/update-on-paid-random-items-restriction-for-uk-users-under-18/3072183) · [Worldwide odds disclosure](https://www.techtimes.com/articles/319148/20260626/koreas-loot-box-rules-push-roblox-disclose-item-odds-worldwide.htm) · [ROLearn retention](https://rolearn.dev/guidance/first-week-retention-optimization/)
