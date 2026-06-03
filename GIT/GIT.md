# Git Master Control Panel - Analyse & Documentatie

Dit document bevat een gedetailleerde analyse van het `git-master.sh` script, inclusief een overzicht van alle menu's, de achterliggende commando's, potentiële duplicaten, en recente uitbreidingen voor verbeterde efficiëntie.

## 1. Overzicht per Menu en Onderdeel

### [1] INFO (Status, History & Analysis)
Dit menu is gericht op het opvragen van informatie over de repository.

*   **1) DASHBOARD (Status & History Overview)**
    *   *Commando's:* `git fetch origin --prune`, `git rev-list --count HEAD`, `git branch -a`, `git branch -vv`, `git status`, `git log -n 20 --oneline --graph`.
*   **2) DIFF VIEWER (Compare changes)**
    *   *Commando's:* `git diff`, `git diff --cached`, `git diff "br1".."br2"`, `git diff "commit_hash"`.
*   **3) FILE HISTORY (Show all commits for a file)**
    *   *Commando's:* `git log --follow --oneline -- "$filename"`, `git log --follow -p -- "$filename"`.
*   **4) SEARCH CODE (Find text in all files)**
    *   *Commando's:* `git grep -n "$search_text"`, `grep -r -n "$search_text" .`.
*   **5) COMMIT FINDER (Search commits by message)**
    *   *Commando's:* `git log --all --oneline --grep="$search_msg"`.
*   **6) BRANCH COMPARE (See differences between branches)**
    *   *Commando's:* `git log "${base_br}".."${cmp_br}" --oneline`, `git diff "${base_br}"..."${cmp_br}" --stat`.

### [2] DEVELOPMENT (Repo & Branch commands)
Dit menu wordt gebruikt voor dagelijkse ontwikkelactiviteiten (branching, commits, synchronisatie).

*   **1) CHECKOUT REPO (Fetch & Switch to Repository)**
    *   *Commando's:* `git fetch origin --prune`, `git branch -r`, `git checkout`, `git pull`.
*   **2) BRANCH EXPLORER (Switch or Create)**
    *   *Commando's:* `git branch -a`, `git checkout -b`.
*   **3) QUICK COMMIT (Stage, Commit & Push)**
    *   *Commando's:* `git add .`, `git commit -m`, `git push origin`.
*   **4) COMMIT LOCAL (Stage & Commit only)** *[Nieuw]*
    *   *Commando's:* `git add .`, `git commit -m`. Committ lokaal zonder direct te pushen.
*   **5) AMEND COMMIT (Update last commit)** *[Nieuw]*
    *   *Commando's:* `git commit --amend`, met of zonder bestandsaanpassingen en optioneel het aanpassen van het commit bericht.
*   **6) SYNC FETCH (Pull remote changes)**
    *   *Commando's:* `git pull origin`.
*   **7) PREPARE UAT (Merge branch into TEST)**
    *   *Commando's:* `git stash`, `git checkout main`, `git pull`, `git checkout -B uat`, `git merge -X theirs`.
*   **8) STAGING PUSH (Force sync current to DEV-STABLE)**
    *   *Commando's:* `git push origin dev-stable --force`.
*   **9) MERGE FIXES (Process external fixes)**
    *   *Commando's:* `git merge`, `git push`, `git branch -D`.
*   **10) RELEASE TAG (Mark current state)**
    *   *Commando's:* `git tag -a`, `git push origin "$v_tag"`.
*   **11) CLEANUP PRUNE (Delete branches gone on GitHub)**
    *   *Commando's:* `git branch -vv` + awk, `git branch -D`.
*   **12) DELETE BRANCH**
    *   *Commando's:* `git branch -D` of `git push origin --delete`.

### [3] FIX (Errors)
Gereedschap voor probleemoplossing, merges en git-fouten.

*   **1) FIX PULL ISSUES**
    *   *Commando's:* `git stash`, `git stash pop`, `git commit`, `git reset --hard HEAD`, `git clean -fd`.
*   **2) SYNC FORCE**
    *   *Commando's:* `git reset --hard origin`, `git push origin --force`.
*   **3) UNDO COMMIT**
    *   *Commando's:* `git reset --soft HEAD~1`.
*   **4) FORCE RESET**
    *   *Commando's:* `git checkout main`, `git reset --hard origin/main`, `git clean -fd`.
*   **5) EMERGENCY**
    *   *Commando's:* `git merge --abort`, `rm -f .git/index.lock`.
*   **6) RESTORE COMMIT**
    *   *Commando's:* `git checkout`, `git revert`, `git reset --hard`.
*   **7) STASH MANAGER** *[Nieuw/Vervangt STASH PULL POP]*
    *   *Beschrijving:* Geavanceerde opties om stashes te beheren.
    *   *Commando's:* `git stash list`, `git stash show`, `git stash apply`, `git stash pop`, `git stash drop`, `git stash clear`.
*   **8) FORGET FILE**
    *   *Commando's:* `git rm --cached`.

### [4] FILES & [5] MAINTENANCE
*   **EXCLUDE SYNC:** Negeert bestanden in git via `.gitignore` en `git rm --cached`.
*   **BACKUP POINT / RESTORE BACKUP:** Creëert en herstelt lokale snapshots.

---

## 2. Redundantie en Optimalisaties

In de analyse kwamen enkele duplicaten naar voren die weggewerkt of verbeterd zijn:

1.  **Redundante Stash functionaliteit:** De optie `STASH PULL POP` was een kopie van acties die al in `FIX PULL ISSUES` zaten. Deze is nu vervangen door een robuuste **STASH MANAGER** in het FIX menu, zodat stashes fatsoenlijk bekeken, toegepast of verwijderd kunnen worden.
2.  **Mist lokaal committen:** `QUICK COMMIT` voerde altijd direct een `git push` uit. Ontwikkelaars willen soms lokaal wijzigingen opbouwen (b.v. een lokale commit) zonder deze meteen online te zetten. Hiervoor is **COMMIT LOCAL** toegevoegd.
3.  **Correcties achteraf:** Het corrigeren van de laatste commit (door een foutje in code, toevoegen van vergeten bestanden, of aanpassen van de typfout in de titel) is een veelvoorkomende actie. **AMEND COMMIT** biedt deze functionaliteit in het DEVELOPMENT menu.

## 3. Nieuwe Functionaliteiten (Toegevoegd)

*   **COMMIT LOCAL:** Neemt lokale veranderingen en voegt deze toe aan een commit zonder direct te pushen.
*   **AMEND COMMIT:** Maakt het mogelijk de laatste commit tekst of inhoud aan te passen, om een verzameling kleine wijzigingen netjes onder te brengen.
*   **STASH MANAGER:** Een volledig submenu onder FIX voor het lijst van stashes (`git stash list`), bekijken van stash content, en toepassen, poppen, weggooien of wissen van de stash cache.
