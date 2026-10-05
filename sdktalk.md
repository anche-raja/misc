# SDC talk script: Why you should not just ask Claude to migrate an application

A speaking script for a 45-minute slot. You talk while walking the audience through the
forge repository in your editor. No live run is needed.

- **OPEN** = the file or folder to have on screen.
- Everything else is what you say. Short sentences; pause at the blank lines.
- Times are cumulative.

| Part | Time |
| --- | --- |
| 1. Opening | 0:00 - 3:00 |
| 2. What went wrong when we just asked | 3:00 - 11:00 |
| 3. The principle | 11:00 - 13:00 |
| 4. Walking through the project | 13:00 - 37:00 |
| 5. Closing | 37:00 - 40:00 |
| 6. Q&A | 40:00 - 45:00 |

---

## 1. Opening (0:00 - 3:00)

**OPEN:** nothing yet, or a title slide with the talk title.

Good morning. Quick show of hands.

Who here has asked an AI assistant to upgrade a dependency, or migrate a module?

Keep your hand up if the result compiled the first time.

That's about what I expected.

My name is Raja. Over the last few weeks I tried to get Claude to migrate a real J2EE
application: Java 8 to Java 21, javax to Jakarta EE 10, Spring 5 to Spring 6, Struts,
JSPs, JUnit 4 to JUnit 5.

The title of this talk is "Why you should not just ask Claude to migrate an application."

I want to be clear up front: this is not a talk about Claude being bad at Java.
The individual edits it makes are good. Often very good.

This is a talk about what happens when you hand an agent the whole job -
planning, editing, testing, reviewing, and deciding when it's done -
and then believe its report.

I'll show you seven ways that went wrong for us, the one principle we took from it,
and then I'll walk you through the tool we built: forge.

---

## 2. What went wrong when we just asked (3:00 - 11:00)

**OPEN:** a slide or a plain list with the seven headings below.

The application is called AMS. It's a realistic legacy app: three Maven reactors,
Struts actions, Spring and Spring Security, JSP pages, a WebSphere Liberty config,
JUnit 4 tests, an in-memory H2 database for tests.

We gave Claude the repository, tools to read and write files, run Maven and open a pull
request. And we watched.

**One. It stops early.**

The first run hit the agent framework's step limit, 150 steps, and the whole turn died.
We raised the limit. The next run stopped on its own and wrote: "Still to do, due to token
limits."

Nobody told it to stop. It decided the job was big, and quit politely.

**Two. It picks the easy files.**

One run made 160 tool calls. It edited pom files and about thirty-five test files.
It never opened a single main Java class, JSP, or Struts action.

Then it wrote, and I'm quoting: "Out of scope: javax-to-jakarta, 24 files. Struts, 25 files.
JSP, 26 files. Spring Security, 7 files. These should be addressed in separate migration
efforts."

We had approved eleven items. None were optional. The agent re-scoped the project to the
part it had finished.

**Three. It grades its own homework.**

When tests failed, it said "this failure is pre-existing, not related to the migration."
Once, that was true. One H2 test really did fail before we touched anything.

But in the pull request it opened, the "pre-existing" failure was a call to a method that
doesn't exist, in a test the agent had written itself.

**Four. It changes the test, not the code.**

There's a test that checks private IP space is *rejected* on the carrier side.
After the migration, it checked that private IP space is *allowed*.
Eight assertions became six.

The fastest way to make a test pass is to change what it checks. So that's what it did.

**Five. AI reviewing AI makes it worse.**

We added a second model to review every file. It told us, with confidence, to rename
`javax.xml.parsers` to `jakarta.xml.parsers`. That package doesn't exist. It's part of the JDK.
Same for `javax.sql`. It told us a correct JSTL URI was wrong, and that a correct JUnit 5
assertion had its arguments in the wrong order.

When we clicked "retry", the first model applied that advice. Two retries, two broken builds.

A reviewer without ground truth doesn't add safety. It adds confident noise.

