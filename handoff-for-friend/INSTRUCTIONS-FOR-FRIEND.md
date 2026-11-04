# 🤝 Quick Start Guide for Claude Code Contributor

Hey! Thanks for helping out on the **Recon Bolt Revival** project.
Vineet is building this on a Windows machine, so having you run **Claude Code** (especially for macOS/Xcode & Swift workflow tasks) saves massive time and helps avoid AI quota bottlenecks.

Everything is synced directly through GitHub — **you do NOT need to zip files or send anything back manually.** You just edit with Claude Code, commit, and push!

---

## ⚡ 1. Getting Access
1. Vineet needs to add your GitHub username as a Collaborator on:
   👉 **`https://github.com/vineetshah11/recon-bolt-revived`**
   *(Settings -> Collaborators -> Add people)*
2. Check your email or GitHub notifications and click **Accept Invitation**.

---

## 💻 2. Clone and Setup
Run this in your terminal:
```bash
git clone --recurse-submodules https://github.com/vineetshah11/recon-bolt-revived.git
cd recon-bolt-revived
```

---

## 🤖 3. Run Claude Code
Because we have created a **`CLAUDE.md`** file in the root of the repository, Claude Code will **automatically read the full project context and guidelines** as soon as you launch it!

Just run:
```bash
claude
```

Inside Claude Code, you can copy-paste any of the pre-made task prompts from `handoff-for-friend/PROMPTS-FOR-CLAUDE-CODE.md`.

---

## 🚀 4. Pushing Changes
When Claude Code finishes a task:
```bash
git status
git add .
git commit -m "feat: <description of task completed>"
git push origin main
```
*(Or create a new branch + Pull Request if you prefer!)*

Once pushed, Vineet can simply run `git pull` on his Windows setup and everything is immediately updated!

