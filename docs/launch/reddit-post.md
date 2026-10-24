**Suggested subreddits:** r/eink, r/dumbphones, r/minimalistphone [TODO: check each sub's rules on ROM / firmware posts before posting]

**Title:** I ported KompaktOS (Android 16) to the Moaan InkPalm Plus, with e-ink and front light controls (free, open source, hobby project, brick risk)

**Images (in order)** (in `docs/images/`; no photos, the phone has no camera):

1. `kompaktos-home.png`: the KompaktOS home screen on the InkPalm Plus
2. `screen-and-light-panel.png`: the Screen & light panel (screen modes, full refresh, contrast, brightness, warmth)
3. `inkpalm-plus-recents.png`: the recent apps panel on the right edge

---

I wanted KompaktOS on my InkPalm Plus, so I made it run. It's now my daily driver.

KompaktOS is a LineageOS-based ROM made for the Mudita Kompakt. This port puts KompaktOS 1.2 (LineageOS 23.2, Android 16, as a GSI) on the InkPalm Plus, keeping the phone's stock Android 11 vendor parts underneath. The repo has the scripts, notes and a small root helper. It doesn't contain KompaktOS or any of Moaan's files.

What works:

- KompaktOS on the e-ink screen, with the display fixed so it draws properly
- Touch, and the touch button below the screen (Home)
- A small root helper in the image, so an app can drive the e-ink modes, the front light and the sleep and power-off screens

The controls themselves are in [InkPalm+](https://github.com/rn-os/inkpalm-plus), my other app, which ships with the port:

- Screen modes: Fast, Soft, Dither, Text, Quality and Auto, per app or everywhere
- Full refresh, contrast, and the front light (brightness, warmth, auto)
- Back from an edge swipe, since KompaktOS has no nav bar
- Hold the touch button for a full refresh
- Recent apps on the right edge
- Your own sleep screen, a power-off screen (Moaan's panda, in English), and auto power-off after a few hours asleep on battery

Some caveats, so nobody is surprised:

- **This is a hobby port tested on one device (mine). You can brick your phone.** There's a way back to stock (reflash your own stock `super` backup, then wipe), and it's written up in the repo, but read it before you flash anything.
- **You bring the proprietary pieces yourself:** a backup of your own stock firmware, and the stock Android 11 display libraries from it. Nothing from Moaan is in the repo. You also get KompaktOS from its own source, not from me.
- Flashing erases the stock system and your data, so back up first.
- One known issue: the power button sometimes doesn't wake the phone. I'm still looking into it.
- The English panda power-off screen needs the latest image build [TODO: image version].
- First boot can take several minutes on e-ink with no feedback.

Not affiliated with Moaan or Mudita. Thanks to KompaktOS, LineageOS, the GSI builders and TrebleDroid / phhusson, whose work this all sits on.

**Install**

1. Read the Risks section and docs/REVERT.md in the repo, and make your own backup
2. Follow docs/FLASH-KOMPAKTOS.md
3. In Obtainium, add `https://github.com/rn-os/inkpalm-plus` for the e-ink and light controls (1.1.0 or later)

GitHub: https://github.com/rn-os/kompaktos-inkpalm-plus

Built with Claude Code. Feedback welcome, especially if you try it and tell me how it goes. Reports of the power button not waking the phone are useful too.