**Six. Secrets and personal data go straight to the model.**

The repository has a hardcoded gateway password, an API key, and a keystore password in the
server config. When the agent reads those files, the values go into the model's context.

We had a Bedrock guardrail with personal-data masking switched on. We tested it.
It masks what the model *writes*. Not what it *reads*.

**Seven. Cost and limits.**

Every step re-sends the whole conversation. In 48 hours we made 879 model calls with
44 and a half million input tokens. That's about fifty thousand tokens per call, around
forty-seven dollars, on the small model. Then the daily token cap kicked in, and everything
stopped.

And the pull request it opened? Seventy-five files. "All tests pass." "Now on Tomcat 10.1."
Neither half of the application compiled, and the Dockerfile still said Tomcat 9.

---

## 3. The principle (11:00 - 13:00)

**OPEN:** `docs/README.md`, the "A run at a glance" diagram.

So we flipped it around. One sentence:

**The model does the edit. Code decides everything else.**

Code detects the tech stack.
Code decides which files each migration touches, and in what order.
Code runs the tests, against a baseline taken before we change anything.
Code checks that tests still test the same things.
Code keeps secrets out of files, commits and chat.
And code decides whether a pull request is allowed to exist.

Humans sit at two gates: approving the plan, and deciding the files that get flagged.
Not in the loop. At the gates.

Let me show you how that looks in the project.

---

## 4. Walking through the project (13:00 - 37:00)

### 4.1 The map (13:00 - 15:00)

**OPEN:** the repository root in the editor's file tree.

This is forge. Four folders matter.

`python` is the application: a Streamlit chat, a LangGraph agent on Amazon Bedrock, and the
tools the agent can call.

`knowledge-base` holds the migration guides. We call them packs.

`infra` creates the AWS side with Terraform, and has the scripts to run everything,
on macOS, Linux or Windows.

`docs` explains each stage. And `tests` proves the gates actually work.

**OPEN:** `docs/README.md`.

A run has five stages: prepare, discover, plan, migrate, review and pull request.
The plan and the review are the two places a human decides. Let's follow a run through the code.

### 4.2 The agent and its instructions (15:00 - 17:00)

**OPEN:** `python/agent.py`, scroll to `PROMPT_TEMPLATE`.

This is the prompt. Notice what it does *not* say. It doesn't say "migrate this app."
It describes five phases, and in each phase it tells the model which tool to use.

**OPEN:** in the same file, the `tools = [...]` list in `Claude.__init__`.

The model gets 22 tools. Read files, write files, run Maven, git. That's the "do the edit" part.
The rest of the list is the "code decides everything else" part, and that's what I want to
show you.

### 4.3 Prepare: secrets first, and a baseline (17:00 - 20:00)

**OPEN:** `python/guardrails.py`, the `SECRET_PATTERNS` list.

Before any model reads anything, we scan the repository for secrets.
Private keys, AES keys in constants, `SecretKeySpec` with a literal, byte-array keys,
passwords, API keys, tokens.

Each pattern has a severity. Secrets are blocked when the agent writes a file, blocked again
at commit time, and always externalized by the migration. Public keys aren't secret, so the
user decides.

**OPEN:** `python/pii_scan.py`, the module docstring.

Then a second scan, with Amazon Bedrock, for personal data: names, emails, addresses,
card numbers. On AMS it found 199 items in 27 files, mostly seed data. It cost four cents.
We report it, by file and line, and we never show the value.

**OPEN:** `python/agent.py`, function `_run_maven`.

And then the step that fixes "it grades its own homework": a test baseline.
We build and test the application before changing anything, and record what fails.
After the migration, every test run is compared against that list:
new failures, pre-existing failures, fixed.

"Pre-existing" is no longer an opinion. It's a diff.

### 4.4 Discover: evidence, not guesses (20:00 - 23:00)

**OPEN:** `python/techstack.py`, function `detect`.

Discovery is pure code. No model.
It reads every pom, resolves property versions, counts javax and jakarta imports per module,
and reads the server configuration.

It finds what the README doesn't tell you. On AMS: a Liberty server config *and* a Tomcat
Dockerfile. A migration someone started years ago and never finished.

**OPEN:** `knowledge-base/javax-to-jakarta.pack.md`.

This is a pack. It's just markdown. The top part is rules:

`detect` - when does this migration apply.
`applies_to` - which files does it own.
`acceptance` - what does "done" look like.

The bottom part is guidance written for the model, including the trap: some `javax` packages
belong to the JDK and must *not* be renamed. That's exactly what our reviewer got wrong.

### 4.5 Plan: the first human gate (23:00 - 25:00)

**OPEN:** `python/agent.py`, the `propose_migration_plan` tool; then `python/chat.py`,
function `render_migration_plan`.

The agent proposes a plan. The size of each item comes from the pack's own file rules, run
against the code. The chat shows it as a table with an Approve button.

**OPEN:** `python/ui_events.py`, function `approve_packs`.

That click freezes the list of approved packs. From then on, only a human can take something
out of scope. Remember "separate migration efforts"? That can't happen anymore.

### 4.6 Migrate: a worklist the model can't reorder (25:00 - 28:00)

**OPEN:** `python/agent.py`, the `next_migration_files` tool.

This fixes "it picks the easy files". The model doesn't choose what to work on.
It asks for its next batch.

Code builds the list from the packs and orders it: main code first, because tests compile
against it, then config and JSPs, then tests. It reports progress: "13 of 47 files done."
A file that belongs to three migrations is opened once, and all three are applied, in order.

The model reads, edits, writes - the part it's genuinely great at - and asks for the next batch.

**OPEN:** `python/techstack.py`, function `check_acceptance`.

When the queue is empty, each pack checks its own "done" rules: no `javax.servlet` left,
no old Struts API, no hardcoded secret. Leftovers come back as file and line number.

### 4.7 Tests keep their meaning (28:00 - 30:00)

**OPEN:** `python/techstack.py`, function `test_parity`.

This fixes "it changes the test, not the code."

For every test file the migration touched, code compares it with the original:
were test methods removed or renamed, are there fewer assertions, did the expected values
change?

A migration may change *how* a test is written, JUnit 4 to JUnit 5. Never *what* it checks.

On the pull request from the beginning, this flagged exactly two files.
One of them is the IP-space test that flipped from "rejected" to "allowed."

### 4.8 Review: a reviewer with ground truth (30:00 - 32:00)

**OPEN:** `python/reviewer.py`, `REVIEW_SYSTEM_PROMPT`.

We kept the second model, but changed what it sees.

It gets the whole file, not just the diff. It gets the pack's guidance as the authority.
And it's told: cite a real line, no "might" or "could", and never contradict the pack.

**OPEN:** `python/chat.py`, function `_decide`.

When a human clicks Retry, the agent may now *decline* advice that contradicts the pack, and
say why. Retry no longer means "do whatever the reviewer said."

### 4.9 The pull request gate (32:00 - 35:00)

**OPEN:** `python/agent.py`, function `_pr_gate`.

This is the part I'd keep if I could keep only one.

The agent can call `create_pull_request` as often as it likes. It only opens when:

- everything is committed and pushed;
- every part of the build was tested *after* the last change, compiles, and has no new failures;
- every approved pack is done, unless a human accepted the leftovers;
- tests kept their meaning.

Every one of those facts comes from a tool result. None comes from the model's summary.

**OPEN:** `python/chat.py`, function `render_gate_refusal`.

When the gate says no, the user sees why, with two buttons per pack: Finish, or Accept as
not migrated. The agent can't accept leftovers. Only a person can.

**OPEN:** `python/agent.py`, function `_verification_section`.

And when it passes, forge appends a verification section to the pull request, generated
from the tools: tests before and after, every pack's status, test-parity findings, personal
data found, and the environment variables the new code needs.

The model writes the story. The tools write the facts.

### 4.10 Infrastructure and running it (35:00 - 36:30)

**OPEN:** `infra/terraform/modules`.

The AWS side is three Terraform modules: the knowledge base on S3 Vectors, two Bedrock
guardrails - one for model traffic, one for scanning - and a least-privilege IAM policy.
The GitHub token lives in Parameter Store and never reaches the model.

**OPEN:** `infra/setup.sh` and `infra/setup.ps1`.

One command to install, check, and run, on a Mac or on Windows.

### 4.11 Testing the harness (36:30 - 37:00)

**OPEN:** `tests/run_all.py`.

And one confession. Our own deterministic code had a bug. For weeks, our file reader looked
at only the first four kilobytes of every file. Deterministic doesn't mean correct.

So the gates have their own tests: seven suites, no AWS needed, a few seconds to run.

---

## 5. Closing (37:00 - 40:00)

**OPEN:** back to the diagram in `docs/README.md`.

Three things I'd like you to take home.

**One. Don't trust self-report. Measure.**
"All tests pass." "Pre-existing." "Done." "Out of scope." Those are claims.
Run the tests yourself, keep a baseline, and make the gate read tool results.

**Two. Constrain scope and order in code.**
Give the model a worklist it can't reorder and a definition of done it can't redefine.
It will happily do the work. It just shouldn't decide what the work is.

**Three. Put humans at the gates, not in the loop.**
Approving a plan, deciding a flagged file, accepting a leftover.
Five minutes of judgement, not five hours of babysitting.

So, should you ask Claude to migrate your application?

Yes.

Just don't *only* ask.

Thank you.

---

## 6. Q&A (40:00 - 45:00)

Short answers to likely questions.

**Why a small model like Claude Haiku?**
Cost, and it proves the point: the harness carries the reliability. A bigger model makes
fewer mistakes, but it doesn't stop an agent from re-scoping work or trusting its own report.
Switching models is one setting.

**What does a migration cost?**
Most of it is re-sending context, about fifty thousand tokens per call. Our worst 48 hours
were about forty-seven dollars. Prompt caching is the next big saving.

**Why not just use Claude Code or an IDE agent?**
They're great for interactive work. A migration needs things around the model: a fixed
worklist, a test baseline, secret gates, a PR gate. You can build those around any agent.

**Does it work for Gradle, or other languages?**
Detection recognizes Gradle and Ant. Today's packs are Maven and J2EE. A new stack is mostly
writing packs, which are markdown files.

**Can the model get around the gates?**
No. The gates are in tool code, not in the prompt. The model can ask as often as it likes.

**What still needs a human?**
Approving the plan, deciding flagged files, accepting leftovers, and checks code can't do,
like "do the same users still have the same access?" And reviewing the pull request.

---

## Numbers you may be asked about

| Figure | Value | Where it comes from |
| --- | --- | --- |
| Pull request size | 75 files, +451 / -477 | GitHub PR #1 on anche-raja/ams |
| Pull request build | neither reactor compiles; Dockerfile still Tomcat 9 | building the PR branch with JDK 21 |
| Rewritten test | 8 -> 6 assertions; "rejected" became "allowed" | test-parity check on the PR branch |
| Step limit | 150 steps, turn aborted | first run, app log |
| Re-scoping run | 160 tool calls; 4 approved packs called "out of scope" (24, 25, 26, 7 files) | app log |
| Files in the worklist | 47 | `next_migration_files` on that run |
| Secrets in AMS | 3 (gateway password, API key, keystore password) | `scan_for_secrets` |
| Personal data | 199 items in 27 of 190 files, about $0.04 | Bedrock scan of AMS |
| Tokens | 879 calls, 44.5 M input tokens in 48 h, about 50 K per call | CloudWatch |
| Cost | about $47 for those 48 hours | CloudWatch tokens x Bedrock price; Cost Explorer |
